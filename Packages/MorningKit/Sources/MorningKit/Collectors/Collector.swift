import Foundation

/// Everything a collector may need. Built once per run by `CollectionPipeline`.
public struct CollectionContext: Sendable {
    public var period: Period
    public var settings: MorningSettings
    public var paths: MorningPaths
    public var tools: Toolbox
    /// Projects known so far (repos found under the roots and from session folders).
    public var projects: [DiscoveredProject]
    /// Whether a collector may show a system permission prompt.
    public var mayRequestPermissions: Bool
    public var calendar: Calendar

    public init(
        period: Period,
        settings: MorningSettings,
        paths: MorningPaths,
        tools: Toolbox,
        projects: [DiscoveredProject] = [],
        mayRequestPermissions: Bool = false,
        calendar: Calendar = .current
    ) {
        self.period = period
        self.settings = settings
        self.paths = paths
        self.tools = tools
        self.projects = projects
        self.mayRequestPermissions = mayRequestPermissions
        self.calendar = calendar
    }

    public var now: Date { period.to }

    /// Local day containing `now`.
    public var today: DateInterval {
        calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: now, duration: 86_400)
    }
}

/// What one collector produced, plus non-fatal problems (e.g. one repo out of ten failed).
public struct CollectorOutput: Sendable {
    public var facts: BriefingFacts
    public var warnings: [String]

    public init(facts: BriefingFacts, warnings: [String] = []) {
        self.facts = facts
        self.warnings = warnings
    }
}

/// A source of facts. Collectors never throw for partial problems: they return what they
/// could gather plus warnings. Throwing `CollectorSkipped` means "not available here";
/// any other error means "broken".
public protocol Collector: Sendable {
    var kind: CollectorKind { get }
    func collect(_ context: CollectionContext) async throws -> CollectorOutput
}

extension BriefingFacts {
    /// An empty fragment for collectors to fill in.
    static func fragment(_ context: CollectionContext) -> BriefingFacts {
        BriefingFacts(period: context.period, collectedAt: context.now)
    }

    /// Rough count of what a fragment contains, for reports.
    var itemCount: Int {
        projects.count + sessions.count + hookEvents.count + commits.count + events.count
            + reminders.count + github.authoredPRs.count + github.reviewRequests.count
            + github.assignedIssues.count + notes.count
    }
}
