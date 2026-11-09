import Foundation
import Testing
@testable import MorningKit

@Suite("Claude transcript parser")
struct ClaudeTranscriptParserTests {
    static let window = Period(
        from: ISODate.parse("2026-11-08T20:00:00Z")!,
        to: ISODate.parse("2026-11-09T07:00:00Z")!
    )

    static let transcript = """
    {"type":"user","message":{"role":"user","content":"Old prompt before the window"},"timestamp":"2026-11-08T10:00:00.000Z","cwd":"/work/app","sessionId":"abc12345-0000","origin":{"kind":"human"}}
    {"type":"custom-title","customTitle":"Fix login flow","sessionId":"abc12345-0000"}
    {"type":"user","message":{"role":"user","content":"Fix the login redirect"},"timestamp":"2026-11-08T22:00:00.000Z","cwd":"/work/app","gitBranch":"fix/login","sessionId":"abc12345-0000","origin":{"kind":"human"},"entrypoint":"cli"}
    {"type":"user","message":{"role":"user","content":"<command-name>/model</command-name>"},"timestamp":"2026-11-08T22:00:01.000Z","cwd":"/work/app","sessionId":"abc12345-0000"}
    {"type":"user","message":{"role":"user","content":"<task-notification>done</task-notification>"},"timestamp":"2026-11-08T22:00:02.000Z","cwd":"/work/app","sessionId":"abc12345-0000","origin":{"kind":"task-notification"}}
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Edit","input":{"file_path":"/work/app/src/Login.swift","old_string":"a","new_string":"b"}}]},"timestamp":"2026-11-08T22:01:00.000Z","cwd":"/work/app","sessionId":"abc12345-0000"}
    {"type":"user","message":{"role":"user","content":[{"tool_use_id":"t1","type":"tool_result","content":"ok"}]},"timestamp":"2026-11-08T22:01:01.000Z","cwd":"/work/app","sessionId":"abc12345-0000"}
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"swift test","description":"Run the test suite"}},{"type":"tool_use","id":"t3","name":"Bash","input":{"command":"ls -la"}}]},"timestamp":"2026-11-08T22:05:00.000Z","cwd":"/work/app/src","sessionId":"abc12345-0000"}
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t4","name":"Bash","input":{"command":"git add . && git commit -q -m \\"Fix redirect after login\\""}}]},"timestamp":"2026-11-08T22:06:00.000Z","cwd":"/work/app","sessionId":"abc12345-0000"}
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t5","name":"mcp__browser__navigate","input":{"url":"x"}}]},"timestamp":"2026-11-08T22:07:00.000Z","cwd":"/work/app","sessionId":"abc12345-0000"}
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Done."}]},"timestamp":"2026-11-08T23:30:00.000Z","cwd":"/work/app","sessionId":"abc12345-0000"}
    {"type":"user","message":{"role":"user","content":"subagent prompt"},"timestamp":"2026-11-08T22:10:00.000Z","cwd":"/work/app","sessionId":"abc12345-0000","isSidechain":true}
    not json at all
    {"type":"cost-state","sessionId":"abc12345-0000","totalLinesAdded":12,"totalLinesRemoved":3}
    """

    @Test func summarisesOnlyTheWindow() throws {
        let session = try #require(ClaudeTranscriptParser.parse(Data(Self.transcript.utf8), period: Self.window, fallbackSessionID: "file"))
        #expect(session.sessionID == "abc12345-0000")
        #expect(session.id == "session:abc12345")
        #expect(session.title == "Fix login flow")
        #expect(session.promptCount == 1)
        #expect(session.prompts == ["Fix the login redirect"])
        #expect(session.branch == "fix/login")
        #expect(session.startedAt == ISODate.parse("2026-11-08T22:00:00Z"))
        // The plain-text answer is read through the fast path and still extends the session.
        #expect(session.endedAt == ISODate.parse("2026-11-08T23:30:00Z"))
    }

    @Test func picksTheRootFolderDespiteCd() throws {
        let session = try #require(ClaudeTranscriptParser.parse(Data(Self.transcript.utf8), period: Self.window, fallbackSessionID: "file"))
        #expect(session.cwd == "/work/app")
        #expect(session.filesEdited == ["src/Login.swift"])
    }

    @Test func countsToolsAndNotableActions() throws {
        let session = try #require(ClaudeTranscriptParser.parse(Data(Self.transcript.utf8), period: Self.window, fallbackSessionID: "file"))
        #expect(session.toolCounts["Edit"] == 1)
        #expect(session.toolCounts["Bash"] == 3)
        #expect(session.toolCounts["mcp:browser"] == 1)
        #expect(session.actions == ["Run the test suite", "Commit: Fix redirect after login"])
    }

    @Test func dropsLineCountsWhenSessionStartedBeforeWindow() throws {
        let session = try #require(ClaudeTranscriptParser.parse(Data(Self.transcript.utf8), period: Self.window, fallbackSessionID: "file"))
        #expect(session.linesAdded == nil)

        let wide = Period(from: ISODate.parse("2026-11-08T00:00:00Z")!, to: Self.window.to)
        let full = try #require(ClaudeTranscriptParser.parse(Data(Self.transcript.utf8), period: wide, fallbackSessionID: "file"))
        #expect(full.linesAdded == 12)
        #expect(full.promptCount == 2)
    }

    @Test func folderComesFromTheWholeSession() throws {
        // Inside this late window the session only touched a subfolder; it still belongs to /work/app.
        let late = Period(from: ISODate.parse("2026-11-08T22:04:00Z")!, to: Self.window.to)
        let session = try #require(ClaudeTranscriptParser.parse(Data(Self.transcript.utf8), period: late, fallbackSessionID: "file"))
        #expect(session.cwd == "/work/app")
    }

    @Test func ignoresSessionsWithoutActivityInWindow() {
        let later = Period(from: ISODate.parse("2026-11-10T00:00:00Z")!, to: ISODate.parse("2026-11-10T08:00:00Z")!)
        #expect(ClaudeTranscriptParser.parse(Data(Self.transcript.utf8), period: later, fallbackSessionID: "file") == nil)
    }

    @Test func cleansPromptsOfHarnessMarkup() {
        let text = "<system-reminder>ignore me</system-reminder>\n<pasted_content id=\"x1\">Build the app</pasted_content id=\"x1\">"
        #expect(ClaudeTranscriptParser.cleanPrompt(text) == "[pasted] Build the app")
    }

    @Test func primaryFolderPrefersExistingFolders() {
        let counts = ["/old/place/thermground": 400, "/new/place/thermground": 12]
        let folder = ClaudeTranscriptParser.primaryFolder(counts) { $0.hasPrefix("/new") }
        #expect(folder == "/new/place/thermground")
    }

    @Test func primaryFolderCoversSubfolders() {
        let counts = ["/a": 5, "/a/b": 20, "/a/b/c": 8, "/x": 10]
        #expect(ClaudeTranscriptParser.primaryFolder(counts) { _ in true } == "/a")
    }

    @Test func quickTimestampReadsWithoutDecoding() {
        let line = Data(#"{"type":"assistant","timestamp":"2026-11-08T22:00:00.500Z","message":{}}"#.utf8)
        #expect(ClaudeTranscriptParser.quickTimestamp(in: line) == ISODate.parse("2026-11-08T22:00:00.500Z"))
    }

    @Test func byteSearchWorksOnSlices() {
        let data = Data("xxhello world".utf8).dropFirst(2)
        #expect(data.rangeOfBytes(Data("world".utf8)) == (data.startIndex + 6)..<(data.startIndex + 11))
        #expect(!data.containsBytes(Data("xx".utf8)))
    }
}
