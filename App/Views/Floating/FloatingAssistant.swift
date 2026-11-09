import AppKit
import MorningKit
import SwiftUI

/// Vega's floating mini assistant: a pill over any app, summoned with the global shortcut.
/// The panel doesn't activate Vega, so the app you were in stays in front; it takes typing,
/// and hides when you click elsewhere (unless Vega is still listening or thinking).
@MainActor
final class FloatingAssistantController {
    /// Shared with the SwiftUI content.
    @Observable
    final class State {
        /// When it was last shown; only answers asked after this appear in its card.
        var shownAt = Date.now
        /// Bumped each time it's shown, to focus the field.
        var focusRequest = 0
        /// An answer card the user closed.
        var dismissedExchange: UUID?
    }

    private let model: AppModel
    private let state = State()
    private var panel: FloatingPanel?
    private var resignObserver: NSObjectProtocol?

    static let width: CGFloat = 660
    /// Gap above the bottom of the screen's visible area (above the Dock).
    static let bottomGap: CGFloat = 28

    init(model: AppModel) {
        self.model = model
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if let panel, panel.isVisible, panel.isKeyWindow { hide() } else { show() }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        state.shownAt = .now
        state.dismissedExchange = nil
        state.focusRequest += 1
        position(panel, height: panel.frame.height)
        panel.orderFrontRegardless()
        panel.makeKey()
        model.sounds.play(.wake)
    }

    func hide() {
        if model.listener.isListening { model.listener.cancel() }
        panel?.orderOut(nil)
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 120),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        panel.onCancel = { [weak self] in self?.hide() }

        let root = FloatingAssistantRoot(state: state, onClose: { [weak self] in self?.hide() }) { [weak self, weak panel] height in
            guard let self, let panel else { return }
            self.position(panel, height: height)
        }
        .environment(model)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        panel.contentView = host

        // Click elsewhere and it gets out of the way, unless Vega is mid-question.
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.model.listener.isListening, !self.model.isThinking else { return }
                self.hide()
            }
        }
        return panel
    }

    /// Keeps the bottom edge fixed above the Dock on the screen with the pointer.
    private func position(_ panel: NSPanel, height: CGFloat) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let bottom = panel.isVisible ? panel.frame.minY : visible.minY + Self.bottomGap
        let x = panel.isVisible ? panel.frame.minX : visible.midX - Self.width / 2
        panel.setFrame(NSRect(x: x, y: bottom, width: Self.width, height: max(height, 1)), display: true)
    }
}

/// A borderless panel that can take keyboard focus without activating the app.
final class FloatingPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

// MARK: - Content

private struct FloatingAssistantRoot: View {
    @Environment(AppModel.self) private var model
    let state: FloatingAssistantController.State
    let onClose: () -> Void
    let onHeight: (CGFloat) -> Void

    var body: some View {
        FloatingAssistantView(state: state, onClose: onClose)
            .environment(\.accent, model.accent)
            .tint(model.accent)
            .padding(DS.Space.xl) // room for the shadow
            .frame(width: FloatingAssistantController.width)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeight($0) }
    }
}

struct FloatingAssistantView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accent) private var accent
    let state: FloatingAssistantController.State
    let onClose: () -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: DS.Space.m) {
            if let exchange = recentExchange {
                AnswerCard(exchange: exchange) { state.dismissedExchange = exchange.id }
                    .transition(.opacity.combined(with: .offset(y: DS.Motion.offset * 3)))
            }
            pill
        }
        .animation(DS.Motion.standard, value: recentExchange)
        .onChange(of: state.focusRequest) { isFocused = true }
        .onAppear { isFocused = true }
    }

    /// The newest question asked since the panel was shown, unless closed.
    private var recentExchange: AppModel.Exchange? {
        guard let last = model.exchanges.last, last.askedAt >= state.shownAt.addingTimeInterval(-1), last.id != state.dismissedExchange else { return nil }
        return last
    }

    private var pill: some View {
        let listener = model.listener
        return HStack(spacing: DS.Space.m) {
            AssistantCore(mood: mood, size: 54, showsRings: false, pulse: model.voice.wordTick)
                .padding(.vertical, -DS.Space.s)
            VStack(alignment: .leading, spacing: 2) {
                Text(status)
                    .font(DS.Font.small)
                    .foregroundStyle(DS.Color.accentInk(accent))
                    .lineLimit(1)
                if listener.isListening {
                    Text(listener.transcript.isEmpty ? "Listening…" : listener.transcript)
                        .font(DS.Font.vegaAsk)
                        .foregroundStyle(listener.transcript.isEmpty ? DS.Color.dim : DS.Color.heading)
                        .lineLimit(1)
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
            Text(GlobalHotKey.options.first { $0.id == GlobalHotKey.storedID }?.label ?? "esc")
                .font(DS.Font.key)
                .foregroundStyle(DS.Color.dim)
            Button(action: model.listen) {
                Image(systemName: listener.isListening ? "waveform" : "mic.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .symbolEffect(.variableColor.iterative, isActive: listener.isListening)
                    .foregroundStyle(Color(hex: 0x0B0A12))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(accent))
                    .shadow(color: accent.opacity(listener.isListening ? 0.6 : 0.3), radius: listener.isListening ? 12 : 6)
            }
            .buttonStyle(.plain)
            .help(listener.isListening ? "Stop listening" : "Talk to Vega")
            .disabled(model.isThinking)
        }
        .padding(.leading, DS.Space.s + DS.Space.xxs)
        .padding(.trailing, DS.Space.s + DS.Space.xxs)
        .padding(.vertical, DS.Space.s + DS.Space.xxs)
        .background(FloatingGlass(shape: Capsule()))
        .overlay(Capsule().strokeBorder(listener.isListening ? accent.opacity(0.7) : .white.opacity(0.12), lineWidth: listener.isListening ? 1.5 : 1))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
    }

    private var mood: AssistantCore.Mood {
        if model.isGenerating || model.isThinking { return .working }
        if model.listener.isListening { return .listening }
        if model.voice.isSpeaking { return .speaking }
        if model.focusBlock != nil { return .focus }
        return .idle
    }

    private var status: String {
        if model.listener.isListening { return "Listening" }
        if model.isThinking { return "Thinking" }
        if model.voice.isSpeaking { return "Speaking" }
        if let block = model.focusBlock {
            let minutes = Int(Date.now.timeIntervalSince(block.startedAt) / 60)
            return "Focus · \(minutes) min · \(block.title)"
        }
        if model.isGenerating { return "Preparing your briefing" }
        return "Vega"
    }

    private func send() {
        let question = text
        text = ""
        model.ask(question)
    }
}

/// The latest answer above the pill: your question, Vega's reply (captioned while she
/// speaks), and her action buttons.
private struct AnswerCard: View {
    @Environment(AppModel.self) private var model
    let exchange: AppModel.Exchange
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s + DS.Space.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text("You asked: \(exchange.question)")
                    .font(DS.Font.small)
                    .foregroundStyle(DS.Color.dim)
                    .lineLimit(2)
                Spacer(minLength: DS.Space.s)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DS.Color.dim)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            if let answer = exchange.answer {
                Text(caption(answer.answer))
                    .font(.system(size: 16.5))
                    .lineSpacing(3)
                    .foregroundStyle(DS.Color.heading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if !answer.actions.isEmpty {
                    HStack(spacing: DS.Space.s) {
                        ForEach(answer.actions, id: \.self) { action in
                            Button(action.label) { model.perform(action) }
                                .buttonStyle(.vegaPill)
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
                HStack(spacing: DS.Space.s) {
                    ProgressView().controlSize(.small)
                    Text("Thinking…")
                        .font(DS.Font.small)
                        .foregroundStyle(DS.Color.dim)
                    Spacer()
                    Button("Stop") { model.stopAsking() }
                        .buttonStyle(.vegaPill)
                }
            }
        }
        .padding(DS.Space.l + DS.Space.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FloatingGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
    }

    /// Dims what she hasn't said yet.
    private func caption(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        let voice = model.voice
        guard voice.currentLineID == exchange.lineID else { return attributed }
        let ns = text as NSString
        let upcoming = ns.substring(from: min(max(voice.spokenLength, 0), ns.length))
        if !upcoming.isEmpty, let range = attributed.range(of: upcoming, options: .backwards) {
            attributed[range].foregroundColor = DS.Color.dim
        }
        return attributed
    }
}

/// Frosted glass behind the floating pieces (system material, tinted by the theme).
private struct FloatingGlass<S: Shape>: View {
    let shape: S

    var body: some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(DS.Color.panel.opacity(0.55)))
    }
}
