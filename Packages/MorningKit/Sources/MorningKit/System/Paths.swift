import Foundation

/// Every location Morning reads or writes. Injectable `home` keeps tests hermetic.
public struct MorningPaths: Sendable, Hashable {
    public static let bundleIdentifier = "com.barisparlak.Morning"
    public static let launchAgentLabel = "com.barisparlak.Morning.scheduler"

    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home.standardizedFileURL
    }

    // App data
    public var appSupport: URL { home.appending(path: "Library/Application Support/Morning", directoryHint: .isDirectory) }
    public var briefings: URL { appSupport.appending(path: "briefings", directoryHint: .isDirectory) }
    public var settingsFile: URL { appSupport.appending(path: "settings.json") }
    public var stateFile: URL { appSupport.appending(path: "state.json") }
    /// Working directory for headless `claude` runs, so they never mix with real project sessions.
    public var runDirectory: URL { appSupport.appending(path: "run", directoryHint: .isDirectory) }
    public var logs: URL { home.appending(path: "Library/Logs/Morning", directoryHint: .isDirectory) }

    // Hook
    public var morningDirectory: URL { home.appending(path: ".morning", directoryHint: .isDirectory) }
    public var hookLog: URL { morningDirectory.appending(path: "log.jsonl") }
    public var hookScript: URL { morningDirectory.appending(path: "hooks/morning-stop-hook.sh") }

    // Claude Code
    public var claudeDirectory: URL { home.appending(path: ".claude", directoryHint: .isDirectory) }
    public var claudeProjects: URL { claudeDirectory.appending(path: "projects", directoryHint: .isDirectory) }
    public var claudeSettings: URL { claudeDirectory.appending(path: "settings.json") }

    // Scheduling
    public var launchAgentPlist: URL {
        home.appending(path: "Library/LaunchAgents/\(Self.launchAgentLabel).plist")
    }

    /// Expands `~` and makes the path absolute.
    public func expand(_ path: String) -> URL {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home.appending(path: String(path.dropFirst(2))).standardizedFileURL }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    /// `/Users/me/dev/x` → `~/dev/x`, for display and for keeping prompts short.
    public func abbreviate(_ path: String) -> String {
        let homePath = home.path
        if path == homePath { return "~" }
        if path.hasPrefix(homePath + "/") { return "~" + path.dropFirst(homePath.count) }
        return path
    }
}
