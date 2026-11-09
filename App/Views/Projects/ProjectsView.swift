import MorningKit
import SwiftUI

/// Every project as a table: slug | branch | last touched | 14-day line | state.
struct ProjectsView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var showsDetail = false
    @FocusState private var focus: Field?

    private enum Field { case table, filter }

    var body: some View {
        let facts = model.currentBriefing?.facts
        HStack(spacing: 0) {
            table(facts: facts)
            // A plain side panel: the system inspector loops layout in a window without a toolbar.
            if showsDetail, let facts, let project = facts.project(model.selectedProjectID) {
                Rectangle().fill(DS.Color.border).frame(width: DS.Size.hairline)
                ProjectDetail(project: project, facts: facts)
                    .frame(width: DS.Size.inspectorWidth)
                    .transition(.opacity.combined(with: .offset(x: DS.Space.l)))
            }
        }
        .animation(DS.Motion.standard, value: showsDetail)
        .onAppear {
            focus = .table
            if model.selectedProjectID != nil { showsDetail = true }
        }
    }

    private func table(facts: BriefingFacts?) -> some View {
        let projects = filtered(facts?.projects ?? [])
        return VStack(alignment: .leading, spacing: DS.Space.l) {
            HStack(spacing: DS.Space.m) {
                HStack(spacing: DS.Space.s) {
                    Text("/").font(DS.Font.meta).foregroundStyle(DS.Color.dim)
                    TextField("filter", text: $query)
                        .textFieldStyle(.plain)
                        .font(DS.Font.meta)
                        .foregroundStyle(DS.Color.text)
                        .focused($focus, equals: .filter)
                        .onSubmit { focus = .table }
                }
                .padding(.horizontal, DS.Space.m)
                .padding(.vertical, DS.Space.s - DS.Space.xxs)
                .frame(maxWidth: DS.Size.filterFieldWidth)
                .background(DS.Color.panel, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                        .strokeBorder(focus == .filter ? DS.Color.dim : DS.Color.border, lineWidth: DS.Size.hairline)
                }
                Spacer()
                Text("\(projects.count) of \(facts?.projects.count ?? 0)")
                    .font(DS.Font.metaSmall)
                    .foregroundStyle(DS.Color.dim)
            }

            if let facts, !facts.projects.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        Panel {
                            header
                        } content: {
                            if projects.isEmpty {
                                ConsoleMessage(text: "no project matches \"\(query)\"")
                            }
                            ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                                if index > 0 { RowDivider() }
                                ProjectTableRow(
                                    project: project,
                                    state: ProjectState(project: project, daysToDeadline: model.daysUntilDeadline(project.id)),
                                    isSelected: model.selectedProjectID == project.id,
                                    isCompact: showsDetail
                                ) {
                                    model.selectedProjectID = project.id
                                    showsDetail = true
                                }
                                .id(project.id)
                            }
                        }
                        KeyboardHints(hints: [("j/k", "move"), ("↵", "details"), ("/", "filter"), ("t e g", "terminal · editor · github"), ("esc", "close")])
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, DS.Space.m)
                    }
                    .scrollContentBackground(.hidden)
                    .focusable()
                    .focused($focus, equals: .table)
                    .focusEffectDisabled()
                    .onKeyPress(keys: [.downArrow, "j"]) { _ in move(1, in: projects, proxy); return .handled }
                    .onKeyPress(keys: [.upArrow, "k"]) { _ in move(-1, in: projects, proxy); return .handled }
                    .onKeyPress(.return) { showsDetail = model.selectedProjectID != nil; return .handled }
                    .onKeyPress(.escape) { showsDetail = false; return .handled }
                    .onKeyPress("/") { focus = .filter; return .handled }
                    .onKeyPress(keys: ["t", "e", "g"]) { press in
                        guard let project = facts.project(model.selectedProjectID) else { return .ignored }
                        switch press.characters {
                        case "t": Opener.terminal(project.path)
                        case "e": Opener.editor(project.path)
                        default: Opener.url(project.webURL)
                        }
                        return .handled
                    }
                }
            } else {
                Panel {
                    ConsoleMessage(text: "no projects yet — they appear after the first briefing", actionTitle: "regenerate", keys: "⌘R", action: model.regenerate)
                }
                Spacer()
            }
        }
        .padding(.horizontal, DS.Space.pageSide)
        .padding(.top, DS.Space.pageTop)
        .frame(maxWidth: DS.Size.contentMaxWidth)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.m) {
                column("  slug", width: DS.Size.projectColumn + DS.Space.xl)
                column("branch", width: nil)
                if !showsDetail { column("last touched", width: DS.Size.projectColumn) }
                column("14d", width: sparklineWidth(compact: showsDetail))
                column("state", width: DS.Size.statusColumn - DS.Space.xl, alignment: .trailing)
            }
            .padding(.horizontal, DS.Space.rowHorizontal)
            .padding(.vertical, DS.Space.s)
            RowDivider()
        }
    }

    private func column(_ title: String, width: CGFloat?, alignment: Alignment = .leading) -> some View {
        Text(title)
            .font(DS.Font.label)
            .tracking(DS.Tracking.label / 2)
            .foregroundStyle(DS.Color.dim)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }

    func sparklineWidth(compact: Bool) -> CGFloat {
        compact ? DS.Size.sparklineCompactWidth : DS.Size.sparkline.width
    }

    private func filtered(_ projects: [ProjectFact]) -> [ProjectFact] {
        guard !query.isEmpty else { return projects }
        return projects.filter { $0.name.localizedCaseInsensitiveContains(query) || ($0.branch ?? "").localizedCaseInsensitiveContains(query) }
    }

    private func move(_ step: Int, in projects: [ProjectFact], _ proxy: ScrollViewProxy) {
        guard !projects.isEmpty else { return }
        let current = projects.firstIndex { $0.id == model.selectedProjectID }
        let next = current.map { min(max($0 + step, 0), projects.count - 1) } ?? 0
        withAnimation(DS.Motion.fast) { model.selectedProjectID = projects[next].id }
        withAnimation(DS.Motion.standard) { proxy.scrollTo(projects[next].id, anchor: .center) }
    }
}

struct ProjectTableRow: View {
    let project: ProjectFact
    let state: ProjectState
    let isSelected: Bool
    /// With the detail panel open: no "last touched" column, shorter sparkline.
    var isCompact = false
    let select: () -> Void
    @State private var isHovered = false
    @Environment(\.accent) private var accent

    var body: some View {
        Button(action: select) {
            HStack(spacing: DS.Space.m) {
                HStack(spacing: DS.Space.xs) {
                    Text(isSelected ? "›" : " ").foregroundStyle(accent)
                    Text(project.name.lowercased()).foregroundStyle(DS.Color.heading)
                }
                .font(DS.Font.meta)
                .lineLimit(1)
                .frame(width: DS.Size.projectColumn + DS.Space.xl, alignment: .leading)
                HStack(spacing: DS.Space.xs) {
                    Text(project.branch ?? (project.kind == .folder ? "—" : "detached"))
                        .foregroundStyle(DS.Color.muted)
                    if project.isDirty { Text("*").foregroundStyle(DS.Color.accentInk(accent)).help("Uncommitted changes") }
                    if project.ahead > 0 { Text("↑\(project.ahead)").foregroundStyle(DS.Color.accentInk(accent)).help("Unpushed commits") }
                }
                .font(DS.Font.meta)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: DS.Size.branchMinWidth, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                if !isCompact {
                    Text(project.lastActivityAt.map { Format.relative($0) } ?? "—")
                        .font(DS.Font.time)
                        .foregroundStyle(DS.Color.dim)
                        .frame(width: DS.Size.projectColumn, alignment: .leading)
                }
                Group {
                    if project.kind == .repo {
                        SparkLine(
                            values: project.commitsLast14Days.isEmpty ? Array(repeating: 0, count: 14) : project.commitsLast14Days,
                            width: isCompact ? DS.Size.sparklineCompactWidth : DS.Size.sparkline.width
                        )
                    } else {
                        Text("—").font(DS.Font.meta).foregroundStyle(DS.Color.dim)
                    }
                }
                .frame(width: isCompact ? DS.Size.sparklineCompactWidth : DS.Size.sparkline.width, alignment: .leading)
                .clipped()
                Text(state.label)
                    .font(DS.Font.tag)
                    .foregroundStyle(state.color(accent: accent))
                    .frame(width: DS.Size.statusColumn - DS.Space.xl, alignment: .trailing)
            }
            .padding(.horizontal, DS.Space.rowHorizontal)
            .padding(.vertical, DS.Space.rowVertical)
            .rowBackground(selected: isSelected, hovered: isHovered)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(DS.Motion.fast) { isHovered = hovering } }
        .accessibilityLabel("\(project.name), \(state.label)")
    }
}

/// The inspector: actions, deadline, flags, branches, recent activity, notes.
struct ProjectDetail: View {
    @Environment(AppModel.self) private var model
    let project: ProjectFact
    let facts: BriefingFacts

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(project.name.lowercased())
                        .font(DS.Font.sans(22, .semibold))
                        .foregroundStyle(DS.Color.heading)
                    Text(PathDisplay.abbreviate(project.path))
                        .font(DS.Font.metaSmall)
                        .foregroundStyle(DS.Color.dim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                HStack(spacing: DS.Space.s) {
                    Button { Opener.terminal(project.path) } label: { ShortcutLabel(title: "terminal", keys: "T") }
                    Button { Opener.editor(project.path) } label: { ShortcutLabel(title: "editor", keys: "E") }
                    if let url = project.webURL {
                        Button { Opener.url(url) } label: { ShortcutLabel(title: "github", keys: "G") }
                    }
                }
                .buttonStyle(.consoleOutline)

                section("stats") {
                    Grid(alignment: .leading, horizontalSpacing: DS.Space.xl, verticalSpacing: DS.Space.s) {
                        GridRow {
                            stat("commits 14d", "\(project.commitsLast14Days.reduce(0, +))")
                            stat("last touched", project.lastActivityAt.map { Format.relative($0) } ?? "—")
                        }
                        GridRow {
                            stat("uncommitted", "\(project.changedFiles + project.untrackedFiles)")
                            stat("unpushed", "\(project.ahead)")
                        }
                    }
                    if project.kind == .repo, !project.commitsLast14Days.isEmpty {
                        SparkLine(values: project.commitsLast14Days)
                    }
                }

                section("deadline") {
                    DeadlineEditor(projectID: project.id)
                }

                let attention = facts.attention.filter { $0.projectID == project.id }
                if !attention.isEmpty {
                    section("attention") {
                        ForEach(attention) { item in
                            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                                Text(item.title).font(DS.Font.small).foregroundStyle(DS.Color.text)
                                Text(item.detail).font(DS.Font.metaSmall).foregroundStyle(DS.Color.dim)
                            }
                        }
                    }
                }

                if !project.branches.isEmpty {
                    section("branches") {
                        ForEach(project.branches, id: \.name) { branch in
                            HStack(spacing: DS.Space.s) {
                                Text(branch.isCurrent ? "*" : " ").foregroundStyle(DS.Color.ok)
                                Text(branch.name).foregroundStyle(DS.Color.text).lineLimit(1)
                                if branch.isStale { Text("stale").foregroundStyle(DS.Color.dim) }
                                if branch.ahead > 0 { Text("↑\(branch.ahead)").foregroundStyle(DS.Color.muted) }
                                if branch.behind > 0 { Text("↓\(branch.behind)").foregroundStyle(DS.Color.muted) }
                                Spacer()
                                Text(branch.lastCommitAt.map { Format.relative($0) } ?? "").foregroundStyle(DS.Color.dim)
                            }
                            .font(DS.Font.metaSmall)
                        }
                    }
                }

                let refs = facts.sessions(for: project.id).map(\.id) + facts.commits(for: project.id).map(\.id)
                if !refs.isEmpty {
                    section("since last briefing") {
                        ForEach(facts.evidence(refs).prefix(12)) { EvidenceRow(evidence: $0) }
                    }
                }

                ForEach(facts.notes.filter { $0.projectID == project.id }) { note in
                    section(note.file.lowercased()) {
                        if note.openItems.isEmpty, let excerpt = note.excerpt {
                            Text(excerpt).font(DS.Font.small).foregroundStyle(DS.Color.muted)
                        }
                        ForEach(note.openItems, id: \.self) { item in
                            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                                ConsoleCheckbox(isOn: false)
                                Text(item).font(DS.Font.small).foregroundStyle(DS.Color.text)
                            }
                        }
                    }
                }
            }
            .padding(DS.Space.xl)
        }
        .background(DS.Color.panel)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            SectionLabel(title)
            content()
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(value).font(DS.Font.meta).foregroundStyle(DS.Color.heading)
            Text(label).font(DS.Font.metaSmall).foregroundStyle(DS.Color.dim)
        }
    }
}

/// Sets or clears the project's deadline (shown as `T-Nd`).
struct DeadlineEditor: View {
    @Environment(AppModel.self) private var model
    let projectID: String

    var body: some View {
        HStack(spacing: DS.Space.s) {
            if let deadline = model.settings.projectDeadlines[projectID] {
                DatePicker("Deadline", selection: Binding(
                    get: { deadline },
                    set: { date in model.updateSettings { $0.projectDeadlines[projectID] = date } }
                ), displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.field)
                if let days = model.daysUntilDeadline(projectID) {
                    Text(days >= 0 ? "T-\(days)d" : "passed").font(DS.Font.tag).foregroundStyle(DS.Color.muted)
                }
                Spacer()
                Button("clear") { model.updateSettings { $0.projectDeadlines[projectID] = nil } }
                    .buttonStyle(.consoleGhost)
            } else {
                Button("+ set deadline") {
                    model.updateSettings { $0.projectDeadlines[projectID] = Calendar.current.date(byAdding: .day, value: 14, to: .now) }
                }
                .buttonStyle(.consoleOutline)
            }
        }
    }
}

/// `j/k move · ↵ details`
struct KeyboardHints: View {
    let hints: [(String, String)]

    var body: some View {
        HStack(spacing: DS.Space.m) {
            ForEach(hints, id: \.0) { keys, action in
                HStack(spacing: DS.Space.xs) {
                    KeyHint(keys)
                    Text(action).font(DS.Font.metaSmall).foregroundStyle(DS.Color.dim)
                }
            }
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
        .environment(\.accent, DS.Color.defaultAccent)
        .frame(width: 1100, height: 700)
        .background(ConsoleBackdrop())
        .preferredColorScheme(.dark)
}

#Preview("Project detail") {
    let facts = MockData.briefing().facts
    ProjectDetail(project: facts.projects[0], facts: facts)
        .environment(AppModel.preview())
        .frame(width: 360, height: 900)
        .preferredColorScheme(.dark)
}
