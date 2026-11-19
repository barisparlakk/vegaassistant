import MorningKit
import SwiftUI

/// A calendar event or reminder as one console row.
struct AgendaRow: Identifiable {
    enum Kind { case allDay, event, reminder }

    let id: String
    let kind: Kind
    let time: String
    let title: String
    let detail: String?
    let start: Date?
    let end: Date?
    let colorHex: String?
    let url: String?
    let isOverdue: Bool

    static func rows(for facts: BriefingFacts) -> [AgendaRow] {
        let events = facts.events.sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }.map { event in
            AgendaRow(
                id: event.id,
                kind: event.isAllDay ? .allDay : .event,
                time: event.isAllDay ? "all-day" : Format.timeRange(event.start, event.end),
                title: event.title,
                detail: [event.calendar, event.location].compactMap { $0?.nilIfBlank }.joined(separator: " · ").nilIfBlank,
                start: event.start,
                end: event.end,
                colorHex: event.colorHex,
                url: event.url,
                isOverdue: false
            )
        }
        let reminders = facts.reminders.map { reminder in
            AgendaRow(
                id: reminder.id,
                kind: .reminder,
                time: reminder.isOverdue ? "overdue" : (reminder.due.map(Format.time) ?? "today"),
                title: reminder.title,
                detail: reminder.list,
                start: nil,
                end: nil,
                colorHex: nil,
                url: nil,
                isOverdue: reminder.isOverdue
            )
        }
        return events + reminders
    }
}

// MARK: - Attention

/// One attention row: Claude's prioritised item, or a raw flag it didn't mention.
struct AttentionRowModel {
    let title: String
    let detail: String?
    let severity: Severity
    let targets: ActionTargets

    static func rows(facts: BriefingFacts, section: GeneratedBriefing.Section?) -> [AttentionRowModel] {
        let items = section?.items ?? []
        let cited = Set(items.flatMap(\.refs))
        let fromModel = items.map { item in
            AttentionRowModel(
                title: item.title,
                detail: item.detail,
                severity: item.priority,
                targets: ActionTargets(facts: facts.attentionFacts(item.refs), project: facts.project(item.projectID))
            )
        }
        let others = facts.attention.filter { !cited.contains($0.id) }.map { fact in
            AttentionRowModel(
                title: fact.title,
                detail: fact.detail,
                severity: fact.severity,
                targets: ActionTargets(facts: [fact], project: facts.project(fact.projectID))
            )
        }
        return fromModel + others
    }
}

/// Where an attention row's buttons lead.
struct ActionTargets {
    var path: String?
    var url: String?

    init(facts: [AttentionFact], project: ProjectFact?) {
        path = facts.lazy.compactMap(\.path).first ?? project?.path
        url = facts.lazy.compactMap(\.url).first ?? project?.webURL
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

