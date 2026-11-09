import EventKit
import Foundation
import MorningKit

/// The real service: MorningKit's generator, stores and system checks.
struct LiveBriefingService: BriefingService {
    let paths: MorningPaths

    init(paths: MorningPaths = MorningPaths()) {
        self.paths = paths
    }

    private var store: BriefingStore { BriefingStore(paths: paths) }
    private var checks: TaskCheckStore { TaskCheckStore(paths: paths) }
    private var settingsStore: SettingsStore { SettingsStore(paths: paths) }

    func latest() async -> Briefing? {
        store.latest()
    }

    func briefing(id: String) async -> Briefing? {
        try? store.load(id)
    }

    func summaries() async -> [BriefingSummary] {
        store.summaries()
    }

    func generate(trigger: Briefing.Trigger, skipIfExists: Bool, onEvent: @escaping @Sendable (GenerationEvent) -> Void) async throws -> Briefing {
        // The app has Info.plist usage strings, so it may show the Calendar/Reminders prompts.
        let generator = BriefingGenerator(settings: settingsStore.load(), paths: paths, mayRequestPermissions: true)
        return try await generator.generate(trigger: trigger, skipIfExists: skipIfExists, onEvent: onEvent)
    }

    /// The helper embedded in this app bundle (Contents/MacOS/morning-cli).
    private var bundledHelper: URL? {
        Bundle.main.url(forAuxiliaryExecutable: "morning-cli")
    }

    func setLaunchAgent(installed: Bool, hour: Int, minute: Int) async throws {
        let manager = LaunchAgentManager(paths: paths)
        if installed {
            guard let helper = bundledHelper else { throw CocoaError(.fileNoSuchFile) }
            try await manager.install(executable: helper, hour: hour, minute: minute)
        } else {
            try await manager.uninstall()
        }
    }

    func setHook(installed: Bool) async throws {
        let installer = HookInstaller(paths: paths)
        if installed { try installer.install() } else { try installer.uninstall() }
    }

    func repairLaunchAgentIfNeeded(hour: Int, minute: Int) async {
        let manager = LaunchAgentManager(paths: paths)
        guard manager.isInstalled, let helper = bundledHelper, manager.installedExecutable != helper.path else { return }
        try? await manager.install(executable: helper, hour: hour, minute: minute)
    }

    func news(for briefingID: String) async -> NewsFeed? {
        NewsStore(paths: paths).latest(onOrBefore: briefingID)
    }

    func refreshNews() async throws -> NewsFeed {
        try await NewsGenerator(settings: settingsStore.load(), paths: paths).refresh()
    }

    func newsState() async -> NewsState {
        NewsStore(paths: paths).loadState()
    }

    func saveNewsState(_ state: NewsState) async {
        try? NewsStore(paths: paths).saveState(state)
    }

    func checkedKeys(for briefingID: String) async -> Set<String> {
        checks.checkedKeys(for: briefingID)
    }

    func setChecked(_ checked: Bool, task: GeneratedBriefing.FocusTask, briefingID: String) async {
        try? checks.setChecked(checked, task: task, in: briefingID)
    }

    func loadSettings() async -> MorningSettings {
        settingsStore.load()
    }

    func saveSettings(_ settings: MorningSettings) async throws {
        try settingsStore.save(settings)
    }

    func requestAccess(to kind: CollectorKind) async -> SystemStatus {
        switch kind {
        case .calendar: _ = await EventKitService.shared.ensureAccess(to: .event, mayPrompt: true)
        case .reminders: _ = await EventKitService.shared.ensureAccess(to: .reminder, mayPrompt: true)
        default: break
        }
        return await systemStatus()
    }

    func systemStatus() async -> SystemStatus {
        let settings = settingsStore.load()
        let claude = await ExecutableResolver(paths: paths).resolve("claude", override: settings.claudePath)
        let auth: ClaudeAuthStatus? = if let claude { await ClaudeAuth.status(executable: claude.url) } else { nil }
        let calendarAccess = EventKitService.calendarAccess
        let calendars = calendarAccess.isGranted ? await EventKitService.shared.sources(for: .event) : []

        return SystemStatus(
            launchAgentInstalled: FileManager.default.fileExists(atPath: paths.launchAgentPlist.path),
            hookInstalled: HookInstaller(paths: paths).isInstalled,
            notificationsAllowed: nil,
            claudePath: claude.map { paths.abbreviate($0.url.path) },
            claudeSignedIn: auth?.isLoggedIn,
            calendarAccess: calendarAccess,
            remindersAccess: EventKitService.remindersAccess,
            calendars: calendars,
            briefingCount: store.ids().count
        )
    }
}
