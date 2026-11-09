import Foundation

/// News feeds next to the briefings (`briefings/YYYY-MM-DD.news.json`) and the shared
/// read/saved state (`news-state.json`).
public struct NewsStore: Sendable {
    public let paths: MorningPaths

    public init(paths: MorningPaths = MorningPaths()) {
        self.paths = paths
    }

    public func url(for id: String) -> URL { paths.briefings.appending(path: "\(id).news.json") }
    var stateFile: URL { paths.appSupport.appending(path: "news-state.json") }

    public func save(_ feed: NewsFeed, id: String) throws {
        try FileManager.default.createDirectory(at: paths.briefings, withIntermediateDirectories: true)
        try JSONCoding.prettyEncoder.encode(feed).write(to: url(for: id), options: .atomic)
    }

    public func load(_ id: String) -> NewsFeed? {
        guard let data = try? Data(contentsOf: url(for: id)) else { return nil }
        return try? JSONCoding.decoder.decode(NewsFeed.self, from: data)
    }

    /// The newest feed on or before `id`.
    public func latest(onOrBefore id: String) -> NewsFeed? {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: paths.briefings.path)) ?? []
        let ids = files.filter { $0.hasSuffix(".news.json") }.map { String($0.dropLast(".news.json".count)) }.filter { $0 <= id }.sorted(by: >)
        return ids.lazy.compactMap(load).first
    }

    public func loadState() -> NewsState {
        guard let data = try? Data(contentsOf: stateFile),
              let state = try? JSONCoding.decoder.decode(NewsState.self, from: data)
        else { return NewsState() }
        return state
    }

    public func saveState(_ state: NewsState) throws {
        try FileManager.default.createDirectory(at: paths.appSupport, withIntermediateDirectories: true)
        try JSONCoding.prettyEncoder.encode(state).write(to: stateFile, options: .atomic)
    }
}
