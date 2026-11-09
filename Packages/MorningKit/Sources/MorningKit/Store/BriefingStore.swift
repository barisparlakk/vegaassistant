import Foundation

/// Lightweight row for the History list, decoded without building the full facts.
public struct BriefingSummary: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var generatedAt: Date
    public var trigger: Briefing.Trigger
    public var headline: String?
    public var focusProjectID: String?
    public var focusProjectName: String?
    public var isFallback: Bool

    public var date: Date? { Briefing.date(forID: id) }
}

/// Briefings as JSON files: `briefings/YYYY-MM-DD.json`. Regenerating a day keeps the
/// previous file under `briefings/.revisions/` (last few only).
public struct BriefingStore: Sendable {
    public let paths: MorningPaths
    static let revisionsKept = 5

    public init(paths: MorningPaths = MorningPaths()) {
        self.paths = paths
    }

    public func url(for id: String) -> URL { paths.briefings.appending(path: "\(id).json") }
    var revisions: URL { paths.briefings.appending(path: ".revisions", directoryHint: .isDirectory) }

    public func save(_ briefing: Briefing) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: paths.briefings, withIntermediateDirectories: true)
        let destination = url(for: briefing.id)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.createDirectory(at: revisions, withIntermediateDirectories: true)
            let stamp = Int(Date.now.timeIntervalSince1970)
            try? fileManager.moveItem(at: destination, to: revisions.appending(path: "\(briefing.id)-\(stamp).json"))
            pruneRevisions(of: briefing.id)
        }
        try JSONCoding.prettyEncoder.encode(briefing).write(to: destination, options: .atomic)
    }

    public func load(_ id: String) throws -> Briefing? {
        let file = url(for: id)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONCoding.decoder.decode(Briefing.self, from: Data(contentsOf: file))
    }

    /// Ids, newest first.
    public func ids() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: paths.briefings.path)) ?? []
        return files
            .filter { $0.hasSuffix(".json") && Briefing.date(forID: String($0.dropLast(5))) != nil }
            .map { String($0.dropLast(5)) }
            .sorted(by: >)
    }

    public func latest() -> Briefing? {
        for id in ids() {
            if let briefing = try? load(id) { return briefing }
        }
        return nil
    }

    public func exists(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: id).path)
    }

    public func summaries() -> [BriefingSummary] {
        ids().compactMap { id in
            guard let data = try? Data(contentsOf: url(for: id)),
                  let header = try? JSONCoding.decoder.decode(Header.self, from: data)
            else { return nil }
            let generated = header.content.briefing
            let focusID = generated?.focus.projectId
            return BriefingSummary(
                id: header.id,
                generatedAt: header.generatedAt,
                trigger: header.trigger,
                headline: generated?.headline,
                focusProjectID: focusID,
                focusProjectName: header.facts.projects.first { $0.id == focusID }?.name,
                isFallback: header.content.kind != "structured"
            )
        }
    }

    public func delete(_ id: String) throws {
        try FileManager.default.removeItem(at: url(for: id))
    }

    private func pruneRevisions(of id: String) {
        let fileManager = FileManager.default
        let names = ((try? fileManager.contentsOfDirectory(atPath: revisions.path)) ?? [])
            .filter { $0.hasPrefix("\(id)-") }
            .sorted(by: >)
        for name in names.dropFirst(Self.revisionsKept) {
            try? fileManager.removeItem(at: revisions.appending(path: name))
        }
    }

    /// Only the keys the History list needs; everything else in the file is skipped.
    private struct Header: Decodable {
        struct Content: Decodable {
            struct Generated: Decodable {
                struct Focus: Decodable { let projectId: String }
                let headline: String
                let focus: Focus
            }
            let kind: String
            let briefing: Generated?
        }
        struct Facts: Decodable {
            struct Project: Decodable { let id: String; let name: String }
            let projects: [Project]
        }
        let id: String
        let generatedAt: Date
        let trigger: Briefing.Trigger
        let content: Content
        let facts: Facts
    }
}
