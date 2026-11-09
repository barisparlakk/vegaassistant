import Foundation

/// The per-user LaunchAgent that runs `morning-cli generate` every morning.
///
/// `StartCalendarInterval` jobs that were missed while the Mac slept run as soon as it wakes,
/// so a 07:00 briefing still arrives when the lid is opened at 08:30. (A Mac that was shut down
/// is covered by the app, which catches up on launch.)
public struct LaunchAgentManager: Sendable {
    public enum AgentError: Error, LocalizedError, Sendable {
        case launchctl(String)

        public var errorDescription: String? {
            switch self {
            case let .launchctl(message): "launchctl couldn't load the scheduler: \(message)"
            }
        }
    }

    public let paths: MorningPaths
    /// Off in tests: write and remove the plist without touching the real launchd.
    public var usesLaunchctl: Bool

    public init(paths: MorningPaths = MorningPaths(), usesLaunchctl: Bool = true) {
        self.paths = paths
        self.usesLaunchctl = usesLaunchctl
    }

    static let launchctl = URL(fileURLWithPath: "/bin/launchctl")
    var label: String { MorningPaths.launchAgentLabel }
    var domain: String { "gui/\(getuid())" }

    public var isInstalled: Bool { FileManager.default.fileExists(atPath: paths.launchAgentPlist.path) }

    /// The helper the installed agent points at, if any.
    public var installedExecutable: String? {
        guard let data = try? Data(contentsOf: paths.launchAgentPlist),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String]
        else { return nil }
        return arguments.first
    }

    public func plist(executable: URL, hour: Int, minute: Int) -> [String: Any] {
        [
            "Label": label,
            "ProgramArguments": [executable.path, "generate", "--trigger", "scheduled", "--if-needed"],
            "StartCalendarInterval": ["Hour": hour, "Minute": minute],
            "RunAtLoad": false,
            "ProcessType": "Standard",
            "StandardOutPath": paths.logs.appending(path: "scheduler.log").path,
            "StandardErrorPath": paths.logs.appending(path: "scheduler.log").path,
            // Shows the agent under "Morning" in System Settings › Login Items.
            "AssociatedBundleIdentifiers": [MorningPaths.bundleIdentifier],
        ]
    }

    /// Writes the plist and (re)loads it. Safe to call again, e.g. after the time changes.
    public func install(executable: URL, hour: Int, minute: Int) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: paths.launchAgentPlist.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.logs, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist(executable: executable, hour: hour, minute: minute), format: .xml, options: 0)
        try data.write(to: paths.launchAgentPlist, options: .atomic)

        guard usesLaunchctl else { return }
        await bootout()
        let result = try await Shell.run(Self.launchctl, ["bootstrap", domain, paths.launchAgentPlist.path], timeout: .seconds(15))
        guard result.succeeded else {
            throw AgentError.launchctl(result.errorOutput.nilIfEmpty ?? "exit status \(result.status)")
        }
    }

    public func uninstall() async throws {
        if usesLaunchctl { await bootout() }
        if isInstalled { try FileManager.default.removeItem(at: paths.launchAgentPlist) }
    }

    /// Whether launchd currently has the job loaded.
    public func isLoaded() async -> Bool {
        guard usesLaunchctl else { return isInstalled }
        let result = try? await Shell.run(Self.launchctl, ["print", "\(domain)/\(label)"], timeout: .seconds(10))
        return result?.succeeded ?? false
    }

    private func bootout() async {
        _ = try? await Shell.run(Self.launchctl, ["bootout", "\(domain)/\(label)"], timeout: .seconds(15))
    }
}

/// How the CLI and the app talk: `morning://` URLs opened with `/usr/bin/open`.
public enum AppHandoff {
    public static let scheme = "morning"
    /// Both open the app: `morning://` (scheduler, notifications) and `vega://` (for you).
    public static let schemes: Set<String> = ["morning", "vega"]

    /// Ask the app to generate (used when the scheduled helper lacks Calendar/Reminders access).
    public static func generateURL(trigger: Briefing.Trigger, ifNeeded: Bool) -> URL {
        URL(string: "\(scheme)://generate?trigger=\(trigger.rawValue)&ifNeeded=\(ifNeeded ? 1 : 0)")!
    }

    /// Tell the app a briefing was saved, so it can post the notification.
    public static func readyURL(id: String) -> URL {
        URL(string: "\(scheme)://ready?id=\(id)")!
    }

    /// Opens a URL in the app without bringing it forward (`-g`) and, if it has to launch,
    /// without showing it (`-j`).
    public static func open(_ url: URL) async -> Bool {
        let result = try? await Shell.run(URL(fileURLWithPath: "/usr/bin/open"), ["-g", "-j", url.absoluteString], timeout: .seconds(20))
        return result?.succeeded ?? false
    }

    public enum Request: Equatable, Sendable {
        case generate(trigger: Briefing.Trigger, ifNeeded: Bool)
        case ready(id: String)
        case today
        /// `vega://ask?q=…` — ask Vega a question.
        case ask(String)
    }

    public static func parse(_ url: URL) -> Request? {
        guard let scheme = url.scheme?.lowercased(), schemes.contains(scheme) else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        switch url.host() {
        case "generate":
            return .generate(trigger: value("trigger").flatMap(Briefing.Trigger.init(rawValue:)) ?? .manual, ifNeeded: value("ifNeeded") == "1")
        case "ready":
            return value("id").map { .ready(id: $0) }
        case "today", nil:
            return .today
        case "ask":
            return value("q").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : .ask($0) }
        default:
            return nil
        }
    }
}
