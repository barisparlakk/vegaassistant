import Foundation

/// Whether the `claude` CLI is signed in to a subscription, read the same way real runs see it.
public struct ClaudeAuthStatus: Sendable, Hashable {
    public var isLoggedIn: Bool
    public var method: String?
    public var plan: String?

    public var summary: String {
        guard isLoggedIn else { return "Not signed in" }
        return ["Signed in", method, plan].compactMap { $0 }.joined(separator: " · ")
    }
}

public enum ClaudeAuth {
    /// Runs `claude auth status` with the scrubbed environment `ClaudeRunner` uses.
    /// Returns nil when the output can't be read (old CLI, crash, timeout).
    public static func status(executable: URL) async -> ClaudeAuthStatus? {
        let environment = ClaudeRunner.environment(from: ProcessInfo.processInfo.environment, executable: executable)
        guard let result = try? await Shell.run(executable, ["auth", "status"], environment: environment, timeout: .seconds(15)),
              let object = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any]
        else { return nil }
        return ClaudeAuthStatus(
            isLoggedIn: object["loggedIn"] as? Bool == true,
            method: object["authMethod"] as? String,
            plan: object["subscriptionType"] as? String
        )
    }
}
