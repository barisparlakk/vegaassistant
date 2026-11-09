import MorningKit
import SwiftUI

/// Claude sessions and commits since the last briefing, grouped by project.
struct OvernightSection: View {
    let facts: BriefingFacts
    let summary: GeneratedBriefing.Section?

    var body: some View {
        let groups = OvernightGroup.make(from: facts, summary: summary)
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(
                "Overnight",
                symbol: "moon.stars",
                subtitle: "since \(Format.relative(facts.period.from))"
            )
            if groups.isEmpty {
                Card {
                    Label("Nothing happened since the last briefing.", systemImage: "moon.zzz")
                        .font(Typography.body)
                        .foregroundStyle(Palette.textSecondary)
                }
            } else {
                VStack(spacing: Spacing.m) {
                    ForEach(groups) { group in
                        OvernightProjectCard(group: group)
                    }
                }
            }
        }
    }
}

/// One project's overnight activity, ready for display.
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
    let headline: String?
    let detail: String?
    let entries: [Entry]
    let sessionCount: Int
    let commitCount: Int

    static func make(from facts: BriefingFacts, summary: GeneratedBriefing.Section?) -> [OvernightGroup] {
        var ids = (facts.sessions.compactMap(\.projectID) + facts.commits.map(\.projectID)).uniqued()
        let unassigned = facts.sessions.filter { $0.projectID == nil }
        if !unassigned.isEmpty { ids.append("other") }

        return ids.map { id in
            let sessions = id == "other" ? unassigned : facts.sessions(for: id)
            let commits = id == "other" ? [] : facts.commits(for: id)
            let project = facts.project(id)
            let item = summary?.items.first { $0.projectID == id }
                ?? (id == "other" ? summary?.items.first { $0.projectID == nil } : nil)
            let entries = (sessions.map(Entry.session) + commits.map(Entry.commit)).sorted { $0.date > $1.date }
            return OvernightGroup(
                id: id,
                name: project?.name ?? (id == "other" ? "Other chats" : id),
                project: project,
                headline: item?.title,
                detail: item?.detail,
                entries: entries,
                sessionCount: sessions.count,
                commitCount: commits.count
            )
        }
        .sorted { ($0.entries.first?.date ?? .distantPast) > ($1.entries.first?.date ?? .distantPast) }
    }
}

struct OvernightProjectCard: View {
    let group: OvernightGroup
    @State private var showsAll = false
    private let collapsedCount = 4

    var body: some View {
        Card(padding: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                header
                if let headline = group.headline {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(headline)
                            .font(Typography.bodyEmphasis)
                        if let detail = group.detail {
                            Text(detail)
                                .font(Typography.caption)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 0) {
                    let visible = showsAll ? group.entries : Array(group.entries.prefix(collapsedCount))
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                        TimelineEntryRow(entry: entry, isLast: index == visible.count - 1)
                    }
                }
                if group.entries.count > collapsedCount {
                    Button(showsAll ? "Show less" : "Show \(group.entries.count - collapsedCount) more") {
                        withAnimation(Motion.spring) { showsAll.toggle() }
                    }
                    .buttonStyle(.borderless)
                    .font(Typography.captionEmphasis)
                    .padding(.leading, Metrics.timelineGutter + Spacing.m)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.s) {
            if group.project != nil {
                ProjectGlyph(id: group.id, name: group.name, size: Metrics.glyphSmall)
            } else {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: Metrics.glyphSmall)
            }
            Text(group.name).font(Typography.cardTitle)
            if let branch = group.project?.branch {
                Text(branch).font(Typography.mono).foregroundStyle(Palette.textTertiary)
            }
            Spacer()
            if group.sessionCount > 0 {
                Label(Format.plural(group.sessionCount, "session"), systemImage: "sparkles")
                    .foregroundStyle(Palette.claude)
            }
            if group.commitCount > 0 {
                Label(Format.plural(group.commitCount, "commit"), systemImage: "smallcircle.filled.circle")
                    .foregroundStyle(Palette.commit)
            }
        }
        .font(Typography.captionEmphasis)
        .labelStyle(.titleAndIcon)
    }
}

/// A timeline node: time in the gutter, a dot on the rail, details that expand to show files.
struct TimelineEntryRow: View {
    let entry: OvernightGroup.Entry
    let isLast: Bool
    @State private var isExpanded = false
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Text(Format.time(entry.date))
                .font(Typography.mono)
                .foregroundStyle(Palette.textTertiary)
                .frame(width: Metrics.timelineGutter, alignment: .trailing)
                .padding(.top, Spacing.xxs)

            rail

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Button {
                    withAnimation(Motion.spring) { isExpanded.toggle() }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                        summary
                        Spacer(minLength: Spacing.s)
                        if !files.isEmpty {
                            Image(systemName: "chevron.right")
                                .font(Typography.caption)
                                .foregroundStyle(Palette.textTertiary)
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                .opacity(isHovered || isExpanded ? 1 : 0)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(files.isEmpty)

                if isExpanded {
                    FileList(files: files)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.bottom, isLast ? 0 : Spacing.m)
        }
        .onHover { isHovered = $0 }
    }

    private var rail: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(nodeColor)
                .frame(width: Metrics.timelineNode, height: Metrics.timelineNode)
                .padding(.top, Spacing.xs)
            if !isLast {
                Rectangle()
                    .fill(Palette.stroke)
                    .frame(width: Metrics.hairline)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: Metrics.timelineNode)
    }

    @ViewBuilder private var summary: some View {
        switch entry {
        case let .session(session):
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "sparkles").foregroundStyle(Palette.claude)
                    Text(session.title ?? "Claude session").font(Typography.bodyEmphasis)
                }
                Text(sessionStats(session))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
        case let .commit(commit):
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text(commit.shortHash)
                    .font(Typography.mono)
                    .foregroundStyle(Palette.commit)
                Text(commit.subject)
                    .font(Typography.body)
                    .lineLimit(1)
                Text("+\(commit.insertions) −\(commit.deletions)")
                    .font(Typography.mono)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private var files: [String] {
        switch entry {
        case let .session(session): session.filesEdited
        case let .commit(commit): commit.files
        }
    }

    private var nodeColor: Color {
        switch entry {
        case .session: Palette.claude
        case .commit: Palette.commit
        }
    }

    private func sessionStats(_ session: SessionFact) -> String {
        var parts = [
            "\(Format.timeRange(session.startedAt, session.endedAt))",
            Format.plural(session.promptCount, "prompt"),
            Format.plural(session.filesEdited.count, "file"),
        ]
        if let added = session.linesAdded, let removed = session.linesRemoved, added + removed > 0 {
            parts.append("+\(added) −\(removed)")
        }
        return parts.joined(separator: " · ")
    }
}

struct FileList: View {
    let files: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            ForEach(files, id: \.self) { file in
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "doc")
                        .foregroundStyle(Palette.textTertiary)
                    Text(file)
                        .font(Typography.mono)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
        }
        .padding(Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
        .textSelection(.enabled)
    }
}

#Preview {
    ScrollView {
        OvernightSection(facts: MockData.briefing().facts, summary: MockData.generated.section(.overnight))
            .padding(Spacing.xxl)
    }
    .frame(width: 860, height: 900)
    .tint(AccentChoice.sunrise.color)
}
