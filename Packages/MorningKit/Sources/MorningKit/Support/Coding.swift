import Foundation

public enum JSONCoding {
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = dateEncoding
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static var prettyEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = dateEncoding
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// Milliseconds are kept so stored briefings round-trip exactly.
    private static var dateEncoding: JSONEncoder.DateEncodingStrategy {
        .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISODate.fractionalString(date))
        }
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = ISODate.parse(string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO 8601 date: \(string)")
            }
            return date
        }
        return decoder
    }
}

public enum ISODate {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plain = Date.ISO8601FormatStyle()

    /// Parses `2026-11-09T07:00:41Z` and `2026-11-09T07:00:41.123Z`.
    public static func parse(_ string: String) -> Date? {
        if let date = try? fractional.parse(string) { return date }
        return try? plain.parse(string)
    }

    public static func string(_ date: Date) -> String { plain.format(date) }
    /// `2026-11-09T07:00:41.123Z`, rounded to the millisecond. Formatted by hand because the
    /// format style truncates, and parsing lands just below the value, so a save/load cycle
    /// would otherwise drift by 1 ms.
    public static func fractionalString(_ date: Date) -> String {
        let totalMilliseconds = (date.timeIntervalSince1970 * 1000).rounded()
        let seconds = (totalMilliseconds / 1000).rounded(.down)
        let milliseconds = Int(totalMilliseconds - seconds * 1000)
        let whole = plain.format(Date(timeIntervalSince1970: seconds))
        return whole.dropLast() + String(format: ".%03dZ", milliseconds)
    }
}

extension String {
    /// Collapses whitespace and cuts to `limit` characters with an ellipsis.
    func condensed(limit: Int) -> String {
        let collapsed = split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(max(0, limit - 1))) + "…"
    }

    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Array {
    /// Keeps the first occurrence of every key, preserving order.
    func uniqued<Key: Hashable>(by key: (Element) -> Key) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert(key($0)).inserted }
    }
}

extension Duration {
    var milliseconds: Int {
        let (seconds, attoseconds) = components
        return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
    }
}
