import Foundation
import Testing
@testable import MorningKit

enum NewsSample {
    static let validJSON = """
    {"categories":[
      {"id":"ai-tech","label":"ai+tech","items":[
        {"title":"MLX adds fused attention kernels","summary":"Faster VLM inference on Apple silicon.","relevance":"Speeds up daybase builds? No — relevant to old projects.","source":"github.com","url":"https://github.com/ml-explore/mlx/releases","publishedAt":"2026-11-09"},
        {"title":"Duplicate with tracking","summary":"Same story.","source":"github.com","url":"https://github.com/ml-explore/mlx/releases/?utm_source=x","publishedAt":"2026-11-09"},
        {"title":"Insecure link","summary":"Should be dropped.","source":"example.com","url":"http://example.com/story"},
        {"title":"Next.js 16.1 ships PPR","summary":"Partial prerendering is stable.","relevance":"daybase is a Next.js app; PPR could speed up Today.","source":"nextjs.org","url":"https://nextjs.org/blog/next-16-1","publishedAt":"2026-11-08T10:00:00Z"},
        {"title":"Third","summary":"x","source":"a.com","url":"https://a.com/3"},
        {"title":"Fourth","summary":"x","source":"a.com","url":"https://a.com/4"}
      ]},
      {"id":"unknown","label":"not configured","items":[{"title":"x","summary":"x","source":"x","url":"https://x.com"}]},
      {"id":"wrong-id","label":"Science","items":[{"title":"Webb finds water","summary":"Spectra show water.","source":"nasa.gov","url":"https://science.nasa.gov/webb"}]}
    ]}
    """

    static let topics = [
        NewsTopic(id: "ai-tech", label: "ai+tech", query: "AI"),
        NewsTopic(id: "research", label: "research", query: "arXiv"),
        NewsTopic(id: "science", label: "science", query: "science"),
    ]
}

@Suite("News")
struct NewsTests {
    static let now = ISODate.parse("2026-11-09T07:00:00Z")!

    @Test func validatorKeepsOnlyGoodItems() throws {
        let reply = ClaudeReply(text: "", structuredOutput: Data(NewsSample.validJSON.utf8), durationMs: 1, costUSD: nil)
        let feed = try NewsValidator.validate(reply, topics: NewsSample.topics, limit: 3, projects: Sample.facts.projects, now: Self.now)

        #expect(feed.categories.map(\.id) == ["ai-tech", "research", "science"]) // configured order, unknown dropped
        let ai = feed.categories[0].items
        #expect(ai.map(\.title) == ["MLX adds fused attention kernels", "Next.js 16.1 ships PPR", "Third"]) // dup, http dropped; capped at 3
        #expect(ai[0].relevance == "Speeds up daybase builds? No — relevant to old projects.") // names a real project
        #expect(ai[1].relevance?.contains("daybase") == true)
        #expect(ai[1].publishedAt == ISODate.parse("2026-11-08T10:00:00Z"))
        #expect(ai[0].publishedAt != nil)
        #expect(feed.categories[1].items.isEmpty)
        #expect(feed.categories[2].items.first?.title == "Webb finds water") // matched by label
        #expect(ai[0].id == NewsValidator.stableID("https://github.com/ml-explore/mlx/releases/"))
    }

    @Test func relevanceWithoutAProjectIsDropped() throws {
        let json = #"{"categories":[{"id":"ai-tech","items":[{"title":"t","summary":"s","relevance":"Useful for your side project","source":"s","url":"https://s.com/a"}]}]}"#
        let reply = ClaudeReply(text: json, structuredOutput: nil, durationMs: 1, costUSD: nil)
        let feed = try NewsValidator.validate(reply, topics: NewsSample.topics, limit: 5, projects: Sample.facts.projects, now: Self.now)
        #expect(feed.categories[0].items.first?.relevance == nil)
    }

    @Test func unreadableAnswerThrows() {
        let reply = ClaudeReply(text: "no news today", structuredOutput: nil, durationMs: 1, costUSD: nil)
        #expect(throws: NewsValidator.NewsError.self) {
            try NewsValidator.validate(reply, topics: NewsSample.topics, limit: 5, projects: [], now: Self.now)
        }
    }

    @Test func promptListsCategoriesAndProjects() throws {
        var settings = MorningSettings()
        settings.newsTopics = NewsSample.topics
        settings.newsItemsPerCategory = 4
        let prompt = NewsPrompt.build(settings: settings, facts: Sample.facts, now: Self.now)
        #expect(prompt.user.contains("id: research · label: research · look for: arXiv"))
        #expect(prompt.user.contains("Today is 2026-11-09"))
        #expect(prompt.user.contains("Find 4 notable stories"))
        #expect(prompt.user.contains("- daybase: Rival features"))
        #expect(prompt.system.contains("WebSearch"))
        let schema = try #require(JSONSerialization.jsonObject(with: Data(prompt.schema.utf8)) as? [String: Any])
        #expect(schema["required"] as? [String] == ["categories"])
    }

    @Test func runnerPreapprovesOnlyNamedTools() {
        let news = ClaudeRunner(executable: URL(fileURLWithPath: "/bin/claude"), model: "sonnet", workingDirectory: URL(fileURLWithPath: "/tmp"), tools: ["WebSearch"])
        let arguments = news.arguments(for: BriefingPrompt(system: "S", user: "U", schema: "{}"))
        #expect(arguments.contains("--allowedTools"))
        #expect(arguments[arguments.firstIndex(of: "--tools")! + 1] == "WebSearch")

        let briefing = ClaudeRunner(executable: URL(fileURLWithPath: "/bin/claude"), model: "sonnet", workingDirectory: URL(fileURLWithPath: "/tmp"))
        let plain = briefing.arguments(for: BriefingPrompt(system: "S", user: "U", schema: "{}"))
        #expect(plain[plain.firstIndex(of: "--tools")! + 1] == "")
        #expect(!plain.contains("--allowedTools"))
    }

    @Test func storeFindsLatestFeedOnOrBefore() throws {
        let home = try TemporaryHome()
        let store = NewsStore(paths: home.paths)
        try store.save(MockData.news(now: Self.now), id: "2026-11-07")
        try store.save(NewsFeed(generatedAt: Self.now, categories: []), id: "2026-11-09")
        #expect(store.latest(onOrBefore: "2026-11-08")?.categories.isEmpty == false)
        #expect(store.latest(onOrBefore: "2026-11-09")?.categories.isEmpty == true)
        #expect(store.latest(onOrBefore: "2026-11-01") == nil)
        // News files don't show up as briefings.
        #expect(BriefingStore(paths: home.paths).ids().isEmpty)

        var state = NewsState()
        state.read.insert("a")
        try store.saveState(state)
        #expect(store.loadState().read == ["a"])
    }

    @Test func settingsDefaultsAndRoundTrip() throws {
        let settings = try JSONCoding.decoder.decode(MorningSettings.self, from: Data("{}".utf8))
        #expect(settings.newsEnabled)
        #expect(settings.newsTopics.map(\.label) == ["ai+tech", "research", "türkiye", "science"])
        #expect(settings.newsItemsPerCategory == 5)
        let again = try JSONCoding.decoder.decode(MorningSettings.self, from: JSONCoding.encoder.encode(settings))
        #expect(again == settings)
    }
}

@Suite("News in the briefing run", .serialized)
struct NewsGenerationTests {
    @Test func briefingSavesNewsAlongside() async throws {
        let home = try TemporaryHome()
        try home.makeRepo("daybase")
        let claude = try GeneratorEndToEndTests.fakeClaude(in: home, answers: [Sample.validJSON])
        let briefing = try await GeneratorEndToEndTests.generator(home, claude: claude).generate(trigger: .manual)

        let report = try #require(briefing.diagnostics.first { $0.kind == .news })
        #expect(report.status == .ok)
        let feed = try #require(NewsStore(paths: home.paths).load(briefing.id))
        #expect(feed.allItems.count >= 1)
        let args = try String(contentsOf: home.root.appending(path: "news-args.txt"), encoding: .utf8)
        #expect(args.contains("--allowedTools WebSearch"))
    }

    @Test func newsFailureDoesNotBlockTheBriefing() async throws {
        let home = try TemporaryHome()
        try home.makeRepo("daybase")
        let claude = try GeneratorEndToEndTests.fakeClaude(in: home, answers: [Sample.validJSON], news: "sorry, no search today")
        let briefing = try await GeneratorEndToEndTests.generator(home, claude: claude).generate(trigger: .manual)
        #expect(briefing.structured != nil)
        #expect(briefing.diagnostics.first { $0.kind == .news }?.status == .failed)
    }
}
