import Foundation
import MorningKit

/// Human-readable dump of collected facts, grouped the way the Today view groups them.
struct ContextRenderer {
    let paths: MorningPaths

    private let time = Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
    private let dayAndTime = Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
    private let day = Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated)

    func render(_ result: CollectionResult) -> String {
        let facts = result.facts
        var out: [String] = []
        let hours = Int(facts.period.to.timeIntervalSince(facts.period.from) / 3600)
        out.append("Vega · context at \(facts.period.to.formatted(dayAndTime))")
        out.append("Window: since \(facts.period.from.formatted(dayAndTime)) (\(hours) h)")

        section("Sources", into: &out)
        for report in result.reports {
            let mark = switch report.status {
            case .ok: "✓"
            case .skipped: "–"
            case .failed: "✗"
            }
            let detail = report.status == .ok ? "\(report.itemCount) items · \(report.durationMs) ms" : (report.message ?? "")
            out.append("  \(mark) \(pad(report.kind.displayName, 22)) \(detail)")
            if report.status == .ok, let warning = report.message {
                for line in warning.split(separator: "\n").prefix(5) { out.append("      ! \(line)") }
            }
        }

        renderOvernight(facts, into: &out)
        renderToday(facts, into: &out)
        renderAttention(facts, into: &out)
        renderProjects(facts, into: &out)
        renderNotes(facts, into: &out)
        return out.joined(separator: "\n")
    }

    private func renderOvernight(_ facts: BriefingFacts, into out: inout [String]) {
        section("Overnight", into: &out)
        let projectIDs = (facts.sessions.compactMap(\.projectID) + facts.commits.map(\.projectID)).uniqued()
        let unassigned = facts.sessions.filter { $0.projectID == nil }
        if projectIDs.isEmpty, unassigned.isEmpty {
            out.append("  Nothing since \(facts.period.from.formatted(dayAndTime)).")
            return
        }
        for id in projectIDs {
            let project = facts.project(id)
            out.append("  \(project?.name ?? id)  [\(id)\(project?.branch.map { " · \($0)" } ?? "")]")
            for session in facts.sessions where session.projectID == id {
                renderSession(session, into: &out)
            }
            for commit in facts.commits where commit.projectID == id {
                out.append("    ● \(commit.shortHash) \(commit.authoredAt.formatted(time))  \(commit.subject)  (\(commit.files.count) files, +\(commit.insertions)/−\(commit.deletions)\(commit.branch.map { ", \($0)" } ?? ""))")
            }
        }
        if !unassigned.isEmpty {
            out.append("  Other sessions")
            for session in unassigned { renderSession(session, into: &out) }
        }
        if !facts.hookEvents.isEmpty {
            out.append("  Stop-hook events: \(facts.hookEvents.count)")
        }
    }

    private func renderSession(_ session: SessionFact, into out: inout [String]) {
        var stats = ["\(session.promptCount) prompts", "\(session.filesEdited.count) files"]
        if let added = session.linesAdded, let removed = session.linesRemoved, added + removed > 0 {
            stats.append("+\(added)/−\(removed)")
        }
        let sameDay = Calendar.current.isDate(session.startedAt, inSameDayAs: session.endedAt)
        let span = sameDay
            ? "\(session.startedAt.formatted(time))–\(session.endedAt.formatted(time))"
            : "\(session.startedAt.formatted(dayAndTime)) – \(session.endedAt.formatted(dayAndTime))"
        out.append("    ◆ \(span)  \(session.title ?? "Session")  (\(stats.joined(separator: " · ")))")
        for prompt in session.prompts.prefix(3) { out.append("        › \(prompt.prefix(110))") }
        if session.prompts.count > 3 { out.append("        › … \(session.prompts.count - 3) more") }
        if !session.filesEdited.isEmpty {
            out.append("        files: " + session.filesEdited.prefix(6).joined(separator: ", ") + (session.filesEdited.count > 6 ? " …" : ""))
        }
        for action in session.actions.prefix(4) { out.append("        ⚙︎ \(action)") }
    }

    private func renderToday(_ facts: BriefingFacts, into out: inout [String]) {
        section("Today", into: &out)
        if facts.events.isEmpty { out.append("  No events.") }
        for event in facts.events {
            let when = event.isAllDay ? "all day    " : "\(event.start.formatted(time))–\(event.end.formatted(time))"
            out.append("  \(when)  \(event.title)  · \(event.calendar)\(event.location.map { " · \($0)" } ?? "")")
        }
        if !facts.reminders.isEmpty {
            out.append("  Reminders")
            for reminder in facts.reminders {
                let due = reminder.due.map { reminder.isOverdue ? "overdue \($0.formatted(day))" : $0.formatted(time) } ?? "no date"
                out.append("    ☐ \(reminder.title)  (\(due) · \(reminder.list))")
            }
        }
    }

    private func renderAttention(_ facts: BriefingFacts, into out: inout [String]) {
        section("Attention", into: &out)
        if facts.attention.isEmpty { out.append("  All clear.") }
        for item in facts.attention.prefix(25) {
            out.append("  [\(item.severity.rawValue.uppercased().padding(toLength: 6, withPad: " ", startingAt: 0))] \(item.title)")
            out.append("           \(item.detail)")
        }
    }

    private func renderProjects(_ facts: BriefingFacts, into out: inout [String]) {
        section("Projects", into: &out)
        for project in facts.projects {
            let spark = project.commitsLast14Days.isEmpty ? "" : sparkline(project.commitsLast14Days)
            let state = project.kind == .folder ? "folder" : (project.isDirty ? "dirty" : "clean")
            let last = project.lastActivityAt.map { $0.formatted(day) } ?? "—"
            out.append("  \(pad(project.name, 22)) \(pad(project.branch ?? "", 22)) \(pad(state, 6)) \(pad(last, 12)) \(spark)")
        }
    }

    private func renderNotes(_ facts: BriefingFacts, into out: inout [String]) {
        guard !facts.notes.isEmpty else { return }
        section("Notes", into: &out)
        for note in facts.notes {
            out.append("  \(facts.project(note.projectID)?.name ?? note.projectID) / \(note.file)")
            for item in note.openItems.prefix(5) { out.append("    ☐ \(item)") }
            if let excerpt = note.excerpt { out.append("    \(excerpt.prefix(160))") }
        }
    }

    private func section(_ title: String, into out: inout [String]) {
        out.append("")
        out.append(title.uppercased())
    }

    private func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? String(text.prefix(width - 1)) + "…" : text.padding(toLength: width, withPad: " ", startingAt: 0)
    }

    private func sparkline(_ values: [Int]) -> String {
        let bars = Array("▁▂▃▄▅▆▇█")
        let peak = max(values.max() ?? 0, 1)
        return String(values.map { $0 == 0 ? "·" : bars[min(bars.count - 1, ($0 * (bars.count - 1)) / peak)] })
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
