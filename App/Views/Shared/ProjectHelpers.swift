import MorningKit
import SwiftUI

/// Open the project in Terminal, the editor, Finder or on GitHub.
struct ProjectOpenMenu: View {
    let project: ProjectFact?

    var body: some View {
        Menu {
            Button("Open in Terminal", systemImage: "terminal") { Opener.terminal(project?.path) }
            Button("Open in Editor", systemImage: "chevron.left.forwardslash.chevron.right") { Opener.editor(project?.path) }
            Button("Show in Finder", systemImage: "folder") { Opener.finder(project?.path) }
            if let url = project?.webURL {
                Divider()
                Button("Open on GitHub", systemImage: "safari") { Opener.url(url) }
            }
        } label: {
            Image(systemName: "arrow.up.forward.app")
                .accessibilityLabel("Open project")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(project == nil)
        .help("Open project")
        .accessibilityLabel("Open project")
    }
}

struct ProjectStatsRow: View {
    let project: ProjectFact

    var body: some View {
        HStack(spacing: Spacing.l) {
            stat("\(project.commitsLast14Days.reduce(0, +))", "commits / 14 d")
            if project.isDirty { stat("\(project.changedFiles + project.untrackedFiles)", "uncommitted") }
            if project.ahead > 0 { stat("\(project.ahead)", "unpushed") }
            if let last = project.lastActivityAt { stat(Format.relative(last), "last touched") }
            Spacer()
            if !project.commitsLast14Days.isEmpty {
                Sparkline(values: project.commitsLast14Days)
                    .frame(width: 120)
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(value).font(Typography.numeric)
            Text(label).font(Typography.caption).foregroundStyle(Palette.textSecondary)
        }
    }
}

/// One cited fact, in a single line.
struct EvidenceRow: View {
    let evidence: BriefingFacts.Evidence

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: Metrics.iconMedium)
            content
            Spacer(minLength: 0)
        }
        .font(Typography.body)
    }

    @ViewBuilder private var content: some View {
        switch evidence {
        case let .session(session):
            Text(session.title ?? "Claude session")
            Text("\(Format.relative(session.endedAt)) · \(Format.plural(session.promptCount, "prompt"))")
                .font(Typography.caption).foregroundStyle(Palette.textSecondary)
        case let .commit(commit):
            Text(commit.shortHash).font(Typography.mono).foregroundStyle(Palette.textSecondary)
            Text(commit.subject).lineLimit(1)
        case let .pullRequest(pr):
            Text("#\(pr.number)").font(Typography.mono).foregroundStyle(Palette.textSecondary)
            Text(pr.title).lineLimit(1)
        case let .issue(issue):
            Text("#\(issue.number)").font(Typography.mono).foregroundStyle(Palette.textSecondary)
            Text(issue.title).lineLimit(1)
        case let .attention(item):
            Text(item.title).lineLimit(1)
        case let .note(note):
            Text("\(note.file): \(note.openItems.first ?? note.excerpt ?? "")").lineLimit(1)
        case let .event(event):
            Text(Format.time(event.start)).font(Typography.mono).foregroundStyle(Palette.textSecondary)
            Text(event.title).lineLimit(1)
        case let .reminder(reminder):
            Text(reminder.title).lineLimit(1)
        }
    }

    private var symbol: String {
        switch evidence {
        case .session: "sparkles"
        case .commit: "smallcircle.filled.circle"
        case .pullRequest: "arrow.triangle.pull"
        case .issue: "exclamationmark.circle"
        case let .attention(item): item.kind.symbol
        case .note: "note.text"
        case .event: "calendar"
        case .reminder: "checklist"
        }
    }

    private var tint: Color {
        switch evidence {
        case .session: Palette.claude
        case .commit: Palette.commit
        case let .attention(item): Palette.severity(item.severity)
        default: Palette.textSecondary
        }
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
