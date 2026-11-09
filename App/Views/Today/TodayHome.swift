import MorningKit
import SwiftUI

// MARK: - Hero

/// Orb, greeting, the day's headline and three numbers, on a softly lit stage.
struct TodayHero<Stats: View>: View {
    let overline: String
    let title: String
    var isWorking = false
    @ViewBuilder var stats: Stats
    @Environment(\.accent) private var accent
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.xxl) {
            AssistantCore(mood: isWorking || model.isGenerating ? .working : (model.focusBlock != nil ? .focus : .idle))
                .padding(.vertical, -DS.Space.l)
            VStack(alignment: .leading, spacing: DS.Space.s + DS.Space.xxs) {
                Text(overline)
                    .font(DS.Font.greeting)
                    .foregroundStyle(DS.Color.accentInk(accent))
                Text(title)
                    .font(DS.Font.heroTitle)
                    .tracking(DS.Tracking.hero)
                    .foregroundStyle(LinearGradient(colors: [DS.Color.heading, DS.Color.muted], startPoint: .top, endPoint: .bottom))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.xxl) {
                    stats
                }
                .padding(.top, DS.Space.s)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DS.Space.xxl + DS.Space.l)
        .padding(.top, DS.Space.xxl + DS.Space.s)
        .padding(.bottom, DS.Space.xxl)
        .frame(maxWidth: DS.Size.contentMaxWidth + DS.Space.xxl, alignment: .leading)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                DS.Color.stageBottom
                RadialGradient(colors: [DS.Color.stageTop, DS.Color.stageTop.opacity(0)], center: UnitPoint(x: 0.15, y: 0), startRadius: 0, endRadius: 900)
            }
        }
        .overlay(alignment: .bottom) { RowDivider() }
    }
}

/// `1h 20m focus`
struct HeroStat: View {
    let value: String
    let label: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
            Text(value)
                .font(DS.Font.heroStat)
                .tracking(-0.6)
                .foregroundStyle(DS.Color.heading)
                .contentTransition(.numericText())
            Text(label)
                .font(DS.Font.small)
                .foregroundStyle(DS.Color.muted)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Card

/// A titled card for the home grid.
struct HomeCard<Trailing: View, Content: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(DS.Font.cardTitle)
                    .foregroundStyle(DS.Color.text)
                Spacer(minLength: DS.Space.s)
                trailing
                    .font(DS.Font.small)
                    .foregroundStyle(DS.Color.muted)
            }
            .padding(.horizontal, DS.Space.l + DS.Space.xs)
            .padding(.top, DS.Space.l + DS.Space.xxs)
            .padding(.bottom, DS.Space.s)
            content
        }
        .padding(.bottom, DS.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.panel, in: RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
                .strokeBorder(DS.Color.border, lineWidth: DS.Size.hairline)
        }
        .shadow(color: DS.Color.shadow, radius: 1.5, y: 1)
    }
}

extension HomeCard where Trailing == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = EmptyView()
        self.content = content()
    }
}

/// A selectable row inside a home card.
struct HomeRow<Content: View>: View {
    var isSelected = false
    let action: () -> Void
    @ViewBuilder var content: Content
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            content
                .padding(.horizontal, DS.Space.l + DS.Space.xs)
                .padding(.vertical, DS.Space.s + DS.Space.xxs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .rowBackground(selected: isSelected, hovered: isHovered)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(DS.Motion.fast) { isHovered = hovering } }
    }
}

// MARK: - News

/// "Worth reading": source and age, title, and the link to a project when there is one.
struct NewsCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accent) private var accent
    let briefingID: String
    @Binding var cursor: ConsoleCursor?

    var body: some View {
        let items = model.newsPreview(for: briefingID)
        HomeCard(title: "Worth reading") {
            Button("All news") { model.selection = .news }
                .buttonStyle(.plain)
                .help("Open News (⌘4)")
        } content: {
            if items.isEmpty {
                Text(model.settings.newsEnabled ? "No news for this day yet." : "News is off. Turn it on in Settings.")
                    .font(DS.Font.small)
                    .foregroundStyle(DS.Color.dim)
                    .padding(.horizontal, DS.Space.l + DS.Space.xs)
                    .padding(.vertical, DS.Space.s)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { RowDivider().padding(.horizontal, DS.Space.l + DS.Space.xs) }
                HomeRow(isSelected: cursor == .news(item.id)) {
                    cursor = .news(item.id)
                    model.openNews(item)
                } content: {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        HStack(spacing: DS.Space.xs) {
                            Text(meta(item))
                            if model.isSaved(item) {
                                Text("· Saved").foregroundStyle(DS.Color.accentInk(accent))
                            }
                        }
                        .font(DS.Font.metaSmall)
                        .foregroundStyle(DS.Color.dim)
                        Text(item.title)
                            .font(DS.Font.newsTitle)
                            .foregroundStyle(DS.Color.heading)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let relevance = item.relevance {
                            Text(relevance)
                                .font(DS.Font.small)
                                .foregroundStyle(DS.Color.accentInk(accent))
                                .lineLimit(1)
                        }
                    }
                    .opacity(model.isRead(item) ? 0.55 : 1)
                }
                .id(ConsoleCursor.news(item.id))
                .help(item.summary)
            }
        }
    }

    private func meta(_ item: NewsItem) -> String {
        [item.source, item.publishedAt.map { Format.relative($0) }].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Overnight

/// What happened while you were away: one line per project.
struct OvernightCard: View {
    @Environment(AppModel.self) private var model
    let facts: BriefingFacts
    let summary: GeneratedBriefing.Section?
    @Binding var cursor: ConsoleCursor?
    @State private var showsAll = false
    private let collapsed = 4

    var body: some View {
        let groups = OvernightGroup.make(from: facts, summary: summary)
        HomeCard(title: "Overnight") {
            Text(counts)
        } content: {
            if groups.isEmpty {
                Text("Nothing ran overnight.")
                    .font(DS.Font.small)
                    .foregroundStyle(DS.Color.dim)
                    .padding(.horizontal, DS.Space.l + DS.Space.xs)
                    .padding(.vertical, DS.Space.s)
            }
            ForEach(showsAll ? groups : Array(groups.prefix(collapsed))) { group in
                HomeRow(isSelected: cursor == .overnight(group.id)) {
                    cursor = .overnight(group.id)
                    open(group)
                } content: {
                    HStack(spacing: DS.Space.m) {
                        Circle().fill(color(group.status)).frame(width: DS.Size.dot + 1, height: DS.Size.dot + 1)
                        (Text(group.name).fontWeight(.medium) + Text(" — \(group.summary)").foregroundStyle(DS.Color.muted))
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: DS.Space.s)
                        Text(Format.time(group.latest))
                            .font(DS.Font.time)
                            .foregroundStyle(DS.Color.dim)
                    }
                }
                .id(ConsoleCursor.overnight(group.id))
                .help(group.project == nil ? group.summary : "Open \(group.name) in Projects")
            }
            if groups.count > collapsed {
                Button(showsAll ? "Show less" : "Show \(groups.count - collapsed) more") {
                    withAnimation(DS.Motion.standard) { showsAll.toggle() }
                }
                .buttonStyle(.plain)
                .font(DS.Font.small)
                .foregroundStyle(DS.Color.muted)
                .padding(.horizontal, DS.Space.l + DS.Space.xs)
                .padding(.top, DS.Space.xs)
            }
        }
    }

    private var counts: String {
        [
            facts.sessions.isEmpty ? nil : Format.plural(facts.sessions.count, "session"),
            facts.commits.isEmpty ? nil : Format.plural(facts.commits.count, "commit"),
        ].compactMap { $0 }.joined(separator: " · ")
    }

    private func color(_ status: StatusTag.Kind) -> Color {
        switch status {
        case .failed: DS.Color.failed
        case .needsYou: DS.Color.warn
        default: DS.Color.ok
        }
    }

    func open(_ group: OvernightGroup) {
        guard let project = group.project else { return }
        model.selectedProjectID = project.id
        model.selection = .projects
    }
}

// MARK: - Decisions

/// Things only you can decide: loose files, branches, reviews. Open in Terminal, editor or GitHub.
struct DecisionsCard: View {
    let facts: BriefingFacts
    let section: GeneratedBriefing.Section?
    @Binding var cursor: ConsoleCursor?
    @State private var showsAll = false
    private let collapsed = 4

    var body: some View {
        let rows = AttentionRowModel.rows(facts: facts, section: section)
        HomeCard(title: "Needs your decision") {
            if !rows.isEmpty { Text("\(rows.count)") }
        } content: {
            if rows.isEmpty {
                Text("Nothing is waiting on you.")
                    .font(DS.Font.small)
                    .foregroundStyle(DS.Color.dim)
                    .padding(.horizontal, DS.Space.l + DS.Space.xs)
                    .padding(.vertical, DS.Space.s)
            }
            ForEach(Array((showsAll ? rows : Array(rows.prefix(collapsed))).enumerated()), id: \.offset) { index, row in
                DecisionRow(row: row, isSelected: cursor == .attention(index)) {
                    cursor = .attention(index)
                }
                .id(ConsoleCursor.attention(index))
            }
            if rows.count > collapsed {
                Button(showsAll ? "Show less" : "Show \(rows.count - collapsed) more") {
                    withAnimation(DS.Motion.standard) { showsAll.toggle() }
                }
                .buttonStyle(.plain)
                .font(DS.Font.small)
                .foregroundStyle(DS.Color.muted)
                .padding(.horizontal, DS.Space.l + DS.Space.xs)
                .padding(.top, DS.Space.xs)
            }
        }
    }
}

struct DecisionRow: View {
    let row: AttentionRowModel
    let isSelected: Bool
    let select: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.Space.m) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(row.title)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.text)
                    .lineLimit(1)
                if isSelected, let detail = row.detail {
                    Text(detail)
                        .font(DS.Font.small)
                        .foregroundStyle(DS.Color.muted)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: DS.Space.s)
            if isHovered || isSelected {
                HStack(spacing: DS.Space.xxs) {
                    if row.targets.path != nil {
                        IconButton(symbol: "terminal", help: "Open in Terminal (t)") { Opener.terminal(row.targets.path) }
                        IconButton(symbol: "chevron.left.forwardslash.chevron.right", help: "Open in editor (e)") { Opener.editor(row.targets.path) }
                    }
                    if row.targets.url != nil {
                        IconButton(symbol: "arrow.up.right.square", help: "Open on GitHub (g)") { Opener.url(row.targets.url) }
                    }
                }
                .transition(.opacity)
            } else {
                Text("t e g")
                    .font(DS.Font.key)
                    .foregroundStyle(DS.Color.dim.opacity(0.7))
            }
        }
        .padding(.horizontal, DS.Space.l + DS.Space.xs)
        .padding(.vertical, DS.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rowBackground(selected: isSelected, hovered: isHovered)
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { hovering in withAnimation(DS.Motion.fast) { isHovered = hovering } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(row.title)
    }
}

// MARK: - Agenda

/// Today's events and reminders, only when there are any.
struct AgendaCard: View {
    let facts: BriefingFacts
    @Binding var cursor: ConsoleCursor?

    var body: some View {
        let rows = AgendaRow.rows(for: facts)
        HomeCard("Calendar") {
            ForEach(rows) { row in
                HomeRow(isSelected: cursor == .agenda(row.id)) {
                    cursor = .agenda(row.id)
                    if let url = row.url { Opener.url(url) }
                } content: {
                    HStack(spacing: DS.Space.m) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color(hex: row.colorHex) ?? DS.Color.dim)
                            .frame(width: 3, height: 16)
                        Text(row.time)
                            .font(DS.Font.time)
                            .foregroundStyle(row.isOverdue ? DS.Color.failed : DS.Color.dim)
                            .frame(width: DS.Size.timeColumn + DS.Space.xxl, alignment: .leading)
                        Text(row.title)
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.text)
                            .lineLimit(1)
                    }
                }
                .id(ConsoleCursor.agenda(row.id))
            }
        }
    }
}

// MARK: - Later

/// Worthwhile work outside today's focus.
struct LaterCard: View {
    let tasks: [GeneratedBriefing.NextTask]
    let facts: BriefingFacts

    var body: some View {
        HomeCard("Also worth doing") {
            ForEach(Array(tasks.prefix(3).enumerated()), id: \.offset) { _, task in
                HStack(spacing: DS.Space.m) {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(task.title).font(DS.Font.body).foregroundStyle(DS.Color.text).lineLimit(1)
                        Text(facts.project(task.projectID)?.name ?? task.projectID)
                            .font(DS.Font.small)
                            .foregroundStyle(DS.Color.dim)
                    }
                    Spacer(minLength: DS.Space.s)
                    Text(Format.estimate(task.estimateMinutes))
                        .font(DS.Font.time)
                        .foregroundStyle(DS.Color.dim)
                }
                .padding(.horizontal, DS.Space.l + DS.Space.xs)
                .padding(.vertical, DS.Space.s)
                .help(task.reason)
            }
        }
    }
}
