import Foundation

/// Progress for the UI's live view and the CLI's status line.
public enum GenerationEvent: Sendable {
    case collecting(CollectionEvent)
    case collected(projects: Int, sessions: Int, commits: Int, events: Int)
    case askingClaude(attempt: Int)
    case retrying(problems: [String])
    case fellBackToMarkdown(problems: [String])
    case saved(Briefing)
}

public enum GeneratorError: Error, LocalizedError, Sendable {
    case claudeNotFound
    case alreadyGeneratedToday(String)

    public var errorDescription: String? {
        switch self {
        case .claudeNotFound: ClaudeError.notInstalled.errorDescription
        case let .alreadyGeneratedToday(id): "Today's briefing (\(id)) already exists."
        }
    }
}

/// Collect → prompt → `claude -p` → validate (retry once) → save.
public struct BriefingGenerator: Sendable {
    public static let maxAttempts = 2

    public var settings: MorningSettings
    public var paths: MorningPaths
    public var mayRequestPermissions: Bool
    public var calendar: Calendar

    public init(settings: MorningSettings, paths: MorningPaths = MorningPaths(), mayRequestPermissions: Bool = false, calendar: Calendar = .current) {
        self.settings = settings
        self.paths = paths
        self.mayRequestPermissions = mayRequestPermissions
        self.calendar = calendar
    }

    public var store: BriefingStore { BriefingStore(paths: paths) }
    public var runState: RunStateStore { RunStateStore(paths: paths) }

    /// The window the next briefing would cover. Regenerating a day keeps that day's start,
    /// so "Overnight" doesn't shrink to the minutes since the previous attempt.
    public func nextPeriod(now: Date = .now) -> Period {
        let todayID = Briefing.id(for: now, calendar: calendar)
        if let existing = try? store.load(todayID) {
            return Period(from: existing.facts.period.from, to: now)
        }
        return LookbackPolicy.period(lastRun: runState.load().lastSuccessfulRun, now: now, maxDays: settings.maxLookbackDays)
    }

    /// Collects and builds the prompt without calling Claude (`morning-cli generate --dry-run`).
    public func preparePrompt(period: Period, onEvent: @escaping @Sendable (GenerationEvent) -> Void = { _ in }) async -> (CollectionResult, BriefingPrompt) {
        let collection = await collect(period: period, onEvent: onEvent)
        let prompt = PromptBuilder(calendar: calendar, paths: paths).build(facts: collection.facts, reports: collection.reports, settings: settings)
        return (collection, prompt)
    }

    public func generate(
        trigger: Briefing.Trigger,
        period requestedPeriod: Period? = nil,
        skipIfExists: Bool = false,
        onEvent: @escaping @Sendable (GenerationEvent) -> Void = { _ in }
    ) async throws -> Briefing {
        let clock = ContinuousClock()
        let started = clock.now
        let now = Date.now
        let id = Briefing.id(for: now, calendar: calendar)
        if skipIfExists, store.exists(id) { throw GeneratorError.alreadyGeneratedToday(id) }

        let lock = try GenerationLock(paths: paths)
        defer { withExtendedLifetime(lock) {} }

        do {
            let period = requestedPeriod ?? nextPeriod(now: now)
            let (collection, prompt) = await preparePrompt(period: period, onEvent: onEvent)
            guard let claude = collection.tools.claude else { throw GeneratorError.claudeNotFound }

            let runner = ClaudeRunner(executable: claude, model: settings.claudeModel, workingDirectory: paths.runDirectory)
            // News runs alongside the briefing call; if the briefing fails, it's cancelled with it.
            async let newsReport = gatherNews(id: id, facts: collection.facts, claude: claude, onEvent: onEvent)
            let (content, attempts, repairs) = try await ask(runner, prompt: prompt, facts: collection.facts, onEvent: onEvent)
            let diagnostics = collection.reports + [await newsReport].compactMap { $0 }

            let briefing = Briefing(
                id: id,
                generatedAt: .now,
                trigger: trigger,
                model: settings.claudeModel,
                durationMs: (clock.now - started).milliseconds,
                attempts: attempts,
                facts: collection.facts,
                content: content,
                diagnostics: diagnostics,
                repairs: repairs
            )
            try store.save(briefing)
            runState.recordSuccess(coveringUntil: period.to)
            onEvent(.saved(briefing))
            return briefing
        } catch {
            runState.recordFailure(error.localizedDescription)
            throw error
        }
    }

    /// The news search, reported like a collector. Never throws: a failure is a report.
    private func gatherNews(id: String, facts: BriefingFacts, claude: URL, onEvent: @escaping @Sendable (GenerationEvent) -> Void) async -> CollectorReport? {
        guard settings.newsEnabled, !settings.newsTopics.isEmpty else { return nil }
        onEvent(.collecting(.started(.news)))
        let clock = ContinuousClock()
        let start = clock.now
        let report: CollectorReport
        do {
            let feed = try await NewsGenerator(settings: settings, paths: paths, calendar: calendar).generate(id: id, facts: facts, claude: claude)
            report = CollectorReport(kind: .news, status: .ok, durationMs: (clock.now - start).milliseconds, itemCount: feed.allItems.count)
        } catch is CancellationError {
            return nil
        } catch {
            report = CollectorReport(kind: .news, status: .failed, durationMs: (clock.now - start).milliseconds, message: error.localizedDescription)
        }
        onEvent(.collecting(.finished(report)))
        return report
    }

    private func collect(period: Period, onEvent: @escaping @Sendable (GenerationEvent) -> Void) async -> CollectionResult {
        let pipeline = CollectionPipeline(settings: settings, paths: paths, mayRequestPermissions: mayRequestPermissions, calendar: calendar)
        let result = await pipeline.run(period: period) { onEvent(.collecting($0)) }
        onEvent(.collected(
            projects: result.facts.projects.count,
            sessions: result.facts.sessions.count,
            commits: result.facts.commits.count,
            events: result.facts.events.count
        ))
        return result
    }

    /// Up to two attempts; the second one is told what was wrong with the first.
    private func ask(
        _ runner: ClaudeRunner,
        prompt: BriefingPrompt,
        facts: BriefingFacts,
        onEvent: @escaping @Sendable (GenerationEvent) -> Void
    ) async throws -> (Briefing.Content, Int, [String]) {
        var currentPrompt = prompt
        var lastReply: ClaudeReply?
        var lastProblems: [String] = []

        for attempt in 1...Self.maxAttempts {
            onEvent(.askingClaude(attempt: attempt))
            let reply: ClaudeReply
            do {
                reply = try await runner.run(currentPrompt)
            } catch let error as ClaudeError where !error.isFatal && attempt < Self.maxAttempts {
                lastProblems = [error.localizedDescription]
                onEvent(.retrying(problems: lastProblems))
                continue
            }
            lastReply = reply

            let outcome = BriefingValidator.evaluate(reply, facts: facts)
            if let briefing = outcome.briefing, outcome.isValid {
                return (.structured(briefing), attempt, outcome.repairs)
            }
            lastProblems = outcome.problems
            if attempt < Self.maxAttempts {
                onEvent(.retrying(problems: outcome.problems))
                currentPrompt = prompt.retry(problems: outcome.problems)
            }
        }

        guard lastReply != nil else { throw ClaudeError.failed(lastProblems.joined(separator: " ")) }
        onEvent(.fellBackToMarkdown(problems: lastProblems))
        let markdown = BriefingValidator.fallbackMarkdown(for: lastReply, facts: facts, problems: lastProblems)
        return (.markdown(markdown), Self.maxAttempts, [])
    }
}
