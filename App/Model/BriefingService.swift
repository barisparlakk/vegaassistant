import Foundation
import MorningKit

/// Everything the UI needs from the outside world. `MockBriefingService` drives previews
/// and demo mode; the live implementation wraps MorningKit's generator and stores.
protocol BriefingService: Sendable {
    func latest() async -> Briefing?
    func briefing(id: String) async -> Briefing?
    func summaries() async -> [BriefingSummary]
    func generate(trigger: Briefing.Trigger, skipIfExists: Bool, onEvent: @escaping @Sendable (GenerationEvent) -> Void) async throws -> Briefing
    func checkedKeys(for briefingID: String) async -> Set<String>
    func setChecked(_ checked: Bool, task: GeneratedBriefing.FocusTask, briefingID: String) async
    func loadSettings() async -> MorningSettings
    func saveSettings(_ settings: MorningSettings) async throws
    func systemStatus() async -> SystemStatus
    /// Shows the system permission prompt if needed, then returns fresh status.
    func requestAccess(to kind: CollectorKind) async -> SystemStatus
    func setLaunchAgent(installed: Bool, hour: Int, minute: Int) async throws
    func setHook(installed: Bool) async throws
    /// Re-points the scheduler at this copy of the app if it was moved.
    func repairLaunchAgentIfNeeded(hour: Int, minute: Int) async
    /// The news feed for a day (or the newest one before it).
    func news(for briefingID: String) async -> NewsFeed?
    func newsState() async -> NewsState
    func saveNewsState(_ state: NewsState) async
    /// Runs the news search now (one web-search run) and saves it as today's feed.
    func refreshNews() async throws -> NewsFeed
    /// Answers a question about the day (one claude run).
    func ask(_ question: VegaQuestion) async throws -> VegaAnswer
}

/// In-memory service with realistic data and a paced fake generation run.
actor MockBriefingService: BriefingService {
    enum Scenario: Sendable { case normal, empty, failing, fallback }

    private var scenario: Scenario
    private var current: Briefing?
    private var checks: [String: Set<String>] = [:]
    private var settings = MorningSettings()
    private var status = SystemStatus.preview

    init(scenario: Scenario = .normal) {
        self.scenario = scenario
        switch scenario {
        case .normal, .failing: current = MockData.briefing()
        case .fallback: current = MockData.fallbackBriefing()
        case .empty: current = nil
        }
        if let current { checks[current.id] = [MockData.generated.focus.tasks[1].checkKey] }
    }

    func latest() async -> Briefing? { current }

    func briefing(id: String) async -> Briefing? {
        guard scenario != .empty else { return nil }
        // Every history day renders the same sample content under its own date.
        var briefing = MockData.briefing()
        if let summary = MockData.summaries().first(where: { $0.id == id }) {
            briefing.id = id
            briefing.generatedAt = summary.generatedAt
            briefing.trigger = summary.trigger
            if summary.isFallback { briefing.content = MockData.fallbackBriefing().content }
        }
        return briefing
    }

    func summaries() async -> [BriefingSummary] {
        scenario == .empty ? [] : MockData.summaries()
    }

    func generate(trigger: Briefing.Trigger, skipIfExists: Bool, onEvent: @escaping @Sendable (GenerationEvent) -> Void) async throws -> Briefing {
        let order: [CollectorKind] = [.claudeSessions, .sessionLog, .git, .github, .notes, .calendar, .reminders]
        for kind in order { onEvent(.collecting(.started(kind))) }
        for (index, kind) in order.enumerated() {
            try await Task.sleep(for: .milliseconds(220 + index * 90))
            let skipped = scenario == .empty && kind == .sessionLog
            onEvent(.collecting(.finished(CollectorReport(kind: kind, status: skipped ? .skipped : .ok, durationMs: 200, itemCount: 3))))
        }
        onEvent(.collected(projects: 7, sessions: 4, commits: 10, events: 5))
        onEvent(.askingClaude(attempt: 1))
        try await Task.sleep(for: .seconds(2.4))
        if scenario == .failing {
            throw ClaudeError.notLoggedIn("Failed to authenticate: OAuth session expired and could not be refreshed")
        }
        var briefing = MockData.briefing()
        briefing.generatedAt = .now
        briefing.trigger = trigger
        current = briefing
        onEvent(.saved(briefing))
        return briefing
    }

    func checkedKeys(for briefingID: String) async -> Set<String> { checks[briefingID] ?? [] }

    func setChecked(_ checked: Bool, task: GeneratedBriefing.FocusTask, briefingID: String) async {
        if checked { checks[briefingID, default: []].insert(task.checkKey) } else { checks[briefingID]?.remove(task.checkKey) }
    }

    func loadSettings() async -> MorningSettings { settings }

    func saveSettings(_ settings: MorningSettings) async throws { self.settings = settings }

    func systemStatus() async -> SystemStatus { status }

    func setLaunchAgent(installed: Bool, hour: Int, minute: Int) async throws {
        status.launchAgentInstalled = installed
    }

    func setHook(installed: Bool) async throws {
        status.hookInstalled = installed
    }

    func repairLaunchAgentIfNeeded(hour: Int, minute: Int) async {}

    private var news = NewsState(read: ["n3"])

    func news(for briefingID: String) async -> NewsFeed? {
        scenario == .empty ? nil : MockData.news()
    }

    func newsState() async -> NewsState { news }

    func saveNewsState(_ state: NewsState) async { news = state }

    func refreshNews() async throws -> NewsFeed {
        try await Task.sleep(for: .seconds(1.5))
        return MockData.news()
    }

    func ask(_ question: VegaQuestion) async throws -> VegaAnswer {
        try await Task.sleep(for: .seconds(1.2))
        let project = question.briefing?.facts.projects.first
        return VegaAnswer(
            answer: "Just the push: four commits are only on your Mac. Everything else is clean.",
            actions: project.map { [VegaAction(kind: .openTerminal, label: "Open Terminal", target: $0.id)] } ?? []
        )
    }

    func requestAccess(to kind: CollectorKind) async -> SystemStatus {
        if kind == .calendar { status.calendarAccess = .granted }
        if kind == .reminders { status.remindersAccess = .granted }
        return status
    }
}
