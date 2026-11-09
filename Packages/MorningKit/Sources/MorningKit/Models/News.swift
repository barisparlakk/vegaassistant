import Foundation

/// Recent news gathered with Claude Code's web search, saved as `briefings/YYYY-MM-DD.news.json`.
public struct NewsFeed: Codable, Sendable, Hashable {
    public var generatedAt: Date
    public var categories: [NewsCategory]

    public init(generatedAt: Date, categories: [NewsCategory]) {
        self.generatedAt = generatedAt
        self.categories = categories
    }

    public var allItems: [NewsItem] { categories.flatMap(\.items) }
}

public struct NewsCategory: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var label: String
    public var items: [NewsItem]

    public init(id: String, label: String, items: [NewsItem]) {
        self.id = id
        self.label = label
        self.items = items
    }
}

public struct NewsItem: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var summary: String
    /// One line linking the story to one of the user's projects, only when genuinely related.
    public var relevance: String?
    public var source: String
    public var url: String
    public var publishedAt: Date?

    public init(id: String, title: String, summary: String, relevance: String? = nil, source: String, url: String, publishedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.summary = summary
        self.relevance = relevance
        self.source = source
        self.url = url
        self.publishedAt = publishedAt
    }
}

/// A news category in Settings: what to search for and how to label it.
public struct NewsTopic: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var label: String
    /// What to look for, in plain words (sources, keywords, regions).
    public var query: String

    public init(id: String, label: String, query: String) {
        self.id = id
        self.label = label
        self.query = query
    }

    public static let defaults: [NewsTopic] = [
        NewsTopic(id: "ai-tech", label: "ai+tech", query: "Notable AI and software engineering news: model releases, developer tools, major product and policy moves."),
        NewsTopic(id: "research", label: "research", query: "Notable new papers on arXiv cs.AI and cs.LG from the last few days, preferring ones with practical impact."),
        NewsTopic(id: "turkiye", label: "türkiye", query: "Important news from Türkiye: economy, technology, science and major national events."),
        NewsTopic(id: "science", label: "science", query: "Significant science news and discoveries across fields."),
    ]
}

/// Which news items were read or saved. Shared by the app and the menu bar.
public struct NewsState: Codable, Sendable, Hashable {
    public var read: Set<String>
    public var saved: [String: NewsItem]

    public init(read: Set<String> = [], saved: [String: NewsItem] = [:]) {
        self.read = read
        self.saved = saved
    }
}
