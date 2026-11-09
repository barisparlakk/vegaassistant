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
        // The status bar is the top edge; the window buttons sit over the left panel.
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

// MARK: - Vega panel

/// The left panel: Vega herself (the star, what she's doing, her voice controls), then navigation.
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.s + DS.Space.xxs) {
                VegaMarkShape()
                    .fill(LinearGradient(colors: [.white, accent], startPoint: .top, endPoint: .bottom))
                    .frame(width: DS.Size.brandOrb, height: DS.Size.brandOrb)
                Text("Vega")
                    .font(DS.Font.brand)
                    .foregroundStyle(DS.Color.heading)
                Spacer()
            }
            .padding(.horizontal, DS.Space.l)
            .padding(.top, DS.Space.s)

            Spacer(minLength: DS.Space.l)

            VegaPresence()

            Spacer(minLength: DS.Space.l)

            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                ForEach(SidebarItem.allCases) { item in
                    SidebarRow(item: item, isSelected: model.selection == item) {
                        model.selection = item
                    }
                }
            }
            .padding(.horizontal, DS.Space.s)
            .padding(.bottom, DS.Space.l)
        }
        .toolbar(removing: .sidebarToggle)
    }
}

/// The star, a one-line status, a waveform while speaking, and pause / replay / mute.
struct VegaPresence: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accent) private var accent

    var body: some View {
        let voice = model.voice
        VStack(spacing: DS.Space.m) {
            AssistantCore(mood: mood, size: DS.Size.orb, pulse: voice.wordTick)

            Text(status)
                .font(DS.Font.button)
                .foregroundStyle(DS.Color.accentInk(accent))
                .contentTransition(.opacity)
                .animation(DS.Motion.standard, value: status)

            VoiceWaveform(isActive: voice.isSpeaking, tick: voice.wordTick)
                .frame(height: DS.Size.waveform)
                .opacity(voice.isSpeaking ? 1 : 0.25)

            if case let .loaded(briefing) = model.today {
                HStack(spacing: DS.Space.s) {
                    if voice.status != .idle {
                        Button(voice.status == .speaking ? "Pause" : "Resume") { voice.togglePause() }
                    }
                    Button(voice.status == .idle ? "Play briefing" : "Replay") { model.speakAgain(briefing) }
                    Button(model.isMuted ? "Unmute" : "Mute") { model.isMuted.toggle() }
                }
                .buttonStyle(.vegaPill)
                .padding(.top, DS.Space.xs)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var mood: AssistantCore.Mood {
        if model.isGenerating || model.isThinking { return .working }
        if model.listener.isListening { return .listening }
        if model.voice.isSpeaking { return .speaking }
        if model.focusBlock != nil { return .focus }
        return .idle
    }

    private var status: String {
        if model.isGenerating { return "Preparing your briefing" }
        if model.listener.isListening { return "Listening" }
        if model.isThinking { return "Thinking" }
        switch model.voice.status {
        case .speaking: return "Speaking"
        case .paused: return "Paused"
        case .idle: break
        }
        if let block = model.focusBlock { return "Focus · \(block.title)" }
        if model.isMuted { return "Muted" }
        return "Here when you need me"
    }
}

/// Bars that dance while Vega speaks and settle when she stops.
struct VoiceWaveform: View {
    let isActive: Bool
    let tick: Int
    private let bars = 13

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isActive)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<bars, id: \.self) { index in
                    let phase = Double(index) * 0.7 + Double(tick % 7) * 0.4
                    let level = isActive ? 0.25 + 0.75 * abs(sin(time * (5 + Double(index % 4)) + phase)) * envelope(index) : 0.12
                    Capsule()
                        .fill(.tint)
                        .frame(width: 3, height: max(3, DS.Size.waveform * level))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }

    /// Taller in the middle.
    private func envelope(_ index: Int) -> Double {
        let center = Double(bars - 1) / 2
        return 1 - abs(Double(index) - center) / (center + 2)
    }
}

/// A navigation row: icon, title, shortcut.
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

/// A project's one-word state, shown in the Projects table.
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
