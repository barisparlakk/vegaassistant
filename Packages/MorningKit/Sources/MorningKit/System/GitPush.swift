import Foundation

/// Pushes a repository's current branch to its upstream: no refspec, never forced, and never
/// waiting on a password or passphrase prompt (it fails instead, with git's message).
public enum GitPush {
    public enum Outcome: Equatable, Sendable {
        case pushed(commits: Int, branch: String, upstream: String)
        case nothingToPush(branch: String)

        public var summary: String {
            switch self {
            case let .pushed(commits, branch, upstream):
                "Pushed \(commits) commit\(commits == 1 ? "" : "s") from \(branch) to \(upstream)."
            case let .nothingToPush(branch):
                "Nothing to push: \(branch) is up to date."
            }
        }
    }

    public enum Failure: Error, LocalizedError, Equatable {
        case noUpstream(branch: String)
        case detachedHead
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case let .noUpstream(branch): "\(branch) has no upstream branch to push to."
            case .detachedHead: "The repository isn't on a branch (detached HEAD)."
            case let .failed(message): message
            }
        }
    }

    /// Environment that turns every credential prompt into an immediate failure.
    static func environment(from parent: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = parent
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_ASKPASS"] = "/usr/bin/false"
        environment["SSH_ASKPASS"] = "/usr/bin/false"
        environment["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes -o ConnectTimeout=15"
        let path = environment["PATH"] ?? "/usr/bin:/bin"
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + path
        return environment
    }

    public static func push(repository: URL, git: URL = URL(fileURLWithPath: "/usr/bin/git")) async throws -> Outcome {
        let environment = environment()
        func run(_ arguments: [String], timeout: Duration = .seconds(20)) async throws -> ProcessResult {
            try await Shell.run(git, ["-C", repository.path] + arguments, environment: environment, timeout: timeout)
        }

        let head = try await run(["rev-parse", "--abbrev-ref", "HEAD"])
        let branch = head.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard head.succeeded, !branch.isEmpty else { throw Failure.failed(head.errorOutput.condensed(limit: 300)) }
        guard branch != "HEAD" else { throw Failure.detachedHead }

        let upstreamResult = try await run(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"])
        let upstream = upstreamResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard upstreamResult.succeeded, !upstream.isEmpty else { throw Failure.noUpstream(branch: branch) }

        // Count now, not from the morning's briefing. A failed count is an error, not "nothing to push".
        let count = try await run(["rev-list", "--count", "@{u}..HEAD"])
        guard count.succeeded, let ahead = Int(count.output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw Failure.failed(count.errorOutput.condensed(limit: 300).nilIfEmpty ?? "Couldn't count the commits to push.")
        }
        guard ahead > 0 else { return .nothingToPush(branch: branch) }

        let push = try await run(["push"], timeout: .seconds(90))
        guard push.succeeded else {
            let message = (push.errorOutput.nilIfEmpty ?? push.output).condensed(limit: 300)
            throw Failure.failed(message.isEmpty ? "git push failed." : message)
        }
        return .pushed(commits: ahead, branch: branch, upstream: upstream)
    }
}
