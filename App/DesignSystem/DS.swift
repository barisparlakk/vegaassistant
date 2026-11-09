import AppKit
import SwiftUI

/// Morning's design system: calm light and dark surfaces, the system font, depth from fine
/// borders and soft shadows, and one glass orb in the hero. Views use these tokens only.
enum DS {
    // MARK: - Spacing (4-pt scale)

    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32

        static let pageTop: CGFloat = 28
        static let pageSide: CGFloat = 32
        static let sectionGap: CGFloat = 24
        static let rowVertical: CGFloat = 9
        static let rowHorizontal: CGFloat = 14
    }

    // MARK: - Radii

    enum Radius {
        static let tag: CGFloat = 4
        static let control: CGFloat = 8
        static let panel: CGFloat = 14
        static let priority: CGFloat = 16
    }

    // MARK: - Sizes

    enum Size {
        static let hairline: CGFloat = 1
        static let statusBarHeight: CGFloat = 48
        static let contentMaxWidth: CGFloat = 1100
        static let sidebarWidth: CGFloat = 228
        static let orb: CGFloat = 230
        static let brandOrb: CGFloat = 20
        static let newsColumn: CGFloat = 360
        static let twoColumnMin: CGFloat = 720
        static let windowMinWidth: CGFloat = 900
        static let windowMinHeight: CGFloat = 600
        static let checkbox: CGFloat = 16
        static let iconButton: CGFloat = 24
        static let icon: CGFloat = 12
        static let dot: CGFloat = 6
        static let glow: CGFloat = 10
        static let sparkline = CGSize(width: 120, height: 18)
        static let sparklineStroke: CGFloat = 1.5
        static let nowLine: CGFloat = 1
        static let timeColumn: CGFloat = 48
        static let projectColumn: CGFloat = 132
        static let statusColumn: CGFloat = 92
        static let indexColumn: CGFloat = 28
        static let skeletonLine: CGFloat = 10
        static let menuBarWidth: CGFloat = 380
        static let historyListWidth: CGFloat = 260
        static let inspectorWidth: CGFloat = 360
        static let backdropGlowRadius: CGFloat = 520
        static let settingsLabelWidth: CGFloat = 220
        static let accentSwatch: CGFloat = 16
        static let windowDefault = CGSize(width: 1280, height: 860)
        static let filterFieldWidth: CGFloat = 280
        static let statusBlockMaxWidth: CGFloat = 280
        static let pathFieldWidth: CGFloat = 320
        static let sparklineCompactWidth: CGFloat = 72
        static let branchMinWidth: CGFloat = 80
        /// Placeholder bar lengths, shaped like the real priority panel.
        enum Skeleton {
            static let label: CGFloat = 180
            static let title: CGFloat = 620
            static let meta: CGFloat = 420
            static let task: CGFloat = 340
            static let taskStep: CGFloat = 40
        }
    }

    // MARK: - Color

    enum Color {
        static let background = dynamic(dark: 0x0F1012, light: 0xFBFBFC)
        static let panel = dynamic(dark: 0x16171A, light: 0xFFFFFF)
        static let panelTop = dynamic(dark: 0x1A1B1F, light: 0xFFFFFF)
        static let border = dynamic(dark: 0x26272B, light: 0xE6E6E9)
        static let divider = dynamic(dark: 0x202125, light: 0xEEEEF0)
        static let selected = dynamic(dark: 0x222327, light: 0xF1F1F3)
        static let selectedStrong = dynamic(dark: 0x2A2B30, light: 0xE8E8EB)
        static let hover = dynamic(dark: 0x1C1D21, light: 0xF5F5F7)
        /// Inset well inside a card (task list).
        static let inset = dynamic(dark: 0x131417, light: 0xFAFAFB)
        static let text = dynamic(dark: 0xEDEEF0, light: 0x1A1B1E)
        static let heading = dynamic(dark: 0xFFFFFF, light: 0x111214)
        static let muted = dynamic(dark: 0xA0A3AA, light: 0x5F6168)
        static let dim = dynamic(dark: 0x80838B, light: 0x7A7D85)
        static let ok = dynamic(dark: 0x4CC38A, light: 0x18794E)
        static let warn = dynamic(dark: 0xF5A524, light: 0xC27C0E)
        static let failed = dynamic(dark: 0xFF6B6B, light: 0xD33A3A)
        /// Soft card shadow.
        static let shadow = SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(white: 0, alpha: appearance.isDark ? 0.40 : 0.06)
        })
        /// Hero stage: a lighter pool of light at the top left.
        static let stageTop = dynamic(dark: 0x24252B, light: 0xFFFFFF)
        static let stageBottom = dynamic(dark: 0x131418, light: 0xF1F1F5)
        /// The neutral pill button ("Begin"): ink fill with inverse text.
        static let inkFill = dynamic(dark: 0xF5F5F7, light: 0x1A1B1E)
        static let onInk = dynamic(dark: 0x0A0A0C, light: 0xFFFFFF)
        /// Text drawn on an accent fill.
        static let onAccent = SwiftUI.Color(hex: 0x0B0C0E)

        static let defaultAccent = SwiftUI.Color(hex: 0x9B7BFF)

        /// Accent readable as text in both modes: the light variant is darkened.
        static func accentInk(_ accent: SwiftUI.Color) -> SwiftUI.Color {
            SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
                let base = NSColor(accent)
                return appearance.isDark ? base : (base.blended(withFraction: 0.35, of: .black) ?? base)
            })
        }

        static func dynamic(dark: UInt32, light: UInt32) -> SwiftUI.Color {
            SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
                NSColor(SwiftUI.Color(hex: appearance.isDark ? dark : light))
            })
        }
    }

    // MARK: - Type

    enum Font {
        enum Weight { case regular, medium, semibold, bold }

        private static func weight(_ weight: Weight) -> SwiftUI.Font.Weight {
            switch weight {
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            }
        }

        /// Numbers, times and keys: the system font with tabular digits.
        static func mono(_ size: CGFloat, _ weight: Weight = .regular) -> SwiftUI.Font {
            .system(size: size, weight: Self.weight(weight)).monospacedDigit()
        }

        /// Everything else: the system font.
        static func sans(_ size: CGFloat, _ weight: Weight = .regular) -> SwiftUI.Font {
            .system(size: size, weight: Self.weight(weight))
        }

        static let brand = sans(15, .semibold)
        static let path = sans(13)
        static let label = sans(11.5, .semibold)
        static let nav = sans(13.5)
        static let navSelected = sans(13.5, .medium)
        static let button = sans(13, .medium)
        static let meta = mono(12.5)
        static let metaSmall = mono(12)
        static let time = mono(12.5)
        static let tag = sans(11, .semibold)
        static let panelTitle = sans(13, .semibold)
        static let key = mono(11.5)
        static let index = mono(12)

        // Hero
        static let greeting = sans(15, .medium)
        static let heroTitle = SwiftUI.Font.system(size: 38, weight: .semibold)
        static let heroStat = SwiftUI.Font.system(size: 30, weight: .light).monospacedDigit()
        static let cardTitle = sans(13, .semibold)

        static let priorityTitle = sans(30, .semibold)
        static let menuTitle = sans(17, .semibold)
        static let rowTitle = sans(14.5, .medium)
        static let newsTitle = sans(15, .semibold)
        static let summary = sans(13)
        static let body = sans(13)
        static let small = sans(12)
    }

    enum Tracking {
        static let title: CGFloat = -0.8
        static let hero: CGFloat = -1.2
        static let label: CGFloat = 0
    }

    // MARK: - Motion (short, no springs)

    enum Motion {
        static let fast = Animation.easeOut(duration: 0.15)
        static let standard = Animation.easeOut(duration: 0.2)
        static let pulse = Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true)
        static let offset: CGFloat = 4
    }
}

// MARK: - Accent environment

extension EnvironmentValues {
    /// The user's accent (Settings › General). Fills use `.tint`; this is for places that
    /// need a concrete Color (gradients, glows).
    @Entry var accent: Color = DS.Color.defaultAccent
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]) != nil
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// From a stored `#RRGGBB` (calendar colors, settings); nil if malformed.
    init?(hex: String?) {
        guard let hex, hex.hasPrefix("#"), hex.count == 7, let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(hex: value)
    }

    /// `#RRGGBB` for storing a picked color in settings.
    var hexString: String? {
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
    }
}
