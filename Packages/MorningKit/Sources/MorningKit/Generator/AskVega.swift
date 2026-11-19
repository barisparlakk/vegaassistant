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
        /// Adds a reminder (title, optional due date).
        case createReminder = "create_reminder"
        /// Adds a calendar event (title, start date, minutes).
        case createEvent = "create_event"
        /// Pushes a project's current branch to its upstream.
        case gitPush = "git_push"
        /// Copies text to the clipboard.
        case copy

        /// Changes your data or leaves the Mac; its label is written by the app, not the model.
        public var writes: Bool {
            switch self {
            case .createReminder, .createEvent, .gitPush: true
            default: false
            }
        }
    }

    public var kind: Kind
    public var label: String
    /// A project id (terminal, editor, push), an https URL, a focus task id, or a view name.
    public var target: String?
    /// Reminder or event title, or the text to copy.
    public var title: String?
    /// Reminder due date or event start, ISO 8601 (local time when it has no offset).
    public var date: String?
    /// Event length in minutes.
    public var minutes: Int?

    public init(kind: Kind, label: String, target: String? = nil, title: String? = nil, date: String? = nil, minutes: Int? = nil) {
        self.kind = kind
        self.label = label
        self.target = target
        self.title = title
        self.date = date
        self.minutes = minutes
    }

    /// The parsed `date`.
    public var parsedDate: Date? { date.flatMap { AskVega.parseDate($0) } }

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

        You can't run anything yourself. When it would help, offer up to three actions as buttons; the \
        person clicks to do them. Each has a short label (two to four words):
        - open_terminal / open_editor: target is a project id from the context.
        - open_url: target is an https URL from the context or your search.
        - start_focus: target is a focus task id from the briefing.
        - show: target is one of \(VegaAction.views.joined(separator: ", ")).
        - regenerate: rebuilds today's briefing; no target.
        - create_reminder: title (short, imperative), optional date for when it's due.
        - create_event: title, date (start), minutes (length, default 30).
        - git_push: target is a project id; pushes its current branch to its upstream. Offer it only \
        when that project has unpushed commits.
        - copy: title is the text to copy (a command, a branch name, a short note).
        Dates are ISO 8601 in the person's local time, e.g. 2026-11-20T09:00:00, and must be in the future. \
        When asked to remind, schedule or push, answer briefly and offer the action; don't claim it's done.
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
    "target":{"type":"string"},\
    "title":{"type":"string","maxLength":200},\
    "date":{"type":"string"},\
    "minutes":{"type":"integer"}}}}}}
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
            case .createReminder:
                guard let title = cleanTitle(action.title) else { return nil }
                action.title = title
                action.target = nil
                if let raw = action.date {
                    guard let due = parseDate(raw), due > question.now else { return nil }
                    action.date = ISODate.fractionalString(due)
                }
                action.minutes = nil
            case .createEvent:
                guard let title = cleanTitle(action.title), let raw = action.date,
                      let start = parseDate(raw), start > question.now else { return nil }
                let minutes = action.minutes ?? 30
                guard (5...480).contains(minutes) else { return nil }
                action.title = title
                action.date = ISODate.fractionalString(start)
                action.minutes = minutes
                action.target = nil
            case .gitPush:
                guard let target, let project = projects.first(where: { $0.id == target || $0.name.caseInsensitiveCompare(target) == .orderedSame }),
                      project.kind == .repo else { return nil }
                action.target = project.id
            case .copy:
                // One line only: pasted into Terminal, a newline would run the first line at once.
                guard let text = action.title?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
                      !text.contains(where: \.isNewline) else { return nil }
                action.title = text
                // Show exactly what gets copied, not the model's description of it.
                action.label = "Copy “\(text.count > 44 ? text.prefix(42) + "…" : Substring(text))”"
            }
            if action.kind.writes {
                action.label = label(for: action, projects: projects, now: question.now)
            }
            return action
        }
        let unique = actions.uniqued(by: { "\($0.kind.rawValue)|\($0.target ?? "")|\($0.title ?? "")|\($0.date ?? "")" })
        return VegaAnswer(answer: answer.isEmpty ? "Sorry, I didn't catch an answer that time." : answer, actions: Array(unique.prefix(3)))
    }

    /// The button text for an action that writes: built from the checked fields, never from
    /// the model's own label (the context includes text from the web and commit messages).
    static func label(for action: VegaAction, projects: [ProjectFact], now: Date) -> String {
        let when = action.parsedDate.map { " · " + spokenTime($0, now: now) } ?? ""
        switch action.kind {
        case .createReminder:
            return "Remind me: \(action.title ?? "")\(when)"
        case .createEvent:
            return "Add to calendar: \(action.title ?? "")\(when), \(action.minutes ?? 30) min"
        case .gitPush:
            let name = projects.first { $0.id == action.target }?.name ?? action.target ?? ""
            return "Push \(name)"
        default:
            return action.label
        }
    }

    /// "today 14:00", "tomorrow 09:00", "Fri 10:30".
    static func spokenTime(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return "today \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return "tomorrow \(time)" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + " " + time
    }

    /// Titles are one line, at most 120 characters.
    static func cleanTitle(_ title: String?) -> String? {
        let line = (title ?? "").split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !line.isEmpty else { return nil }
        return String(line.prefix(120))
    }

    /// ISO 8601 with an offset, or without one (then it's local time); seconds optional.
    public static func parseDate(_ raw: String, timeZone: TimeZone = .current) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = ISODate.parse(text) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
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
