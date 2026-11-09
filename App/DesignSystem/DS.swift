import AppKit
import SwiftUI

/// Morning's design system: a dark, dense "dev console". Designed dark-first; light values
/// are derived so the app still works in light mode. Views use these tokens only.
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
        static let priority: CGFloat = 18
    }

    // MARK: - Sizes

    enum Size {
        static let hairline: CGFloat = 1
        static let statusBarHeight: CGFloat = 48
        static let contentMaxWidth: CGFloat = 1100
        static let sidebarWidth: CGFloat = 228
        static let windowMinWidth: CGFloat = 900
        static let windowMinHeight: CGFloat = 600
        static let checkbox: CGFloat = 14
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
        static let background = dynamic(dark: 0x0B0C0E, light: 0xF6F5F2)
        static let panel = dynamic(dark: 0x111216, light: 0xFFFFFF)
        static let panelTop = dynamic(dark: 0x15161B, light: 0xFFFCF6)
        static let border = dynamic(dark: 0x23252B, light: 0xE1DFD9)
        static let divider = dynamic(dark: 0x1C1E22, light: 0xEDEBE6)
        static let selected = dynamic(dark: 0x24262B, light: 0xECEAE4)
        static let selectedStrong = dynamic(dark: 0x2A2C33, light: 0xE3E0D8)
        static let hover = dynamic(dark: 0x1A1B20, light: 0xF1EFEA)
        /// Inset well inside the priority panel (task list).
        static let inset = dynamic(dark: 0x0F1013, light: 0xFAF9F6)
        static let text = dynamic(dark: 0xE8E6E1, light: 0x1E1D1B)
        static let heading = dynamic(dark: 0xFFFFFF, light: 0x000000)
        static let muted = dynamic(dark: 0x9A9A94, light: 0x66655F)
        static let dim = dynamic(dark: 0x8A8A84, light: 0x84837D)
        static let ok = dynamic(dark: 0x7CE38B, light: 0x1F9447)
        static let failed = dynamic(dark: 0xFF6B6B, light: 0xD33A3A)
        /// Text drawn on an accent fill.
        static let onAccent = SwiftUI.Color(hex: 0x0B0C0E)

        static let defaultAccent = SwiftUI.Color(hex: 0xFFB547)

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

        static func mono(_ size: CGFloat, _ weight: Weight = .regular) -> SwiftUI.Font {
            let name = switch weight {
            case .regular: "IBMPlexMono"
            case .medium: "IBMPlexMono-Medm"
            case .semibold: "IBMPlexMono-SmBld"
            case .bold: "IBMPlexMono-Bold"
            }
            return .custom(name, fixedSize: size)
        }

        static func sans(_ size: CGFloat, _ weight: Weight = .regular) -> SwiftUI.Font {
            let name = switch weight {
            case .regular: "IBMPlexSans"
            case .medium: "IBMPlexSans-Medm"
            case .semibold, .bold: "IBMPlexSans-SmBld"
            }
            return .custom(name, fixedSize: size)
        }

        // Mono: labels, metadata, nav, buttons, times, statuses, section titles.
        static let brand = mono(13, .bold)
        static let path = mono(12)
        static let label = mono(10.5, .medium)
        static let nav = mono(12.5)
        static let button = mono(12, .medium)
        static let meta = mono(12)
        static let metaSmall = mono(11)
        static let time = mono(12)
        static let tag = mono(10.5, .semibold)
        static let panelTitle = mono(12, .medium)
        static let key = mono(10.5, .medium)
        static let index = mono(11)

        // Sans: headlines, task titles, summaries.
        static let priorityTitle = sans(36, .semibold)
        static let menuTitle = sans(17, .semibold)
        static let rowTitle = sans(13.5, .medium)
        static let newsTitle = sans(15, .semibold)
        static let summary = sans(13)
        static let body = sans(13)
        static let small = sans(12)
    }

    enum Tracking {
        static let title: CGFloat = -0.8
        static let label: CGFloat = 1.1
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
