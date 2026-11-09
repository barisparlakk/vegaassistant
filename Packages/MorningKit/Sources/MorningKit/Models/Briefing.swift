import Foundation

/// A stored briefing: the collected facts plus what the model wrote about them.
/// Saved as `briefings/YYYY-MM-DD.json`.
public struct Briefing: Codable, Sendable, Hashable, Identifiable {
    public static let currentSchemaVersion = 1

    public enum Trigger: String, Codable, Sendable { case scheduled, manual }

    public enum Content: Sendable, Hashable {
        case structured(GeneratedBriefing)
        /// Shown when the model's answer couldn't be validated twice in a row.
        case markdown(String)

        public var structured: GeneratedBriefing? {
            if case let .structured(briefing) = self { briefing } else { nil }
        }
    }

    public var schemaVersion: Int
    /// Local date, `YYYY-MM-DD`.
    public var id: String
    public var generatedAt: Date
    public var trigger: Trigger
    public var model: String
    public var durationMs: Int
    public var attempts: Int
    public var facts: BriefingFacts
    public var content: Content
    public var diagnostics: [CollectorReport]
    /// Fixes the validator applied (unknown references dropped, estimates clamped…).
    public var repairs: [String]

    public init(
        id: String,
        generatedAt: Date,
        trigger: Trigger,
        model: String,
        durationMs: Int,
        attempts: Int,
        facts: BriefingFacts,
        content: Content,
        diagnostics: [CollectorReport],
        repairs: [String] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.generatedAt = generatedAt
        self.trigger = trigger
        self.model = model
        self.durationMs = durationMs
        self.attempts = attempts
        self.facts = facts
        self.content = content
        self.diagnostics = diagnostics
        self.repairs = repairs
    }

    public var structured: GeneratedBriefing? { content.structured }

    /// The `YYYY-MM-DD` id for the local day containing `date`.
    public static func id(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The local midnight a briefing id stands for.
    public static func date(forID id: String, calendar: Calendar = .current) -> Date? {
        let parts = id.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

extension Briefing.Content: Codable {
    private enum CodingKeys: String, CodingKey { case kind, briefing, text }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "structured": self = .structured(try container.decode(GeneratedBriefing.self, forKey: .briefing))
        default: self = .markdown(try container.decode(String.self, forKey: .text))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .structured(briefing):
            try container.encode("structured", forKey: .kind)
            try container.encode(briefing, forKey: .briefing)
        case let .markdown(text):
            try container.encode("markdown", forKey: .kind)
            try container.encode(text, forKey: .text)
        }
    }
}

// MARK: - Model output

public typealias Priority = Severity

/// Exactly what the model returns (see `BriefingSchema`). Facts are referenced by id only.
public struct GeneratedBriefing: Codable, Sendable, Hashable {
    public var headline: String
    public var focus: Focus
    public var sections: [Section]
    public var nextTasks: [NextTask]

    public init(headline: String, focus: Focus, sections: [Section] = [], nextTasks: [NextTask] = []) {
        self.headline = headline
        self.focus = focus
        self.sections = sections
        self.nextTasks = nextTasks
    }

    public func section(_ kind: Section.Kind) -> Section? { sections.first { $0.kind == kind } }

    public struct Focus: Codable, Sendable, Hashable {
        public enum Confidence: String, Codable, Sendable { case high, medium, low }

        public var projectID: String
        public var reason: String
        public var confidence: Confidence
        public var tasks: [FocusTask]

        public init(projectID: String, reason: String, confidence: Confidence, tasks: [FocusTask]) {
            self.projectID = projectID
            self.reason = reason
            self.confidence = confidence
            self.tasks = tasks
        }

        enum CodingKeys: String, CodingKey {
            case projectID = "projectId", reason, confidence, tasks
        }
    }

    public struct FocusTask: Codable, Sendable, Hashable, Identifiable {
        /// Assigned by the validator (`t1`…), not by the model.
        public var id: String
        public var title: String
        public var detail: String
        public var estimateMinutes: Int
        public var refs: [String]

        public init(id: String = "", title: String, detail: String, estimateMinutes: Int, refs: [String] = []) {
            self.id = id
            self.title = title
            self.detail = detail
            self.estimateMinutes = estimateMinutes
            self.refs = refs
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
            title = try c.decode(String.self, forKey: .title)
            detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
            estimateMinutes = try c.decodeIfPresent(Int.self, forKey: .estimateMinutes) ?? 30
            refs = try c.decodeIfPresent([String].self, forKey: .refs) ?? []
        }

        /// Stable across regenerations of the same day, so a checked task stays checked
        /// when the model proposes it again.
        public var checkKey: String {
            title.lowercased().filter { $0.isLetter || $0.isNumber }
        }
    }

    public struct Section: Codable, Sendable, Hashable, Identifiable {
        public enum Kind: String, Codable, Sendable, CaseIterable {
            case overnight, agenda, attention, notes, other

            public init(from decoder: any Decoder) throws {
                let raw = try decoder.singleValueContainer().decode(String.self)
                self = Kind(rawValue: raw) ?? .other
            }
        }

        public var kind: Kind
        public var title: String
        public var summary: String?
        public var items: [Item]

        public var id: Kind { kind }

        public init(kind: Kind, title: String, summary: String? = nil, items: [Item]) {
            self.kind = kind
            self.title = title
            self.summary = summary
            self.items = items
        }
    }

    public struct Item: Codable, Sendable, Hashable {
        public var title: String
        public var detail: String?
        public var priority: Priority
        public var projectID: String?
        public var refs: [String]
        public var estimateMinutes: Int?

        public init(title: String, detail: String? = nil, priority: Priority = .medium, projectID: String? = nil, refs: [String] = [], estimateMinutes: Int? = nil) {
            self.title = title
            self.detail = detail
            self.priority = priority
            self.projectID = projectID
            self.refs = refs
            self.estimateMinutes = estimateMinutes
        }

        enum CodingKeys: String, CodingKey {
            case title, detail, priority, projectID = "projectId", refs, estimateMinutes
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = try c.decode(String.self, forKey: .title)
            detail = try c.decodeIfPresent(String.self, forKey: .detail)
            priority = (try? c.decodeIfPresent(Priority.self, forKey: .priority)) ?? .medium
            projectID = try c.decodeIfPresent(String.self, forKey: .projectID)
            refs = try c.decodeIfPresent([String].self, forKey: .refs) ?? []
            estimateMinutes = try c.decodeIfPresent(Int.self, forKey: .estimateMinutes)
        }
    }

    public struct NextTask: Codable, Sendable, Hashable {
        public var title: String
        public var projectID: String
        public var priority: Priority
        public var estimateMinutes: Int
        public var reason: String

        public init(title: String, projectID: String, priority: Priority, estimateMinutes: Int, reason: String) {
            self.title = title
            self.projectID = projectID
            self.priority = priority
            self.estimateMinutes = estimateMinutes
            self.reason = reason
        }

        enum CodingKeys: String, CodingKey {
            case title, projectID = "projectId", priority, estimateMinutes, reason
        }
    }
}
