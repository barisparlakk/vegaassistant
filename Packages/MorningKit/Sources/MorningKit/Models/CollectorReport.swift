import Foundation

/// How a single collector fared. Stored with each briefing and shown in the UI,
/// so a failing source is visible instead of silently missing.
public struct CollectorReport: Codable, Sendable, Hashable, Identifiable {
    public enum Status: String, Codable, Sendable {
        case ok, skipped, failed
    }

    public var kind: CollectorKind
    public var status: Status
    public var durationMs: Int
    public var itemCount: Int
    public var message: String?

    public var id: CollectorKind { kind }

    public init(kind: CollectorKind, status: Status, durationMs: Int = 0, itemCount: Int = 0, message: String? = nil) {
        self.kind = kind
        self.status = status
        self.durationMs = durationMs
        self.itemCount = itemCount
        self.message = message
    }
}

/// Thrown by a collector to say "not available here" rather than "broken".
public struct CollectorSkipped: Error, Sendable, LocalizedError {
    public let reason: String
    public init(_ reason: String) { self.reason = reason }
    public var errorDescription: String? { reason }
}
