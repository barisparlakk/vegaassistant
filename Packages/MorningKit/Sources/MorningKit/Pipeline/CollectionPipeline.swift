import Foundation

public enum CollectionEvent: Sendable {
    case resolvedTools(Toolbox)
    case started(CollectorKind)
    case finished(CollectorReport)
    case discoveredProjects(Int)
}

public struct CollectionResult: Sendable {
    public var facts: BriefingFacts
    public var reports: [CollectorReport]
    public var tools: Toolbox
}

/// Runs collectors in two phases and stitches their output together:
/// 1. Claude sessions + hook log, alongside repo discovery under the roots.
/// 2. Git, GitHub, notes, calendar, reminders — with the full project list,
///    including repos found only through session folders.
public struct CollectionPipeline: Sendable {
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

    public func run(period: Period, onEvent: @escaping @Sendable (CollectionEvent) -> Void = { _ in }) async -> CollectionResult {
        let tools = await Toolbox.resolve(settings: settings, paths: paths)
        onEvent(.resolvedTools(tools))

        var context = CollectionContext(
            period: period,
            settings: settings,
            paths: paths,
            tools: tools,
            mayRequestPermissions: mayRequestPermissions,
            calendar: calendar
        )

        // Phase 1
        let roots = settings.repoRoots.map(paths.expand)
        let depth = settings.scanDepth
        async let rootRepos = Task.detached(priority: .userInitiated) { RepoDiscovery.scan(roots: roots, depth: depth) }.value
        let phaseOne = await runAll([ClaudeSessionsCollector(), SessionLogCollector()], context: context, onEvent: onEvent)

        var facts = BriefingFacts(period: period, collectedAt: period.to)
        var reports: [CollectorReport] = []
        for (output, report) in phaseOne {
            if let output { facts.merge(output.facts) }
            reports.append(report)
        }

        let projects = discoverProjects(rootRepos: await rootRepos, sessions: facts.sessions, hookEvents: facts.hookEvents)
        context.projects = projects
        onEvent(.discoveredProjects(projects.count))

        // Phase 2
        let phaseTwo: [any Collector] = [GitCollector(), GitHubCollector(), NotesCollector(), CalendarCollector(), RemindersCollector()]
        for (output, report) in await runAll(phaseTwo, context: context, onEvent: onEvent) {
            if let output { facts.merge(output.facts) }
            reports.append(report)
        }

        facts = Self.assemble(facts, discovered: projects, staleDays: settings.staleBranchDays)
        let order = CollectorKind.allCases
        reports.sort { (order.firstIndex(of: $0.kind) ?? 0) < (order.firstIndex(of: $1.kind) ?? 0) }
        return CollectionResult(facts: facts, reports: reports, tools: tools)
    }

    // MARK: - Running collectors

    private func runAll(
        _ collectors: [any Collector],
        context: CollectionContext,
        onEvent: @escaping @Sendable (CollectionEvent) -> Void
    ) async -> [(CollectorOutput?, CollectorReport)] {
        await withTaskGroup(of: (CollectorOutput?, CollectorReport).self) { group in
            for collector in collectors {
                guard context.settings.isEnabled(collector.kind) else {
                    let report = CollectorReport(kind: collector.kind, status: .skipped, message: "Turned off in Settings")
                    onEvent(.finished(report))
                    group.addTask { (nil, report) }
                    continue
                }
                group.addTask {
                    onEvent(.started(collector.kind))
                    let result = await Self.execute(collector, context: context)
                    onEvent(.finished(result.1))
                    return result
                }
            }
            var results: [(CollectorOutput?, CollectorReport)] = []
            for await result in group { results.append(result) }
            return results
        }
    }

    static func execute(_ collector: any Collector, context: CollectionContext) async -> (CollectorOutput?, CollectorReport) {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let output = try await collector.collect(context)
            let warnings = output.warnings.isEmpty ? nil : output.warnings.joined(separator: "\n")
            return (output, CollectorReport(
                kind: collector.kind,
                status: .ok,
                durationMs: (clock.now - start).milliseconds,
                itemCount: output.facts.itemCount,
                message: warnings
            ))
        } catch let skipped as CollectorSkipped {
            return (nil, CollectorReport(kind: collector.kind, status: .skipped, durationMs: (clock.now - start).milliseconds, message: skipped.reason))
        } catch {
            return (nil, CollectorReport(kind: collector.kind, status: .failed, durationMs: (clock.now - start).milliseconds, message: error.localizedDescription))
        }
    }

    // MARK: - Projects

    private func discoverProjects(rootRepos: [URL], sessions: [SessionFact], hookEvents: [HookEventFact]) -> [DiscoveredProject] {
        guard settings.discoverFromClaudeSessions else {
            return RepoDiscovery.identify(repos: rootRepos, folders: [])
        }
        let fileManager = FileManager.default
        let home = paths.home
        let runDirectory = paths.runDirectory.path
        let folders = (sessions.map(\.cwd) + hookEvents.compactMap(\.cwd))
            .uniqued(by: { $0 })
            .filter { !$0.hasPrefix(runDirectory) && fileManager.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        let library = home.appending(path: "Library").path

        var repos = rootRepos
        var plainFolders: [URL] = []
        for folder in folders {
            if let root = RepoDiscovery.repositoryRoot(containing: folder, ceiling: home) {
                repos.append(root)
            } else if Self.isUserFolder(folder, home: home.path, library: library),
                      RepoDiscovery.project(containing: folder.path, in: RepoDiscovery.identify(repos: repos, folders: [])) == nil {
                plainFolders.append(folder)
            }
        }
        return RepoDiscovery.identify(repos: repos, folders: plainFolders)
    }

    /// A folder the user works in, as opposed to app-managed space (Claude's scratch
    /// workspaces under ~/Library, temp folders, dotfolders). Sessions there stay unassigned.
    static func isUserFolder(_ folder: URL, home: String, library: String) -> Bool {
        let path = folder.standardizedFileURL.path
        guard path.hasPrefix(home + "/"), !path.hasPrefix(library + "/") else { return false }
        let relative = path.dropFirst(home.count + 1)
        return !relative.split(separator: "/").contains { $0.hasPrefix(".") }
    }

    /// Links every fact to its project, adds folder-only projects, computes last activity and attention.
    static func assemble(_ input: BriefingFacts, discovered: [DiscoveredProject], staleDays: Int) -> BriefingFacts {
        var facts = input

        for index in facts.sessions.indices {
            facts.sessions[index].projectID = RepoDiscovery.project(containing: facts.sessions[index].cwd, in: discovered)?.id
        }
        for index in facts.hookEvents.indices {
            if let cwd = facts.hookEvents[index].cwd {
                facts.hookEvents[index].projectID = RepoDiscovery.project(containing: cwd, in: discovered)?.id
            }
        }

        // Folder projects (and repos git couldn't read) still deserve a card.
        let known = Set(facts.projects.map(\.id))
        for project in discovered where !known.contains(project.id) {
            facts.projects.append(ProjectFact(id: project.id, name: project.name, path: project.path, kind: project.kind))
        }

        var lastSession: [String: Date] = [:]
        for session in facts.sessions {
            guard let id = session.projectID else { continue }
            lastSession[id] = max(lastSession[id] ?? .distantPast, session.endedAt)
        }
        for index in facts.projects.indices {
            let candidates = [facts.projects[index].lastCommitAt, lastSession[facts.projects[index].id]].compactMap { $0 }
            facts.projects[index].lastActivityAt = candidates.max()
        }

        var slugToProject: [String: String] = [:]
        for project in facts.projects {
            if let slug = project.githubSlug?.lowercased() { slugToProject[slug] = project.id }
        }
        for index in facts.github.authoredPRs.indices {
            facts.github.authoredPRs[index].projectID = slugToProject[facts.github.authoredPRs[index].repo.lowercased()]
        }
        for index in facts.github.reviewRequests.indices {
            facts.github.reviewRequests[index].projectID = slugToProject[facts.github.reviewRequests[index].repo.lowercased()]
        }
        for index in facts.github.assignedIssues.indices {
            facts.github.assignedIssues[index].projectID = slugToProject[facts.github.assignedIssues[index].repo.lowercased()]
        }

        facts.projects.sort {
            ($0.lastActivityAt ?? .distantPast, $1.name) > ($1.lastActivityAt ?? .distantPast, $0.name)
        }
        facts.attention = AttentionRules.derive(from: facts, now: facts.period.to, staleDays: staleDays)
        return facts
    }
}

/// Decides the window a briefing covers.
public enum LookbackPolicy {
    /// From the last successful briefing, or 24 hours; never more than `maxDays` back.
    public static func period(lastRun: Date?, now: Date = .now, maxDays: Int) -> Period {
        let fallback = now.addingTimeInterval(-24 * 3600)
        let floor = now.addingTimeInterval(-Double(max(1, maxDays)) * 86_400)
        let from = max(lastRun ?? fallback, floor)
        return Period(from: min(from, now), to: now)
    }

    /// Parses "24h", "3d", "90m" or an ISO 8601 date.
    public static func parseSince(_ value: String, now: Date = .now) -> Date? {
        if let date = ISODate.parse(value) { return date }
        guard let unit = value.last, let amount = Double(value.dropLast()) else { return nil }
        let seconds: Double? = switch unit {
        case "m": amount * 60
        case "h": amount * 3600
        case "d": amount * 86_400
        default: nil
        }
        return seconds.map { now.addingTimeInterval(-$0) }
    }
}
