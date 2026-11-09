import AppKit
import Foundation
import MorningKit
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case today, history, projects, news, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .history: "History"
        case .projects: "Projects"
        case .news: "News"
        case .settings: "Settings"
        }
    }

    /// Shown in the sidebar and command menus.
    var keys: String {
        switch self {
        case .settings: "⌘,"
        default: "⌘\(shortcut.character)"
        }
    }

    static let views: [SidebarItem] = [.today, .history, .projects, .news]

    var symbol: String {
        switch self {
        case .today: "sparkle"
        case .history: "clock.arrow.circlepath"
        case .projects: "square.grid.2x2"
        case .news: "newspaper"
        case .settings: "gearshape"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .today: "1"
        case .history: "2"
        case .projects: "3"
        case .news: "4"
        case .settings: ","
        }
    }
}

/// What the Today screen shows when not generating.
enum TodayState {
    case loading
    case empty
    case loaded(Briefing)
}

@MainActor
@Observable
final class AppModel {
    var selection: SidebarItem = .today
    var today: TodayState = .loading
    var history: [BriefingSummary] = []
    var selectedHistoryID: String?
    var selectedProjectID: String?
    var historyBriefing: Briefing?
    var generation: GenerationProgress?
    var lastError: String?
    var settings = MorningSettings()
    var system = SystemStatus()
    /// Vega's voice and interface sounds.
    let voice = VegaVoice()
    @ObservationIgnored let sounds = VegaSounds()
    /// Shown as an alert in Settings when installing the scheduler or hook fails.
    var settingsError: String?
    @ObservationIgnored private var rescheduleTask: Task<Void, Never>?
    private(set) var checkedKeys: [String: Set<String>] = [:]

    let service: any BriefingService

    init(service: any BriefingService) {
        self.service = service
    }

    /// The user's accent: a stored `#RRGGBB`, or the console amber.
    var accent: Color {
        guard let hex = settings.accentColorHex, hex.hasPrefix("#"), let value = UInt32(hex.dropFirst(), radix: 16) else {
            return DS.Color.defaultAccent
        }
        return Color(hex: value)
    }

    /// Days until a project's deadline, if one is set.
    func daysUntilDeadline(_ projectID: String, now: Date = .now) -> Int? {
        guard let deadline = settings.projectDeadlines[projectID] else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: deadline)).day
    }

    var isGenerating: Bool { generation != nil }

    var currentBriefing: Briefing? {
        if case let .loaded(briefing) = today { briefing } else { nil }
    }

    // MARK: Loading

    func load() async {
        settings = await service.loadSettings()
        await reloadBriefings()
        // Resolving claude and asking for its login takes a second; don't hold the UI for it.
        system = await service.systemStatus()
        system.notificationsAllowed = await notificationStatus()
        await service.repairLaunchAgentIfNeeded(hour: settings.briefingHour, minute: settings.briefingMinute)
        catchUpIfNeeded()
    }

    /// launchd catches up after sleep, but not after a shutdown: if the scheduler is on, the
    /// briefing time has passed and today has no briefing, generate it now.
    func catchUpIfNeeded(now: Date = .now) {
        guard system.launchAgentInstalled, !isGenerating, currentBriefing?.id != Briefing.id(for: now),
              let due = Calendar.current.date(bySettingHour: settings.briefingHour, minute: settings.briefingMinute, second: 0, of: now),
              now >= due
        else { return }
        regenerate(trigger: .scheduled, ifNeeded: true)
    }

    // MARK: URLs

    func handle(_ url: URL) {
        switch AppHandoff.parse(url) {
        case let .generate(trigger, ifNeeded):
            regenerate(trigger: trigger, ifNeeded: ifNeeded)
        case .ready:
            Task {
                await reloadBriefings()
                if let briefing = currentBriefing { await notifyIfBackground(briefing, force: true) }
            }
        case .today:
            selection = .today
            NSApp.activate()
        case nil:
            break
        }
    }

    /// Picks up briefings written by the scheduled run or the CLI while the app was in the background.
    func reloadBriefings() async {
        guard !isGenerating else { return }
        if let briefing = await service.latest() {
            checkedKeys[briefing.id] = await service.checkedKeys(for: briefing.id)
            if currentBriefing?.generatedAt != briefing.generatedAt {
                withAnimation(DS.Motion.standard) { today = .loaded(briefing) }
            }
        } else {
            today = .empty
        }
        history = await service.summaries()
        newsState = await service.newsState()
        await loadNews(for: currentBriefing?.id ?? Briefing.id(for: .now))
    }

    /// True when the newest briefing is from an earlier day.
    var isTodayStale: Bool {
        guard let briefing = currentBriefing else { return false }
        return briefing.id != Briefing.id(for: .now)
    }

    func selectHistory(_ id: String?) async {
        selectedHistoryID = id
        guard let id else {
            historyBriefing = nil
            return
        }
        let briefing = await service.briefing(id: id)
        if let briefing { checkedKeys[briefing.id] = await service.checkedKeys(for: briefing.id) }
        await loadNews(for: id)
        guard selectedHistoryID == id else { return }
        withAnimation(DS.Motion.standard) { historyBriefing = briefing }
    }

    // MARK: Generation

    func regenerate() {
        regenerate(trigger: .manual, ifNeeded: false)
    }

    func regenerate(trigger: Briefing.Trigger, ifNeeded: Bool) {
        guard !isGenerating else { return }
        lastError = nil
        let progress = GenerationProgress()
        withAnimation(DS.Motion.standard) { generation = progress }
        let service = service
        Task {
            do {
                let briefing = try await service.generate(trigger: trigger, skipIfExists: ifNeeded) { event in
                    Task { @MainActor in progress.apply(event) }
                }
                checkedKeys[briefing.id] = await service.checkedKeys(for: briefing.id)
                history = await service.summaries()
                if selectedHistoryID == briefing.id { historyBriefing = briefing }
                await loadNews(for: briefing.id)
                withAnimation(DS.Motion.standard) {
                    today = .loaded(briefing)
                    generation = nil
                }
                sounds.play(.ready)
                await notifyIfBackground(briefing, force: trigger == .scheduled)
                system = await service.systemStatus()
                system.notificationsAllowed = await notificationStatus()
            } catch GeneratorError.alreadyGeneratedToday {
                withAnimation(DS.Motion.standard) { generation = nil }
                await reloadBriefings()
            } catch {
                withAnimation(DS.Motion.standard) {
                    lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    generation = nil
                    if case .loading = today { today = .empty }
                }
            }
        }
    }

    /// Notifies when the briefing arrives while you're elsewhere, or always for scheduled runs.
    private func notifyIfBackground(_ briefing: Briefing, force: Bool) async {
        guard force || !NSApp.isActive else { return }
        await Notifier.shared.briefingReady(briefing)
    }

    private func notificationStatus() async -> Bool? {
        guard service is LiveBriefingService else { return system.notificationsAllowed }
        return await Notifier.shared.authorizationStatus()
    }

    // MARK: News

    var newsFeeds: [String: NewsFeed] = [:]
    var newsState = NewsState()
    var isRefreshingNews = false
    var newsError: String?

    /// The id news is shown for: today's briefing (or today, before the first one).
    var newsID: String { currentBriefing?.id ?? Briefing.id(for: .now) }

    var currentNews: NewsFeed? { newsFeeds[newsID] }

    func refreshNews() {
        guard !isRefreshingNews else { return }
        isRefreshingNews = true
        newsError = nil
        let service = service
        let id = Briefing.id(for: .now)
        Task {
            do {
                let feed = try await service.refreshNews()
                withAnimation(DS.Motion.standard) {
                    newsFeeds[id] = feed
                    if newsID != id { newsFeeds[newsID] = feed }
                }
            } catch {
                newsError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isRefreshingNews = false
        }
    }

    func loadNews(for briefingID: String) async {
        newsFeeds[briefingID] = await service.news(for: briefingID)
    }

    /// Top three for the Today preview: stories tied to a project first, then one per category.
    func newsPreview(for briefingID: String) -> [NewsItem] {
        guard settings.newsEnabled, let feed = newsFeeds[briefingID] else { return [] }
        let related = feed.allItems.filter { $0.relevance != nil }
        let firsts = feed.categories.compactMap(\.items.first)
        return Array((related + firsts + feed.allItems).uniqued(by: \.id).prefix(3))
    }

    func isRead(_ item: NewsItem) -> Bool { newsState.read.contains(item.id) }
    func isSaved(_ item: NewsItem) -> Bool { newsState.saved[item.id] != nil }

    func openNews(_ item: NewsItem) {
        Opener.url(item.url)
        guard !isRead(item) else { return }
        withAnimation(DS.Motion.fast) { _ = newsState.read.insert(item.id) }
        persistNewsState()
    }

    func toggleSaved(_ item: NewsItem) {
        withAnimation(DS.Motion.fast) {
            if isSaved(item) { newsState.saved[item.id] = nil } else { newsState.saved[item.id] = item }
        }
        persistNewsState()
    }

    private func persistNewsState() {
        let state = newsState
        let service = service
        Task { await service.saveNewsState(state) }
    }

    // MARK: Focus blocks & skips (app-local)

    /// A timed focus block on one task, shown in the status bar. Kept in UserDefaults:
    /// it's a UI convenience, not part of the briefing.
    struct FocusBlock: Codable, Equatable {
        var briefingID: String
        var taskKey: String
        var title: String
        var startedAt: Date
    }

    var focusBlock: FocusBlock? = AppModel.storedBlock() {
        didSet { AppModel.store(focusBlock, key: Self.blockKey) }
    }

    private(set) var skippedKeys: [String: Set<String>] = AppModel.storedSkips() {
        didSet { AppModel.store(skippedKeys.mapValues { $0.sorted() }, key: Self.skipsKey) }
    }

    func startBlock(_ task: GeneratedBriefing.FocusTask, in briefingID: String) {
        withAnimation(DS.Motion.fast) {
            if focusBlock?.taskKey == task.checkKey {
                focusBlock = nil
                sounds.play(.focusEnd)
                return
            }
            // Done or skipped tasks don't get a block.
            guard !isChecked(task, in: briefingID), !isSkipped(task, in: briefingID) else { return }
            focusBlock = FocusBlock(briefingID: briefingID, taskKey: task.checkKey, title: task.title, startedAt: .now)
            sounds.play(.focusStart)
        }
    }

    // MARK: Voice

    static let speakOnOpenKey = "vega.speakOnOpen"
    static let mutedKey = "vega.muted"
    private static let spokenKey = "vega.spokenBriefingID"

    var speaksOnOpen: Bool = UserDefaults.standard.object(forKey: AppModel.speakOnOpenKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(speaksOnOpen, forKey: Self.speakOnOpenKey) }
    }

    var isMuted: Bool = UserDefaults.standard.bool(forKey: AppModel.mutedKey) {
        didSet {
            UserDefaults.standard.set(isMuted, forKey: Self.mutedKey)
            if isMuted { voice.stop() }
        }
    }

    /// Vega's script for a briefing, with today's news.
    func script(for briefing: Briefing, isToday: Bool) -> [VegaLine] {
        VegaScript.lines(for: briefing, news: newsPreview(for: briefing.id), isToday: isToday)
    }

    /// Speaks today's briefing the first time it's opened (once per briefing), or shows it.
    /// Later calls for the same briefing (news arriving, a regenerate) refresh the lines
    /// without interrupting her.
    func presentToday(_ briefing: Briefing) {
        let lines = script(for: briefing, isToday: true)
        if presentedBriefingID == briefing.id {
            if voice.status == .idle, voice.lines != lines { voice.speak(lines, silently: true) }
            return
        }
        presentedBriefingID = briefing.id
        let alreadySpoken = UserDefaults.standard.string(forKey: Self.spokenKey) == briefing.id
        if !alreadySpoken, speaksOnOpen, !isMuted {
            UserDefaults.standard.set(briefing.id, forKey: Self.spokenKey)
            sounds.play(.wake)
            voice.speak(lines)
        } else {
            voice.speak(lines, silently: true)
        }
    }

    @ObservationIgnored private var presentedBriefingID: String?

    /// Plays today's briefing from the top (the Replay button).
    func speakAgain(_ briefing: Briefing) {
        if isMuted { isMuted = false }
        sounds.play(.wake)
        voice.speak(script(for: briefing, isToday: true))
    }

    func stopBlock() {
        guard focusBlock != nil else { return }
        withAnimation(DS.Motion.fast) { focusBlock = nil }
        sounds.play(.focusEnd)
    }

    func isSkipped(_ task: GeneratedBriefing.FocusTask, in briefingID: String) -> Bool {
        skippedKeys[briefingID]?.contains(task.checkKey) ?? false
    }

    func toggleSkip(_ task: GeneratedBriefing.FocusTask, in briefingID: String) {
        withAnimation(DS.Motion.fast) {
            if isSkipped(task, in: briefingID) {
                skippedKeys[briefingID]?.remove(task.checkKey)
            } else {
                skippedKeys[briefingID, default: []].insert(task.checkKey)
                if focusBlock?.taskKey == task.checkKey { focusBlock = nil }
            }
        }
    }

    private static let blockKey = "focusBlock"
    private static let skipsKey = "skippedTasks"

    private static func storedBlock() -> FocusBlock? {
        UserDefaults.standard.data(forKey: blockKey).flatMap { try? JSONDecoder().decode(FocusBlock.self, from: $0) }
    }

    private static func storedSkips() -> [String: Set<String>] {
        guard let data = UserDefaults.standard.data(forKey: skipsKey),
              let value = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        return value.mapValues(Set.init)
    }

    private static func store(_ value: some Encodable, key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }

    // MARK: Tasks

    func isChecked(_ task: GeneratedBriefing.FocusTask, in briefingID: String) -> Bool {
        checkedKeys[briefingID]?.contains(task.checkKey) ?? false
    }

    func toggle(_ task: GeneratedBriefing.FocusTask, in briefingID: String) {
        let checked = !isChecked(task, in: briefingID)
        if checked { sounds.play(.done) }
        withAnimation(DS.Motion.fast) {
            if checked {
                checkedKeys[briefingID, default: []].insert(task.checkKey)
            } else {
                checkedKeys[briefingID]?.remove(task.checkKey)
            }
        }
        let service = service
        Task { await service.setChecked(checked, task: task, briefingID: briefingID) }
    }

    // MARK: Settings

    func updateSettings(_ change: (inout MorningSettings) -> Void) {
        change(&settings)
        let snapshot = settings
        let service = service
        Task { try? await service.saveSettings(snapshot) }
    }
}

/// Installation and permission state shown in Settings.
struct SystemStatus: Sendable {
    var launchAgentInstalled = false
    var hookInstalled = false
    var notificationsAllowed: Bool?
    var claudePath: String?
    var claudeSignedIn: Bool?
    var calendarAccess: EventKitAccess = .notDetermined
    var remindersAccess: EventKitAccess = .notDetermined
    var calendars: [EventKitSource] = []
    var briefingCount = 0

    static let preview = SystemStatus(
        launchAgentInstalled: true,
        hookInstalled: false,
        notificationsAllowed: true,
        claudePath: "~/.local/bin/claude",
        claudeSignedIn: true,
        calendarAccess: .granted,
        remindersAccess: .notDetermined,
        calendars: [
            EventKitSource(id: "work", title: "Work", account: "iCloud", colorHex: "#3B82F6"),
            EventKitSource(id: "personal", title: "Personal", account: "iCloud", colorHex: "#F59E0B"),
            EventKitSource(id: "projects", title: "Projects", account: "iCloud", colorHex: "#8E6CEF"),
            EventKitSource(id: "holidays", title: "Holidays in Türkiye", account: "Subscribed", colorHex: "#10B981"),
        ],
        briefingCount: 10
    )
}

extension AppModel {
    // Wired to the real system in milestones (d) and (e).
    func setLaunchAgentInstalled(_ installed: Bool) {
        let service = service
        let (hour, minute) = (settings.briefingHour, settings.briefingMinute)
        Task {
            do {
                try await service.setLaunchAgent(installed: installed, hour: hour, minute: minute)
                // The scheduled run notifies, so ask for permission when it's turned on.
                if installed { _ = await Notifier.shared.requestAuthorization() }
            } catch {
                settingsError = error.localizedDescription
            }
            await refreshStatus()
        }
    }

    func setHookInstalled(_ installed: Bool) {
        let service = service
        Task {
            do {
                try await service.setHook(installed: installed)
            } catch {
                settingsError = error.localizedDescription
            }
            await refreshStatus()
        }
    }

    func requestNotifications() {
        Task {
            if await Notifier.shared.authorizationStatus() == false {
                Opener.url("x-apple.systempreferences:com.apple.Notifications-Settings.extension")
            } else {
                _ = await Notifier.shared.requestAuthorization()
            }
            await refreshStatus()
        }
    }

    /// Re-installs the scheduler after the briefing time changes (debounced while the picker moves).
    func briefingTimeChanged() {
        guard system.launchAgentInstalled else { return }
        rescheduleTask?.cancel()
        rescheduleTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            setLaunchAgentInstalled(true)
        }
    }

    private func refreshStatus() async {
        var status = await service.systemStatus()
        status.notificationsAllowed = await notificationStatus()
        withAnimation(DS.Motion.fast) { system = status }
    }

    func requestCalendarAccess() { requestAccess(.calendar) }

    func requestRemindersAccess() { requestAccess(.reminders) }

    private func requestAccess(_ kind: CollectorKind) {
        let service = service
        Task {
            var status = await service.requestAccess(to: kind)
            status.notificationsAllowed = system.notificationsAllowed
            withAnimation(DS.Motion.fast) { system = status }
        }
    }

    /// Re-reads status after a settings change that affects it (e.g. a new claude path).
    func refreshSystemStatus() {
        Task { await refreshStatus() }
    }

    func openDataFolder() {
        Opener.finder(MorningPaths().briefings.path)
    }
}

extension AppModel {
    /// A model already loaded with sample data, for previews.
    static func preview(_ scenario: MockBriefingService.Scenario = .normal, generating: Bool = false) -> AppModel {
        let model = AppModel(service: MockBriefingService(scenario: scenario))
        switch scenario {
        case .empty: model.today = .empty
        case .fallback: model.today = .loaded(MockData.fallbackBriefing())
        case .normal, .failing: model.today = .loaded(MockData.briefing())
        }
        if scenario == .failing {
            model.lastError = ClaudeError.notLoggedIn("OAuth session expired").errorDescription
        }
        model.history = scenario == .empty ? [] : MockData.summaries()
        model.checkedKeys[MockData.briefing().id] = [MockData.generated.focus.tasks[1].checkKey]
        if generating { model.generation = .preview }
        model.system = .preview
        if scenario != .empty {
            model.newsFeeds[MockData.briefing().id] = MockData.news()
            model.newsState = NewsState(read: ["n3"])
        }
        return model
    }
}
