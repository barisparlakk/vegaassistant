import MorningKit
import SwiftUI

/// One project's overnight activity.
struct OvernightGroup: Identifiable {
    enum Entry: Identifiable {
        case session(SessionFact)
        case commit(CommitFact)

        var id: String {
            switch self {
            case let .session(session): session.id
            case let .commit(commit): commit.id
            }
        }

        var date: Date {
            switch self {
            case let .session(session): session.endedAt
            case let .commit(commit): commit.authoredAt
            }
        }
    }

    let id: String
    let name: String
    let project: ProjectFact?
    let summary: String
    let entries: [Entry]
    let status: StatusTag.Kind

    var latest: Date { entries.first?.date ?? .distantPast }

    static func make(from facts: BriefingFacts, summary: GeneratedBriefing.Section?) -> [OvernightGroup] {
        var ids = (facts.sessions.compactMap(\.projectID) + facts.commits.map(\.projectID)).uniqued()
        let unassigned = facts.sessions.filter { $0.projectID == nil }
        if !unassigned.isEmpty { ids.append("other") }

        return ids.map { id in
            let sessions = id == "other" ? unassigned : facts.sessions(for: id)
            let commits = id == "other" ? [] : facts.commits(for: id)
            let project = facts.project(id)
            let item = summary?.items.first { $0.projectID == id }
            let entries = (sessions.map(Entry.session) + commits.map(Entry.commit)).sorted { $0.date > $1.date }
            let fallback = [
                sessions.count > 0 ? Format.plural(sessions.count, "session") : nil,
                commits.count > 0 ? Format.plural(commits.count, "commit") : nil,
            ].compactMap { $0 }.joined(separator: ", ")
            return OvernightGroup(
                id: id,
                name: project?.name ?? (id == "other" ? "chats" : id),
                project: project,
                summary: item?.title ?? sessions.first?.title ?? fallback,
                entries: entries,
                status: status(for: id, facts: facts)
            )
        }
        .sorted { $0.latest > $1.latest }
    }

    /// FAILED on failing checks; NEEDS_YOU when work is left uncommitted, unpushed or
    /// waiting on review changes; DONE otherwise.
    static func status(for projectID: String, facts: BriefingFacts) -> StatusTag.Kind {
        let flags = facts.attention.filter { $0.projectID == projectID }.map(\.kind)
        if flags.contains(.failingChecks) { return .failed }
        let needsYou: Set<AttentionFact.Kind> = [.uncommittedChanges, .unpushedCommits, .changesRequested, .upstreamGone, .behindRemote]
        return flags.contains(where: needsYou.contains) ? .needsYou : .done
    }
}

/// `overnight.log` — time | project | summary | status; a row expands to its files.
struct OvernightLogPanel: View {
    let facts: BriefingFacts
    let summary: GeneratedBriefing.Section?
    @Binding var cursor: ConsoleCursor?
    @Binding var expanded: Set<String>

    var body: some View {
        let groups = OvernightGroup.make(from: facts, summary: summary)
        Panel("overnight.log", counts: "\(Format.plural(facts.sessions.count, "session")) · \(Format.plural(facts.commits.count, "commit"))") {
            if groups.isEmpty {
                ConsoleMessage(text: "quiet night — nothing since \(Format.time(facts.period.from))")
            }
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                if index > 0 { RowDivider() }
                OvernightRow(
                    group: group,
                    isSelected: cursor == .overnight(group.id),
                    isExpanded: expanded.contains(group.id)
                ) {
                    cursor = .overnight(group.id)
                    withAnimation(DS.Motion.standard) {
                        if expanded.contains(group.id) { expanded.remove(group.id) } else { expanded.insert(group.id) }
                    }
                }
                .id(ConsoleCursor.overnight(group.id))
            }
        }
    }
}

struct OvernightRow: View {
    let group: OvernightGroup
    let isSelected: Bool
    let isExpanded: Bool
    let toggle: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.m) {
                    Text(Format.time(group.latest))
                        .font(DS.Font.time)
                        .foregroundStyle(DS.Color.dim)
                        .frame(width: DS.Size.timeColumn, alignment: .leading)
                    Text(group.name.lowercased())
                        .font(DS.Font.meta)
                        .foregroundStyle(DS.Color.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: DS.Size.projectColumn, alignment: .leading)
                    Text(group.summary)
                        .font(DS.Font.summary)
                        .foregroundStyle(DS.Color.text)
                        .lineLimit(isExpanded ? 3 : 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    StatusTag(kind: group.status)
                        .frame(width: DS.Size.statusColumn, alignment: .trailing)
                }
                .padding(.horizontal, DS.Space.rowHorizontal)
                .padding(.vertical, DS.Space.rowVertical)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    ForEach(group.entries) { entry in
                        EntryLine(entry: entry)
                    }
                }
                .padding(.leading, DS.Space.rowHorizontal + DS.Size.timeColumn + DS.Space.m)
                .padding(.trailing, DS.Space.rowHorizontal)
                .padding(.bottom, DS.Space.m)
                .transition(.opacity.combined(with: .offset(y: -DS.Motion.offset)))
            }
        }
        .rowBackground(selected: isSelected, hovered: isHovered)
        .onHover { hovering in withAnimation(DS.Motion.fast) { isHovered = hovering } }
        .accessibilityElement(children: .combine)
        .accessibilityHint(isExpanded ? "Collapse" : "Show files changed")
    }
}

/// One session or commit inside an expanded overnight row, with its files.
private struct EntryLine: View {
    let entry: OvernightGroup.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                switch entry {
                case let .session(session):
                    Text("session").font(DS.Font.tag).foregroundStyle(DS.Color.dim)
                    Text(Format.timeRange(session.startedAt, session.endedAt)).font(DS.Font.metaSmall).foregroundStyle(DS.Color.dim)
                    Text(session.title ?? "Claude session").font(DS.Font.small).foregroundStyle(DS.Color.muted).lineLimit(1)
                case let .commit(commit):
                    Text(commit.shortHash).font(DS.Font.metaSmall).foregroundStyle(DS.Color.muted)
                    Text(commit.subject).font(DS.Font.small).foregroundStyle(DS.Color.muted).lineLimit(1)
                    Text("+\(commit.insertions) −\(commit.deletions)").font(DS.Font.metaSmall).foregroundStyle(DS.Color.dim)
                }
            }
            ForEach(files.prefix(8), id: \.self) { file in
                Text("  \(file)")
                    .font(DS.Font.metaSmall)
                    .foregroundStyle(DS.Color.dim)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .textSelection(.enabled)
            }
            if files.count > 8 {
                Text("  … \(files.count - 8) more").font(DS.Font.metaSmall).foregroundStyle(DS.Color.dim)
            }
        }
    }

    private var files: [String] {
        switch entry {
        case let .session(session): session.filesEdited
        case let .commit(commit): commit.files
        }
    }
}

#Preview("overnight.log") {
    @Previewable @State var cursor: ConsoleCursor?
    @Previewable @State var expanded: Set<String> = ["repo:thermground"]
    OvernightLogPanel(facts: MockData.briefing().facts, summary: MockData.generated.section(.overnight), cursor: $cursor, expanded: $expanded)
        .padding(DS.Space.xxl)
        .frame(width: 1040)
        .background(ConsoleBackdrop())
        .preferredColorScheme(.dark)
}
