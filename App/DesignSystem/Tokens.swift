import MorningKit
import SwiftUI

// The single source of visual constants. Views use these tokens, never raw numbers.

/// 4-pt spacing scale.
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

enum Radius {
    static let xs: CGFloat = 4
    static let s: CGFloat = 6
    static let m: CGFloat = 10
    static let l: CGFloat = 14
    static let xl: CGFloat = 20
}

/// Fixed sizes that aren't spacing: widths, icon boxes, rule thickness.
enum Metrics {
    static let contentMaxWidth: CGFloat = 920
    static let readableTextWidth: CGFloat = 640
    static let hairline: CGFloat = 1
    static let rule: CGFloat = 2
    static let iconSmall: CGFloat = 14
    static let iconMedium: CGFloat = 18
    static let glyphSmall: CGFloat = 22
    static let glyphMedium: CGFloat = 28
    static let glyphLarge: CGFloat = 40
    static let checkbox: CGFloat = 20
    static let severityBar: CGFloat = 3
    static let timelineNode: CGFloat = 8
    static let timelineGutter: CGFloat = 52
    static let agendaHourHeight: CGFloat = 46
    static let agendaMinEventHeight: CGFloat = 22
    static let nowDot: CGFloat = 8
    static let sparklineHeight: CGFloat = 28
    static let sparklineBarSpacing: CGFloat = 2
    static let projectCardMinWidth: CGFloat = 210
    static let sidebarMinWidth: CGFloat = 200
    static let sidebarIdealWidth: CGFloat = 220
    static let windowMinWidth: CGFloat = 820
    static let windowMinHeight: CGFloat = 560
    static let menuBarWidth: CGFloat = 360
    static let emptyStateIcon: CGFloat = 72
    static let shimmerLine: CGFloat = 12
    static let historyListWidth: CGFloat = 280
    static let backdropGlowHeight: CGFloat = 320
    static let remindersColumnWidth: CGFloat = 280
    static let focusDetailMaxWidth: CGFloat = 640
    static let evidenceLimit = 10
    static let inspectorMinWidth: CGFloat = 320
    static let inspectorIdealWidth: CGFloat = 360
    static let inspectorMaxWidth: CGFloat = 460
}

enum Typography {
    static let overline = Font.system(size: 11, weight: .semibold).width(.expanded)
    static let greeting = Font.system(size: 30, weight: .bold)
    static let headline = Font.system(size: 19, weight: .medium)
    static let sectionTitle = Font.system(size: 15, weight: .semibold)
    static let cardTitle = Font.system(size: 14, weight: .semibold)
    static let body = Font.system(size: 13)
    static let bodyEmphasis = Font.system(size: 13, weight: .medium)
    static let caption = Font.system(size: 11)
    static let captionEmphasis = Font.system(size: 11, weight: .medium)
    static let mono = Font.system(size: 11, design: .monospaced)
    static let monoEmphasis = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let numeric = Font.system(size: 12, weight: .medium).monospacedDigit()
    static let focusProject = Font.system(size: 22, weight: .bold)
    static let menuBarTitle = Font.system(size: 13, weight: .semibold)
}

/// Semantic colors. Everything adapts to light/dark through system colors or explicit pairs.
enum Palette {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(lightVariant: .white.opacity(0.78), dark: .white.opacity(0.055))
    static let surfaceRaised = Color(lightVariant: .white, dark: .white.opacity(0.085))
    static let surfaceSunken = Color(lightVariant: .black.opacity(0.035), dark: .black.opacity(0.22))
    static let stroke = Color(lightVariant: .black.opacity(0.08), dark: .white.opacity(0.09))
    static let strokeStrong = Color(lightVariant: .black.opacity(0.14), dark: .white.opacity(0.16))
    static let separator = Color(nsColor: .separatorColor)
    static let shadow = Color(lightVariant: .black.opacity(0.06), dark: .black.opacity(0.35))

    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)

    static let high = Color(lightVariant: Color(red: 0.86, green: 0.24, blue: 0.22), dark: Color(red: 1.0, green: 0.42, blue: 0.38))
    static let medium = Color(lightVariant: Color(red: 0.88, green: 0.55, blue: 0.08), dark: Color(red: 1.0, green: 0.72, blue: 0.3))
    static let low = Color(nsColor: .tertiaryLabelColor)
    static let success = Color(lightVariant: Color(red: 0.2, green: 0.62, blue: 0.36), dark: Color(red: 0.36, green: 0.82, blue: 0.5))
    static let now = Color(red: 1.0, green: 0.27, blue: 0.23)
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let commit = Color(lightVariant: Color(red: 0.33, green: 0.38, blue: 0.86), dark: Color(red: 0.55, green: 0.6, blue: 1.0))

    static func severity(_ severity: Severity) -> Color {
        switch severity {
        case .high: high
        case .medium: medium
        case .low: low
        }
    }

    /// Deterministic per-project hue so a project keeps its color everywhere.
    static func project(_ id: String) -> Color {
        let hues: [Double] = [0.02, 0.08, 0.13, 0.33, 0.47, 0.55, 0.61, 0.7, 0.78, 0.9]
        let index = id.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value } % UInt32(hues.count)
        return Color(hue: hues[Int(index)], saturation: 0.55, brightness: 0.82)
    }
}

/// Accent choices offered in Settings.
enum AccentChoice: String, CaseIterable, Identifiable {
    case sunrise, indigo, teal, rose, graphite

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .sunrise: Color("AccentColor")
        case .indigo: Color(red: 0.36, green: 0.36, blue: 0.9)
        case .teal: Color(red: 0.1, green: 0.62, blue: 0.64)
        case .rose: Color(red: 0.88, green: 0.3, blue: 0.48)
        case .graphite: Color(lightVariant: Color(white: 0.3), dark: Color(white: 0.75))
        }
    }

    init(hex: String?) {
        self = hex.flatMap(AccentChoice.init(rawValue:)) ?? .sunrise
    }
}

enum Motion {
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.9)
    static let gentle = Animation.easeInOut(duration: 0.25)
    static let shimmer = Animation.linear(duration: 1.4).repeatForever(autoreverses: false)
    static let pulse = Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true)

    /// Staggered entrance for list items.
    static func stagger(_ index: Int) -> Animation {
        spring.delay(Double(min(index, 8)) * 0.035)
    }
}

extension Color {
    /// A color with separate light and dark values.
    init(lightVariant light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil
                ? NSColor(dark)
                : NSColor(light)
        })
    }

    init?(hex: String?) {
        guard let hex, hex.hasPrefix("#"), hex.count == 7, let value = Int(hex.dropFirst(), radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
