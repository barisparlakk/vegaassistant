import MorningKit
import SwiftUI

/// Every discovered project, with a detail inspector.
struct ProjectsView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedID: String?
    @State private var query = ""

    var body: some View {
        Group {
            if let facts = model.currentBriefing?.facts, !facts.projects.isEmpty {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.projectCardMinWidth), spacing: Spacing.m)], spacing: Spacing.m) {
                        ForEach(filtered(facts.projects)) { project in
                            Button {
                                withAnimation(Motion.spring) { selectedID = selectedID == project.id ? nil : project.id }
                            } label: {
                                ProjectCard(
                                    project: project,
                                    attentionCount: facts.attention.filter { $0.projectID == project.id }.count,
                                    isSelected: selectedID == project.id,
                                    showsMenu: false
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(project.name)
                            .accessibilityValue(selectedID == project.id ? "selected" : "")
                            // The open menu sits outside the button so both stay usable.
                            .overlay(alignment: .topTrailing) {
                                ProjectOpenMenu(project: project)
                                    .padding(Spacing.l)
                            }
                        }
                    }
                    .padding(Spacing.xxl)
                }
                .background(ConsoleBackdrop())
                .inspector(isPresented: Binding(get: { selectedID != nil }, set: { if !$0 { selectedID = nil } })) {
                    if let project = facts.project(selectedID) {
                        ProjectDetail(project: project, facts: facts)
                            .inspectorColumnWidth(min: Metrics.inspectorMinWidth, ideal: Metrics.inspectorIdealWidth, max: Metrics.inspectorMaxWidth)
                    }
                }
                .searchable(text: $query, placement: .toolbar, prompt: "Filter projects")
            } else {
                ContentUnavailableView {
                    Label("No projects yet", systemImage: "square.grid.2x2")
                } description: {
                    Text("Projects appear after the first briefing scans your repository folders.")
                } actions: {
                    Button("Choose folders…") { model.selection = .settings }
                }
            }
        }
        .navigationTitle("Projects")
    }

    private func filtered(_ projects: [ProjectFact]) -> [ProjectFact] {
        guard !query.isEmpty else { return projects }
        return projects.filter { $0.name.localizedCaseInsensitiveContains(query) || ($0.branch ?? "").localizedCaseInsensitiveContains(query) }
    }
}

struct ProjectDetail: View {
    let project: ProjectFact
    let facts: BriefingFacts

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                HStack(spacing: Spacing.m) {
                    ProjectGlyph(id: project.id, name: project.name, size: Metrics.glyphLarge)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(project.name).font(Typography.focusProject)
                        Text(PathDisplay.abbreviate(project.path))
                            .font(Typography.mono)
                            .foregroundStyle(Palette.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                FlowLayout(spacing: Spacing.s) {
                    Button("Terminal", systemImage: "terminal") { Opener.terminal(project.path) }
                    Button("Editor", systemImage: "chevron.left.forwardslash.chevron.right") { Opener.editor(project.path) }
                    if let url = project.webURL {
                        Button("GitHub", systemImage: "safari") { Opener.url(url) }
                    }
                }
                .glassButtonStyle()
                .controlSize(.small)

                CompactProjectStats(project: project)

                let attention = facts.attention.filter { $0.projectID == project.id }
                if !attention.isEmpty {
                    detailSection("Needs attention") {
                        ForEach(attention) { item in
                            Label {
                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(item.title).font(Typography.body)
                                    Text(item.detail).font(Typography.caption).foregroundStyle(Palette.textSecondary)
                                }
                            } icon: {
                                Image(systemName: item.kind.symbol).foregroundStyle(Palette.severity(item.severity))
                            }
                        }
                    }
                }

                if !project.branches.isEmpty {
                    detailSection("Branches") {
                        ForEach(project.branches, id: \.name) { branch in
                            HStack(spacing: Spacing.s) {
                                Image(systemName: branch.isCurrent ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(branch.isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(Palette.textTertiary))
                                Text(branch.name).font(Typography.mono)
                                if branch.isStale { Pill(text: "stale", tint: Palette.medium) }
                                if branch.ahead > 0 { Pill(text: "↑\(branch.ahead)", tint: Palette.medium) }
                                if branch.behind > 0 { Pill(text: "↓\(branch.behind)") }
                                Spacer()
                                Text(branch.lastCommitAt.map { Format.relative($0) } ?? "")
                                    .font(Typography.caption)
                                    .foregroundStyle(Palette.textTertiary)
                            }
                        }
                    }
                }

                let sessions = facts.sessions(for: project.id)
                let commits = facts.commits(for: project.id)
                if !sessions.isEmpty || !commits.isEmpty {
                    detailSection("Since the last briefing") {
                        ForEach(sessions) { EvidenceRow(evidence: .session($0)) }
                        ForEach(commits) { EvidenceRow(evidence: .commit($0)) }
                    }
                }

                ForEach(facts.notes.filter { $0.projectID == project.id }) { note in
                    detailSection(note.file) {
                        if note.openItems.isEmpty, let excerpt = note.excerpt {
                            Text(excerpt).font(Typography.caption).foregroundStyle(Palette.textSecondary)
                        }
                        ForEach(note.openItems, id: \.self) { item in
                            Label(item, systemImage: "square")
                                .font(Typography.body)
                        }
                    }
                }
            }
            .padding(Spacing.xl)
        }
    }

    private func detailSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title.uppercased())
                .font(Typography.overline)
                .tracking(1)
                .foregroundStyle(Palette.textSecondary)
            content()
        }
    }
}

/// Stats laid out for a narrow column: a 2-wide grid and a full-width sparkline.
struct CompactProjectStats: View {
    let project: ProjectFact

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Grid(alignment: .leading, horizontalSpacing: Spacing.xl, verticalSpacing: Spacing.m) {
                GridRow {
                    stat("\(project.commitsLast14Days.reduce(0, +))", "commits, 14 days")
                    stat(project.lastActivityAt.map { Format.relative($0) } ?? "—", "last touched")
                }
                GridRow {
                    stat("\(project.changedFiles + project.untrackedFiles)", "uncommitted files")
                    stat("\(project.ahead)", "unpushed commits")
                }
            }
            if project.kind == .repo, !project.commitsLast14Days.isEmpty {
                Sparkline(values: project.commitsLast14Days)
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(value).font(Typography.numeric)
            Text(label).font(Typography.caption).foregroundStyle(Palette.textSecondary).fixedSize()
        }
    }
}

enum PathDisplay {
    static func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

#Preview("Projects") {
    ProjectsView()
        .environment(AppModel.preview())
        .tint(AccentChoice.sunrise.color)
        .frame(width: 1100, height: 760)
}

#Preview("Project detail") {
    let facts = MockData.briefing().facts
    ProjectDetail(project: facts.projects[0], facts: facts)
        .frame(width: 380, height: 800)
        .tint(AccentChoice.sunrise.color)
}
