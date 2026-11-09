import Foundation
import MorningKit

func runDoctor() async {
    let paths = MorningPaths()
    let settings = SettingsStore(paths: paths).load()
    let resolver = ExecutableResolver(paths: paths)

    print("Morning doctor\n")
    print("Tools")
    var claudeURL: URL?
    for (name, override) in [("claude", settings.claudePath), ("git", settings.gitPath), ("gh", settings.ghPath)] {
        let label = name.padding(toLength: 7, withPad: " ", startingAt: 0)
        guard let resolution = await resolver.resolve(name, override: override) else {
            print("  ✗ \(label) not found" + (override.map { " at override \($0)" } ?? ""))
            continue
        }
        if name == "claude" { claudeURL = resolution.url }
        let version = (try? await Shell.output(resolution.url, ["--version"], timeout: .seconds(10)))?
            .split(whereSeparator: \.isNewline).first.map(String.init) ?? "?"
        print("  ✓ \(label) \(paths.abbreviate(resolution.url.path))  (\(resolution.source.rawValue); \(version))")
    }

    print("\nClaude subscription")
    if let claudeURL {
        print("  \(await claudeLoginStatus(claudeURL))")
    } else {
        print("  ✗ claude not found")
    }
    if ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil {
        print("  ! ANTHROPIC_API_KEY is set here; Morning removes it before calling claude, so the subscription is used.")
    }
    print("  Model: \(settings.claudeModel)")

    print("\nPermissions")
    print("  Calendar   \(EventKitService.calendarAccess.explanation)")
    print("  Reminders  \(EventKitService.remindersAccess.explanation)")

    print("\nState")
    let state = RunStateStore(paths: paths).load()
    let format = Date.FormatStyle(date: .abbreviated, time: .shortened)
    print("  Last briefing window ended: \(state.lastSuccessfulRun?.formatted(format) ?? "never")")
    if let error = state.lastError {
        print("  Last error (\(state.consecutiveFailures)× in a row): \(error.condensedForDisplay)")
    }
    print("  Saved briefings: \(BriefingStore(paths: paths).ids().count)")

    print("\nPaths")
    let fileManager = FileManager.default
    let rows: [(String, URL)] = [
        ("Settings", paths.settingsFile),
        ("Briefings", paths.briefings),
        ("Claude history", paths.claudeProjects),
        ("Claude settings", paths.claudeSettings),
        ("Hook log", paths.hookLog),
        ("LaunchAgent", paths.launchAgentPlist),
    ]
    for (label, url) in rows {
        let mark = fileManager.fileExists(atPath: url.path) ? "✓" : "·"
        print("  \(mark) \(label.padding(toLength: 16, withPad: " ", startingAt: 0)) \(paths.abbreviate(url.path))")
    }

    print("\nRepositories")
    let repos = RepoDiscovery.scan(roots: settings.repoRoots.map(paths.expand), depth: settings.scanDepth)
    print("  \(repos.count) found under \(settings.repoRoots.joined(separator: ", ")) (depth \(settings.scanDepth))")
    for repo in repos.prefix(30) { print("    \(paths.abbreviate(repo.path))") }
}

/// Asks `claude auth status` with the same scrubbed environment real runs use.
func claudeLoginStatus(_ claude: URL) async -> String {
    guard let status = await ClaudeAuth.status(executable: claude) else { return "? couldn't read `claude auth status`" }
    guard status.isLoggedIn else { return "✗ not signed in — run `claude auth login` in Terminal" }
    return "✓ signed in (\([status.method, status.plan].compactMap { $0 }.joined(separator: ", ")))"
}

private extension String {
    var condensedForDisplay: String {
        let collapsed = split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.count > 200 ? String(collapsed.prefix(199)) + "…" : collapsed
    }
}
