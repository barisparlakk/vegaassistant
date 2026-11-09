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
        let lines = model.todayLines.isEmpty ? model.script(for: briefing, isToday: true) : model.todayLines
        // While she reads the briefing, lines appear as she reaches them.
        let visible = model.isSpeakingScript ? min(voice.currentLine + 1, lines.count) : lines.count

        // The ask bar is a sibling, not a child, of the conversation, so the conversation's
        // keys (space, r, return) never see what you type into it.
        ZStack(alignment: .bottom) {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xl + DS.Space.xs) {
                    banner
                    ForEach(Array(lines.prefix(max(visible, 1))), id: \.id) { line in
                        VStack(alignment: .leading, spacing: DS.Space.m + DS.Space.xxs) {
                            caption(line)
                            attachment(for: line)
                        }
                        .id(line.id)
                        .transition(.opacity.combined(with: .offset(y: DS.Motion.offset * 2)))
                    }
                    if !model.isSpeakingScript {
                        SourcesLine(briefing: briefing)
                        ForEach(model.exchanges) { exchange in
                            ExchangeView(exchange: exchange, caption: caption)
                                .id(exchange.id)
                                .transition(.opacity.combined(with: .offset(y: DS.Motion.offset * 2)))
                        }
                    }
                    Color.clear.frame(height: 1).id(Self.bottom)
                }
                .animation(DS.Motion.standard, value: visible)
                .padding(.horizontal, DS.Space.xxl + DS.Space.l)
                .padding(.top, DS.Space.xxl)
                .padding(.bottom, DS.Size.askBarClearance)
                .frame(maxWidth: DS.Size.conversationWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .onChange(of: voice.currentLine) { _, index in
                guard model.isSpeakingScript, lines.indices.contains(index) else { return }
                withAnimation(DS.Motion.standard) { proxy.scrollTo(lines[index].id, anchor: .center) }
            }
            .onChange(of: model.exchanges) {
                withAnimation(DS.Motion.standard) { proxy.scrollTo(Self.bottom, anchor: .bottom) }
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
        // These keys belong to the conversation only; while the ask bar has focus they're text.
        .onKeyPress(.space) {
            guard isFocused else { return .ignored }
            if voice.status == .idle { model.speakAgain(briefing) } else { voice.togglePause() }
            return .handled
        }
        .onKeyPress(.escape) {
            voice.stop()
            model.listener.cancel()
            isFocused = true
            return .handled
        }
        .onKeyPress("r") {
            guard isFocused else { return .ignored }
            model.speakAgain(briefing)
            return .handled
        }
        .onKeyPress(.return) {
            guard isFocused, let generated = briefing.structured,
                  let next = generated.focus.tasks.first(where: { !model.isChecked($0, in: briefing.id) && !model.isSkipped($0, in: briefing.id) })
            else { return .ignored }
            model.startBlock(next, in: briefing.id)
            return .handled
        }

        AskBar()
        }
    }

    private static let bottom = "conversation-bottom"

    // MARK: Lines

    /// The line's text; while it's being said, the part still to come is dimmed.
    private func caption(_ line: VegaLine) -> some View {
        let voice = model.voice
        var text = AttributedString(line.text)
        if voice.currentLineID == line.id {
            let length = (line.text as NSString).length
            let cut = min(max(voice.spokenLength, 0), length)
            let upcoming = (line.text as NSString).substring(from: cut)
            if !upcoming.isEmpty, let range = text.range(of: upcoming, options: .backwards) {
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

// MARK: - Exchanges

/// Your question (right) and Vega's answer with her action buttons.
private struct ExchangeView<Caption: View>: View {
    @Environment(AppModel.self) private var model
    let exchange: AppModel.Exchange
    let caption: (VegaLine) -> Caption

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text(exchange.question)
                .font(DS.Font.body.leading(.loose))
                .foregroundStyle(DS.Color.text)
                .padding(.horizontal, DS.Space.l)
                .padding(.vertical, DS.Space.s + DS.Space.xxs)
                .background(DS.Color.selected, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 5, topTrailingRadius: 18, style: .continuous))
                .frame(maxWidth: DS.Size.conversationWidth * 0.6, alignment: .trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .textSelection(.enabled)

            if let answer = exchange.answer {
                caption(VegaLine(id: exchange.lineID, text: answer.answer))
                if !answer.actions.isEmpty {
                    HStack(spacing: DS.Space.s) {
                        ForEach(answer.actions, id: \.self) { action in
                            Button(action.label) { model.perform(action) }
                                .buttonStyle(.vegaPill)
                                .help(help(for: action))
                        }
                    }
                }
            } else if let error = exchange.error {
                HStack(spacing: DS.Space.s) {
                    Text(error == "Stopped." ? "Stopped." : "I couldn't answer that: \(error)")
                        .font(DS.Font.small)
                        .foregroundStyle(DS.Color.failed)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try again") { model.retry(exchange) }
                        .buttonStyle(.vegaPill)
                }
            } else {
                HStack(spacing: DS.Space.m) {
                    ThinkingDots()
                    Button("Stop") { model.stopAsking() }
                        .buttonStyle(.vegaPill)
                }
            }
        }
    }

    private func help(for action: VegaAction) -> String {
        switch action.kind {
        case .openTerminal: "Open the project in Terminal"
        case .openEditor: "Open the project in your editor"
        case .openURL: action.target ?? "Open the link"
        case .startFocus: "Start a focus block on this task"
        case .show: "Go to \(action.target ?? "")"
        case .regenerate: "Rebuild today's briefing"
        }
    }
}

/// Three dots that breathe while Vega thinks.
private struct ThinkingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(.tint)
                        .frame(width: 7, height: 7)
                        .opacity(0.3 + 0.7 * max(0, sin(time * 4 - Double(index) * 0.7)))
                }
                Text("Thinking")
                    .font(DS.Font.small)
                    .foregroundStyle(DS.Color.dim)
                    .padding(.leading, DS.Space.xs)
            }
        }
        .accessibilityLabel("Vega is thinking")
    }
}

// MARK: - Ask bar

/// "Ask Vega anything…": type and press Return, or press the mic and talk.
struct AskBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accent) private var accent
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        let listener = model.listener
        VStack(spacing: DS.Space.xs) {
            if case let .unavailable(reason) = listener.status {
                Text(reason)
                    .font(DS.Font.small)
                    .foregroundStyle(DS.Color.failed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Space.l)
            }
            HStack(spacing: DS.Space.m) {
                Image(systemName: "sparkle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Color.accentInk(accent))
                ZStack(alignment: .leading) {
                    if listener.isListening {
                        Text(listener.transcript.isEmpty ? "Listening…" : listener.transcript)
                            .font(DS.Font.vegaAsk)
                            .foregroundStyle(listener.transcript.isEmpty ? DS.Color.dim : DS.Color.heading)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        TextField("Ask Vega anything…", text: $text)
                            .textFieldStyle(.plain)
                            .font(DS.Font.vegaAsk)
                            .focused($isFocused)
                            .onSubmit(send)
                            .disabled(model.isThinking)
                    }
                }
                Text(listener.isListening ? "pause to send" : "⌘K")
                    .font(DS.Font.key)
                    .foregroundStyle(DS.Color.dim)
                Button(action: model.listen) {
                    Image(systemName: listener.isListening ? "waveform" : "mic.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .symbolEffect(.variableColor.iterative, isActive: listener.isListening)
                        .foregroundStyle(Color(hex: 0x0B0A12))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(accent))
                        .shadow(color: accent.opacity(listener.isListening ? 0.6 : 0.3), radius: listener.isListening ? 12 : 6)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .help(listener.isListening ? "Stop listening" : "Talk to Vega (⇧⌘K)")
                .disabled(model.isThinking)
            }
            .padding(.leading, DS.Space.l + DS.Space.xxs)
            .padding(.trailing, DS.Space.s)
            .padding(.vertical, DS.Space.s)
            .background(Capsule().fill(DS.Color.panel))
            .overlay(Capsule().strokeBorder(listener.isListening ? accent.opacity(0.7) : DS.Color.border, lineWidth: listener.isListening ? 1.5 : DS.Size.hairline))
            .shadow(color: DS.Color.shadow, radius: 18, y: 8)
        }
        .padding(.horizontal, DS.Space.xxl + DS.Space.l)
        .padding(.top, DS.Space.s)
        .padding(.bottom, DS.Space.l + DS.Space.xs)
        .frame(maxWidth: DS.Size.conversationWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) {
            LinearGradient(colors: [DS.Color.background.opacity(0), DS.Color.background], startPoint: .top, endPoint: .center)
                .allowsHitTesting(false)
        }
        .background {
            // ⌘K focuses the field.
            Button("Ask Vega") { isFocused = true }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .animation(DS.Motion.standard, value: listener.status)
    }

    private func send() {
        let question = text
        text = ""
        model.ask(question)
    }
}
