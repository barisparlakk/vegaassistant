import Foundation
import Testing
@testable import MorningKit

// MARK: - Fixtures

enum Sample {
    static let now = ISODate.parse("2026-11-09T07:00:00Z")!

    static var facts: BriefingFacts {
        var facts = BriefingFacts(period: Period(from: now.addingTimeInterval(-86_400), to: now))
        facts.projects = [
            ProjectFact(id: "repo:daybase", name: "daybase", path: "/w/daybase", kind: .repo, branch: "feat/rival", defaultBranch: "main", untrackedFiles: 3, lastActivityAt: now.addingTimeInterval(-4 * 3600), commitsLast14Days: [0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 9]),
            ProjectFact(id: "repo:old", name: "old", path: "/w/old", kind: .repo, lastActivityAt: now.addingTimeInterval(-90 * 86_400)),
        ]
        facts.sessions = [SessionFact(sessionID: "1f12ce81-aaaa", projectID: "repo:daybase", cwd: "/w/daybase", title: "Rival features", startedAt: now.addingTimeInterval(-9 * 3600), endedAt: now.addingTimeInterval(-4 * 3600), promptCount: 3, prompts: ["Look for what's missing", "add features", "stop"])]
        facts.commits = [CommitFact(hash: "0f0fa02a1b2c3d4e", projectID: "repo:daybase", subject: "feat(db): add intermittent fasts", author: "me", authoredAt: now.addingTimeInterval(-5 * 3600), branch: "feat/rival", files: ["a.ts"], insertions: 40)]
        facts.attention = [AttentionFact(id: "attn:dirty:repo:daybase", kind: .uncommittedChanges, severity: .low, projectID: "repo:daybase", title: "Uncommitted changes in daybase", detail: "3 untracked")]
        return facts
    }

    static let validJSON = """
    {"headline":"Land the daybase rival features branch before starting anything new.",
     "focus":{"projectId":"repo:daybase","reason":"Nine commits landed overnight on feat/rival and the tree has untracked files.","confidence":"high",
       "tasks":[{"title":"Review the fasting queries","detail":"Check the start/stop actions.","estimateMinutes":45,"refs":["commit:0f0fa02a1b","made:up"]},
                {"title":"Commit the untracked files","detail":"Or delete them.","estimateMinutes":2,"refs":["attn:dirty:repo:daybase"]},
                {"title":"Open a PR for feat/rival","detail":"Squash the db commits.","estimateMinutes":30,"refs":[]},
                {"title":"A fourth task","detail":"Too many.","estimateMinutes":10,"refs":[]}]},
     "sections":[{"kind":"attention","title":"Attention","items":[{"title":"Tidy daybase","priority":"low","refs":["attn:dirty:repo:daybase"]}]},
                 {"kind":"overnight","title":"Overnight","items":[{"title":"Added fasting, measurements and coach limits","priority":"high","projectId":"repo:daybase","refs":["session:1f12ce81","commit:0f0fa02a1b"]}]},
                 {"kind":"notes","title":"Notes","items":[]}],
     "nextTasks":[{"title":"Archive old","projectId":"repo:old","priority":"low","estimateMinutes":15,"reason":"Untouched for 90 days."},
                  {"title":"Ghost","projectId":"repo:ghost","priority":"low","estimateMinutes":15,"reason":"x"}]}
    """

    static func reply(_ json: String, structured: Bool = true) -> ClaudeReply {
        ClaudeReply(text: structured ? "" : json, structuredOutput: structured ? Data(json.utf8) : nil, durationMs: 1, costUSD: nil)
    }
}

// MARK: - Schema & validation

@Suite("Briefing schema and validator")
struct ValidatorTests {
    @Test func schemaIsValidJSONAndDescribesTheModel() throws {
        let schema = try #require(JSONSerialization.jsonObject(with: Data(BriefingSchema.json.utf8)) as? [String: Any])
        #expect(schema["required"] as? [String] == ["headline", "focus", "sections", "nextTasks"])
        // Every property the schema allows must decode into the Codable model.
        let draft = try JSONDecoder().decode(GeneratedBriefing.self, from: Data(Sample.validJSON.utf8))
        #expect(draft.focus.tasks.count == 4)
    }

    @Test func repairsSoftIssues() throws {
        let outcome = BriefingValidator.evaluate(Sample.reply(Sample.validJSON), facts: Sample.facts)
        #expect(outcome.isValid)
        let briefing = try #require(outcome.briefing)
        #expect(briefing.focus.tasks.map(\.id) == ["t1", "t2", "t3"])
        #expect(briefing.focus.tasks[0].refs == ["commit:0f0fa02a1b"])
        #expect(briefing.focus.tasks[1].estimateMinutes == 5)
        #expect(briefing.sections.map(\.kind) == [.overnight, .attention]) // reordered, empty notes dropped
        #expect(briefing.nextTasks.map(\.projectID) == ["repo:old"])
        #expect(outcome.repairs.contains { $0.contains("made:up") })
        #expect(outcome.repairs.contains { $0.contains("first 3 of 4") })
    }

    @Test func dropsNextTasksThatRepeatFocusOrAttention() throws {
        let json = Sample.validJSON
            .replacingOccurrences(of: #"{"title":"Tidy daybase","priority":"low","refs""#, with: #"{"title":"Tidy old","priority":"low","projectId":"repo:old","refs""#)
            .replacingOccurrences(of: #"{"title":"Ghost","projectId":"repo:ghost""#, with: #"{"title":"More daybase","projectId":"repo:daybase""#)
        let outcome = BriefingValidator.evaluate(Sample.reply(json), facts: Sample.facts)
        let briefing = try #require(outcome.briefing)
        #expect(briefing.nextTasks.isEmpty) // repo:old is in attention, repo:daybase is the focus
        #expect(outcome.repairs.contains { $0.contains("repeating the focus or attention") })
    }

    @Test func idsInTextBecomeReadable() {
        var facts = Sample.facts
        facts.projects.append(ProjectFact(id: "repo:barissparlak.github.io", name: "barissparlak.github.io", path: "/w/site", kind: .repo))
        let cases: [(String, String)] = [
            ("Merge it, for example commit:8f9a61f6f8 and commit:87bc5dab50.", "Merge it, for example 8f9a61f and 87bc5da."),
            ("Fix pr:barisparlakk/daybase#42 on repo:daybase", "Fix #42 on daybase"),
            ("Push branch:daybase/feat/rival-features now", "Push feat/rival-features now"),
            ("Tidy repo:barissparlak.github.io.", "Tidy barissparlak.github.io."),
            ("Clean up (attn:dirty:repo:Notary) first", "Clean up first"),
            ("No ids here", "No ids here"),
        ]
        for (input, expected) in cases {
            #expect(BriefingValidator.humanizeIDs(in: input, facts: facts).0 == expected)
        }
    }

    @Test func rejectsUnknownFocusProject() {
        let json = Sample.validJSON.replacingOccurrences(of: #""projectId":"repo:daybase","reason""#, with: #""projectId":"repo:nope","reason""#)
        let outcome = BriefingValidator.evaluate(Sample.reply(json), facts: Sample.facts)
        #expect(!outcome.isValid)
        #expect(outcome.problems.first?.contains("repo:nope") == true)
        #expect(outcome.problems.first?.contains("repo:daybase") == true) // tells the model what's allowed
    }

    @Test func readsJSONFromTextWhenStructuredOutputIsMissing() {
        let fenced = "Here you go:\n```json\n\(Sample.validJSON)\n```"
        #expect(BriefingValidator.evaluate(Sample.reply(fenced, structured: false), facts: Sample.facts).isValid)
    }

    @Test func nonJSONIsAProblem() {
        let outcome = BriefingValidator.evaluate(Sample.reply("Sorry, I can't.", structured: false), facts: Sample.facts)
        #expect(outcome.briefing == nil)
        #expect(!outcome.problems.isEmpty)
    }

    @Test func fallbackRendersDecodableAnswersAsMarkdown() {
        let markdown = BriefingValidator.fallbackMarkdown(for: Sample.reply(Sample.validJSON), facts: Sample.facts, problems: ["x"])
        #expect(markdown.hasPrefix("# Land the daybase"))
        #expect(markdown.contains("## Focus: daybase"))
        #expect(markdown.contains("didn't pass validation"))
        #expect(BriefingValidator.fallbackMarkdown(for: Sample.reply("plain words", structured: false), facts: Sample.facts, problems: []) == "plain words")
    }
}

// MARK: - Prompt

@Suite("Prompt builder")
struct PromptBuilderTests {
    @Test func contextCarriesIdsAndSkipsQuietProjects() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Istanbul"))
        let reports = [CollectorReport(kind: .calendar, status: .skipped, message: "Calendar: Not requested yet")]
        var settings = MorningSettings()
        settings.extraInstructions = "Keep it under 200 words."
        let prompt = PromptBuilder(calendar: calendar).build(facts: Sample.facts, reports: reports, settings: settings)

        #expect(prompt.user.contains("Keep it under 200 words."))
        #expect(prompt.user.contains(#""id":"repo:daybase""#))
        #expect(prompt.user.contains(#""quietProjects":["old"]"#))
        #expect(prompt.user.contains("commit:0f0fa02a1b"))
        #expect(prompt.user.contains("session:1f12ce81"))
        #expect(prompt.user.contains("Calendar: unavailable"))
        #expect(prompt.user.contains("Monday 2026-11-09 10:00 (Europe/Istanbul)"))
        #expect(prompt.system.contains("Never write URLs"))
        #expect(prompt.schema == BriefingSchema.json)
    }

    @Test func retryAppendsProblems() {
        let prompt = BriefingPrompt(system: "s", user: "u", schema: "{}").retry(problems: ["headline is empty."])
        #expect(prompt.user.hasSuffix("- headline is empty.\nReturn the corrected JSON object only."))
    }

    @Test func samplingKeepsBothEnds() {
        let prompts = (1...20).map { "p\($0)" }
        let sampled = PromptBuilder.sample(prompts, limit: 8)
        #expect(sampled.first == "p1")
        #expect(sampled.last == "p20")
        #expect(sampled.count == 9)
    }
}

// MARK: - Runner

@Suite("Claude runner")
struct ClaudeRunnerTests {
    @Test func environmentIsScrubbed() {
        let parent = [
            "HOME": "/Users/me", "PATH": "/usr/bin:/bin",
            "ANTHROPIC_API_KEY": "sk-secret", "ANTHROPIC_BASE_URL": "http://proxy", "ANTHROPIC_AUTH_TOKEN": "t",
            "CLAUDECODE": "1", "CLAUDE_CODE_ENTRYPOINT": "sdk", "CLAUDE_CODE_OAUTH_SCOPES": "x",
            "CLAUDE_CONFIG_DIR": "/Users/me/.claude-work",
        ]
        let environment = ClaudeRunner.environment(from: parent, executable: URL(fileURLWithPath: "/Users/me/.local/bin/claude"))
        #expect(environment.keys.filter { $0.hasPrefix("ANTHROPIC") }.isEmpty)
        #expect(environment["CLAUDECODE"] == nil)
        #expect(environment["CLAUDE_CODE_ENTRYPOINT"] == nil)
        #expect(environment["CLAUDE_CONFIG_DIR"] == "/Users/me/.claude-work")
        #expect(environment["MORNING_GENERATING"] == "1")
        #expect(environment["HOME"] == "/Users/me")
        #expect(environment["PATH"]?.hasPrefix("/Users/me/.local/bin:/opt/homebrew/bin") == true)
    }

    @Test func argumentsDisableToolsAndPersistence() {
        let runner = ClaudeRunner(executable: URL(fileURLWithPath: "/bin/claude"), model: "opus", workingDirectory: URL(fileURLWithPath: "/tmp"))
        let arguments = runner.arguments(for: BriefingPrompt(system: "S", user: "U", schema: "{}"))
        #expect(arguments.starts(with: ["-p", "--output-format", "json", "--json-schema", "{}", "--model", "opus"]))
        #expect(arguments.contains("--no-session-persistence"))
        #expect(arguments.contains("--strict-mcp-config"))
        #expect(!arguments.contains("U")) // the prompt goes through stdin
    }

    @Test func parsesStructuredReplies() throws {
        let stdout = #"{"type":"result","is_error":false,"result":"","structured_output":{"a":1},"duration_ms":1200,"total_cost_usd":0.01}"#
        let reply = try ClaudeRunner.parse(ProcessResult(status: 0, stdout: Data(stdout.utf8), stderr: Data()))
        #expect(reply.durationMs == 1200)
        #expect(reply.structuredOutput.map { String(decoding: $0, as: UTF8.self) } == #"{"a":1}"#)
    }

    @Test func classifiesErrors() {
        // Captured from a real run with an expired login.
        let stdout = #"{"type":"result","subtype":"success","is_error":true,"result":"Failed to authenticate: OAuth session expired and could not be refreshed","terminal_reason":"api_error"}"#
        #expect(throws: ClaudeError.notLoggedIn("Failed to authenticate: OAuth session expired and could not be refreshed")) {
            try ClaudeRunner.parse(ProcessResult(status: 1, stdout: Data(stdout.utf8), stderr: Data()))
        }
        #expect(ClaudeRunner.classify("Claude AI usage limit reached|1762700000").isFatal)
        #expect(!ClaudeRunner.classify("socket hang up").isFatal)
    }
}

// MARK: - Store

@Suite("Store")
struct StoreTests {
    @Test func saveLoadListAndRevisions() throws {
        let home = try TemporaryHome()
        let store = BriefingStore(paths: home.paths)
        let draft = try #require(BriefingValidator.evaluate(Sample.reply(Sample.validJSON), facts: Sample.facts).briefing)
        let first = Briefing(id: "2026-11-09", generatedAt: Sample.now, trigger: .scheduled, model: "sonnet", durationMs: 10, attempts: 1, facts: Sample.facts, content: .structured(draft), diagnostics: [])
        try store.save(first)
        try store.save(first) // regenerate the same day
        try store.save(Briefing(id: "2026-11-08", generatedAt: Sample.now.addingTimeInterval(-86_400), trigger: .manual, model: "sonnet", durationMs: 10, attempts: 2, facts: Sample.facts, content: .markdown("# text"), diagnostics: []))

        #expect(store.ids() == ["2026-11-09", "2026-11-08"])
        #expect(try encoded(store.load("2026-11-09")) == encoded(first))
        let summaries = store.summaries()
        #expect(summaries.first?.focusProjectName == "daybase")
        #expect(summaries.first?.headline?.hasPrefix("Land") == true)
        #expect(summaries.last?.isFallback == true)
        let revisions = try FileManager.default.contentsOfDirectory(atPath: store.revisions.path)
        #expect(revisions.count == 1)
    }

    @Test func taskChecksSurviveRegeneration() throws {
        let home = try TemporaryHome()
        let checks = TaskCheckStore(paths: home.paths)
        let task = GeneratedBriefing.FocusTask(id: "t1", title: "Review the fasting queries", detail: "", estimateMinutes: 30)
        try checks.setChecked(true, task: task, in: "2026-11-09")
        var regenerated = task
        regenerated.id = "t3"
        regenerated.title = "Review the fasting queries."
        #expect(checks.isChecked(regenerated, in: "2026-11-09"))
        #expect(!checks.isChecked(task, in: "2026-11-10"))
        try checks.setChecked(false, task: task, in: "2026-11-09")
        #expect(!checks.isChecked(task, in: "2026-11-09"))
    }

    @Test func lockIsExclusive() throws {
        let home = try TemporaryHome()
        let held = try GenerationLock(paths: home.paths)
        #expect(throws: GenerationLock.Busy.self) { _ = try GenerationLock(paths: home.paths) }
        _ = held
    }

    @Test func datesRoundTripToTheMillisecond() throws {
        for offset in [0.0, 0.0004, 0.9475, 0.9999, 12.3456] {
            let date = Date(timeIntervalSince1970: 1_762_650_000 + offset)
            let once = ISODate.fractionalString(date)
            let twice = ISODate.fractionalString(try #require(ISODate.parse(once)))
            #expect(once == twice)
        }
        #expect(ISODate.fractionalString(Date(timeIntervalSince1970: 0.9999)) == "1970-01-01T00:00:01.000Z")
    }

    @Test func briefingIDsUseLocalDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Istanbul"))
        let lateEvening = try #require(ISODate.parse("2026-11-08T22:30:00Z")) // 01:30 on the 9th in Istanbul
        #expect(Briefing.id(for: lateEvening, calendar: calendar) == "2026-11-09")
    }
}

// MARK: - End to end with a fake `claude`

@Suite("Generator end to end", .serialized)
struct GeneratorEndToEndTests {
    /// A stand-in for `claude -p`: answers from files, counts calls, records argv and env.
    /// The news run is told apart by its `--tools WebSearch` argument and answered from
    /// `news.json`, so briefing answers keep their numbering.
    static func fakeClaude(in home: TemporaryHome, answers: [String], news: String = NewsSample.validJSON) throws -> URL {
        for (index, answer) in answers.enumerated() {
            let reply: [String: Any] = ["type": "result", "is_error": false, "result": answer, "duration_ms": 5]
            try JSONSerialization.data(withJSONObject: reply).write(to: home.root.appending(path: "answer\(index + 1).json"))
        }
        let newsReply: [String: Any] = ["type": "result", "is_error": false, "result": news, "duration_ms": 5]
        try JSONSerialization.data(withJSONObject: newsReply).write(to: home.root.appending(path: "news.json"))
        let script = home.root.appending(path: "claude")
        try """
        #!/bin/sh
        dir="$(dirname "$0")"
        case "$*" in *WebSearch*) cat > "$dir/news-stdin.txt"; echo "$*" > "$dir/news-args.txt"; cat "$dir/news.json"; exit 0;; esac
        n=$(( $(cat "$dir/count" 2>/dev/null || echo 0) + 1 ))
        echo $n > "$dir/count"
        cat > "$dir/stdin$n.txt"
        env > "$dir/env$n.txt"
        file="$dir/answer$n.json"; [ -f "$file" ] || file="$dir/answer\(answers.count).json"
        cat "$file"
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    static func generator(_ home: TemporaryHome, claude: URL) -> BriefingGenerator {
        var settings = MorningSettings()
        settings.repoRoots = [home.root.appending(path: "dev").path]
        settings.enabledCollectors = [.git, .claudeSessions, .notes]
        settings.claudePath = claude.path
        return BriefingGenerator(settings: settings, paths: home.paths)
    }

    @Test func savesAValidatedBriefing() async throws {
        let home = try TemporaryHome()
        try home.makeRepo("daybase")
        let claude = try Self.fakeClaude(in: home, answers: [Sample.validJSON])
        let briefing = try await Self.generator(home, claude: claude).generate(trigger: .manual)

        #expect(briefing.attempts == 1)
        #expect(briefing.structured?.focus.projectID == "repo:daybase")
        #expect(briefing.facts.projects.map(\.id) == ["repo:daybase"])
        #expect(try encoded(BriefingStore(paths: home.paths).load(briefing.id)) == encoded(briefing))
        let lastRun = try #require(RunStateStore(paths: home.paths).load().lastSuccessfulRun)
        #expect(abs(lastRun.timeIntervalSince(briefing.facts.period.to)) < 0.001)

        let stdin = try String(contentsOf: home.root.appending(path: "stdin1.txt"), encoding: .utf8)
        #expect(stdin.contains("CONTEXT:"))
        let environment = try String(contentsOf: home.root.appending(path: "env1.txt"), encoding: .utf8)
        #expect(environment.contains("MORNING_GENERATING=1"))
        #expect(!environment.contains("ANTHROPIC_API_KEY"))
    }

    @Test func regeneratingKeepsTheDaysWindow() async throws {
        let home = try TemporaryHome()
        try home.makeRepo("daybase")
        let claude = try Self.fakeClaude(in: home, answers: [Sample.validJSON])
        let generator = Self.generator(home, claude: claude)
        let first = try await generator.generate(trigger: .scheduled)
        let second = try await generator.generate(trigger: .manual)
        #expect(second.id == first.id)
        // Read back from disk, so equal to the millisecond.
        #expect(abs(second.facts.period.from.timeIntervalSince(first.facts.period.from)) < 0.001)
        #expect(second.facts.period.to > first.facts.period.to)
    }

    @Test func retriesOnceWithTheProblems() async throws {
        let home = try TemporaryHome()
        try home.makeRepo("daybase")
        let bad = Sample.validJSON.replacingOccurrences(of: #""projectId":"repo:daybase","reason""#, with: #""projectId":"repo:nope","reason""#)
        let claude = try Self.fakeClaude(in: home, answers: [bad, Sample.validJSON])
        let briefing = try await Self.generator(home, claude: claude).generate(trigger: .manual)

        #expect(briefing.attempts == 2)
        #expect(briefing.structured != nil)
        let secondPrompt = try String(contentsOf: home.root.appending(path: "stdin2.txt"), encoding: .utf8)
        #expect(secondPrompt.contains("Your previous answer was rejected"))
        #expect(secondPrompt.contains("repo:nope"))
    }

    @Test func fallsBackToMarkdownAfterTwoFailures() async throws {
        let home = try TemporaryHome()
        try home.makeRepo("daybase")
        let claude = try Self.fakeClaude(in: home, answers: ["Here is your day: ship daybase."])
        let briefing = try await Self.generator(home, claude: claude).generate(trigger: .scheduled)

        guard case let .markdown(text) = briefing.content else {
            Issue.record("expected markdown fallback")
            return
        }
        #expect(text.hasPrefix("Here is your day"))
        #expect(briefing.attempts == 2)
    }

    @Test func skipIfExistsAndLoginErrorsAreReported() async throws {
        let home = try TemporaryHome()
        try home.makeRepo("daybase")
        let script = home.root.appending(path: "claude")
        try """
        #!/bin/sh
        cat > /dev/null
        echo '{"type":"result","is_error":true,"result":"Failed to authenticate: OAuth session expired"}'
        exit 1
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let generator = Self.generator(home, claude: script)
        await #expect(throws: ClaudeError.self) { _ = try await generator.generate(trigger: .scheduled) }
        let state = RunStateStore(paths: home.paths).load()
        #expect(state.consecutiveFailures == 1)
        #expect(state.lastError?.contains("claude auth login") == true)
        #expect(BriefingStore(paths: home.paths).ids().isEmpty)
    }
}

// MARK: - Helpers

/// JSON keeps milliseconds, not the sub-millisecond part of `Date.now`; compare encoded forms.
func encoded(_ briefing: Briefing?) throws -> Data {
    try JSONCoding.encoder.encode(briefing)
}

struct TemporaryHome {
    let root: URL
    var paths: MorningPaths { MorningPaths(home: root) }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "morning-tests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// A real git repository with one commit under `~/dev`.
    func makeRepo(_ name: String) throws {
        let repo = root.appending(path: "dev/\(name)")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try "hello".write(to: repo.appending(path: "README.md"), atomically: true, encoding: .utf8)
        for arguments in [
            ["init", "-q", "-b", "main"],
            ["add", "."],
            ["-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-q", "-m", "Initial commit"],
        ] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", repo.path] + arguments
            try process.run()
            process.waitUntilExit()
        }
    }
}

@Suite("Mock data")
struct MockDataTests {
    @Test func mockBriefingPassesTheValidatorUntouched() throws {
        let briefing = MockData.briefing()
        let outcome = BriefingValidator.validate(MockData.generated, facts: briefing.facts)
        #expect(outcome.isValid)
        #expect(outcome.repairs.isEmpty, "Mock data drifted from the facts: \(outcome.repairs)")
        #expect(try #require(outcome.briefing) == MockData.generated)
    }

    @Test func historyIDsAreDistinctDays() {
        let ids = MockData.summaries().map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
