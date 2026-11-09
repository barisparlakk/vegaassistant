import MorningKit
import SwiftUI

// MARK: - Card

/// The standard content container: a quiet raised surface with a hairline edge.
/// (Liquid Glass is reserved for floating controls, per the HIG; content sits on surfaces.)
struct Card<Content: View>: View {
    var padding: CGFloat = Spacing.l
    var radius: CGFloat = Radius.l
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(radius: radius)
    }
}

extension View {
    func cardSurface(radius: CGFloat = Radius.l, fill: Color = Palette.surface) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill)
                .shadow(color: Palette.shadow, radius: Spacing.s, y: Spacing.xxs)
        }
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Palette.stroke, lineWidth: Metrics.hairline)
        }
    }

    /// Liquid Glass on macOS 26+, a material with a hairline edge before that.
    @ViewBuilder
    func glassSurface(in shape: some Shape = Capsule(), interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay { shape.stroke(Palette.stroke, lineWidth: Metrics.hairline) }
        }
    }

    /// Glass button style on macOS 26+, bordered elsewhere.
    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }
}

// MARK: - Section header

struct SectionHeader<Accessory: View>: View {
    let title: String
    var symbol: String?
    var subtitle: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            if let symbol {
                Image(systemName: symbol)
                    .font(Typography.sectionTitle)
                    .foregroundStyle(.tint)
                    .frame(width: Metrics.iconMedium)
            }
            Text(title)
                .font(Typography.sectionTitle)
            if let subtitle {
                Text(subtitle)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: Spacing.s)
            accessory
        }
        .padding(.horizontal, Spacing.xs)
    }
}

extension SectionHeader where Accessory == EmptyView {
    init(_ title: String, symbol: String? = nil, subtitle: String? = nil) {
        self.init(title: title, symbol: symbol, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Pills & badges

struct Pill: View {
    let text: String
    var symbol: String?
    var tint: Color = Palette.textSecondary
    var monospaced = false

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text).lineLimit(1)
        }
        .font(monospaced ? Typography.mono : Typography.captionEmphasis)
        .foregroundStyle(tint)
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xxs + 1)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

struct SeverityBar: View {
    let severity: Severity

    var body: some View {
        Capsule()
            .fill(Palette.severity(severity))
            .frame(width: Metrics.severityBar)
            .accessibilityLabel("\(severity.rawValue) priority")
    }
}

/// Rounded square with the project's initial in its own hue.
struct ProjectGlyph: View {
    let id: String
    let name: String
    var size: CGFloat = Metrics.glyphMedium

    var body: some View {
        let color = Palette.project(id)
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Sparkline

/// 14-day commit histogram. Today's bar uses the accent.
struct Sparkline: View {
    let values: [Int]
    var height: CGFloat = Metrics.sparklineHeight

    var body: some View {
        let peak = max(values.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: Metrics.sparklineBarSpacing) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                let isToday = index == values.count - 1
                RoundedRectangle(cornerRadius: Radius.xs / 2, style: .continuous)
                    .fill(value == 0 ? AnyShapeStyle(Palette.surfaceSunken) : (isToday ? AnyShapeStyle(.tint) : AnyShapeStyle(.tint.opacity(0.45))))
                    .frame(height: value == 0 ? Metrics.rule : max(Metrics.rule * 2, height * CGFloat(value) / CGFloat(peak)))
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityElement()
        .accessibilityLabel("\(values.reduce(0, +)) commits in the last 14 days")
    }
}

// MARK: - Buttons

/// Small icon button that reveals itself on row hover.
struct HoverIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Typography.bodyEmphasis)
                .frame(width: Metrics.glyphMedium, height: Metrics.glyphMedium)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Round checkbox with a spring fill.
struct CheckCircle: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(Palette.strokeStrong), lineWidth: 1.5)
            Circle()
                .fill(.tint)
                .scaleEffect(isOn ? 1 : 0.2)
                .opacity(isOn ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: Metrics.checkbox * 0.5, weight: .bold))
                .foregroundStyle(.white)
                .scaleEffect(isOn ? 1 : 0.4)
                .opacity(isOn ? 1 : 0)
        }
        .frame(width: Metrics.checkbox, height: Metrics.checkbox)
        .animation(Motion.snappy, value: isOn)
    }
}

// MARK: - Shimmer

/// Animated highlight sweep for skeleton placeholders.
struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.35), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.6)
                    .offset(x: phase * proxy.size.width * 1.6)
                    .blendMode(.plusLighter)
                }
                .mask(content)
                .allowsHitTesting(false)
            }
            .onAppear {
                withAnimation(Motion.shimmer) { phase = 1 }
            }
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }
}

/// Grey bar standing in for a line of text.
struct SkeletonLine: View {
    var width: CGFloat?
    var height: CGFloat = Metrics.shimmerLine

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Palette.surfaceSunken)
            .frame(maxWidth: width ?? .infinity)
            .frame(width: width, height: height)
    }
}

// MARK: - Previews

#Preview("Components") {
    VStack(alignment: .leading, spacing: Spacing.l) {
        SectionHeader("Overnight", symbol: "moon.stars", subtitle: "since 07:00 yesterday")
        Card {
            HStack(spacing: Spacing.m) {
                ProjectGlyph(id: "repo:daybase", name: "daybase")
                VStack(alignment: .leading) {
                    Text("daybase").font(Typography.cardTitle)
                    Pill(text: "feat/rival-features", symbol: "arrow.triangle.branch", monospaced: true)
                }
                Spacer()
                Sparkline(values: [0, 1, 0, 3, 0, 0, 2, 5, 0, 0, 1, 0, 9, 4]).frame(width: 120)
            }
        }
        HStack(spacing: Spacing.m) {
            CheckCircle(isOn: true)
            CheckCircle(isOn: false)
            Pill(text: "45 min", symbol: "clock")
            Pill(text: "high", tint: Palette.high)
            HoverIconButton(symbol: "terminal", help: "Open in Terminal") {}
        }
        VStack(alignment: .leading, spacing: Spacing.s) {
            SkeletonLine(width: 220)
            SkeletonLine()
            SkeletonLine(width: 300)
        }
        .shimmering()
    }
    .padding(Spacing.xl)
    .frame(width: 520)
    .tint(AccentChoice.sunrise.color)
}
