import MorningKit
import SwiftUI

/// Open a project in Terminal, the editor, Finder or on GitHub.
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
            Image(systemName: "arrow.up.forward.square")
                .font(.system(size: DS.Size.icon, weight: .medium))
                .foregroundStyle(DS.Color.dim)
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

/// One cited fact, on a single mono/sans line.
struct EvidenceRow: View {
    let evidence: BriefingFacts.Evidence

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
            Text(kind)
                .font(DS.Font.tag)
                .foregroundStyle(DS.Color.dim)
                .frame(width: DS.Size.timeColumn + DS.Space.l, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var content: some View {
        switch evidence {
        case let .session(session):
            line(session.title ?? "Claude session", meta: "\(Format.relative(session.endedAt)) · \(Format.plural(session.promptCount, "prompt"))")
        case let .commit(commit):
            line(commit.subject, meta: commit.shortHash)
        case let .pullRequest(pr):
            line(pr.title, meta: "#\(pr.number)")
        case let .issue(issue):
            line(issue.title, meta: "#\(issue.number)")
        case let .attention(item):
            line(item.title, meta: nil)
        case let .note(note):
            line(note.openItems.first ?? note.excerpt ?? note.file, meta: note.file.lowercased())
        case let .event(event):
            line(event.title, meta: Format.time(event.start))
        case let .reminder(reminder):
            line(reminder.title, meta: nil)
        }
    }

    private func line(_ text: String, meta: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
            if let meta {
                Text(meta).font(DS.Font.metaSmall).foregroundStyle(DS.Color.dim)
            }
            Text(text).font(DS.Font.small).foregroundStyle(DS.Color.muted).lineLimit(1)
        }
    }

    private var kind: String {
        switch evidence {
        case .session: "SESSION"
        case .commit: "COMMIT"
        case .pullRequest: "PR"
        case .issue: "ISSUE"
        case .attention: "FLAG"
        case .note: "NOTE"
        case .event: "EVENT"
        case .reminder: "REMIND"
        }
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

#Preview("Evidence rows") {
    let facts = MockData.briefing().facts
    VStack(alignment: .leading, spacing: DS.Space.s) {
        ForEach(facts.evidence(facts.sessions.map(\.id) + facts.commits.prefix(3).map(\.id) + ["pr:barisparlakk/daybase#42"])) { EvidenceRow(evidence: $0) }
        ProjectOpenMenu(project: facts.projects.first)
    }
    .padding(DS.Space.xxl)
    .frame(width: 640)
    .background(ConsoleBackdrop())
    .preferredColorScheme(.dark)
}
