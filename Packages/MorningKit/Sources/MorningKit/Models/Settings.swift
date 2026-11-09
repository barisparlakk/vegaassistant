import Foundation

public enum CollectorKind: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case claudeSessions, sessionLog, git, github, calendar, reminders, notes

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeSessions: "Claude Code sessions"
        case .sessionLog: "Stop-hook log"
        case .git: "Git repositories"
        case .github: "GitHub"
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        case .notes: "TODO.md / NOTES.md"
        }
    }

    public var symbolName: String {
        switch self {
        case .claudeSessions: "sparkles"
        case .sessionLog: "list.bullet.rectangle"
        case .git: "arrow.triangle.branch"
        case .github: "arrow.triangle.pull"
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .notes: "note.text"
        }
    }
}

/// Settings shared by the app and the CLI. Stored as JSON so both processes read the same file.
/// Every key decodes with a default, so older files keep working when fields are added.
public struct MorningSettings: Codable, Sendable, Hashable {
    public var repoRoots: [String]
    public var scanDepth: Int
    public var discoverFromClaudeSessions: Bool
    public var briefingHour: Int
    public var briefingMinute: Int
    public var enabledCollectors: Set<CollectorKind>
    /// Empty means all calendars.
    public var calendarIDs: [String]
    /// Empty means all reminder lists.
    public var reminderListIDs: [String]
    public var claudeModel: String
    public var claudePath: String?
    public var gitPath: String?
    public var ghPath: String?
    public var extraInstructions: String
    public var staleBranchDays: Int
    public var maxLookbackDays: Int
    public var accentColorHex: String?
    /// Optional deadlines per project id (`repo:daybase` → date), shown as `T-18d`.
    public var projectDeadlines: [String: Date]

    public static let `default` = MorningSettings()

    public init(
        repoRoots: [String] = ["~/dev", "~/Developer", "~/Projects", "~/Desktop"],
        scanDepth: Int = 3,
        discoverFromClaudeSessions: Bool = true,
        briefingHour: Int = 7,
        briefingMinute: Int = 0,
        enabledCollectors: Set<CollectorKind> = Set(CollectorKind.allCases),
        calendarIDs: [String] = [],
        reminderListIDs: [String] = [],
        claudeModel: String = "sonnet",
        claudePath: String? = nil,
        gitPath: String? = nil,
        ghPath: String? = nil,
        extraInstructions: String = "",
        staleBranchDays: Int = 14,
        maxLookbackDays: Int = 4,
        accentColorHex: String? = nil,
        projectDeadlines: [String: Date] = [:]
    ) {
        self.repoRoots = repoRoots
        self.scanDepth = scanDepth
        self.discoverFromClaudeSessions = discoverFromClaudeSessions
        self.briefingHour = briefingHour
        self.briefingMinute = briefingMinute
        self.enabledCollectors = enabledCollectors
        self.calendarIDs = calendarIDs
        self.reminderListIDs = reminderListIDs
        self.claudeModel = claudeModel
        self.claudePath = claudePath
        self.gitPath = gitPath
        self.ghPath = ghPath
        self.extraInstructions = extraInstructions
        self.staleBranchDays = staleBranchDays
        self.maxLookbackDays = maxLookbackDays
        self.accentColorHex = accentColorHex
        self.projectDeadlines = projectDeadlines
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MorningSettings.default
        repoRoots = try c.decodeIfPresent([String].self, forKey: .repoRoots) ?? d.repoRoots
        scanDepth = try c.decodeIfPresent(Int.self, forKey: .scanDepth) ?? d.scanDepth
        discoverFromClaudeSessions = try c.decodeIfPresent(Bool.self, forKey: .discoverFromClaudeSessions) ?? d.discoverFromClaudeSessions
        briefingHour = try c.decodeIfPresent(Int.self, forKey: .briefingHour) ?? d.briefingHour
        briefingMinute = try c.decodeIfPresent(Int.self, forKey: .briefingMinute) ?? d.briefingMinute
        // Unknown collector names (from a newer version) are ignored rather than failing the file.
        let rawCollectors = try c.decodeIfPresent([String].self, forKey: .enabledCollectors)
        enabledCollectors = rawCollectors.map { Set($0.compactMap(CollectorKind.init(rawValue:))) } ?? d.enabledCollectors
        calendarIDs = try c.decodeIfPresent([String].self, forKey: .calendarIDs) ?? d.calendarIDs
        reminderListIDs = try c.decodeIfPresent([String].self, forKey: .reminderListIDs) ?? d.reminderListIDs
        claudeModel = try c.decodeIfPresent(String.self, forKey: .claudeModel) ?? d.claudeModel
        claudePath = try c.decodeIfPresent(String.self, forKey: .claudePath)
        gitPath = try c.decodeIfPresent(String.self, forKey: .gitPath)
        ghPath = try c.decodeIfPresent(String.self, forKey: .ghPath)
        extraInstructions = try c.decodeIfPresent(String.self, forKey: .extraInstructions) ?? d.extraInstructions
        staleBranchDays = try c.decodeIfPresent(Int.self, forKey: .staleBranchDays) ?? d.staleBranchDays
        maxLookbackDays = try c.decodeIfPresent(Int.self, forKey: .maxLookbackDays) ?? d.maxLookbackDays
        accentColorHex = try c.decodeIfPresent(String.self, forKey: .accentColorHex)
        projectDeadlines = try c.decodeIfPresent([String: Date].self, forKey: .projectDeadlines) ?? [:]
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(repoRoots, forKey: .repoRoots)
        try c.encode(scanDepth, forKey: .scanDepth)
        try c.encode(discoverFromClaudeSessions, forKey: .discoverFromClaudeSessions)
        try c.encode(briefingHour, forKey: .briefingHour)
        try c.encode(briefingMinute, forKey: .briefingMinute)
        try c.encode(enabledCollectors.map(\.rawValue).sorted(), forKey: .enabledCollectors)
        try c.encode(calendarIDs, forKey: .calendarIDs)
        try c.encode(reminderListIDs, forKey: .reminderListIDs)
        try c.encode(claudeModel, forKey: .claudeModel)
        try c.encodeIfPresent(claudePath, forKey: .claudePath)
        try c.encodeIfPresent(gitPath, forKey: .gitPath)
        try c.encodeIfPresent(ghPath, forKey: .ghPath)
        try c.encode(extraInstructions, forKey: .extraInstructions)
        try c.encode(staleBranchDays, forKey: .staleBranchDays)
        try c.encode(maxLookbackDays, forKey: .maxLookbackDays)
        try c.encodeIfPresent(accentColorHex, forKey: .accentColorHex)
        try c.encode(projectDeadlines, forKey: .projectDeadlines)
    }

    private enum CodingKeys: String, CodingKey {
        case repoRoots, scanDepth, discoverFromClaudeSessions, briefingHour, briefingMinute
        case enabledCollectors, calendarIDs, reminderListIDs, claudeModel, claudePath, gitPath, ghPath
        case extraInstructions, staleBranchDays, maxLookbackDays, accentColorHex, projectDeadlines
    }

    public func isEnabled(_ kind: CollectorKind) -> Bool { enabledCollectors.contains(kind) }
}

public struct SettingsStore: Sendable {
    public let paths: MorningPaths

    public init(paths: MorningPaths = MorningPaths()) {
        self.paths = paths
    }

    public func load() -> MorningSettings {
        guard let data = try? Data(contentsOf: paths.settingsFile),
              let settings = try? JSONCoding.decoder.decode(MorningSettings.self, from: data)
        else { return .default }
        return settings
    }

    public func save(_ settings: MorningSettings) throws {
        try FileManager.default.createDirectory(at: paths.appSupport, withIntermediateDirectories: true)
        let data = try JSONCoding.prettyEncoder.encode(settings)
        try data.write(to: paths.settingsFile, options: .atomic)
    }
}
