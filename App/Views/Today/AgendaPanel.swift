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

/// `agenda` — mono time rows with a thin now-line, then reminders.
struct AgendaPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accent) private var accent
    let briefing: Briefing
    var isToday: Bool
    @Binding var cursor: ConsoleCursor?

    var body: some View {
        let rows = AgendaRow.rows(for: briefing.facts)
        let events = rows.filter { $0.kind != .reminder }
        let reminders = rows.filter { $0.kind == .reminder }
        Panel("agenda", counts: "\(Format.plural(events.count, "event")) · \(Format.plural(reminders.count, "reminder"))") {
            TimelineView(.everyMinute) { context in
                VStack(spacing: 0) {
                    if let message = unavailable(.calendar) {
                        message
                    } else if events.isEmpty {
                        ConsoleMessage(text: "no events — the day is yours")
                    }
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, row in
                        if isToday, showsNowLine(before: index, in: events, now: context.date) {
                            NowLine(now: context.date)
                        }
                        AgendaLine(row: row, isPast: isToday && (row.end.map { $0 < context.date } ?? false), isSelected: cursor == .agenda(row.id))
                            .id(ConsoleCursor.agenda(row.id))
                    }
                    if isToday, showsNowLine(before: events.count, in: events, now: context.date), !events.isEmpty {
                        NowLine(now: context.date)
                    }
                    RowDivider()
                    if let message = unavailable(.reminders) {
                        message
                    } else if reminders.isEmpty {
                        ConsoleMessage(text: "no reminders due")
                    }
                    ForEach(reminders) { row in
                        AgendaLine(row: row, isPast: false, isSelected: cursor == .agenda(row.id))
                            .id(ConsoleCursor.agenda(row.id))
                    }
                }
            }
        }
    }

    /// The now-line goes before the first timed event that hasn't started.
    private func showsNowLine(before index: Int, in events: [AgendaRow], now: Date) -> Bool {
        let timed = events.enumerated().filter { $0.element.kind == .event }
        guard let firstUpcoming = timed.first(where: { ($0.element.start ?? .distantPast) > now })?.offset else {
            return index == events.count && !timed.isEmpty
        }
        return index == firstUpcoming
    }

    private func unavailable(_ kind: CollectorKind) -> ConsoleMessage? {
        guard let report = briefing.diagnostics.first(where: { $0.kind == kind }), report.status != .ok else { return nil }
        let access = kind == .calendar ? model.system.calendarAccess : model.system.remindersAccess
        let name = kind == .calendar ? "calendar" : "reminders"
        switch access {
        case .granted:
            return ConsoleMessage(text: "\(name) connected", actionTitle: "regenerate", keys: "⌘R", action: model.regenerate)
        case .notDetermined:
            return ConsoleMessage(text: "\(name) not connected", actionTitle: "allow access", keys: "") {
                if kind == .calendar { model.requestCalendarAccess() } else { model.requestRemindersAccess() }
            }
        default:
            return ConsoleMessage(text: "\(name) access denied", actionTitle: "open system settings", keys: "") {
                Opener.url("x-apple.systempreferences:com.apple.preference.security?Privacy_\(kind == .calendar ? "Calendars" : "Reminders")")
            }
        }
    }
}

private struct AgendaLine: View {
    let row: AgendaRow
    let isPast: Bool
    let isSelected: Bool
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.m) {
            Text(row.time)
                .font(DS.Font.time)
                .foregroundStyle(row.isOverdue ? DS.Color.failed : DS.Color.dim)
                .frame(width: DS.Size.timeColumn * 2 + DS.Space.s, alignment: .leading)
            if row.kind == .reminder {
                ConsoleCheckbox(isOn: false)
            } else {
                Rectangle()
                    .fill(Color(hex: row.colorHex) ?? accent)
                    .frame(width: DS.Size.hairline * 2, height: DS.Size.checkbox)
            }
            Text(row.title)
                .font(DS.Font.rowTitle)
                .foregroundStyle(DS.Color.text)
                .lineLimit(1)
            if let detail = row.detail {
                Text(detail.lowercased())
                    .font(DS.Font.metaSmall)
                    .foregroundStyle(DS.Color.dim)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let url = row.url {
                IconButton(symbol: "video", help: "Join") { Opener.url(url) }
            }
        }
        .padding(.horizontal, DS.Space.rowHorizontal)
        .padding(.vertical, DS.Space.rowVertical - DS.Space.xxs)
        .opacity(isPast ? 0.45 : 1)
        .rowBackground(selected: isSelected)
    }
}

/// Thin accent line marking the current time.
private struct NowLine: View {
    let now: Date
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Text("now \(Format.time(now))")
                .font(DS.Font.tag)
                .foregroundStyle(DS.Color.accentInk(accent))
            Rectangle()
                .fill(accent)
                .frame(height: DS.Size.nowLine)
        }
        .padding(.horizontal, DS.Space.rowHorizontal)
        .padding(.vertical, DS.Space.xxs)
        .accessibilityLabel("Now, \(Format.time(now))")
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

/// `attention` — PRs, stale branches, dirty repos, with Terminal / editor / GitHub.
struct AttentionPanel: View {
    let facts: BriefingFacts
    let section: GeneratedBriefing.Section?
    @Binding var cursor: ConsoleCursor?
    @State private var showsAll = false
    private let collapsed = 5

    var body: some View {
        let rows = AttentionRowModel.rows(facts: facts, section: section)
        Panel("attention", counts: Format.plural(facts.attention.count, "flag")) {
            if rows.isEmpty {
                ConsoleMessage(text: "all clear — no open prs, dirty trees or stale branches", tone: DS.Color.ok)
            }
            let visible = showsAll ? rows : Array(rows.prefix(collapsed))
            ForEach(Array(visible.enumerated()), id: \.offset) { index, row in
                if index > 0 { RowDivider() }
                AttentionLine(row: row, isSelected: cursor == .attention(index))
                    .id(ConsoleCursor.attention(index))
            }
            if rows.count > collapsed {
                RowDivider()
                Button(showsAll ? "show less" : "+\(rows.count - collapsed) more") {
                    withAnimation(DS.Motion.standard) { showsAll.toggle() }
                }
                .buttonStyle(.consoleGhost)
                .padding(.horizontal, DS.Space.xs)
                .padding(.vertical, DS.Space.xs)
            }
        }
    }
}

private struct AttentionLine: View {
    let row: AttentionRowModel
    let isSelected: Bool
    @State private var isHovered = false
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.m) {
            Text(marker)
                .font(DS.Font.tag)
                .foregroundStyle(markerColor)
                .frame(width: DS.Space.l, alignment: .leading)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(row.title)
                    .font(DS.Font.rowTitle)
                    .foregroundStyle(DS.Color.text)
                    .lineLimit(2)
                if let detail = row.detail {
                    Text(detail)
                        .font(DS.Font.small)
                        .foregroundStyle(DS.Color.dim)
                        .lineLimit(isSelected ? 4 : 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: DS.Space.xxs) {
                if row.targets.path != nil {
                    IconButton(symbol: "terminal", help: "Open in Terminal (T)") { Opener.terminal(row.targets.path) }
                    IconButton(symbol: "chevron.left.forwardslash.chevron.right", help: "Open in editor (E)") { Opener.editor(row.targets.path) }
                }
                if row.targets.url != nil {
                    IconButton(symbol: "arrow.up.right.square", help: "Open on GitHub (G)") { Opener.url(row.targets.url) }
                }
            }
            .opacity(isHovered || isSelected ? 1 : 0.55)
        }
        .padding(.horizontal, DS.Space.rowHorizontal)
        .padding(.vertical, DS.Space.rowVertical)
        .rowBackground(selected: isSelected, hovered: isHovered)
        .onHover { hovering in withAnimation(DS.Motion.fast) { isHovered = hovering } }
    }

    private var marker: String {
        switch row.severity {
        case .high: "!!"
        case .medium: "!"
        case .low: "·"
        }
    }

    private var markerColor: Color {
        switch row.severity {
        case .high: DS.Color.failed
        case .medium: DS.Color.accentInk(accent)
        case .low: DS.Color.dim
        }
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview("agenda + attention") {
    @Previewable @State var cursor: ConsoleCursor? = .attention(0)
    let briefing = MockData.briefing()
    HStack(alignment: .top, spacing: DS.Space.sectionGap) {
        AgendaPanel(briefing: briefing, isToday: true, cursor: $cursor)
        AttentionPanel(facts: briefing.facts, section: MockData.generated.section(.attention), cursor: $cursor)
    }
    .padding(DS.Space.xxl)
    .frame(width: 1100)
    .background(ConsoleBackdrop())
    .environment(AppModel.preview())
    .preferredColorScheme(.dark)
}
