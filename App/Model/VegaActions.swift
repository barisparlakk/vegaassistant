import EventKit
import Foundation

/// The parts of Vega's actions that write to Calendar and Reminders.
@MainActor
enum VegaActions {
    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    private static let store = EKEventStore()

    /// Adds a reminder to the default list, with an alert at `due` when there is one.
    static func addReminder(title: String, due: Date?) async throws -> String {
        guard try await store.requestFullAccessToReminders() else {
            throw Failure("Vega isn't allowed to add reminders. Allow it in System Settings › Privacy & Security › Reminders.")
        }
        guard let list = store.defaultCalendarForNewReminders() ?? store.calendars(for: .reminder).first(where: \.allowsContentModifications) else {
            throw Failure("There's no reminders list to add to.")
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = list
        if let due {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        try store.save(reminder, commit: true)
        return "Added to \(list.title)"
    }

    /// Adds an event to the default calendar.
    static func addEvent(title: String, start: Date, minutes: Int) async throws -> String {
        guard try await store.requestFullAccessToEvents() else {
            throw Failure("Vega isn't allowed to add events. Allow it in System Settings › Privacy & Security › Calendars.")
        }
        guard let calendar = store.defaultCalendarForNewEvents ?? store.calendars(for: .event).first(where: \.allowsContentModifications) else {
            throw Failure("There's no calendar to add to.")
        }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(TimeInterval(minutes * 60))
        event.calendar = calendar
        try store.save(event, span: .thisEvent, commit: true)
        return "Added to \(calendar.title)"
    }
}
