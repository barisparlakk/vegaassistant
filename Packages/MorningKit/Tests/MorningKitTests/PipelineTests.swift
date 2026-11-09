import Foundation
import Testing
@testable import MorningKit

@Suite("Pipeline, rules and small parsers")
struct PipelineTests {
    static let now = ISODate.parse("2026-11-09T07:00:00Z")!

    // MARK: Attention

    @Test func attentionRanksBySeverityThenRecency() {
        let repo = ProjectFact(
            id: "repo:app", name: "app", path: "/work/app", kind: .repo, branch: "main",
            githubSlug: "me/app", changedFiles: 2, ahead: 1, hasUpstream: true,
            lastActivityAt: Self.now.addingTimeInterval(-3 * 86_400),
            branches: [
                BranchFact(name: "main", upstream: "origin/main", ahead: 1, isCurrent: true),
                BranchFact(name: "old-idea", lastCommitAt: Self.now.addingTimeInterval(-40 * 86_400), isStale: true),
            ]
        )
        let failing = PullRequestFact(number: 7, title: "Speed up sync", url: "https://github.com/me/app/pull/7", repo: "me/app", updatedAt: Self.now.addingTimeInterval(-3600), checks: .failure)
        let review = PullRequestFact(number: 9, title: "Teammate change", url: "https://github.com/me/app/pull/9", repo: "me/app", author: "pal", createdAt: Self.now.addingTimeInterval(-2 * 86_400), updatedAt: Self.now.addingTimeInterval(-7200))
        let facts = BriefingFacts(
            period: Period(from: Self.now.addingTimeInterval(-86_400), to: Self.now),
            projects: [repo],
            github: GitHubFacts(authoredPRs: [failing], reviewRequests: [review])
        )

        let items = AttentionRules.derive(from: facts, now: Self.now, staleDays: 14)
        #expect(items.map(\.kind) == [.failingChecks, .reviewRequested, .uncommittedChanges, .unpushedCommits, .staleBranch])
        #expect(items[0].url == "https://github.com/me/app/pull/7")
        #expect(items[0].path == "/work/app")
        #expect(items[1].detail.contains("waiting 2 days"))
        #expect(items[2].severity == .medium) // dirty for 3 days
        #expect(items[4].refs.contains("branch:app/old-idea"))
    }

    @Test func approvedPullRequestIsReadyToMerge() {
        let pr = PullRequestFact(number: 1, title: "Ship it", url: "u", repo: "me/app", updatedAt: Self.now, reviewDecision: "APPROVED", checks: .success)
        let facts = BriefingFacts(period: Period(from: Self.now, to: Self.now), github: GitHubFacts(authoredPRs: [pr]))
        #expect(AttentionRules.derive(from: facts, now: Self.now, staleDays: 14).first?.kind == .readyToMerge)
    }

    // MARK: Assembly

    @Test func assembleLinksFactsToProjects() {
        let discovered = [
            DiscoveredProject(id: "repo:app", name: "app", path: "/work/app", kind: .repo),
            DiscoveredProject(id: "dir:notes", name: "notes", path: "/work/notes", kind: .folder),
        ]
        let sessionEnd = Self.now.addingTimeInterval(-600)
        var input = BriefingFacts(period: Period(from: Self.now.addingTimeInterval(-86_400), to: Self.now))
        input.projects = [ProjectFact(id: "repo:app", name: "app", path: "/work/app", kind: .repo, githubSlug: "Me/App", lastCommitAt: Self.now.addingTimeInterval(-7200))]
        input.sessions = [
            SessionFact(sessionID: "s1", cwd: "/work/app/sub", startedAt: sessionEnd.addingTimeInterval(-60), endedAt: sessionEnd),
            SessionFact(sessionID: "s2", cwd: "/work/notes", startedAt: Self.now.addingTimeInterval(-9000), endedAt: Self.now.addingTimeInterval(-8000)),
            SessionFact(sessionID: "s3", cwd: "/elsewhere", startedAt: Self.now, endedAt: Self.now),
        ]
        input.github = GitHubFacts(authoredPRs: [PullRequestFact(number: 3, title: "t", url: "u", repo: "me/app", updatedAt: Self.now)])

        let facts = CollectionPipeline.assemble(input, discovered: discovered, staleDays: 14)
        #expect(facts.sessions.map(\.projectID) == ["repo:app", "dir:notes", nil])
        #expect(facts.projects.map(\.id) == ["repo:app", "dir:notes"])
        #expect(facts.projects[0].lastActivityAt == sessionEnd)
        #expect(facts.github.authoredPRs[0].projectID == "repo:app")
    }

    @Test func userFoldersExcludeAppManagedSpace() {
        let home = "/Users/me"
        let library = "/Users/me/Library"
        #expect(CollectionPipeline.isUserFolder(URL(fileURLWithPath: "/Users/me/Desktop/brief"), home: home, library: library))
        #expect(!CollectionPipeline.isUserFolder(URL(fileURLWithPath: "/Users/me/Library/Application Support/Claude/scratch"), home: home, library: library))
        #expect(!CollectionPipeline.isUserFolder(URL(fileURLWithPath: "/Users/me/.claude/worktrees/x"), home: home, library: library))
        #expect(!CollectionPipeline.isUserFolder(URL(fileURLWithPath: "/private/tmp/x"), home: home, library: library))
        #expect(!CollectionPipeline.isUserFolder(URL(fileURLWithPath: "/Users/me"), home: home, library: library))
    }

    // MARK: Discovery

    @Test func duplicateNamesGetParentPrefix() {
        let projects = RepoDiscovery.identify(
            repos: [URL(fileURLWithPath: "/a/work/api"), URL(fileURLWithPath: "/a/side/api"), URL(fileURLWithPath: "/a/web")],
            folders: [URL(fileURLWithPath: "/a/web"), URL(fileURLWithPath: "/a/docs")]
        )
        #expect(projects.map(\.id) == ["repo:work/api", "repo:side/api", "repo:web", "dir:docs"])
    }

    @Test func deepestContainingProjectWins() {
        let projects = [
            DiscoveredProject(id: "repo:mono", name: "mono", path: "/w/mono", kind: .repo),
            DiscoveredProject(id: "repo:pkg", name: "pkg", path: "/w/mono/packages/pkg", kind: .repo),
        ]
        #expect(RepoDiscovery.project(containing: "/w/mono/packages/pkg/src", in: projects)?.id == "repo:pkg")
        #expect(RepoDiscovery.project(containing: "/w/mono/apps", in: projects)?.id == "repo:mono")
        #expect(RepoDiscovery.project(containing: "/w/monolith", in: projects) == nil)
    }

    @Test func scanFindsReposAndSkipsNoise() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "morning-scan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for folder in ["one/.git", "group/two/.git", "group/two/nested/.git", "node_modules/dep/.git", "deep/a/b/c/.git"] {
            try FileManager.default.createDirectory(at: root.appending(path: folder), withIntermediateDirectories: true)
        }
        // Compare on resolved paths: the temp folder lives behind the /var → /private/var symlink.
        let base = root.resolvingSymlinksInPath().path + "/"
        let found = RepoDiscovery.scan(roots: [root], depth: 3).map { $0.resolvingSymlinksInPath().path.replacingOccurrences(of: base, with: "") }
        #expect(found == ["group/two", "one"])
    }

    // MARK: Lookback

    @Test func lookbackUsesLastRunWithinLimits() {
        let lastRun = Self.now.addingTimeInterval(-10 * 3600)
        #expect(LookbackPolicy.period(lastRun: lastRun, now: Self.now, maxDays: 4).from == lastRun)
        #expect(LookbackPolicy.period(lastRun: nil, now: Self.now, maxDays: 4).from == Self.now.addingTimeInterval(-86_400))
        #expect(LookbackPolicy.period(lastRun: Self.now.addingTimeInterval(-30 * 86_400), now: Self.now, maxDays: 4).from == Self.now.addingTimeInterval(-4 * 86_400))
    }

    @Test func parseSince() {
        #expect(LookbackPolicy.parseSince("90m", now: Self.now) == Self.now.addingTimeInterval(-5400))
        #expect(LookbackPolicy.parseSince("2d", now: Self.now) == Self.now.addingTimeInterval(-172_800))
        #expect(LookbackPolicy.parseSince("2026-11-08T07:00:00Z", now: Self.now) == ISODate.parse("2026-11-08T07:00:00Z"))
        #expect(LookbackPolicy.parseSince("soon", now: Self.now) == nil)
    }

    // MARK: Settings

    @Test func settingsFillMissingKeysAndIgnoreUnknownCollectors() throws {
        let json = #"{"claudeModel":"opus","enabledCollectors":["git","fax"],"futureKey":true}"#
        let settings = try JSONCoding.decoder.decode(MorningSettings.self, from: Data(json.utf8))
        #expect(settings.claudeModel == "opus")
        #expect(settings.enabledCollectors == [.git])
        #expect(settings.briefingHour == 7)
        #expect(settings.repoRoots == MorningSettings.default.repoRoots)

        let roundTrip = try JSONCoding.decoder.decode(MorningSettings.self, from: JSONCoding.encoder.encode(settings))
        #expect(roundTrip == settings)
    }

    // MARK: Notes & hook log

    @Test func notesPreferUncheckedCheckboxes() {
        let parsed = NotesCollector.parse("""
        # TODO
        - [ ] Wire up sync
        - [x] Ship v1
        * [ ] Write README
        - plain bullet
        """)
        #expect(parsed.items == ["Wire up sync", "Write README"])
    }

    @Test func notesFallBackToBulletsThenExcerpt() {
        #expect(NotesCollector.parse("- one\n2. two").items == ["one", "two"])
        let prose = NotesCollector.parse("# Notes\nThe API is flaky on cold start.")
        #expect(prose.items.isEmpty)
        #expect(prose.excerpt == "# Notes · The API is flaky on cold start.")
    }

    @Test func hookLogParsesWindowedEntries() {
        let log = """
        {"ts":"2026-11-08T23:00:00Z","event":{"session_id":"s1","cwd":"/work/app","hook_event_name":"Stop","stop_hook_active":false}}
        {"ts":"2026-11-01T23:00:00Z","event":{"session_id":"old"}}
        garbage
        """
        let events = SessionLogCollector.parse(Data(log.utf8), period: Period(from: ISODate.parse("2026-11-08T00:00:00Z")!, to: Self.now))
        #expect(events.count == 1)
        #expect(events[0].sessionID == "s1")
        #expect(events[0].cwd == "/work/app")
    }

    @Test func githubResponseParsing() throws {
        let json = """
        {"data":{"viewer":{"login":"me"},
          "authored":{"nodes":[{"number":4,"title":"Add sync","url":"https://github.com/me/app/pull/4","isDraft":false,"createdAt":"2026-11-07T10:00:00Z","updatedAt":"2026-11-08T10:00:00Z","headRefName":"sync","reviewDecision":"CHANGES_REQUESTED","repository":{"nameWithOwner":"me/app"},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"FAILURE"}}}]}}, {}]},
          "reviews":{"nodes":[]},
          "issues":{"nodes":[{"number":12,"title":"Crash on launch","url":"https://github.com/me/app/issues/12","updatedAt":"2026-11-08T09:00:00Z","labels":{"nodes":[{"name":"bug"}]},"repository":{"nameWithOwner":"me/app"}}]}}}
        """
        let facts = try GitHubCollector.parse(Data(json.utf8))
        #expect(facts.login == "me")
        #expect(facts.authoredPRs.count == 1)
        #expect(facts.authoredPRs[0].checks == .failure)
        #expect(facts.authoredPRs[0].id == "pr:me/app#4")
        #expect(facts.assignedIssues[0].labels == ["bug"])
    }
}

@Suite("Shell")
struct ShellTests {
    @Test func capturesOutputAndStatus() async throws {
        let result = try await Shell.run(URL(fileURLWithPath: "/bin/sh"), ["-c", "echo out; echo err >&2; exit 3"])
        #expect(result.status == 3)
        #expect(result.output == "out\n")
        #expect(result.errorOutput == "err\n")
    }

    @Test func feedsStandardInput() async throws {
        let payload = String(repeating: "morning ", count: 50_000) // larger than a pipe buffer
        let result = try await Shell.run(URL(fileURLWithPath: "/bin/cat"), input: Data(payload.utf8))
        #expect(result.output == payload)
    }

    @Test func timesOut() async {
        await #expect(throws: ShellError.self) {
            _ = try await Shell.run(URL(fileURLWithPath: "/bin/sleep"), ["5"], timeout: .milliseconds(300))
        }
    }

    @Test func reportsMissingExecutable() async {
        await #expect(throws: ShellError.self) {
            _ = try await Shell.run(URL(fileURLWithPath: "/nonexistent/tool"))
        }
    }
}
