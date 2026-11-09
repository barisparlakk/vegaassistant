import Foundation

/// Plain Markdown rendering of a briefing — used for the fallback view, `morning-cli show`
/// and copying a briefing elsewhere.
public enum BriefingMarkdown {
    public static func render(_ briefing: Briefing) -> String {
        switch briefing.content {
        case let .structured(generated): render(generated, facts: briefing.facts)
        case let .markdown(text): text
        }
    }

    public static func render(_ briefing: GeneratedBriefing, facts: BriefingFacts) -> String {
        var lines: [String] = ["# \(briefing.headline)", ""]
        let focusName = facts.project(briefing.focus.projectID)?.name ?? briefing.focus.projectID

        lines.append("## Focus: \(focusName)")
        lines.append("")
        lines.append(briefing.focus.reason)
        lines.append("")
        for task in briefing.focus.tasks {
            lines.append("- [ ] **\(task.title)** · \(minutes(task.estimateMinutes))")
            if !task.detail.isEmpty { lines.append("  \(task.detail)") }
        }

        for section in briefing.sections {
            lines.append("")
            lines.append("## \(section.title)")
            if let summary = section.summary {
                lines.append("")
                lines.append(summary)
            }
            lines.append("")
            for item in section.items {
                var line = "- \(item.priority == .high ? "**\(item.title)**" : item.title)"
                if let project = facts.project(item.projectID)?.name { line += " _(\(project))_" }
                if let estimate = item.estimateMinutes { line += " · \(minutes(estimate))" }
                lines.append(line)
                if let detail = item.detail { lines.append("  \(detail)") }
            }
        }

        if !briefing.nextTasks.isEmpty {
            lines.append("")
            lines.append("## Also worth doing")
            lines.append("")
            for task in briefing.nextTasks {
                let project = facts.project(task.projectID)?.name ?? task.projectID
                lines.append("- \(task.title) _(\(project), \(minutes(task.estimateMinutes)))_ — \(task.reason)")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func minutes(_ value: Int) -> String {
        value < 60 ? "\(value) min" : (value % 60 == 0 ? "\(value / 60) h" : "\(value / 60) h \(value % 60) min")
    }
}
