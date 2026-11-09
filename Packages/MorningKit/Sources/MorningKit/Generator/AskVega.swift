import Foundation

/// A question for Vega and what she knows when answering it.
public struct VegaQuestion: Sendable {
    public var text: String
    public var briefing: Briefing?
    public var news: [NewsItem]
    /// Earlier questions and answers today, oldest first.
    public var history: [VegaExchangeRecord]
    public var userName: String?
    /// The task being worked on in a focus block, if any.
    public var focusBlock: String?
    /// IDs of focus tasks already checked off.
    public var checkedTaskIDs: [String]
    public var now: Date

    public init(text: String, briefing: Briefing?, news: [NewsItem] = [], history: [VegaExchangeRecord] = [], userName: String? = nil, focusBlock: String? = nil, checkedTaskIDs: [String] = [], now: Date = .now) {
        self.text = text
        self.briefing = briefing
        self.news = news
        self.history = history
        self.userName = userName
        self.focusBlock = focusBlock
        self.checkedTaskIDs = checkedTaskIDs
        self.now = now
    }
}

public struct VegaExchangeRecord: Codable, Sendable, Hashable {
    public var question: String
    public var answer: String

    public init(question: String, answer: String) {
        self.question = question
        self.answer = answer
    }
}

/// Vega's reply: one to three spoken sentences, plus up to three things she can do for you.
public struct VegaAnswer: Codable, Sendable, Hashable {
    public var answer: String
    public var actions: [VegaAction]

    public init(answer: String, actions: [VegaAction] = []) {
        self.answer = answer
        self.actions = actions
    }
}

public struct VegaAction: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case openTerminal = "open_terminal"
        case openEditor = "open_editor"
        case openURL = "open_url"
        case startFocus = "start_focus"
        case show
        case regenerate
    }

    public var kind: Kind
    public var label: String
    /// A project id (terminal, editor), an https URL, a focus task id, or a view name.
    public var target: String?

    public init(kind: Kind, label: String, target: String? = nil) {
        self.kind = kind
        self.label = label
        self.target = target
    }

    /// Views `show` may open.
    public static let views = ["today", "projects", "news", "history", "settings"]
}

/// Answers a question about your day with one headless `claude -p` call on the subscription.
/// Context comes from the stored briefing; the only tool is web search, for questions that need
/// current information.
public enum AskVega {
    /// Answers usually take 5–15 s; a run that hasn't answered by this point is usually stuck
    /// before it started (the app retries once).
    public static let timeout: Duration = .seconds(45)
    public static let tools = ["WebSearch"]
    static let commitLimit = 40
    static let historyLimit = 6

    public static func ask(_ question: VegaQuestion, settings: MorningSettings, paths: MorningPaths = MorningPaths()) async throws -> VegaAnswer {
        guard let claude = await ExecutableResolver(paths: paths).resolve("claude", override: settings.claudePath)?.url else {
            throw GeneratorError.claudeNotFound
        }
        let runner = ClaudeRunner(executable: claude, model: settings.claudeModel, workingDirectory: paths.runDirectory, timeout: timeout, tools: tools)
        let reply = try await runner.run(prompt(for: question))
        return validate(reply, question: question)
    }

    // MARK: Prompt

    public static func prompt(for question: VegaQuestion) -> BriefingPrompt {
        let name = question.userName ?? "the user"
        let system = """
        You are Vega, \(name)'s personal assistant, living in a macOS app on their Mac. You know their day \
        from the context: last night's Claude Code sessions, git activity, open pull requests, calendar, \
        reminders, the briefing you prepared this morning, and today's news.

        Answer the way a sharp, warm assistant speaks out loud:
        - One to three short sentences, about 50 words at most (more only if asked for detail). Lead with the \
        answer itself. Plain words. No markdown, lists, headings, code formatting or emoji.
        - Use exact project names, numbers and times from the context. Never invent facts; if the context \
        doesn't say, say so briefly.
        - Use web search only when the question needs current information that isn't in the context.
        - Speak to \(name) directly ("you"), and don't repeat the question.

        You can't run commands yourself. When it would help, offer up to three actions, each with a short \
        button label (two to four words):
        - open_terminal / open_editor: target is a project id from the context.
        - open_url: target is an https URL from the context or your search.
        - start_focus: target is a focus task id from the briefing.
        - show: target is one of \(VegaAction.views.joined(separator: ", ")).
        - regenerate: rebuilds today's briefing; no target.
        Return only the JSON object.
        """
        var user = "Now: \(ISODate.fractionalString(question.now)) (\(question.now.formatted(.dateTime.weekday(.wide).hour().minute())))\n"
        if let focus = question.focusBlock { user += "Focus block running: \(focus)\n" }
        if !question.checkedTaskIDs.isEmpty { user += "Tasks already done: \(question.checkedTaskIDs.joined(separator: ", "))\n" }
        user += "\nContext (JSON):\n" + contextJSON(for: question) + "\n"
        let history = question.history.suffix(historyLimit)
        if !history.isEmpty {
            user += "\nEarlier today:\n" + history.map { "Q: \($0.question)\nA: \($0.answer)" }.joined(separator: "\n") + "\n"
        }
        user += "\nQuestion: \(question.text)"
        return BriefingPrompt(system: system, user: user, schema: schema)
    }

    private struct Context: Encodable {
        var briefing: GeneratedBriefing?
        var briefingText: String?
        var facts: BriefingFacts?
        var news: [NewsItem]
    }

    static func contextJSON(for question: VegaQuestion) -> String {
        var facts = question.briefing?.facts
        facts?.hookEvents = []
        let recent = (facts?.commits ?? []).sorted { $0.authoredAt > $1.authoredAt }.prefix(commitLimit)
        facts?.commits = Array(recent)
        var text: String?
        if case let .markdown(markdown)? = question.briefing?.content { text = markdown }
        let context = Context(briefing: question.briefing?.structured, briefingText: text, facts: facts, news: question.news)
        guard let data = try? JSONCoding.encoder.encode(context) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    static let schema = """
    {"type":"object","additionalProperties":false,"required":["answer","actions"],"properties":{\
    "answer":{"type":"string","minLength":1},\
    "actions":{"type":"array","maxItems":3,"items":{"type":"object","additionalProperties":false,"required":["kind","label"],"properties":{\
    "kind":{"type":"string","enum":[\(VegaAction.Kind.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ","))]},\
    "label":{"type":"string","minLength":1,"maxLength":40},\
    "target":{"type":"string"}}}}}}
    """

    // MARK: Validation

    /// Keeps the answer speakable and drops any action that doesn't point at something real.
    public static func validate(_ reply: ClaudeReply, question: VegaQuestion) -> VegaAnswer {
        let decoded = reply.structuredOutput.flatMap { try? JSONDecoder().decode(VegaAnswer.self, from: $0) }
        let raw = decoded?.answer ?? reply.text
        let answer = speakable(raw)
        let facts = question.briefing?.facts
        let projects = facts?.projects ?? []
        let taskIDs = Set(question.briefing?.structured?.focus.tasks.map(\.id) ?? [])

        let actions = (decoded?.actions ?? []).compactMap { action -> VegaAction? in
            var action = action
            action.label = action.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !action.label.isEmpty else { return nil }
            let target = action.target?.trimmingCharacters(in: .whitespacesAndNewlines)
            switch action.kind {
            case .openTerminal, .openEditor:
                // Accept an id or a name; store the id.
                guard let target, let project = projects.first(where: { $0.id == target || $0.name.caseInsensitiveCompare(target) == .orderedSame }) else { return nil }
                action.target = project.id
            case .openURL:
                guard let target, let url = URL(string: target), url.scheme == "https", url.host() != nil else { return nil }
                action.target = target
            case .startFocus:
                guard let target, taskIDs.contains(target) else { return nil }
            case .show:
                guard let target = target?.lowercased(), VegaAction.views.contains(target) else { return nil }
                action.target = target
            case .regenerate:
                action.target = nil
            }
            return action
        }
        return VegaAnswer(answer: answer.isEmpty ? "Sorry, I didn't catch an answer that time." : answer, actions: Array(actions.uniqued(by: { "\($0.kind.rawValue)|\($0.target ?? "")" }).prefix(3)))
    }

    /// Strips markdown that would be read aloud as symbols.
    static func speakable(_ text: String) -> String {
        var result = text
        for token in ["**", "__", "`", "### ", "## ", "# "] {
            result = result.replacingOccurrences(of: token, with: "")
        }
        result = result.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?m)^\s*[-*•]\s+"#, with: "", options: .regularExpression)
        return result.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}
