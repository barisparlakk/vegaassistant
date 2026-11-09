import MorningKit
import SwiftUI

// MARK: - Backdrop

/// The window background.
struct ConsoleBackdrop: View {
    var body: some View {
        DS.Color.background.ignoresSafeArea()
    }
}

// MARK: - Panels

/// Content card: solid surface, hairline border, soft shadow, radius 14. Optional header.
struct Panel<Header: View, Content: View>: View {
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.panel, in: RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
                .strokeBorder(DS.Color.border, lineWidth: DS.Size.hairline)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous))
        .shadow(color: DS.Color.shadow, radius: 1.5, y: 1)
    }
}

extension Panel where Header == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.header = EmptyView()
        self.content = content()
    }
}

extension Panel where Header == PanelHeader<Text> {
    /// A panel with a title and right-aligned counts.
    init(_ title: String, counts: String? = nil, @ViewBuilder content: () -> Content) {
        self.header = PanelHeader(title: title) { Text(counts ?? "") }
        self.content = content()
    }
}

/// `overnight.log ······ 4 sessions · 27 commits`
struct PanelHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.s) {
                Text(title)
                    .font(DS.Font.panelTitle)
                    .foregroundStyle(DS.Color.text)
                Spacer(minLength: DS.Space.s)
                trailing
                    .font(DS.Font.metaSmall)
                    .foregroundStyle(DS.Color.dim)
            }
            .padding(.horizontal, DS.Space.rowHorizontal)
            .padding(.vertical, DS.Space.s + DS.Space.xxs)
            RowDivider()
        }
    }
}

/// The focus card's surface: accent-tinted gradient border, soft lift.
struct PriorityPanelBackground: ViewModifier {
    @Environment(\.accent) private var accent

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.priority, style: .continuous)
                    .fill(LinearGradient(colors: [DS.Color.panelTop, DS.Color.panel], startPoint: .top, endPoint: .bottom))
            }
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.priority, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [accent.opacity(0.6), DS.Color.border], startPoint: .top, endPoint: .center),
                        lineWidth: DS.Size.hairline
                    )
            }
            .shadow(color: DS.Color.shadow, radius: 1.5, y: 1)
            .shadow(color: DS.Color.shadow, radius: 20, y: 14)
    }
}

extension View {
    func priorityPanel() -> some View { modifier(PriorityPanelBackground()) }
}

struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(DS.Color.divider)
            .frame(height: DS.Size.hairline)
    }
}

/// Background for a table row: hover and keyboard selection.
struct RowBackground: ViewModifier {
    var isSelected: Bool
    var isHovered: Bool

    func body(content: Content) -> some View {
        content
            .background(isSelected ? DS.Color.selectedStrong : (isHovered ? DS.Color.selected : .clear))
            .animation(DS.Motion.fast, value: isSelected)
            .animation(DS.Motion.fast, value: isHovered)
    }
}

extension View {
    func rowBackground(selected: Bool, hovered: Bool = false) -> some View {
        modifier(RowBackground(isSelected: selected, isHovered: hovered))
    }
}

// MARK: - Labels & tags

/// "Views", "Projects" — small section label.
struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.prefix(1).uppercased() + text.dropFirst())
            .font(DS.Font.label)
            .tracking(DS.Tracking.label)
            .foregroundStyle(DS.Color.dim)
    }
}

/// `DONE` / `NEEDS_YOU` / `FAILED` and other mono statuses.
struct StatusTag: View {
    enum Kind {
        case done, needsYou, failed, active, idle, custom(String, Color)

        var label: String {
            switch self {
            case .done: "DONE"
            case .needsYou: "NEEDS_YOU"
            case .failed: "FAILED"
            case .active: "ACTIVE"
            case .idle: "IDLE"
            case let .custom(label, _): label
            }
        }
    }

    let kind: Kind
    @Environment(\.accent) private var accent

    var body: some View {
        Text(kind.label)
            .font(DS.Font.tag)
            .tracking(0.4)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
    }

    private var color: Color {
        switch kind {
        case .done, .active: DS.Color.ok
        case .needsYou: DS.Color.accentInk(accent)
        case .failed: DS.Color.failed
        case .idle: DS.Color.dim
        case let .custom(_, color): color
        }
    }
}

/// `⌘R`, `↵`, `j/k` — a quiet shortcut hint.
struct KeyHint: View {
    let keys: String

    init(_ keys: String) { self.keys = keys }

    var body: some View {
        Text(keys)
            .font(DS.Font.key)
            .foregroundStyle(DS.Color.dim)
            .accessibilityHidden(true)
    }
}

/// Status dot.
struct GlowDot: View {
    var color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: DS.Size.dot, height: DS.Size.dot)

    }
}

// MARK: - Buttons

/// Buttons. `.primary` is the neutral ink pill; `.outline` a hairline control; `.ghost` text only.
struct ConsoleButtonStyle: ButtonStyle {
    enum Kind { case primary, outline, ghost }
    var kind: Kind = .outline
    @Environment(\.accent) private var accent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Font.button)
            .lineLimit(1)
            .padding(.horizontal, kind == .primary ? DS.Space.l + DS.Space.xs : DS.Space.m)
            .padding(.vertical, kind == .primary ? DS.Space.s + DS.Space.xxs : DS.Space.s - DS.Space.xxs)
            .foregroundStyle(foreground)
            .background {
                if kind == .primary {
                    Capsule().fill(fill(pressed: configuration.isPressed))
                } else {
                    RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                        .fill(fill(pressed: configuration.isPressed))
                }
            }
            .overlay {
                if kind == .outline {
                    RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                        .strokeBorder(DS.Color.border, lineWidth: DS.Size.hairline)
                }
            }
            .shadow(color: kind == .outline ? DS.Color.shadow : .clear, radius: 1, y: 1)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
            .animation(DS.Motion.fast, value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: DS.Color.onInk
        case .outline: DS.Color.text
        case .ghost: DS.Color.muted
        }
    }

    private func fill(pressed: Bool) -> Color {
        switch kind {
        case .primary: DS.Color.inkFill.opacity(pressed ? 0.8 : 1)
        case .outline: pressed ? DS.Color.selectedStrong : DS.Color.panel
        case .ghost: pressed ? DS.Color.selectedStrong : .clear
        }
    }
}

extension ButtonStyle where Self == ConsoleButtonStyle {
    static var consolePrimary: ConsoleButtonStyle { ConsoleButtonStyle(kind: .primary) }
    static var consoleOutline: ConsoleButtonStyle { ConsoleButtonStyle(kind: .outline) }
    static var consoleGhost: ConsoleButtonStyle { ConsoleButtonStyle(kind: .ghost) }
}

/// A small rounded pill (Vega's voice controls, quick replies).
struct VegaPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Font.button)
            .foregroundStyle(DS.Color.text)
            .padding(.horizontal, DS.Space.m + DS.Space.xxs)
            .padding(.vertical, DS.Space.xs + DS.Space.xxs)
            .background(Capsule().fill(configuration.isPressed ? DS.Color.selectedStrong : DS.Color.selected))
            .overlay(Capsule().strokeBorder(DS.Color.border, lineWidth: DS.Size.hairline))
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == VegaPillButtonStyle {
    static var vegaPill: VegaPillButtonStyle { VegaPillButtonStyle() }
}

/// "Label ⌘R" — a button label with its shortcut hint.
struct ShortcutLabel: View {
    let title: String
    let keys: String
    var onAccent = false

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Text(title)
            Text(keys)
                .font(DS.Font.key)
                .opacity(onAccent ? 0.6 : 1)
                .foregroundStyle(onAccent ? DS.Color.onInk : DS.Color.dim)
        }
    }
}

/// Small square icon button for row actions (Terminal / editor / GitHub).
struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: DS.Size.icon, weight: .medium))
                .foregroundStyle(isHovered ? DS.Color.text : DS.Color.dim)
                .frame(width: DS.Size.iconButton, height: DS.Size.iconButton)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.control - DS.Space.xxs, style: .continuous)
                        .fill(isHovered ? DS.Color.selectedStrong : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(DS.Motion.fast) { isHovered = hovering } }
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Inputs

/// Rounded checkbox.
struct ConsoleCheckbox: View {
    let isOn: Bool
    @Environment(\.accent) private var accent

    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.tag, style: .continuous)
            .fill(isOn ? accent : DS.Color.panel)
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.tag, style: .continuous)
                    .strokeBorder(isOn ? accent : DS.Color.dim.opacity(0.7), lineWidth: DS.Size.hairline)
            }
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: DS.Size.checkbox * 0.6, weight: .heavy))
                        .foregroundStyle(DS.Color.onAccent)
                }
            }
            .frame(width: DS.Size.checkbox, height: DS.Size.checkbox)
            .animation(DS.Motion.fast, value: isOn)
    }
}

// MARK: - Data

/// 14-day activity as a thin accent line.
struct SparkLine: View {
    let values: [Int]
    var width: CGFloat = DS.Size.sparkline.width
    @Environment(\.accent) private var accent

    var body: some View {
        GeometryReader { proxy in
            let peak = CGFloat(max(values.max() ?? 0, 1))
            let step = values.count > 1 ? proxy.size.width / CGFloat(values.count - 1) : 0
            let points = values.enumerated().map { index, value in
                CGPoint(
                    x: CGFloat(index) * step,
                    y: proxy.size.height - DS.Size.sparklineStroke - CGFloat(value) / peak * (proxy.size.height - DS.Size.sparklineStroke * 2)
                )
            }
            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                .stroke(values.contains { $0 > 0 } ? accent : DS.Color.border, style: StrokeStyle(lineWidth: DS.Size.sparklineStroke, lineCap: .round, lineJoin: .round))
                if let last = points.last, values.last ?? 0 > 0 {
                    Circle()
                        .fill(accent)
                        .frame(width: DS.Size.dot - DS.Space.xxs, height: DS.Size.dot - DS.Space.xxs)
                        .position(last)
                }
            }
        }
        .frame(width: width, height: DS.Size.sparkline.height)
        .accessibilityElement()
        .accessibilityLabel("\(values.reduce(0, +)) commits in the last 14 days")
    }
}

// MARK: - Loading

/// Placeholder bar inside skeleton rows.
struct SkeletonBar: View {
    var width: CGFloat?

    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.tag, style: .continuous)
            .fill(DS.Color.selected)
            .frame(width: width, height: DS.Size.skeletonLine)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

/// Gentle opacity pulse for skeletons (no shimmer sweep, no spinner).
struct SkeletonPulse: ViewModifier {
    @State private var dimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(dimmed ? 0.45 : 1)
            .onAppear { withAnimation(DS.Motion.pulse) { dimmed = true } }
            .accessibilityLabel("Loading")
    }
}

extension View {
    func skeletonPulse() -> some View { modifier(SkeletonPulse()) }
}

/// N skeleton rows shaped like a table: time | project | summary | status.
struct SkeletonRows: View {
    var count = 4

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                if index > 0 { RowDivider() }
                HStack(spacing: DS.Space.m) {
                    SkeletonBar(width: DS.Size.timeColumn - DS.Space.s)
                    SkeletonBar(width: DS.Size.projectColumn - DS.Space.xl)
                    SkeletonBar(width: CGFloat(260 + (index % 3) * 70))
                    Spacer()
                    SkeletonBar(width: DS.Size.statusColumn - DS.Space.xl)
                }
                .padding(.horizontal, DS.Space.rowHorizontal)
                .padding(.vertical, DS.Space.rowVertical + DS.Space.xxs)
            }
        }
        .skeletonPulse()
    }
}

// MARK: - One-line states

/// `no briefing for today — regenerate ⌘R`
struct ConsoleMessage: View {
    let text: String
    var actionTitle: String?
    var keys: String?
    var tone: Color = DS.Color.muted
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Text(text)
                .font(DS.Font.meta)
                .foregroundStyle(tone)
            if let actionTitle, let action {
                Text("—").font(DS.Font.meta).foregroundStyle(DS.Color.dim)
                Button(action: action) {
                    ShortcutLabel(title: actionTitle, keys: keys ?? "")
                }
                .buttonStyle(.consoleGhost)
            }
        }
        .padding(.horizontal, DS.Space.rowHorizontal)
        .padding(.vertical, DS.Space.m)
    }
}

// MARK: - Previews

#Preview("Design system") {
    VStack(alignment: .leading, spacing: DS.Space.xl) {
        Panel("overnight.log", counts: "4 sessions · 27 commits") {
            HStack(spacing: DS.Space.m) {
                Text("02:50").font(DS.Font.time).foregroundStyle(DS.Color.dim)
                Text("daybase").font(DS.Font.meta).foregroundStyle(DS.Color.text)
                Text("Built most of the rival-feature set").font(DS.Font.summary).foregroundStyle(DS.Color.text)
                Spacer()
                StatusTag(kind: .needsYou)
            }
            .padding(.horizontal, DS.Space.rowHorizontal)
            .padding(.vertical, DS.Space.rowVertical)
            RowDivider()
            SkeletonRows(count: 2)
        }
        HStack(spacing: DS.Space.m) {
            Button {} label: { ShortcutLabel(title: "start block", keys: "↵", onAccent: true) }
                .buttonStyle(.consolePrimary)
            Button {} label: { ShortcutLabel(title: "skip", keys: "⌫") }
                .buttonStyle(.consoleOutline)
            StatusTag(kind: .done)
            StatusTag(kind: .failed)
            KeyHint("⌘R")
            ConsoleCheckbox(isOn: true)
            ConsoleCheckbox(isOn: false)
            SparkLine(values: [0, 2, 0, 0, 5, 3, 0, 0, 0, 4, 0, 0, 23, 28])
            GlowDot(color: DS.Color.defaultAccent)
        }
        ConsoleMessage(text: "no briefing for today", actionTitle: "regenerate", keys: "⌘R") {}
    }
    .padding(DS.Space.xxl)
    .frame(width: 900)
    .background(ConsoleBackdrop())
    .preferredColorScheme(.dark)
}
