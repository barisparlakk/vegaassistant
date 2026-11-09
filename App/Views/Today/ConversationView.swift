import MorningKit
import SwiftUI

/// Today as a conversation: Vega's lines arrive as she says them, each with its card
/// (the focus tasks, the decisions, the news). Already heard? Everything is shown at once.
struct ConversationView: View {
    @Environment(AppModel.self) private var model
    let briefing: Briefing

    @State private var cursor: ConsoleCursor?
    @FocusState private var isFocused: Bool

    var body: some View {
        let voice = model.voice
        let lines = voice.lines.isEmpty ? model.script(for: briefing, isToday: true) : voice.lines
        let visible = voice.status == .idle ? lines.count : min(voice.currentLine + 1, lines.count)

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xl + DS.Space.xs) {
                    banner
                    ForEach(Array(lines.prefix(max(visible, 1)).enumerated()), id: \.element.id) { index, line in
                        VStack(alignment: .leading, spacing: DS.Space.m + DS.Space.xxs) {
                            caption(line, isCurrent: voice.status != .idle && index == voice.currentLine, spoken: voice.spokenLength)
                            attachment(for: line)
                        }
                        .id(line.id)
                        .transition(.opacity.combined(with: .offset(y: DS.Motion.offset * 2)))
                    }
                    if voice.status == .idle {
                        SourcesLine(briefing: briefing)
                            .padding(.top, DS.Space.l)
                    }
                }
                .animation(DS.Motion.standard, value: visible)
                .padding(.horizontal, DS.Space.xxl + DS.Space.l)
                .padding(.top, DS.Space.xxl)
                .padding(.bottom, DS.Space.xxl * 2)
                .frame(maxWidth: DS.Size.conversationWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .onChange(of: voice.currentLine) { _, index in
                guard voice.status != .idle, lines.indices.contains(index) else { return }
                withAnimation(DS.Motion.standard) { proxy.scrollTo(lines[index].id, anchor: .center) }
            }
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear {
            isFocused = true
            model.presentToday(briefing)
        }
        .onChange(of: briefing) { model.presentToday(briefing) }
        .onChange(of: model.newsPreview(for: briefing.id).map(\.id)) { model.presentToday(briefing) }
        // Anything that arrived while she was talking (news, a regenerate) shows once she's done.
        .onChange(of: voice.status) { _, status in
            if status == .idle { model.presentToday(briefing) }
        }
        .onKeyPress(.space) {
            if voice.status == .idle { model.speakAgain(briefing) } else { voice.togglePause() }
            return .handled
        }
        .onKeyPress(.escape) { voice.stop(); return .handled }
        .onKeyPress("r") { model.speakAgain(briefing); return .handled }
        .onKeyPress(.return) {
            guard let generated = briefing.structured,
                  let next = generated.focus.tasks.first(where: { !model.isChecked($0, in: briefing.id) && !model.isSkipped($0, in: briefing.id) })
            else { return .ignored }
            model.startBlock(next, in: briefing.id)
            return .handled
        }
    }

    // MARK: Lines

    /// The line's text; while it's being said, the part still to come is dimmed.
    private func caption(_ line: VegaLine, isCurrent: Bool, spoken: Int) -> some View {
        var text = AttributedString(line.text)
        if isCurrent {
            let length = (line.text as NSString).length
            let cut = min(max(spoken, 0), length)
            let upcoming = (line.text as NSString).substring(from: cut)
            if let range = text.range(of: upcoming, options: .backwards) {
                text[range].foregroundColor = DS.Color.dim
            }
        }
        return Text(text)
            .font(line.isOpening ? DS.Font.vegaOpening : DS.Font.vegaLine)
            .tracking(line.isOpening ? -0.3 : -0.1)
            .lineSpacing(line.isOpening ? 2 : 4)
            .foregroundStyle(DS.Color.heading)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    @ViewBuilder
    private func attachment(for line: VegaLine) -> some View {
        let generated = briefing.structured
        switch line.attachment {
        case .none:
            EmptyView()
        case .focusTasks:
            if let generated {
                PriorityPanel(briefing: briefing, focus: generated.focus, headline: generated.headline, cursor: $cursor)
            }
        case .overnight:
            OvernightCard(facts: briefing.facts, summary: generated?.section(.overnight), cursor: $cursor)
        case .decisions:
            DecisionsCard(facts: briefing.facts, section: generated?.section(.attention), cursor: $cursor)
        case .agenda:
            AgendaCard(facts: briefing.facts, cursor: $cursor)
        case .news:
            NewsCard(briefingID: briefing.id, cursor: $cursor)
        case .fallback:
            FallbackPanel(briefing: briefing)
        }
    }

    @ViewBuilder private var banner: some View {
        if let error = model.lastError {
            ConsoleMessage(text: "Regenerating failed: \(error)", actionTitle: "Try again", keys: "⌘R", tone: DS.Color.failed, action: model.regenerate)
                .padding(.horizontal, -DS.Space.rowHorizontal)
        } else if model.isTodayStale {
            let day = (Briefing.date(forID: briefing.id) ?? briefing.generatedAt).formatted(.dateTime.weekday(.wide).day().month(.wide))
            ConsoleMessage(text: "This is \(day)'s briefing. Today's hasn't run yet.", actionTitle: "Regenerate", keys: "⌘R", action: model.regenerate)
                .padding(.horizontal, -DS.Space.rowHorizontal)
        }
    }
}

/// While a briefing is being prepared: Vega says so, and shows what she's doing.
struct ConversationWaiting: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("\(Format.greeting()). Give me a moment, I'm putting your briefing together.")
                .font(DS.Font.vegaOpening)
                .tracking(-0.3)
                .foregroundStyle(DS.Color.heading)
                .fixedSize(horizontal: false, vertical: true)
            if let generation = model.generation {
                TimelineView(.periodic(from: generation.startedAt, by: 1)) { context in
                    Text(generation.consoleLine(now: context.date))
                        .font(DS.Font.meta)
                        .foregroundStyle(DS.Color.muted)
                        .contentTransition(.opacity)
                }
            }
            Spacer()
        }
        .padding(.horizontal, DS.Space.xxl + DS.Space.l)
        .padding(.top, DS.Space.xxl)
        .frame(maxWidth: DS.Size.conversationWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
