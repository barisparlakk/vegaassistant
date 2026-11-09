import Foundation

/// Reads TODO.md / NOTES.md at each project root: open checklist items plus a short excerpt.
public struct NotesCollector: Collector {
    public let kind = CollectorKind.notes

    static let fileNames: Set<String> = ["todo.md", "notes.md", "todo.txt", "todo"]
    static let maxItems = 20
    static let excerptLength = 600
    static let maxFileSize = 512 * 1024

    public init() {}

    public func collect(_ context: CollectionContext) async throws -> CollectorOutput {
        let fileManager = FileManager.default
        var fragment = BriefingFacts.fragment(context)

        for project in context.projects {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: project.path) else { continue }
            for name in entries.sorted() where Self.fileNames.contains(name.lowercased()) {
                let url = project.url.appending(path: name)
                let attributes = try? fileManager.attributesOfItem(atPath: url.path)
                if let size = attributes?[.size] as? Int, size > Self.maxFileSize { continue }
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }

                let parsed = Self.parse(text)
                guard !parsed.items.isEmpty || parsed.excerpt != nil else { continue }
                fragment.notes.append(NoteFact(
                    projectID: project.id,
                    file: name,
                    path: url.path,
                    openItems: parsed.items,
                    excerpt: parsed.items.isEmpty ? parsed.excerpt : nil,
                    modifiedAt: attributes?[.modificationDate] as? Date
                ))
            }
        }
        return CollectorOutput(facts: fragment)
    }

    /// Unchecked `- [ ]` items win. Without any checkboxes, plain bullets count as open items.
    /// Otherwise the start of the file becomes an excerpt.
    static func parse(_ text: String) -> (items: [String], excerpt: String?) {
        var checkboxes: [String] = []
        var bullets: [String] = []
        var sawCheckbox = false

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let match = line.wholeMatch(of: /[-*+]\s+\[(?<mark>[ xX])\]\s+(?<text>.+)/) {
                sawCheckbox = true
                if match.output.mark == " " { checkboxes.append(String(match.output.text)) }
            } else if let match = line.wholeMatch(of: /(?:[-*+]|\d+\.)\s+(?<text>.+)/) {
                bullets.append(String(match.output.text))
            }
        }

        let items = (sawCheckbox ? checkboxes : bullets)
            .map { $0.condensed(limit: 200) }
            .prefix(maxItems)
        let excerpt = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
            .nilIfEmpty?
            .condensed(limit: excerptLength)
        return (Array(items), excerpt)
    }
}
