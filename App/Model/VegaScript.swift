import Foundation
import MorningKit

/// Turns a briefing into what Vega says: a few short spoken lines, each with its card.
enum VegaScript {
    static func lines(for briefing: Briefing, news: [NewsItem], isToday: Bool, now: Date = .now) -> [VegaLine] {
        let facts = briefing.facts
        var lines: [VegaLine] = []
        let opening = isToday ? "\(Format.greeting(at: now)). Here's where things stand." : "Here's how \(day(briefing)) looked."
        lines.append(VegaLine(id: "opening", text: opening, isOpening: true))

        guard let generated = briefing.structured else {
            lines.append(VegaLine(id: "fallback", text: "I couldn't lay the briefing out cleanly this time, so here it is as text.", attachment: .fallback))
            return lines
        }

        // Focus
        let project = facts.project(generated.focus.projectID)?.name ?? generated.focus.projectID
        let minutes = generated.focus.tasks.reduce(0) { $0 + $1.estimateMinutes }
        var focus = "The focus is \(project). \(sentence(generated.headline))"
        if minutes > 0 { focus += " That's about \(spoken(minutes: minutes))." }
        lines.append(VegaLine(id: "focus", text: focus, attachment: .focusTasks))

        // Overnight
        let sessions = facts.sessions.count
        let commits = facts.commits.count
        if sessions + commits > 0 {
            let names = OvernightGroup.make(from: facts, summary: generated.section(.overnight)).prefix(3).map(\.name)
            var text = "Overnight, \(counted(sessions, "session")) and \(counted(commits, "commit"))"
            if !names.isEmpty { text += " across \(list(names))" }
            lines.append(VegaLine(id: "overnight", text: text + ".", attachment: .overnight))
        }

        // Decisions
        let decisions = AttentionRowModel.rows(facts: facts, section: generated.section(.attention))
        if let first = decisions.first {
            let lead = decisions.count == 1 ? "One thing needs your call:" : "\(number(decisions.count).capitalized) things need your call. First,"
            lines.append(VegaLine(id: "decisions", text: "\(lead) \(lowercasedStart(sentence(first.title)))", attachment: .decisions))
        }

        // Calendar
        let events = facts.events.filter { !$0.isAllDay }.sorted { $0.start < $1.start }
        if isToday {
            if let next = events.first(where: { $0.end > now }) {
                let count = events.count == 1 ? "One meeting today" : "\(number(events.count).capitalized) meetings today"
                lines.append(VegaLine(id: "agenda", text: "\(count). Next is \(next.title) at \(Format.time(next.start)).", attachment: .agenda))
            } else if !facts.reminders.isEmpty {
                lines.append(VegaLine(id: "agenda", text: "No meetings, but \(counted(facts.reminders.count, "reminder")) due today.", attachment: .agenda))
            } else {
                lines.append(VegaLine(id: "agenda", text: "Your calendar is clear."))
            }
        }

        // News
        if let story = news.first {
            var text = "One story worth your time: \(sentence(story.title))"
            if let relevance = story.relevance { text += " \(sentence(relevance))" }
            lines.append(VegaLine(id: "news", text: text, attachment: .news))
        }

        if isToday {
            lines.append(VegaLine(id: "closing", text: "That's everything. Start when you're ready."))
        }
        return lines
    }

    // MARK: Wording

    private static func day(_ briefing: Briefing) -> String {
        (Briefing.date(forID: briefing.id) ?? briefing.generatedAt).formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    /// Ends with a period unless it already ends with punctuation.
    static func sentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return trimmed }
        return ".!?".contains(last) ? trimmed : trimmed + "."
    }

    /// "Push the commits" → "push the commits", but leaves names like "Notary" alone when it's a
    /// single capitalized word followed by more capitals.
    static func lowercasedStart(_ text: String) -> String {
        guard let first = text.first, first.isUppercase else { return text }
        let firstWord = text.prefix { $0 != " " }
        if firstWord.count > 1, firstWord.dropFirst().contains(where: \.isUppercase) { return text }
        return first.lowercased() + text.dropFirst()
    }

    static func spoken(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        let hourText = hours == 1 ? "an hour" : "\(number(hours)) hours"
        switch (hours, rest) {
        case (0, _): return "\(number(rest)) minutes"
        case (_, 0): return hourText
        case (_, 30): return hours == 1 ? "an hour and a half" : "\(number(hours)) and a half hours"
        default: return "\(hourText) and \(number(rest)) minutes"
        }
    }

    static func number(_ value: Int) -> String {
        value <= 12 ? (NumberFormatter.localizedString(from: NSNumber(value: value), number: .spellOut)) : "\(value)"
    }

    static func counted(_ value: Int, _ noun: String) -> String {
        "\(number(value)) \(noun)\(value == 1 ? "" : "s")"
    }

    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        case 2: "\(items[0]) and \(items[1])"
        default: items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }
}
