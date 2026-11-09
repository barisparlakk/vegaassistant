import Foundation

public struct ClaudeReply: Sendable {
    /// The `result` text (for structured runs, usually the JSON as text too).
    public var text: String
    /// `structured_output`, re-serialised, when `--json-schema` was honoured.
    public var structuredOutput: Data?
    public var durationMs: Int
    public var costUSD: Double?
}

public enum ClaudeError: Error, LocalizedError, Sendable, Equatable {
    case notInstalled
    case notLoggedIn(String)
    case usageLimited(String)
    case timedOut(seconds: Int)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            "Claude Code isn't installed or couldn't be found. Set its path in Settings › Claude."
        case let .notLoggedIn(detail):
            "Claude Code isn't signed in to your subscription. Run `claude auth login` in Terminal. (\(detail))"
        case let .usageLimited(detail):
            "Claude usage limit reached — try again later. (\(detail))"
        case let .timedOut(seconds):
            "Claude didn't answer within \(seconds) seconds."
        case let .failed(detail):
            "Claude Code failed: \(detail)"
        }
    }

    /// Errors that a second attempt won't fix.
    public var isFatal: Bool {
        switch self {
        case .notInstalled, .notLoggedIn, .usageLimited: true
        case .timedOut, .failed: false
        }
    }
}

/// Runs Claude Code headless (`claude -p`) on the user's subscription.
///
/// The child gets a scrubbed environment: no `ANTHROPIC_*` variables (so an API key or a
/// proxy URL can never switch billing away from the subscription) and none of the
/// `CLAUDE*` variables a parent Claude Code session exports (which would redirect auth).
public struct ClaudeRunner: Sendable {
    public var executable: URL
    public var model: String
    public var workingDirectory: URL
    public var timeout: Duration

    public init(executable: URL, model: String, workingDirectory: URL, timeout: Duration = .seconds(300)) {
        self.executable = executable
        self.model = model
        self.workingDirectory = workingDirectory
        self.timeout = timeout
    }

    /// Variables kept from the parent, even though they match the scrub prefixes.
    static let preservedVariables: Set<String> = ["CLAUDE_CONFIG_DIR"]

    public static func environment(from parent: [String: String], executable: URL) -> [String: String] {
        var environment = parent.filter { key, _ in
            if preservedVariables.contains(key) { return true }
            return !key.hasPrefix("ANTHROPIC_") && !key.hasPrefix("CLAUDE")
        }
        environment.removeValue(forKey: "ANTHROPIC_API_KEY") // explicit, even though the prefix rule covers it
        environment["MORNING_GENERATING"] = "1" // the Stop hook ignores our own runs
        environment["NO_COLOR"] = "1"
        // launchd and Finder give a bare PATH; claude may need node or git from Homebrew.
        let pathEntries = [executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin"]
            + (parent["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init)
        environment["PATH"] = pathEntries.uniqued(by: { $0 }).joined(separator: ":")
        return environment
    }

    public func arguments(for prompt: BriefingPrompt) -> [String] {
        [
            "-p",
            "--output-format", "json",
            "--json-schema", prompt.schema,
            "--model", model,
            "--system-prompt", prompt.system,
            "--tools", "", // everything is in the prompt; no file or shell access
            "--strict-mcp-config", // don't start the user's MCP servers
            "--setting-sources", "", // ignore user/project settings, including their hooks
            "--no-session-persistence", // keep briefing runs out of ~/.claude/projects
        ]
    }

    public func run(_ prompt: BriefingPrompt) async throws -> ClaudeReply {
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        let result: ProcessResult
        do {
            result = try await Shell.run(
                executable,
                arguments(for: prompt),
                in: workingDirectory,
                environment: Self.environment(from: ProcessInfo.processInfo.environment, executable: executable),
                input: Data(prompt.user.utf8),
                timeout: timeout
            )
        } catch let error as ShellError {
            switch error {
            case .launchFailed: throw ClaudeError.notInstalled
            case let .timedOut(_, seconds): throw ClaudeError.timedOut(seconds: seconds)
            case let .failed(_, _, stderr): throw ClaudeError.failed(stderr)
            }
        }
        return try Self.parse(result)
    }

    static func parse(_ result: ProcessResult) throws -> ClaudeReply {
        guard let object = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any] else {
            let detail = (result.errorOutput.nilIfEmpty ?? result.output.nilIfEmpty ?? "exit status \(result.status)")
            throw classify(detail.condensed(limit: 400))
        }
        let text = object["result"] as? String ?? ""
        if object["is_error"] as? Bool == true {
            throw classify(text.nilIfEmpty ?? (object["terminal_reason"] as? String) ?? "unknown error")
        }
        let structured = object["structured_output"].flatMap { value -> Data? in
            guard JSONSerialization.isValidJSONObject(value) else { return nil }
            return try? JSONSerialization.data(withJSONObject: value)
        }
        return ClaudeReply(
            text: text,
            structuredOutput: structured,
            durationMs: object["duration_ms"] as? Int ?? 0,
            costUSD: object["total_cost_usd"] as? Double
        )
    }

    static func classify(_ message: String) -> ClaudeError {
        let lowered = message.lowercased()
        if ["authenticate", "oauth", "log in", "login", "invalid api key", "not logged"].contains(where: lowered.contains) {
            return .notLoggedIn(message)
        }
        if ["usage limit", "rate limit", "limit reached", "quota"].contains(where: lowered.contains) {
            return .usageLimited(message)
        }
        return .failed(message)
    }
}
