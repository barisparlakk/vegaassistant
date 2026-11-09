import CryptoKit
import Foundation

/// Collects recent news with Claude Code's web search and returns a validated `NewsFeed`.
///
/// Runs as its own headless call (tools: WebSearch only), alongside the briefing call, so it
/// adds little wall time. Failures never block the briefing.
public struct NewsGenerator: Sendable {
    public var settings: MorningSettings
    public var paths: MorningPaths
    public var calendar: Calendar

    public init(settings: MorningSettings, paths: MorningPaths = MorningPaths(), calendar: Calendar = .current) {
        self.settings = settings
        self.paths = paths
        self.calendar = calendar
    }

    static let timeout: Duration = .seconds(480)
    static let tools = ["WebSearch"]

    /// Runs the search, validates, saves `briefings/<id>.news.json` and returns the feed.
    public func generate(id: String, facts: BriefingFacts?, claude: URL, now: Date = .now) async throws -> NewsFeed {
        let prompt = NewsPrompt.build(settings: settings, facts: facts, now: now, calendar: calendar)
        let runner = ClaudeRunner(
            executable: claude,
            model: settings.claudeModel,
            workingDirectory: paths.runDirectory,
            timeout: Self.timeout,
            tools: Self.tools
        )
        let reply = try await runner.run(prompt)
        // Keep the raw answer for troubleshooting (local, overwritten each run).
        let raw = reply.structuredOutput ?? Data(reply.text.utf8)
        try? raw.write(to: paths.runDirectory.appending(path: "news-last-reply.json"), options: .atomic)
        let feed = try NewsValidator.validate(reply, topics: settings.newsTopics, limit: settings.newsItemsPerCategory, projects: facts?.projects ?? [], now: now)
        try NewsStore(paths: paths).save(feed, id: id)
        return feed
    }

    /// Standalone refresh (CLI `news --refresh`, the News view's refresh): collects only the
    /// project list needed for relevance, from the latest briefing.
    public func refresh(now: Date = .now) async throws -> NewsFeed {
        let id = Briefing.id(for: now, calendar: calendar)
        let facts = BriefingStore(paths: paths).latest()?.facts
        guard let claude = await ExecutableResolver(paths: paths).resolve("claude", override: settings.claudePath)?.url else {
            throw GeneratorError.claudeNotFound
        }
        return try await generate(id: id, facts: facts, claude: claude, now: now)
    }
}

// MARK: - Prompt & schema

public enum NewsPrompt {
    public static func build(settings: MorningSettings, facts: BriefingFacts?, now: Date, calendar: Calendar = .current) -> BriefingPrompt {
        var english = calendar
        english.locale = Locale(identifier: "en_US_POSIX")
        let day = Briefing.id(for: now, calendar: english)
        let target = settings.newsItemsPerCategory

        var user = "Today is \(day) (\(calendar.timeZone.identifier)). Find \(target) notable stories for each of these categories:\n"
        for topic in settings.newsTopics {
            user += "- id: \(topic.id) · label: \(topic.label) · look for: \(topic.query)\n"
        }
        let projects = projectContext(facts)
        if !projects.isEmpty {
            user += "\nPROJECTS (for the optional relevance line):\n" + projects.joined(separator: "\n") + "\n"
        }
        user += "\nReturn the JSON object only."
        return BriefingPrompt(system: systemPrompt, user: user, schema: schema)
    }

    /// One line per active project: name plus what it's about, from recent sessions/commits.
    static func projectContext(_ facts: BriefingFacts?) -> [String] {
        guard let facts else { return [] }
        let active = facts.projects.filter { project in
            facts.sessions.contains { $0.projectID == project.id } || facts.commits.contains { $0.projectID == project.id }
                || (project.lastActivityAt.map { facts.period.to.timeIntervalSince($0) < 14 * 86_400 } ?? false)
        }
        return active.prefix(12).map { project in
            let hints = (facts.sessions.filter { $0.projectID == project.id }.compactMap(\.title)
                + facts.commits.filter { $0.projectID == project.id }.map(\.subject))
                .prefix(3)
                .map { $0.condensed(limit: 80) }
            return "- \(project.name)" + (hints.isEmpty ? "" : ": " + hints.joined(separator: "; "))
        }
    }

    static let systemPrompt = """
    You are the news desk for one software developer's morning briefing. Use the WebSearch tool to find recent, notable stories for each requested category, then return one JSON object matching the provided schema. No markdown, no commentary.

    Rules
    - Search properly: run at least one WebSearch per category, with specific queries that include today's date or month (e.g. "AI model release November 2026", "arXiv cs.LG new papers this week"). Run more searches for broad categories.
    - Aim for the requested number of stories per category. There is almost always enough news; return fewer only when a category is genuinely quiet.
    - Only include stories you actually found with WebSearch in this session. Never invent stories, numbers, quotes or links.
    - `url` is the article's own https URL from the search results (not a search page or a site's front page).
    - Recency: news from the last 3 days; research papers from the last 14 days.
    - One item per story: never list the same event twice from different outlets.
    - `title` and `summary` in English, even when the source isn't (translate titles). `summary`: one or two factual sentences, no hype.
    - `source`: the publication's name or domain. `publishedAt`: ISO 8601 date (YYYY-MM-DD) when known.
    - `relevance`: include it only when a story genuinely matters for one of the user's PROJECTS, as one line that names the project. Otherwise leave it out. Most items should have none.
    - Order items by importance; prefer primary and reputable sources over reposts.
    - Use the category ids and labels exactly as given.
    """

    static let schema: String = {
        let item: [String: Any] = [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "summary": ["type": "string"],
                "relevance": ["type": "string"],
                "source": ["type": "string"],
                "url": ["type": "string"],
                "publishedAt": ["type": "string"],
            ],
            "required": ["title", "summary", "source", "url"],
            "additionalProperties": false,
        ]
        let category: [String: Any] = [
            "type": "object",
            "properties": [
                "id": ["type": "string"],
                "label": ["type": "string"],
                "items": ["type": "array", "items": item],
            ],
            "required": ["id", "items"],
            "additionalProperties": false,
        ]
        let root: [String: Any] = [
            "type": "object",
            "properties": ["categories": ["type": "array", "items": category]],
            "required": ["categories"],
            "additionalProperties": false,
        ]
        let data = try! JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }()
}

// MARK: - Validation

public enum NewsValidator {
    public enum NewsError: Error, LocalizedError, Sendable {
        case unreadable

        public var errorDescription: String? { "The news answer wasn't a JSON object matching the schema." }
    }

    struct Draft: Decodable {
        struct Category: Decodable {
            let id: String
            let label: String?
            let items: [Item]
        }

        struct Item: Decodable {
            let title: String
            let summary: String
            let relevance: String?
            let source: String
            let url: String
            let publishedAt: String?
        }

        let categories: [Category]
    }

    /// Keeps the configured categories in their order, only https links, no duplicates,
    /// at most `limit` per category, and relevance lines that name a real project.
    public static func validate(_ reply: ClaudeReply, topics: [NewsTopic], limit: Int, projects: [ProjectFact], now: Date) throws -> NewsFeed {
        guard let draft = decode(reply) else { throw NewsError.unreadable }
        let projectNames = projects.map { $0.name.lowercased() }
        var seenURLs = Set<String>()

        let categories = topics.map { topic -> NewsCategory in
            let source = draft.categories.first { $0.id == topic.id }
                ?? draft.categories.first { ($0.label ?? "").lowercased() == topic.label.lowercased() }
            let items = (source?.items ?? []).compactMap { item -> NewsItem? in
                let url = item.url.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let parsed = URL(string: url), parsed.scheme == "https", parsed.host() != nil,
                      let title = item.title.nilIfEmpty, seenURLs.insert(canonical(url)).inserted
                else { return nil }
                let relevance = item.relevance?.nilIfEmpty.flatMap { line in
                    projectNames.contains { line.lowercased().contains($0) } ? line : nil
                }
                return NewsItem(
                    id: stableID(url),
                    title: title.condensed(limit: 200),
                    summary: item.summary.condensed(limit: 400),
                    relevance: relevance?.condensed(limit: 200),
                    source: item.source.nilIfEmpty ?? parsed.host() ?? "",
                    url: url,
                    publishedAt: item.publishedAt.flatMap(parseDate)
                )
            }
            return NewsCategory(id: topic.id, label: topic.label, items: Array(items.prefix(max(1, limit))))
        }
        return NewsFeed(generatedAt: now, categories: categories)
    }

    static func decode(_ reply: ClaudeReply) -> Draft? {
        let decoder = JSONDecoder()
        if let data = reply.structuredOutput, let draft = try? decoder.decode(Draft.self, from: data) { return draft }
        guard let json = BriefingValidator.extractJSONObject(from: reply.text) else { return nil }
        return try? decoder.decode(Draft.self, from: Data(json.utf8))
    }

    /// Same URL with or without a trailing slash, fragment or tracking query counts once.
    static func canonical(_ url: String) -> String {
        guard var components = URLComponents(string: url) else { return url.lowercased() }
        components.fragment = nil
        components.queryItems = components.queryItems?.filter { !$0.name.lowercased().hasPrefix("utm_") }
        if components.queryItems?.isEmpty == true { components.queryItems = nil }
        var value = (components.string ?? url).lowercased()
        if value.hasSuffix("/") { value.removeLast() }
        return value
    }

    /// Short, stable id so read/saved state survives a refresh of the same story.
    static func stableID(_ url: String) -> String {
        SHA256.hash(data: Data(canonical(url).utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    static func parseDate(_ value: String) -> Date? {
        if let date = ISODate.parse(value) { return date }
        let style = Date.ISO8601FormatStyle().year().month().day().dateSeparator(.dash)
        return try? style.parse(String(value.prefix(10)))
    }
}
