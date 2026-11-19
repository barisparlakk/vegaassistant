import Foundation

/// How a news category's stored label is shown. Labels written in lowercase (like the
/// defaults "ai+tech" or "research") get a capital; a few defaults get nicer names.
/// Labels with capitals are shown as written.
enum NewsLabel {
    static let defaults = ["ai+tech": "AI & tech", "ai": "AI"]

    static func display(_ label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        if let nicer = defaults[trimmed.lowercased()] { return nicer }
        guard trimmed == trimmed.lowercased(), let first = trimmed.first else { return trimmed }
        return first.uppercased() + trimmed.dropFirst()
    }
}
