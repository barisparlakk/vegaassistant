import MorningKit
import SwiftUI

/// Glass sidebar | status bar over the selected view.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(DS.Size.sidebarWidth)
        } detail: {
            VStack(spacing: 0) {
                StatusBar()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .id(model.selection)
            }
            .background(ConsoleBackdrop())
            .animation(DS.Motion.fast, value: model.selection)
            // The status bar takes the title bar's place.
            .ignoresSafeArea(.container, edges: .top)
        }
        // No window toolbar: the status bar is the top edge; traffic lights sit over the sidebar.
        .toolbar(.hidden, for: .windowToolbar)
    }

    @ViewBuilder private var content: some View {
        switch model.selection {
        case .today: TodayView()
        case .history: HistoryView()
        case .projects: ProjectsView()
        case .news: NewsView()
        case .settings: SettingsView()
        }
    }
}

// MARK: - Sidebar

/// The system sidebar material with the orb, the views and active projects.
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accent) private var accent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                HStack(spacing: DS.Space.s + DS.Space.xxs) {
                    VegaMarkShape()
                        .fill(LinearGradient(colors: [.white, accent], startPoint: .top, endPoint: .bottom))
                        .frame(width: DS.Size.brandOrb, height: DS.Size.brandOrb)
                    Text("Vega")
                        .font(DS.Font.brand)
                        .foregroundStyle(DS.Color.heading)
                }
                .padding(.horizontal, DS.Space.s)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    ForEach(SidebarItem.allCases) { item in
                        SidebarRow(item: item, isSelected: model.selection == item) {
                            model.selection = item
                        }
                    }
                }

                SidebarProjects()
            }
            .padding(.horizontal, DS.Space.s)
            .padding(.top, DS.Space.s)
            .padding(.bottom, DS.Space.xl)
        }
        .scrollIndicators(.never)
        .toolbar(removing: .sidebarToggle)
    }
}

struct SidebarRow: View {
    let item: SidebarItem
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.accent) private var accent

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s) {
                Image(systemName: item.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? DS.Color.accentInk(accent) : DS.Color.dim)
                    .frame(width: DS.Space.l + DS.Space.xs)
                Text(item.title)
                    .font(isSelected ? DS.Font.navSelected : DS.Font.nav)
                    .foregroundStyle(isSelected ? DS.Color.heading : DS.Color.muted)
                Spacer()
                Text(item.keys)
                    .font(DS.Font.key)
                    .foregroundStyle(DS.Color.dim)
                    .opacity(isSelected || isHovered ? 1 : 0.6)
            }
            .padding(.horizontal, DS.Space.s)
            .padding(.vertical, DS.Space.s - DS.Space.xxs)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .fill(isSelected ? DS.Color.selected : (isHovered ? DS.Color.hover : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(DS.Motion.fast) { isHovered = hovering } }
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// Repo slugs with their state: a deadline (accent), active (ok) or idle (dim).
struct SidebarProjects: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accent) private var accent

    var body: some View {
        let projects = model.currentBriefing?.facts.activeProjects ?? []
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            SectionLabel("Projects")
                .padding(.horizontal, DS.Space.s)
                .padding(.bottom, DS.Space.xs)
            if projects.isEmpty {
                Text("None yet")
                    .font(DS.Font.metaSmall)
                    .foregroundStyle(DS.Color.dim)
                    .padding(.horizontal, DS.Space.s)
            }
            ForEach(projects) { project in
                Button {
                    model.selection = .projects
                    model.selectedProjectID = project.id
                } label: {
                    HStack(spacing: DS.Space.s) {
                        Text(project.name)
                            .font(DS.Font.small)
                            .foregroundStyle(DS.Color.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: DS.Space.xs)
                        state(for: project)
                    }
                    .padding(.horizontal, DS.Space.s)
                    .padding(.vertical, DS.Space.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func state(for project: ProjectFact) -> some View {
        let state = ProjectState(project: project, daysToDeadline: model.daysUntilDeadline(project.id))
        Text(state.label)
            .font(DS.Font.tag)
            .foregroundStyle(state.color(accent: accent))
    }
}

/// A project's one-word state, shared by the sidebar and the Projects table.
struct ProjectState {
    enum Kind { case deadline(Int), active, idle }
    let kind: Kind

    init(project: ProjectFact, daysToDeadline: Int?, now: Date = .now) {
        if let days = daysToDeadline, days >= 0 {
            kind = .deadline(days)
        } else if let last = project.lastActivityAt, now.timeIntervalSince(last) < 2 * 86_400 {
            kind = .active
        } else {
            kind = .idle
        }
    }

    var label: String {
        switch kind {
        case let .deadline(days): "T-\(days)d"
        case .active: "Active"
        case .idle: "Idle"
        }
    }

    func color(accent: Color) -> Color {
        switch kind {
        case .deadline: DS.Color.accentInk(accent)
        case .active: DS.Color.ok
        case .idle: DS.Color.dim
        }
    }
}

// MARK: - Status bar

/// `Today ··················· ● Ready at 07:00  [Regenerate ⌘R]`
struct StatusBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.m) {
                Text(model.selection.title)
                    .font(DS.Font.cardTitle)
                    .foregroundStyle(DS.Color.text)
                Spacer(minLength: DS.Space.l)
                status
                Button {
                    model.regenerate()
                } label: {
                    ShortcutLabel(title: model.isGenerating ? "Working…" : "Regenerate", keys: "⌘R")
                }
                .buttonStyle(.consoleOutline)
                .disabled(model.isGenerating)
                .help("Regenerate today's briefing")
            }
            .padding(.horizontal, DS.Space.pageSide - DS.Space.s)
            .frame(height: DS.Size.statusBarHeight)
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
            RowDivider()
        }
    }

    @ViewBuilder private var status: some View {
        HStack(spacing: DS.Space.s) {
            if let block = model.focusBlock, !model.isGenerating {
                Button(action: model.stopBlock) {
                    TimelineView(.periodic(from: block.startedAt, by: 1)) { context in
                        Text("Focus \(Format.clock(context.date.timeIntervalSince(block.startedAt))) · \(block.title)")
                            .font(DS.Font.meta)
                            .foregroundStyle(DS.Color.accentInk(accent))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: DS.Size.statusBlockMaxWidth, alignment: .trailing)
                    }
                }
                .buttonStyle(.plain)
                .help("Stop the focus block")
                Text("·").font(DS.Font.meta).foregroundStyle(DS.Color.dim)
            }
            if let generation = model.generation {
                GlowDot(color: accent)
                    .skeletonPulse()
                TimelineView(.periodic(from: generation.startedAt, by: 1)) { context in
                    Text(generation.consoleLine(now: context.date))
                        .font(DS.Font.meta)
                        .foregroundStyle(DS.Color.text)
                        .contentTransition(.opacity)
                }
            } else if let error = model.lastError {
                GlowDot(color: DS.Color.failed)
                Text("Last run failed")
                    .font(DS.Font.meta)
                    .foregroundStyle(DS.Color.failed)
                    .help(error)
            } else if let briefing = model.currentBriefing {
                GlowDot(color: briefing.structured == nil ? DS.Color.failed : accent)
                Text("Ready at \(Format.time(briefing.generatedAt))\(briefing.structured == nil ? " · shown as text" : "")")
                    .font(DS.Font.meta)
                    .foregroundStyle(DS.Color.muted)
            } else {
                GlowDot(color: DS.Color.dim)
                Text("No runs yet")
                    .font(DS.Font.meta)
                    .foregroundStyle(DS.Color.dim)
            }
        }
        .lineLimit(1)
    }
}

#Preview("Root") {
    RootView()
        .environment(AppModel.preview())
        .environment(\.accent, DS.Color.defaultAccent)
        .tint(DS.Color.defaultAccent)
        .frame(width: 1280, height: 860)
        .preferredColorScheme(.dark)
}

#Preview("Root — generating") {
    RootView()
        .environment(AppModel.preview(generating: true))
        .environment(\.accent, DS.Color.defaultAccent)
        .frame(width: 1280, height: 860)
        .preferredColorScheme(.dark)
}
