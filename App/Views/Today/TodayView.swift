import MorningKit
import SwiftUI

/// Today: the hero, then focus, overnight, news and decisions.
struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.isGenerating {
                TodaySkeleton()
            } else {
                switch model.today {
                case .loading:
                    TodaySkeleton()
                case .empty:
                    VStack(alignment: .leading, spacing: 0) {
                        if let error = model.lastError {
                            ConsoleMessage(text: "The last run failed: \(error)", actionTitle: "Try again", keys: "⌘R", tone: DS.Color.failed, action: model.regenerate)
                        } else {
                            ConsoleMessage(text: "No briefing for today yet.", actionTitle: "Regenerate", keys: "⌘R", action: model.regenerate)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, DS.Space.pageSide - DS.Space.rowHorizontal)
                    .padding(.top, DS.Space.pageTop)
                case let .loaded(briefing):
                    BriefingConsole(briefing: briefing, isToday: true)
                }
            }
        }
        .transition(.opacity)
        .animation(DS.Motion.standard, value: model.isGenerating)
    }
}

// MARK: - Cursor

/// One keyboard cursor across every selectable row on the page.
enum ConsoleCursor: Hashable {
    case task(String)
    case overnight(String)
    case agenda(String)
    case attention(Int)
    case news(String)
}

/// A full briefing as the home layout. Read-only in History.
struct BriefingConsole: View {
    @Environment(AppModel.self) private var model
    let briefing: Briefing
    var isToday: Bool

    @State private var cursor: ConsoleCursor?
    @State private var width: CGFloat = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    hero
                    VStack(alignment: .leading, spacing: DS.Space.l + DS.Space.xs) {
                        banner
                        if let generated = briefing.structured {
                            if width >= DS.Size.twoColumnMin {
                                HStack(alignment: .top, spacing: DS.Space.l + DS.Space.xs) {
                                    leftColumn(generated).frame(maxWidth: .infinity)
                                    rightColumn(generated).frame(width: min(DS.Size.newsColumn, width * 0.4))
                                }
                            } else {
                                VStack(spacing: DS.Space.l + DS.Space.xs) {
                                    leftColumn(generated)
                                    rightColumn(generated)
                                }
                            }
                        } else {
                            FallbackPanel(briefing: briefing)
                        }
                        SourcesLine(briefing: briefing)
                            .padding(.top, DS.Space.s)
                    }
                    .padding(.horizontal, DS.Space.xxl + DS.Space.l)
                    .padding(.top, DS.Space.xl + DS.Space.xs)
                    .padding(.bottom, DS.Space.xxl + DS.Space.l)
                    .frame(maxWidth: DS.Size.contentMaxWidth + DS.Space.xxl)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width - 2 * (DS.Space.xxl + DS.Space.l) } action: { newWidth in
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { width = newWidth }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .scrollContentBackground(.hidden)
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onAppear { isFocused = true }
            .onKeyPress(keys: [.downArrow, "j"]) { _ in move(1, proxy); return .handled }
            .onKeyPress(keys: [.upArrow, "k"]) { _ in move(-1, proxy); return .handled }
            .onKeyPress(.space) { activate(.toggle) }
            .onKeyPress(.return) { activate(.primary) }
            .onKeyPress(.delete) { activate(.skip) }
            .onKeyPress(keys: ["t", "e", "g", "s"]) { press in activate(.letter(press.characters)) }
            .onKeyPress(.escape) { cursor = nil; return .handled }
        }
    }

    private var date: Date { Briefing.date(forID: briefing.id) ?? briefing.generatedAt }

    private var hero: some View {
        let generated = briefing.structured
        let day = date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let overline = isToday ? "\(Format.greeting()) · \(day)" : day
        let total = generated?.focus.tasks.reduce(0) { $0 + $1.estimateMinutes } ?? 0
        let meetings = briefing.facts.events.filter { !$0.isAllDay }.count
        let decisions = AttentionRowModel.rows(facts: briefing.facts, section: generated?.section(.attention)).count
        return TodayHero(overline: overline, title: generated?.headline ?? "Here's your briefing.") {
            if generated != nil {
                HeroStat(value: Format.estimate(total), label: "focus")
            }
            HeroStat(value: "\(meetings)", label: meetings == 1 ? "meeting" : "meetings")
            HeroStat(value: "\(decisions)", label: decisions == 1 ? "needs you" : "need you")
        }
    }

    private func leftColumn(_ generated: GeneratedBriefing) -> some View {
        VStack(spacing: DS.Space.l + DS.Space.xs) {
            PriorityPanel(briefing: briefing, focus: generated.focus, headline: generated.headline, isReadOnly: !isToday, cursor: $cursor)
            OvernightCard(facts: briefing.facts, summary: generated.section(.overnight), cursor: $cursor)
            if !AgendaRow.rows(for: briefing.facts).isEmpty {
                AgendaCard(facts: briefing.facts, cursor: $cursor)
            }
        }
    }

    private func rightColumn(_ generated: GeneratedBriefing) -> some View {
        VStack(spacing: DS.Space.l + DS.Space.xs) {
            NewsCard(briefingID: briefing.id, cursor: $cursor)
            DecisionsCard(facts: briefing.facts, section: generated.section(.attention), cursor: $cursor)
            if !generated.nextTasks.isEmpty {
                LaterCard(tasks: generated.nextTasks, facts: briefing.facts)
            }
        }
    }

    @ViewBuilder private var banner: some View {
        if isToday, let error = model.lastError {
            ConsoleMessage(text: "Regenerating failed: \(error)", actionTitle: "Try again", keys: "⌘R", tone: DS.Color.failed, action: model.regenerate)
                .padding(.horizontal, -DS.Space.rowHorizontal)
        } else if isToday, model.isTodayStale {
            let day = date.formatted(.dateTime.weekday(.wide).day().month(.wide))
            ConsoleMessage(text: "Showing \(day). Today's briefing hasn't run yet.", actionTitle: "Regenerate", keys: "⌘R", action: model.regenerate)
                .padding(.horizontal, -DS.Space.rowHorizontal)
        }
    }

    // MARK: Keyboard

    /// Every selectable row, top to bottom.
    private var order: [ConsoleCursor] {
        guard let generated = briefing.structured else { return [] }
        let facts = briefing.facts
        var rows: [ConsoleCursor] = generated.focus.tasks.map { .task($0.id) }
        rows += OvernightGroup.make(from: facts, summary: generated.section(.overnight)).prefix(4).map { .overnight($0.id) }
        rows += AgendaRow.rows(for: facts).map { .agenda($0.id) }
        rows += model.newsPreview(for: briefing.id).map { .news($0.id) }
        rows += AttentionRowModel.rows(facts: facts, section: generated.section(.attention)).prefix(4).indices.map { .attention($0) }
        return rows
    }

    private func move(_ step: Int, _ proxy: ScrollViewProxy) {
        let rows = order
        guard !rows.isEmpty else { return }
        let index = cursor.flatMap(rows.firstIndex(of:)).map { min(max($0 + step, 0), rows.count - 1) } ?? 0
        withAnimation(DS.Motion.fast) { cursor = rows[index] }
        withAnimation(DS.Motion.standard) { proxy.scrollTo(rows[index], anchor: .center) }
    }

    private enum Action { case toggle, primary, skip, letter(String) }

    private func activate(_ action: Action) -> KeyPress.Result {
        guard let cursor, let generated = briefing.structured else {
            if case .primary = action, isToday, let first = briefing.structured?.focus.tasks.first(where: { !model.isChecked($0, in: briefing.id) }) {
                model.startBlock(first, in: briefing.id)
                return .handled
            }
            return .ignored
        }
        switch cursor {
        case let .task(id):
            guard isToday, let task = generated.focus.tasks.first(where: { $0.id == id }) else { return .ignored }
            switch action {
            case .toggle: model.toggle(task, in: briefing.id)
            case .primary: model.startBlock(task, in: briefing.id)
            case .skip: model.toggleSkip(task, in: briefing.id)
            case .letter: return .ignored
            }
        case let .overnight(id):
            guard case .primary = action,
                  let project = OvernightGroup.make(from: briefing.facts, summary: generated.section(.overnight)).first(where: { $0.id == id })?.project
            else { return .ignored }
            model.selectedProjectID = project.id
            model.selection = .projects
        case .agenda:
            return .ignored
        case let .attention(index):
            let rows = AttentionRowModel.rows(facts: briefing.facts, section: generated.section(.attention))
            guard rows.indices.contains(index) else { return .ignored }
            let targets = rows[index].targets
            switch action {
            case .primary: if targets.url != nil { Opener.url(targets.url) } else { Opener.terminal(targets.path) }
            case .letter("t"): Opener.terminal(targets.path)
            case .letter("e"): Opener.editor(targets.path)
            case .letter("g"): Opener.url(targets.url)
            default: return .ignored
            }
        case let .news(id):
            guard let item = model.newsPreview(for: briefing.id).first(where: { $0.id == id }) else { return .ignored }
            switch action {
            case .primary: model.openNews(item)
            case .letter("s"): model.toggleSaved(item)
            default: return .ignored
            }
        }
        return .handled
    }
}

#Preview("Today") {
    TodayView()
        .environment(AppModel.preview())
        .environment(\.accent, DS.Color.defaultAccent)
        .tint(DS.Color.defaultAccent)
        .frame(width: 1100, height: 1500)
        .background(ConsoleBackdrop())
        .preferredColorScheme(.dark)
}

#Preview("Today — light") {
    TodayView()
        .environment(AppModel.preview())
        .environment(\.accent, DS.Color.defaultAccent)
        .tint(DS.Color.defaultAccent)
        .frame(width: 1100, height: 1500)
        .background(ConsoleBackdrop())
        .preferredColorScheme(.light)
}

#Preview("Today — loading") {
    TodayView()
        .environment(AppModel.preview(generating: true))
        .frame(width: 1100, height: 900)
        .background(ConsoleBackdrop())
        .preferredColorScheme(.dark)
}

#Preview("Today — empty") {
    TodayView()
        .environment(AppModel.preview(.empty))
        .frame(width: 1100, height: 300)
        .background(ConsoleBackdrop())
        .preferredColorScheme(.dark)
}
