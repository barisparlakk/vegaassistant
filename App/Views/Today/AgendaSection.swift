import MorningKit
import SwiftUI

/// Today's calendar as a vertical timeline with a now-line, plus reminders.
struct AgendaSection: View {
    let briefing: Briefing
    let summary: GeneratedBriefing.Section?
    var isToday: Bool

    var body: some View {
        let facts = briefing.facts
        let calendarReport = briefing.diagnostics.first { $0.kind == .calendar }
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(isToday ? "Today" : "That day", symbol: "calendar")

            if let text = summary?.summary {
                Text(text)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: Metrics.readableTextWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Spacing.xs)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Spacing.m) {
                    agendaCard(facts: facts, report: calendarReport)
                    RemindersCard(reminders: facts.reminders, prep: summary?.items ?? [], facts: facts, report: briefing.diagnostics.first { $0.kind == .reminders })
                        .frame(width: Metrics.remindersColumnWidth)
                }
                VStack(spacing: Spacing.m) {
                    agendaCard(facts: facts, report: calendarReport)
                    RemindersCard(reminders: facts.reminders, prep: summary?.items ?? [], facts: facts, report: briefing.diagnostics.first { $0.kind == .reminders })
                }
            }
        }
    }

    @ViewBuilder
    private func agendaCard(facts: BriefingFacts, report: CollectorReport?) -> some View {
        Card(padding: Spacing.l) {
            if let report, report.status != .ok {
                SourceUnavailableView(kind: .calendar, report: report)
            } else if facts.events.isEmpty {
                Label("Nothing on the calendar — the whole day is yours.", systemImage: "sun.max")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
            } else {
                AgendaTimeline(events: facts.events, day: Briefing.date(forID: briefing.id) ?? briefing.generatedAt, showsNow: isToday)
            }
        }
        .frame(minWidth: Metrics.remindersColumnWidth * 1.4)
    }
}

/// Hour grid with events positioned by time and placed side by side when they overlap.
struct AgendaTimeline: View {
    let events: [EventFact]
    let day: Date
    var showsNow: Bool

    var body: some View {
        let timed = events.filter { !$0.isAllDay }
        let allDay = events.filter(\.isAllDay)
        let range = hourRange(for: timed)
        let totalHeight = CGFloat(range.count) * Metrics.agendaHourHeight

        VStack(alignment: .leading, spacing: Spacing.m) {
            if !allDay.isEmpty {
                HStack(spacing: Spacing.s) {
                    ForEach(allDay) { event in
                        Pill(text: event.title, symbol: "sun.max", tint: Color(hex: event.colorHex) ?? Palette.textSecondary)
                    }
                }
            }

            TimelineView(.everyMinute) { context in
                ZStack(alignment: .topLeading) {
                    // Hour lines and labels
                    VStack(spacing: 0) {
                        ForEach(range, id: \.self) { hour in
                            HStack(alignment: .top, spacing: Spacing.s) {
                                Text(String(format: "%02d:00", hour))
                                    .font(Typography.mono)
                                    .foregroundStyle(Palette.textTertiary)
                                    .frame(width: Metrics.timelineGutter - Spacing.s, alignment: .trailing)
                                    .offset(y: -Spacing.s + Spacing.xxs)
                                Rectangle()
                                    .fill(Palette.stroke)
                                    .frame(height: Metrics.hairline)
                            }
                            .frame(height: Metrics.agendaHourHeight, alignment: .top)
                        }
                    }

                    // Events
                    GeometryReader { proxy in
                        let width = proxy.size.width - Metrics.timelineGutter
                        ForEach(layout(timed)) { slot in
                            let columnWidth = width / CGFloat(slot.columns)
                            AgendaEventBlock(event: slot.event, isPast: showsNow && slot.event.end < context.date)
                                .frame(width: columnWidth - Spacing.xs, height: max(Metrics.agendaMinEventHeight, height(of: slot.event)))
                                .offset(x: Metrics.timelineGutter + columnWidth * CGFloat(slot.column), y: y(for: slot.event.start, range: range))
                        }
                    }

                    // Now-line
                    if showsNow, let nowY = nowOffset(context.date, range: range) {
                        HStack(spacing: 0) {
                            Spacer().frame(width: Metrics.timelineGutter - Metrics.nowDot / 2)
                            Circle().fill(Palette.now).frame(width: Metrics.nowDot, height: Metrics.nowDot)
                            Rectangle().fill(Palette.now).frame(height: Metrics.rule)
                        }
                        .offset(y: nowY - Metrics.nowDot / 2)
                        .accessibilityLabel("Now, \(Format.time(context.date))")
                    }
                }
                .frame(height: totalHeight)
            }
        }
    }

    // MARK: Geometry

    private func hourRange(for events: [EventFact]) -> [Int] {
        let calendar = Calendar.current
        let starts = events.map { calendar.component(.hour, from: $0.start) }
        let ends = events.map { calendar.component(.hour, from: $0.end) + 1 }
        let nowHour = showsNow ? [calendar.component(.hour, from: .now)] : []
        let first = max(0, min((starts + nowHour).min() ?? 9, 8))
        let last = min(24, max((ends + nowHour.map { $0 + 1 }).max() ?? 18, 18))
        return Array(first..<last)
    }

    private func minutes(_ date: Date) -> CGFloat {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        return CGFloat(date.timeIntervalSince(start) / 60)
    }

    private func y(for date: Date, range: [Int]) -> CGFloat {
        (minutes(date) - CGFloat((range.first ?? 0) * 60)) / 60 * Metrics.agendaHourHeight
    }

    private func height(of event: EventFact) -> CGFloat {
        CGFloat(event.end.timeIntervalSince(event.start) / 3600) * Metrics.agendaHourHeight - Spacing.xxs
    }

    private func nowOffset(_ now: Date, range: [Int]) -> CGFloat? {
        guard Calendar.current.isDate(now, inSameDayAs: day) else { return nil }
        let offset = y(for: now, range: range)
        return offset >= 0 && offset <= CGFloat(range.count) * Metrics.agendaHourHeight ? offset : nil
    }

    struct Slot: Identifiable {
        let event: EventFact
        let column: Int
        let columns: Int
        var id: String { event.id }
    }

    /// Where an event visually ends: short events are drawn taller than their duration.
    private func visualEnd(_ event: EventFact) -> Date {
        let minimum = Double(Metrics.agendaMinEventHeight / Metrics.agendaHourHeight) * 3600
        return max(event.end, event.start.addingTimeInterval(minimum))
    }

    /// Greedy column assignment within clusters of (visually) overlapping events.
    private func layout(_ events: [EventFact]) -> [Slot] {
        let sorted = events.sorted { $0.start < $1.start }
        var slots: [Slot] = []
        var cluster: [(EventFact, Int)] = []
        var clusterEnd = Date.distantPast

        func flush() {
            let columns = (cluster.map(\.1).max() ?? 0) + 1
            slots += cluster.map { Slot(event: $0.0, column: $0.1, columns: columns) }
            cluster.removeAll()
        }

        for event in sorted {
            if event.start >= clusterEnd { flush() }
            var used = Set<Int>()
            for (other, column) in cluster where visualEnd(other) > event.start { used.insert(column) }
            let column = (0...).first { !used.contains($0) } ?? 0
            cluster.append((event, column))
            clusterEnd = max(clusterEnd, visualEnd(event))
        }
        flush()
        return slots
    }
}

struct AgendaEventBlock: View {
    let event: EventFact
    let isPast: Bool

    var body: some View {
        let color = Color(hex: event.colorHex) ?? Color.accentColor
        let details = [Format.timeRange(event.start, event.end), event.location].compactMap { $0 }.joined(separator: " · ")
        let isShort = event.end.timeIntervalSince(event.start) < 40 * 60
        HStack(alignment: .top, spacing: Spacing.s) {
            Capsule().fill(color).frame(width: Metrics.severityBar)
            if isShort {
                // One line so short events stay inside their block.
                (Text(event.title).font(Typography.captionEmphasis)
                    + Text("  \(details)").font(Typography.caption).foregroundStyle(Palette.textSecondary))
                    .lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(event.title)
                        .font(Typography.captionEmphasis)
                        .lineLimit(1)
                    Text(details)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let url = event.url {
                Button {
                    Opener.url(url)
                } label: {
                    Image(systemName: "video.fill")
                }
                .buttonStyle(.borderless)
                .help("Join")
            }
        }
        .padding(.vertical, Spacing.xs)
        .padding(.trailing, Spacing.s)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
        .opacity(isPast ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }
}

struct RemindersCard: View {
    let reminders: [ReminderFact]
    let prep: [GeneratedBriefing.Item]
    let facts: BriefingFacts
    let report: CollectorReport?

    var body: some View {
        Card(padding: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Label("Reminders", systemImage: "checklist")
                    .font(Typography.cardTitle)
                if let report, report.status != .ok {
                    SourceUnavailableView(kind: .reminders, report: report)
                } else if reminders.isEmpty {
                    Text("Nothing due today.")
                        .font(Typography.body)
                        .foregroundStyle(Palette.textSecondary)
                } else {
                    ForEach(reminders) { reminder in
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                            Image(systemName: "circle")
                                .foregroundStyle(reminder.isOverdue ? Palette.high : (reminder.priority.isHighReminderPriority ? Palette.medium : Palette.textTertiary))
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(reminder.title).font(Typography.body)
                                Text(dueText(reminder))
                                    .font(Typography.caption)
                                    .foregroundStyle(reminder.isOverdue ? Palette.high : Palette.textSecondary)
                            }
                        }
                    }
                }
                let prepItems = prep.filter { item in !item.refs.contains { $0.hasPrefix("reminder:") } }
                if !prepItems.isEmpty {
                    Divider()
                    Label("Prep", systemImage: "wand.and.sparkles")
                        .font(Typography.captionEmphasis)
                        .foregroundStyle(.tint)
                    ForEach(prepItems, id: \.title) { item in
                        Text(item.title)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func dueText(_ reminder: ReminderFact) -> String {
        guard let due = reminder.due else { return reminder.list }
        if reminder.isOverdue { return "Overdue · \(Format.relative(due))" }
        return "\(Format.time(due)) · \(reminder.list)"
    }
}

/// Explains a source that couldn't be read, in place of its content.
/// Explains a source that couldn't be read, in place of its content, with the fix one click away.
struct SourceUnavailableView: View {
    @Environment(AppModel.self) private var model
    let kind: CollectorKind
    let report: CollectorReport

    var body: some View {
        let access = kind == .calendar ? model.system.calendarAccess : model.system.remindersAccess
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: kind == .calendar ? "calendar.badge.exclamationmark" : "checklist.unchecked")
                .font(.system(size: Metrics.iconMedium))
                .foregroundStyle(Palette.textTertiary)
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(title(access)).font(Typography.bodyEmphasis)
                Text(message(access))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                action(access)
                    .controlSize(.small)
            }
        }
    }

    private var name: String { kind == .calendar ? "Calendar" : "Reminders" }

    private func title(_ access: EventKitAccess) -> String {
        access.isGranted ? "\(name) is connected now" : "\(name) isn't connected"
    }

    private func message(_ access: EventKitAccess) -> String {
        if access.isGranted { return "Regenerate to include it in this briefing." }
        guard access == .notDetermined else { return access.explanation }
        return kind == .calendar
            ? "Allow access so the briefing can plan around your meetings."
            : "Allow access so the briefing includes what's due today."
    }

    @ViewBuilder
    private func action(_ access: EventKitAccess) -> some View {
        switch access {
        case .granted:
            Button("Regenerate", systemImage: "arrow.clockwise") { model.regenerate() }
                .glassButtonStyle()
                .disabled(model.isGenerating)
        case .notDetermined:
            Button("Allow access…") {
                if kind == .calendar { model.requestCalendarAccess() } else { model.requestRemindersAccess() }
            }
            .glassButtonStyle(prominent: true)
        default:
            Button("Open System Settings") {
                Opener.url("x-apple.systempreferences:com.apple.preference.security?Privacy_\(kind == .calendar ? "Calendars" : "Reminders")")
            }
            .glassButtonStyle()
        }
    }
}

private extension Int {
    var isHighReminderPriority: Bool { (1...4).contains(self) }
}

#Preview("Agenda") {
    ScrollView {
        AgendaSection(briefing: MockData.briefing(), summary: MockData.generated.section(.agenda), isToday: true)
            .padding(Spacing.xxl)
    }
    .frame(width: 900, height: 820)
    .environment(AppModel.preview())
    .tint(AccentChoice.sunrise.color)
}

#Preview("Agenda — no calendar access") {
    var briefing = MockData.briefing()
    briefing.facts.events = []
    briefing.diagnostics = [CollectorReport(kind: .calendar, status: .skipped, message: "Calendar: Not requested yet")]
    return AgendaSection(briefing: briefing, summary: nil, isToday: true)
        .padding(Spacing.xxl)
        .frame(width: 900)
        .environment({ let model = AppModel.preview(); model.system.calendarAccess = .notDetermined; return model }())
        .tint(AccentChoice.sunrise.color)
}
