import AppKit
import Foundation
import MorningKit

/// Shared display formatting so every view words time the same way.
enum Format {
    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    static func timeRange(_ start: Date, _ end: Date) -> String {
        "\(time(start))–\(time(end))"
    }

    /// "now", "12 min ago", "3 h ago", "yesterday 18:40", "Mon 09:12".
    static func relative(_ date: Date, now: Date = .now) -> String {
        let seconds = now.timeIntervalSince(date)
        let calendar = Calendar.current
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(seconds / 60)) min ago"
        case ..<(6 * 3600): return "\(Int(seconds / 3600)) h ago"
        default:
            if calendar.isDateInToday(date) { return "today \(time(date))" }
            if calendar.isDateInYesterday(date) { return "yesterday \(time(date))" }
            if seconds < 6 * 86_400 { return date.formatted(.dateTime.weekday(.abbreviated)) + " " + time(date) }
            let days = Int(seconds / 86_400)
            return days < 60 ? "\(days) days ago" : date.formatted(.dateTime.day().month(.abbreviated).year())
        }
    }

    static func minutes(_ value: Int) -> String {
        if value < 60 { return "\(value) min" }
        return value % 60 == 0 ? "\(value / 60) h" : "\(value / 60) h \(value % 60) min"
    }

    static func overline(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased()
    }

    static func greeting(at date: Date = .now) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let part = switch hour {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Working late"
        }
        let first = NSFullUserName().split(separator: " ").first.map(String.init)
        return first.map { "\(part), \($0)" } ?? part
    }

    static func plural(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }
}

/// Opens projects and links in the user's tools.
@MainActor
enum Opener {
    static func url(_ string: String?) {
        guard let string, let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    static func terminal(_ path: String?) {
        open(path, bundleIDs: ["com.mitchellh.ghostty", "com.googlecode.iterm2", "com.apple.Terminal"])
    }

    static func editor(_ path: String?) {
        open(path, bundleIDs: ["com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed", "com.apple.dt.Xcode"])
    }

    static func finder(_ path: String?) {
        guard let path else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    static var hasEditor: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") != nil
    }

    private static func open(_ path: String?, bundleIDs: [String]) {
        guard let path else { return }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        guard let app = bundleIDs.lazy.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }).first else {
            NSWorkspace.shared.open(folder)
            return
        }
        NSWorkspace.shared.open([folder], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
}
