import Foundation
import Testing
@testable import MorningKit

@Suite("Ask Vega")
struct AskVegaTests {
    static let briefing = MockData.briefing()

    static func question(_ text: String = "What's left on thermground?") -> VegaQuestion {
        VegaQuestion(
            text: text,
            briefing: briefing,
            news: MockData.news().allItems,
            history: [VegaExchangeRecord(question: "Hi", answer: "Hello.")],
            userName: "Barış",
            focusBlock: "Push the commits",
            checkedTaskIDs: ["t1"]
        )
    }

    static func reply(_ json: String) -> ClaudeReply {
        ClaudeReply(text: "", structuredOutput: Data(json.utf8), durationMs: 1, costUSD: nil)
    }

    @Test func promptCarriesTheQuestionContextAndHistory() {
        let prompt = AskVega.prompt(for: Self.question())
        #expect(prompt.system.contains("You are Vega, Barış's personal assistant"))
        #expect(prompt.user.hasSuffix("Question: What's left on thermground?"))
        #expect(prompt.user.contains("Focus block running: Push the commits"))
        #expect(prompt.user.contains("Q: Hi\nA: Hello."))
        #expect(prompt.user.contains("\"headline\""))
        #expect(!prompt.user.contains("\"hookEvents\":[{"))
        #expect(prompt.schema.contains("open_terminal"))
    }

    @Test func keepsOnlyActionsThatPointAtRealThings() throws {
        let project = try #require(Self.briefing.facts.projects.first)
        let task = try #require(Self.briefing.structured?.focus.tasks.first)
        let json = """
        {"answer":"Four commits are waiting to be pushed.","actions":[
          {"kind":"open_terminal","label":"Open Terminal","target":"\(project.name)"},
          {"kind":"open_terminal","label":"Twice","target":"\(project.id)"},
          {"kind":"open_editor","label":"Editor","target":"no-such-project"},
          {"kind":"open_url","label":"Insecure","target":"http://example.com"},
          {"kind":"start_focus","label":"Start","target":"\(task.id)"},
          {"kind":"show","label":"News","target":"News"},
          {"kind":"start_focus","label":"Bad task","target":"nope"}
        ]}
        """
        let answer = AskVega.validate(Self.reply(json), question: Self.question())
        #expect(answer.answer == "Four commits are waiting to be pushed.")
        #expect(answer.actions.map(\.kind) == [.openTerminal, .startFocus, .show])
        #expect(answer.actions[0].target == project.id)
        #expect(answer.actions[2].target == "news")
    }

    @Test func makesPlainTextSpeakable() {
        let reply = ClaudeReply(text: "**Yes.** You have:\n- two [PRs](https://x.com)\n- `one` branch", structuredOutput: nil, durationMs: 1, costUSD: nil)
        let answer = AskVega.validate(reply, question: Self.question())
        #expect(answer.answer == "Yes. You have: two PRs one branch")
        #expect(answer.actions.isEmpty)
    }

    @Test func emptyAnswerGetsAPoliteFallback() {
        let answer = AskVega.validate(Self.reply(#"{"answer":"  ","actions":[]}"#), question: Self.question())
        #expect(answer.answer.hasPrefix("Sorry"))
    }

    @Test func vegaLinksAskQuestions() {
        #expect(AppHandoff.parse(URL(string: "vega://ask?q=What%27s%20next%3F")!) == .ask("What's next?"))
        #expect(AppHandoff.parse(URL(string: "vega://ask?q=%20")!) == nil)
        #expect(AppHandoff.parse(URL(string: "vega://today")!) == .today)
        #expect(AppHandoff.parse(URL(string: "morning://today")!) == .today)
        #expect(AppHandoff.parse(URL(string: "https://example.com")!) == nil)
    }
}
