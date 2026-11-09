import Foundation
import Testing
@testable import MorningKit

@Suite("Stop hook installer")
struct HookInstallerTests {
    static let existing = """
    {
      "model": "sonnet",
      "attribution": { "commit": "", "pr": "" },
      "hooks": {
        "Stop": [ { "hooks": [ { "type": "command", "command": "/usr/local/bin/notify-done" } ] } ],
        "PreToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "guard.sh" } ] } ]
      }
    }
    """

    func settings(_ home: TemporaryHome) throws -> [String: Any] {
        let data = try Data(contentsOf: home.paths.claudeSettings)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func mergesWithoutTouchingOtherSettings() throws {
        let home = try TemporaryHome()
        try FileManager.default.createDirectory(at: home.paths.claudeDirectory, withIntermediateDirectories: true)
        try Self.existing.write(to: home.paths.claudeSettings, atomically: true, encoding: .utf8)
        let installer = HookInstaller(paths: home.paths)

        let backup = try #require(try installer.install())
        #expect(try String(contentsOf: backup, encoding: .utf8) == Self.existing)
        #expect(installer.isInstalled)

        let merged = try settings(home)
        #expect(merged["model"] as? String == "sonnet")
        #expect((merged["attribution"] as? [String: String])?["commit"] == "")
        let hooks = try #require(merged["hooks"] as? [String: Any])
        #expect((hooks["PreToolUse"] as? [Any])?.count == 1)
        let stopCommands = (hooks["Stop"] as? [Any] ?? []).flatMap(HookInstaller.commands)
        #expect(stopCommands == ["/usr/local/bin/notify-done", home.paths.hookScript.path])

        // Installing twice changes nothing and makes no second backup.
        #expect(try installer.install() == nil)
        #expect((try settings(home)["hooks"] as? [String: Any])?["Stop"] as? [Any] != nil)
        #expect(((try settings(home)["hooks"] as? [String: Any])?["Stop"] as? [Any])?.count == 2)
    }

    @Test func uninstallRemovesOnlyOurEntry() throws {
        let home = try TemporaryHome()
        try FileManager.default.createDirectory(at: home.paths.claudeDirectory, withIntermediateDirectories: true)
        try Self.existing.write(to: home.paths.claudeSettings, atomically: true, encoding: .utf8)
        let installer = HookInstaller(paths: home.paths)
        try installer.install()
        try installer.uninstall()

        #expect(!installer.isInstalled)
        let hooks = try #require(try settings(home)["hooks"] as? [String: Any])
        #expect((hooks["Stop"] as? [Any] ?? []).flatMap(HookInstaller.commands) == ["/usr/local/bin/notify-done"])
        #expect(try installer.uninstall() == nil)
    }

    @Test func createsSettingsWhenMissingAndCleansUpWhenRemoved() throws {
        let home = try TemporaryHome()
        let installer = HookInstaller(paths: home.paths)
        #expect(try installer.install() == nil) // nothing to back up
        #expect(installer.isInstalled)
        try installer.uninstall()
        #expect(try settings(home).isEmpty) // no empty "hooks"/"Stop" left behind
    }

    @Test func refusesToOverwriteBrokenSettings() throws {
        let home = try TemporaryHome()
        try FileManager.default.createDirectory(at: home.paths.claudeDirectory, withIntermediateDirectories: true)
        try "{ \"model\": ".write(to: home.paths.claudeSettings, atomically: true, encoding: .utf8)
        #expect(throws: HookInstaller.HookError.self) { try HookInstaller(paths: home.paths).install() }
        #expect(try String(contentsOf: home.paths.claudeSettings, encoding: .utf8) == "{ \"model\": ")
    }

    @Test func scriptAppendsWhatTheCollectorReads() async throws {
        let home = try TemporaryHome()
        try HookInstaller(paths: home.paths).install()
        let payload = #"{"session_id":"abc","cwd":"/w/app","hook_event_name":"Stop","stop_hook_active":false}"#
        let environment = ["HOME": home.root.path, "PATH": "/usr/bin:/bin"]

        // Always pass the temporary HOME: the script writes to $HOME/.morning.
        let result = try await Shell.run(home.paths.hookScript, environment: environment, input: Data((payload + "\n").utf8), timeout: .seconds(5))
        #expect(result.status == 0)
        // Morning's own headless runs set this marker and must not be logged.
        let skipped = try await Shell.run(home.paths.hookScript, environment: environment.merging(["MORNING_GENERATING": "1"]) { $1 }, input: Data(payload.utf8))
        #expect(skipped.status == 0)

        let log = try Data(contentsOf: home.paths.hookLog)
        let events = SessionLogCollector.parse(log, period: Period(from: .now.addingTimeInterval(-60), to: .now.addingTimeInterval(60)))
        #expect(events.count == 1)
        #expect(events.first?.sessionID == "abc")
        #expect(events.first?.cwd == "/w/app")
    }
}

@Suite("Scheduler")
struct SchedulerTests {
    @Test func writesAValidPlist() async throws {
        let home = try TemporaryHome()
        let manager = LaunchAgentManager(paths: home.paths, usesLaunchctl: false)
        let executable = URL(fileURLWithPath: "/Applications/Morning.app/Contents/MacOS/morning-cli")
        try await manager.install(executable: executable, hour: 6, minute: 45)

        #expect(manager.isInstalled)
        #expect(manager.installedExecutable == executable.path)
        let data = try Data(contentsOf: home.paths.launchAgentPlist)
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["Label"] as? String == MorningPaths.launchAgentLabel)
        #expect(plist["ProgramArguments"] as? [String] == [executable.path, "generate", "--trigger", "scheduled", "--if-needed"])
        #expect(plist["StartCalendarInterval"] as? [String: Int] == ["Hour": 6, "Minute": 45])
        #expect(plist["RunAtLoad"] as? Bool == false)

        let lint = try await Shell.run(URL(fileURLWithPath: "/usr/bin/plutil"), ["-lint", home.paths.launchAgentPlist.path])
        #expect(lint.succeeded)

        try await manager.uninstall()
        #expect(!manager.isInstalled)
    }

    @Test func handoffURLsRoundTrip() {
        #expect(AppHandoff.parse(AppHandoff.generateURL(trigger: .scheduled, ifNeeded: true)) == .generate(trigger: .scheduled, ifNeeded: true))
        #expect(AppHandoff.parse(AppHandoff.readyURL(id: "2026-11-09")) == .ready(id: "2026-11-09"))
        #expect(AppHandoff.parse(URL(string: "morning://today")!) == .today)
        #expect(AppHandoff.parse(URL(string: "https://example.com")!) == nil)
    }
}
