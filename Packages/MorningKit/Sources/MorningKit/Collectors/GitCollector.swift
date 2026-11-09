import Foundation

/// Inspects every discovered repository: branch, dirty state, unpushed and stale branches,
/// commits in the window, and a 14-day activity histogram.
public struct GitCollector: Collector {
    public let kind = CollectorKind.git
    static let maxConcurrentRepos = 6

    public init() {}

    public func collect(_ context: CollectionContext) async throws -> CollectorOutput {
        guard let gitURL = context.tools.git else { throw CollectorSkipped("git not found") }
        let repos = context.projects.filter { $0.kind == .repo }
        guard !repos.isEmpty else {
            throw CollectorSkipped("No repositories under \(context.settings.repoRoots.joined(separator: ", "))")
        }

        var fragment = BriefingFacts.fragment(context)
        var warnings: [String] = []

        await withTaskGroup(of: Result<RepoSnapshot, RepoError>.self) { group in
            var pending = repos[...]
            func enqueue() {
                guard let repo = pending.popFirst() else { return }
                group.addTask {
                    do {
                        return .success(try await Self.inspect(repo, git: gitURL, context: context))
                    } catch {
                        return .failure(RepoError(repo: repo.name, message: error.localizedDescription))
                    }
                }
            }
            for _ in 0..<Self.maxConcurrentRepos { enqueue() }
            for await result in group {
                switch result {
                case let .success(snapshot):
                    fragment.projects.append(snapshot.project)
                    fragment.commits += snapshot.commits
                case let .failure(error):
                    warnings.append("\(error.repo): \(error.message)")
                }
                enqueue()
            }
        }

        if fragment.projects.isEmpty, !warnings.isEmpty {
            throw ShellError.failed(command: "git", status: 1, stderr: warnings.joined(separator: "; "))
        }
        fragment.projects.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        fragment.commits.sort { $0.authoredAt > $1.authoredAt }
        return CollectorOutput(facts: fragment, warnings: warnings)
    }

    private struct RepoSnapshot: Sendable {
        var project: ProjectFact
        var commits: [CommitFact]
    }

    private struct RepoError: Error, Sendable {
        let repo: String
        let message: String
    }

    // MARK: - Per-repo inspection

    private static func inspect(_ repo: DiscoveredProject, git gitURL: URL, context: CollectionContext) async throws -> RepoSnapshot {
        let git = GitCommand(executable: gitURL, repository: repo.url)
        let calendar = context.calendar
        let now = context.now
        let histogramStart = calendar.date(byAdding: .day, value: -13, to: calendar.startOfDay(for: now)) ?? now

        async let statusOutput = git.run(["status", "--porcelain=v1", "--branch", "--untracked-files=normal"])
        async let refsOutput = git.run([
            "for-each-ref", "refs/heads",
            "--format=%(refname:short)%1f%(committerdate:unix)%1f%(upstream:short)%1f%(upstream:track,nobracket)%1f%(HEAD)",
        ])
        async let originHead = git.runOptional(["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"])
        async let remoteURL = git.runOptional(["remote", "get-url", "origin"])
        // Empty repositories make `git log` fail; that just means "no commits".
        async let logOutput = git.runOptional([
            "log", "--branches", "--no-merges", "--source", "-n", "200",
            "--since=\(GitParsing.gitDate(context.period.from))",
            "--format=%x1e%H%x1f%an%x1f%at%x1f%S%x1f%s", "--numstat",
        ])
        async let histogramOutput = git.runOptional([
            "log", "--branches", "--no-merges", "-n", "3000",
            "--since=\(GitParsing.gitDate(histogramStart))", "--format=%at",
        ])

        let status = GitParsing.parseStatus(try await statusOutput)
        let refs = GitParsing.parseRefs(try await refsOutput)
        let branchNames = Set(refs.map(\.name))
        let defaultBranch = GitParsing.defaultBranch(
            originHead: await originHead,
            localBranches: branchNames,
            current: status.branch
        )
        let merged: Set<String> = if let defaultBranch {
            Set(GitParsing.lines(await git.runOptional(["branch", "--merged", defaultBranch, "--format=%(refname:short)"])))
        } else {
            []
        }

        let staleCutoff = now.addingTimeInterval(-Double(context.settings.staleBranchDays) * 86_400)
        let branches = refs.map { ref -> BranchFact in
            let isMerged = merged.contains(ref.name) && ref.name != defaultBranch
            let isStale = !ref.isCurrent && ref.name != defaultBranch && !isMerged
                && (ref.lastCommitAt.map { $0 < staleCutoff } ?? false)
            return BranchFact(
                name: ref.name,
                lastCommitAt: ref.lastCommitAt,
                upstream: ref.upstream,
                upstreamGone: ref.upstreamGone,
                ahead: ref.ahead,
                behind: ref.behind,
                isCurrent: ref.isCurrent,
                isMerged: isMerged,
                isStale: isStale
            )
        }

        let remote = await remoteURL.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let commits = GitParsing.parseLog(await logOutput ?? "", projectID: repo.id)
        let histogram = GitParsing.histogram(
            timestamps: GitParsing.lines(await histogramOutput).compactMap { TimeInterval($0) }.map(Date.init(timeIntervalSince1970:)),
            endingAt: now,
            calendar: calendar
        )

        let project = ProjectFact(
            id: repo.id,
            name: repo.name,
            path: repo.path,
            kind: .repo,
            branch: status.branch,
            defaultBranch: defaultBranch,
            githubSlug: remote.flatMap { GitParsing.githubSlug(fromRemote: $0) },
            webURL: remote.flatMap { GitParsing.webURL(fromRemote: $0) },
            changedFiles: status.changed,
            untrackedFiles: status.untracked,
            ahead: status.ahead,
            behind: status.behind,
            hasUpstream: status.upstream != nil,
            lastCommitAt: refs.compactMap(\.lastCommitAt).max(),
            lastActivityAt: refs.compactMap(\.lastCommitAt).max(),
            commitsLast14Days: histogram,
            branches: branches
        )
        return RepoSnapshot(project: project, commits: commits)
    }
}

// MARK: - Command wrapper

struct GitCommand: Sendable {
    let executable: URL
    let repository: URL

    static let environment: [String: String] = {
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0" // never take index.lock away from the user's editor
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_PAGER"] = "cat"
        environment["LC_ALL"] = "C"
        return environment
    }()

    func run(_ arguments: [String]) async throws -> String {
        try await Shell.output(
            executable,
            ["-C", repository.path, "-c", "core.quotePath=false", "-c", "color.ui=false"] + arguments,
            environment: Self.environment,
            timeout: .seconds(20)
        )
    }

    func runOptional(_ arguments: [String]) async -> String? {
        try? await run(arguments)
    }
}

// MARK: - Parsing (pure, unit-tested)

enum GitParsing {
    struct Status: Equatable {
        var branch: String?
        var upstream: String?
        var ahead = 0
        var behind = 0
        var changed = 0
        var untracked = 0
    }

    struct Ref: Equatable {
        var name: String
        var lastCommitAt: Date?
        var upstream: String?
        var upstreamGone = false
        var ahead = 0
        var behind = 0
        var isCurrent = false
    }

    static func lines(_ output: String?) -> [String] {
        (output ?? "").split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
    }

    /// `git status --porcelain=v1 --branch`.
    static func parseStatus(_ output: String) -> Status {
        var status = Status()
        for line in lines(output) {
            if line.hasPrefix("## ") {
                parseBranchHeader(String(line.dropFirst(3)), into: &status)
            } else if line.hasPrefix("??") {
                status.untracked += 1
            } else if !line.hasPrefix("!!") {
                status.changed += 1
            }
        }
        return status
    }

    private static func parseBranchHeader(_ header: String, into status: inout Status) {
        // "main...origin/main [ahead 1, behind 2]" | "main" | "No commits yet on main" | "HEAD (no branch)"
        if header.hasPrefix("No commits yet on ") {
            status.branch = String(header.dropFirst("No commits yet on ".count))
            return
        }
        if header.hasPrefix("HEAD (no branch)") { return }
        var rest = Substring(header)
        var tracking: Substring?
        if let bracket = rest.firstIndex(of: "[") {
            tracking = rest[rest.index(after: bracket)...].dropLast()
            rest = rest[..<bracket].dropLast()
        }
        let parts = rest.components(separatedBy: "...")
        status.branch = parts.first.map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count > 1 { status.upstream = parts[1].trimmingCharacters(in: .whitespaces) }
        if let tracking {
            let counts = parseTrack(String(tracking))
            status.ahead = counts.ahead
            status.behind = counts.behind
        }
    }

    /// "ahead 2, behind 1" | "gone" | "".
    static func parseTrack(_ track: String) -> (ahead: Int, behind: Int, gone: Bool) {
        var ahead = 0
        var behind = 0
        for piece in track.split(separator: ",") {
            let words = piece.split(separator: " ")
            guard words.count == 2, let value = Int(words[1]) else { continue }
            if words[0] == "ahead" { ahead = value }
            if words[0] == "behind" { behind = value }
        }
        return (ahead, behind, track.trimmingCharacters(in: .whitespaces) == "gone")
    }

    /// Fields separated by U+001F, see the `for-each-ref --format` in `GitCollector`.
    static func parseRefs(_ output: String) -> [Ref] {
        lines(output).compactMap { line in
            let fields = line.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 5, !fields[0].isEmpty else { return nil }
            let track = parseTrack(fields[3])
            return Ref(
                name: fields[0],
                lastCommitAt: TimeInterval(fields[1]).map(Date.init(timeIntervalSince1970:)),
                upstream: fields[2].nilIfEmpty,
                upstreamGone: track.gone,
                ahead: track.ahead,
                behind: track.behind,
                isCurrent: fields[4] == "*"
            )
        }
    }

    static func defaultBranch(originHead: String?, localBranches: Set<String>, current: String?) -> String? {
        if let originHead = originHead?.trimmingCharacters(in: .whitespacesAndNewlines),
           let name = originHead.split(separator: "/", maxSplits: 1).last.map(String.init),
           localBranches.contains(name) {
            return name
        }
        for candidate in ["main", "master", "trunk", "develop"] where localBranches.contains(candidate) {
            return candidate
        }
        return current
    }

    /// `git log --format=%x1e%H%x1f%an%x1f%at%x1f%S%x1f%s --numstat`.
    static func parseLog(_ output: String, projectID: String) -> [CommitFact] {
        output.split(separator: "\u{1e}").compactMap { record in
            let recordLines = record.split(whereSeparator: \.isNewline)
            guard let header = recordLines.first else { return nil }
            let fields = header.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 5, let seconds = TimeInterval(fields[2]) else { return nil }

            var files: [String] = []
            var insertions = 0
            var deletions = 0
            for statLine in recordLines.dropFirst() {
                let columns = statLine.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
                guard columns.count == 3 else { continue }
                insertions += Int(columns[0]) ?? 0 // "-" for binary files
                deletions += Int(columns[1]) ?? 0
                files.append(String(columns[2]))
            }
            let source = fields[3]
            let branch = source.hasPrefix("refs/heads/") ? String(source.dropFirst("refs/heads/".count)) : source.nilIfEmpty
            return CommitFact(
                hash: fields[0],
                projectID: projectID,
                subject: fields[4...].joined(separator: " ").condensed(limit: 200),
                author: fields[1],
                authoredAt: Date(timeIntervalSince1970: seconds),
                branch: branch,
                files: Array(files.prefix(30)),
                insertions: insertions,
                deletions: deletions
            )
        }
    }

    /// Commits per local day for the 14 days ending today, oldest first.
    static func histogram(timestamps: [Date], endingAt now: Date, calendar: Calendar) -> [Int] {
        let today = calendar.startOfDay(for: now)
        var buckets = Array(repeating: 0, count: 14)
        for date in timestamps {
            let day = calendar.startOfDay(for: date)
            guard let offset = calendar.dateComponents([.day], from: day, to: today).day,
                  (0..<14).contains(offset)
            else { continue }
            buckets[13 - offset] += 1
        }
        return buckets
    }

    /// `git@github.com:owner/repo.git`, `https://github.com/owner/repo`, `ssh://git@github.com/owner/repo.git`.
    static func githubSlug(fromRemote remote: String) -> String? {
        guard let (host, path) = hostAndPath(remote), host.lowercased() == "github.com" else { return nil }
        let parts = path.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        return "\(parts[0])/\(parts[1])"
    }

    static func webURL(fromRemote remote: String) -> String? {
        guard let (host, path) = hostAndPath(remote) else { return nil }
        return "https://\(host)/\(path)"
    }

    private static func hostAndPath(_ remote: String) -> (String, String)? {
        var value = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasSuffix(".git") { value.removeLast(4) }
        if let url = URL(string: value), let host = url.host(), url.scheme != nil {
            let path = url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return path.isEmpty ? nil : (host, path)
        }
        // scp-like: user@host:owner/repo
        guard let colon = value.firstIndex(of: ":") else { return nil }
        let hostPart = value[..<colon]
        let host = hostPart.split(separator: "@").last.map(String.init) ?? String(hostPart)
        let path = String(value[value.index(after: colon)...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return host.isEmpty || path.isEmpty ? nil : (host, path)
    }

    /// Format git's `--since` parses unambiguously.
    static func gitDate(_ date: Date) -> String {
        let style = Date.ISO8601FormatStyle(dateSeparator: .dash, dateTimeSeparator: .space, timeZone: .gmt)
        return style.format(date).replacingOccurrences(of: "Z", with: " +0000")
    }
}
