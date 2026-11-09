import Foundation

/// Installs the Claude Code Stop hook that appends to `~/.morning/log.jsonl`.
///
/// The hook is a tiny POSIX shell script with no dependencies. It always exits 0 so it can
/// never block or fail a Claude Code session, and it ignores Morning's own headless runs.
/// `~/.claude/settings.json` is edited conservatively: backed up first, our entry added or
/// removed, everything else left as it was, and an unreadable file is never overwritten.
public struct HookInstaller: Sendable {
    public enum HookError: Error, LocalizedError, Sendable {
        case unreadableSettings(String)

        public var errorDescription: String? {
            switch self {
            case let .unreadableSettings(reason):
                "~/.claude/settings.json isn't valid JSON, so Morning left it untouched (\(reason)). Fix it, or add the hook by hand."
            }
        }
    }

    public let paths: MorningPaths

    public init(paths: MorningPaths = MorningPaths()) {
        self.paths = paths
    }

    static let marker = "morning-stop-hook"

    public static let script = """
    #!/bin/sh
    # Morning — Claude Code Stop hook.
    # Appends {"ts": <UTC time>, "event": <hook JSON from stdin>} to ~/.morning/log.jsonl.
    # Never fails and never blocks the session.
    [ "$MORNING_GENERATING" = "1" ] && exit 0
    dir="$HOME/.morning"
    mkdir -p "$dir" 2>/dev/null || exit 0
    payload=$(cat | tr -d '\\n')
    [ -n "$payload" ] || exit 0
    printf '{"ts":"%s","event":%s}\\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$payload" >> "$dir/log.jsonl" 2>/dev/null
    exit 0

    """

    /// The `settings.json` fragment, for people who prefer to add it themselves.
    public var settingsSnippet: String {
        """
        {
          "hooks": {
            "Stop": [
              { "hooks": [ { "type": "command", "command": "\(paths.hookScript.path)" } ] }
            ]
          }
        }
        """
    }

    public var isInstalled: Bool {
        guard let settings = try? readSettings() else { return false }
        return Self.containsOurHook(settings)
    }

    /// Writes the script and merges the hook into Claude Code's settings. Idempotent.
    /// Returns the backup it made, if there was a settings file to back up.
    @discardableResult
    public func install() throws -> URL? {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: paths.hookScript.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.script.write(to: paths.hookScript, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: paths.hookScript.path)

        var settings = try readSettings() ?? [:]
        guard !Self.containsOurHook(settings, command: paths.hookScript.path) else { return nil }
        let backup = try backupSettings()
        settings = Self.removingOurHook(from: settings) // drops entries pointing at an old path
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var stop = hooks["Stop"] as? [Any] ?? []
        stop.append(["hooks": [["type": "command", "command": paths.hookScript.path]]])
        hooks["Stop"] = stop
        settings["hooks"] = hooks
        try writeSettings(settings)
        return backup
    }

    /// Removes our entry (and only ours). Leaves the script in place harmlessly.
    @discardableResult
    public func uninstall() throws -> URL? {
        guard let settings = try readSettings(), Self.containsOurHook(settings) else { return nil }
        let backup = try backupSettings()
        try writeSettings(Self.removingOurHook(from: settings))
        return backup
    }

    // MARK: - Settings file

    func readSettings() throws -> [String: Any]? {
        guard let data = try? Data(contentsOf: paths.claudeSettings) else { return nil }
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x09 || $0 == 0x0D }) { return [:] }
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw HookError.unreadableSettings("top level isn't an object")
            }
            return object
        } catch let error as HookError {
            throw error
        } catch {
            throw HookError.unreadableSettings(error.localizedDescription)
        }
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        try FileManager.default.createDirectory(at: paths.claudeDirectory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: paths.claudeSettings, options: .atomic)
    }

    private func backupSettings() throws -> URL? {
        guard FileManager.default.fileExists(atPath: paths.claudeSettings.path) else { return nil }
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted).dateSeparator(.omitted))
        let backup = paths.claudeDirectory.appending(path: "settings.json.morning-backup-\(stamp)")
        try? FileManager.default.removeItem(at: backup)
        try FileManager.default.copyItem(at: paths.claudeSettings, to: backup)
        return backup
    }

    // MARK: - Pure helpers (tested)

    static func commands(in entry: Any) -> [String] {
        guard let group = entry as? [String: Any], let hooks = group["hooks"] as? [Any] else { return [] }
        return hooks.compactMap { ($0 as? [String: Any])?["command"] as? String }
    }

    static func containsOurHook(_ settings: [String: Any], command: String? = nil) -> Bool {
        let stop = (settings["hooks"] as? [String: Any])?["Stop"] as? [Any] ?? []
        return stop.contains { entry in
            commands(in: entry).contains { existing in
                if let command { existing == command } else { existing.contains(marker) }
            }
        }
    }

    static func removingOurHook(from settings: [String: Any]) -> [String: Any] {
        var settings = settings
        guard var hooks = settings["hooks"] as? [String: Any], let stop = hooks["Stop"] as? [Any] else { return settings }
        let kept = stop.compactMap { entry -> Any? in
            guard var group = entry as? [String: Any], let inner = group["hooks"] as? [Any] else { return entry }
            let remaining = inner.filter { !((($0 as? [String: Any])?["command"] as? String)?.contains(marker) ?? false) }
            if remaining.isEmpty { return nil }
            group["hooks"] = remaining
            return group
        }
        if kept.isEmpty { hooks.removeValue(forKey: "Stop") } else { hooks["Stop"] = kept }
        if hooks.isEmpty { settings.removeValue(forKey: "hooks") } else { settings["hooks"] = hooks }
        return settings
    }
}
