import CoreGraphics
import EventKit
import Foundation

public enum EventKitAccess: String, Sendable, Codable {
    case granted, notDetermined, denied, restricted, writeOnly

    public var isGranted: Bool { self == .granted }

    public var explanation: String {
        switch self {
        case .granted: "Access granted"
        case .notDetermined: "Not requested yet"
        case .denied: "Denied — enable it in System Settings › Privacy & Security"
        case .restricted: "Restricted by a device policy"
        case .writeOnly: "Only write access granted — full access is needed to read"
        }
    }
}

public struct EventKitSource: Sendable, Hashable, Identifiable, Codable {
    public var id: String
    public var title: String
    public var account: String
    public var colorHex: String?

    public init(id: String, title: String, account: String, colorHex: String? = nil) {
        self.id = id
        self.title = title
        self.account = account
        self.colorHex = colorHex
    }
}

/// Owns the single `EKEventStore` for the process. EventKit objects never leave the actor:
/// they're mapped to Sendable facts inside it.
public actor EventKitService {
    public static let shared = EventKitService()

    private let store = EKEventStore()

    public static var calendarAccess: EventKitAccess { access(for: .event) }
    public static var remindersAccess: EventKitAccess { access(for: .reminder) }

    public static func access(for type: EKEntityType) -> EventKitAccess {
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        case .writeOnly: .writeOnly
        @unknown default: .denied
        }
    }

    /// The process must declare a usage string, or macOS terminates it on request.
    static func canPrompt(for type: EKEntityType) -> Bool {
        let key = type == .event ? "NSCalendarsFullAccessUsageDescription" : "NSRemindersFullAccessUsageDescription"
        return Bundle.main.object(forInfoDictionaryKey: key) != nil
    }

    /// Returns the current access, asking the user first if allowed and not yet decided.
    public func ensureAccess(to type: EKEntityType, mayPrompt: Bool) async -> EventKitAccess {
        let current = Self.access(for: type)
        guard current == .notDetermined, mayPrompt, Self.canPrompt(for: type) else { return current }
        let granted: Bool = await withCheckedContinuation { continuation in
            let completion: @Sendable (Bool, (any Error)?) -> Void = { granted, _ in
                continuation.resume(returning: granted)
            }
            if type == .event {
                store.requestFullAccessToEvents(completion: completion)
            } else {
                store.requestFullAccessToReminders(completion: completion)
            }
        }
        return granted ? .granted : Self.access(for: type)
    }

    public func sources(for type: EKEntityType) -> [EventKitSource] {
        store.calendars(for: type).map { calendar in
            EventKitSource(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                account: calendar.source?.title ?? "",
                colorHex: calendar.cgColor.flatMap(Self.hex)
            )
        }
        .sorted { ($0.account, $0.title) < ($1.account, $1.title) }
    }

    func events(in interval: DateInterval, calendarIDs: [String]) -> [EventFact] {
        let calendars = selectedCalendars(for: .event, ids: calendarIDs)
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: calendars)
        return store.events(matching: predicate)
            .filter { $0.status != .canceled && !Self.isDeclined($0) }
            .map { event in
                EventFact(
                    id: "event:\(event.calendarItemIdentifier.prefix(12))-\(Int(event.startDate.timeIntervalSince1970))",
                    title: event.title?.nilIfEmpty ?? "Untitled event",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    calendar: event.calendar?.title ?? "",
                    colorHex: event.calendar?.cgColor.flatMap(Self.hex),
                    location: event.location?.nilIfEmpty,
                    url: event.url?.absoluteString ?? Self.meetingLink(in: event),
                    notes: event.notes?.nilIfEmpty?.condensed(limit: 240),
                    attendeeCount: event.attendees?.count ?? 0
                )
            }
            .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
    }

    func reminders(dueBy end: Date, now: Date, listIDs: [String]) async -> [ReminderFact] {
        let calendars = selectedCalendars(for: .reminder, ids: listIDs)
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
        let facts: [ReminderFact] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let mapped = (reminders ?? []).compactMap { reminder -> ReminderFact? in
                    let due = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
                    // Due today or overdue, or undated but marked important.
                    let relevant = due.map { $0 <= end } ?? (1...4).contains(reminder.priority)
                    guard relevant else { return nil }
                    return ReminderFact(
                        id: "reminder:\(reminder.calendarItemIdentifier.prefix(12))",
                        title: reminder.title?.nilIfEmpty ?? "Untitled reminder",
                        due: due,
                        priority: reminder.priority,
                        list: reminder.calendar?.title ?? "",
                        isOverdue: due.map { $0 < now } ?? false,
                        notes: reminder.notes?.nilIfEmpty?.condensed(limit: 160)
                    )
                }
                continuation.resume(returning: mapped)
            }
        }
        return Array(
            facts.sorted { ($0.due ?? .distantFuture, $0.priority) < ($1.due ?? .distantFuture, $1.priority) }
                .prefix(30)
        )
    }

    private func selectedCalendars(for type: EKEntityType, ids: [String]) -> [EKCalendar]? {
        guard !ids.isEmpty else { return nil }
        let wanted = Set(ids)
        let calendars = store.calendars(for: type).filter { wanted.contains($0.calendarIdentifier) }
        return calendars.isEmpty ? nil : calendars
    }

    private static func isDeclined(_ event: EKEvent) -> Bool {
        event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
    }

    /// Video-call links usually live in the location or notes, not `url`.
    private static func meetingLink(in event: EKEvent) -> String? {
        let haystack = [event.location, event.notes].compactMap { $0 }.joined(separator: " ")
        guard !haystack.isEmpty,
              let match = haystack.firstMatch(of: /https:\/\/[^\s<>"]*(zoom\.us|meet\.google\.com|teams\.microsoft\.com|webex\.com)[^\s<>"]*/)
        else { return nil }
        return String(match.output.0)
    }

    static func hex(_ color: CGColor) -> String? {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.converted(to: srgb, intent: .defaultIntent, options: nil),
              let components = converted.components, components.count >= 3
        else { return nil }
        let channels = components.prefix(3).map { Int((max(0, min(1, $0)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2])
    }
}

public struct CalendarCollector: Collector {
    public let kind = CollectorKind.calendar

    public init() {}

    public func collect(_ context: CollectionContext) async throws -> CollectorOutput {
        let service = EventKitService.shared
        let access = await service.ensureAccess(to: .event, mayPrompt: context.mayRequestPermissions)
        guard access.isGranted else { throw CollectorSkipped("Calendar: \(access.explanation)") }
        var fragment = BriefingFacts.fragment(context)
        fragment.events = await service.events(in: context.today, calendarIDs: context.settings.calendarIDs)
        return CollectorOutput(facts: fragment)
    }
}

public struct RemindersCollector: Collector {
    public let kind = CollectorKind.reminders

    public init() {}

    public func collect(_ context: CollectionContext) async throws -> CollectorOutput {
        let service = EventKitService.shared
        let access = await service.ensureAccess(to: .reminder, mayPrompt: context.mayRequestPermissions)
        guard access.isGranted else { throw CollectorSkipped("Reminders: \(access.explanation)") }
        var fragment = BriefingFacts.fragment(context)
        fragment.reminders = await service.reminders(
            dueBy: context.today.end,
            now: context.now,
            listIDs: context.settings.reminderListIDs
        )
        return CollectorOutput(facts: fragment)
    }
}
