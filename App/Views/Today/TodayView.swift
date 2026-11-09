import MorningKit
import SwiftUI

/// Today: priority, overnight.log, agenda, attention, news.feed.
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
                            ConsoleMessage(text: "last run failed: \(error.lowercased())", actionTitle: "retry", keys: "⌘R", tone: DS.Color.failed, action: model.regenerate)
                        } else {
                            ConsoleMessage(text: "no briefing for today", actionTitle: "regenerate", keys: "⌘R", action: model.regenerate)
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

/// A full briefing laid out as console panels. Read-only in History.
struct BriefingConsole: View {
    @Environment(AppModel.self) private var model
    let briefing: Briefing
    var isToday: Bool

    @State private var cursor: ConsoleCursor?
    @State private var expanded: Set<String> = []
    @FocusState private var isFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.sectionGap) {
                    banner
                    if let generated = briefing.structured {
                        PriorityPanel(briefing: briefing, focus: generated.focus, headline: generated.headline, isReadOnly: !isToday, cursor: $cursor)
                        OvernightLogPanel(facts: briefing.facts, summary: generated.section(.overnight), cursor: $cursor, expanded: $expanded)
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: DS.Space.sectionGap) {
                                AgendaPanel(briefing: briefing, isToday: isToday, cursor: $cursor)
                                AttentionPanel(facts: briefing.facts, section: generated.section(.attention), cursor: $cursor)
                            }
                            VStack(spacing: DS.Space.sectionGap) {
                                AgendaPanel(briefing: briefing, isToday: isToday, cursor: $cursor)
                                AttentionPanel(facts: briefing.facts, section: generated.section(.attention), cursor: $cursor)
                            }
                        }
                        NewsPreviewPanel(briefingID: briefing.id, cursor: $cursor)
                        if !generated.nextTasks.isEmpty {
                            BacklogPanel(tasks: generated.nextTasks, facts: briefing.facts)
                        }
                    } else {
                        FallbackPanel(briefing: briefing)
                    }
                    SourcesLine(briefing: briefing)
                    KeyboardLegend()
                }
                .padding(.horizontal, DS.Space.pageSide)
                .padding(.vertical, DS.Space.pageTop)
                .frame(maxWidth: DS.Size.contentMaxWidth)
                .frame(maxWidth: .infinity)
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

    @ViewBuilder private var banner: some View {
        if isToday, let error = model.lastError {
            ConsoleMessage(text: "regenerate failed: \(error.lowercased())", actionTitle: "retry", keys: "⌘R", tone: DS.Color.failed, action: model.regenerate)
                .padding(.horizontal, -DS.Space.rowHorizontal)
        } else if isToday, model.isTodayStale {
            let day = Format.consoleDate(Briefing.date(forID: briefing.id) ?? briefing.generatedAt).lowercased()
            ConsoleMessage(text: "showing \(day) — today's hasn't run", actionTitle: "regenerate", keys: "⌘R", action: model.regenerate)
                .padding(.horizontal, -DS.Space.rowHorizontal)
        }
    }

    // MARK: Keyboard

    /// Every selectable row, top to bottom.
    private var order: [ConsoleCursor] {
        guard let generated = briefing.structured else { return [] }
        let facts = briefing.facts
        var rows: [ConsoleCursor] = generated.focus.tasks.map { .task($0.id) }
        rows += OvernightGroup.make(from: facts, summary: generated.section(.overnight)).map { .overnight($0.id) }
        rows += AgendaRow.rows(for: facts).map { .agenda($0.id) }
        rows += AttentionRowModel.rows(facts: facts, section: generated.section(.attention)).indices.map { .attention($0) }
        rows += model.newsPreview(for: briefing.id).map { .news($0.id) }
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
            guard case .primary = action else { return .ignored }
            withAnimation(DS.Motion.standard) {
                if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
            }
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

/// `j/k move · space check · ↵ start / open · ⌫ skip · t e g open in terminal / editor / github`
struct KeyboardLegend: View {
    var body: some View {
        HStack(spacing: DS.Space.m) {
            legend("j/k", "move")
            legend("space", "check")
            legend("↵", "start · open")
            legend("⌫", "skip")
            legend("t e g", "terminal · editor · github")
            legend("s", "save")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legend(_ keys: String, _ action: String) -> some View {
        HStack(spacing: DS.Space.xs) {
            KeyHint(keys)
            Text(action).font(DS.Font.metaSmall).foregroundStyle(DS.Color.dim)
        }
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
