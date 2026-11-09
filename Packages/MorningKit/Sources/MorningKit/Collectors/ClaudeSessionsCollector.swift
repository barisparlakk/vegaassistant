import Foundation

/// Reads Claude Code transcripts in `~/.claude/projects/*/*.jsonl` and summarises
/// what happened inside the briefing window.
public struct ClaudeSessionsCollector: Collector {
    public let kind = CollectorKind.claudeSessions

    public init() {}

    public func collect(_ context: CollectionContext) async throws -> CollectorOutput {
        let root = context.paths.claudeProjects
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path) else {
            throw CollectorSkipped("No Claude Code history at \(context.paths.abbreviate(root.path))")
        }

        let period = context.period
        let excludedPrefix = context.paths.runDirectory.path
        let files = Self.transcripts(in: root, modifiedSince: period.from)

        let sessions = await withTaskGroup(of: SessionFact?.self) { group in
            for file in files {
                group.addTask {
                    guard let data = try? Data(contentsOf: file, options: .alwaysMapped) else { return nil }
                    let fallbackID = file.deletingPathExtension().lastPathComponent
                    return ClaudeTranscriptParser.parse(data, period: period, fallbackSessionID: fallbackID)
                }
            }
            var result: [SessionFact] = []
            for await session in group {
                if let session, !session.cwd.hasPrefix(excludedPrefix) { result.append(session) }
            }
            return result
        }

        var fragment = BriefingFacts.fragment(context)
        fragment.sessions = sessions.sorted { $0.startedAt < $1.startedAt }
        return CollectorOutput(facts: fragment)
    }

    /// Top-level transcripts only (subagent transcripts live in nested folders).
    static func transcripts(in root: URL, modifiedSince date: Date) -> [URL] {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let projectFolders = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return projectFolders.flatMap { folder -> [URL] in
            let files = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
            return files.filter { file in
                guard file.pathExtension == "jsonl",
                      let values = try? file.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      let modified = values.contentModificationDate
                else { return false }
                return modified >= date
            }
        }
    }
}

// MARK: - Parser

public enum ClaudeTranscriptParser {
    static let maxPrompts = 20
    static let promptLength = 400
    static let maxFiles = 40
    static let maxActions = 12

    static let editingTools: Set<String> = ["Edit", "MultiEdit", "Write", "NotebookEdit"]

    /// Shell commands worth mentioning in a briefing.
    static let notableCommandPatterns = [
        "git commit", "git push", "git merge", "git rebase", "git tag", "gh pr", "gh release",
        "test", "build", "deploy", "release", "publish", "migrate", "install", "lint",
    ]

    /// Prefixes of user-role messages that the harness, not the human, wrote.
    static let syntheticPrefixes = [
        "<command-", "<local-command", "<task-notification", "<bash-", "<user-memory-input",
        "[Request interrupted", "Caveat:", "This session is being continued",
    ]

    public static func parse(_ data: Data, period: Period, fallbackSessionID: String) -> SessionFact? {
        var accumulator = Accumulator()
        let decoder = JSONDecoder()

        for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            switch classify(line) {
            case .skip:
                continue
            case .timestampOnly:
                if let timestamp = quickTimestamp(in: line) { accumulator.touch(timestamp, period: period) }
            case .decode:
                guard let record = try? decoder.decode(TranscriptLine.self, from: line) else { continue }
                accumulator.consume(record, period: period)
            }
        }
        return accumulator.session(fallbackID: fallbackSessionID)
    }

    private enum LineKind { case skip, timestampOnly, decode }

    /// Cheap byte-level triage so the expensive lines (tool results, long answers) are
    /// never fully decoded. Only prompts, tool calls and session metadata need decoding.
    private static func classify(_ line: Data) -> LineKind {
        if line.containsBytes(Markers.user) {
            return !line.containsBytes(Markers.toolUseID) ? .decode : .timestampOnly
        }
        if line.containsBytes(Markers.assistant) {
            if line.containsBytes(Markers.sidechain) { return .skip }
            return line.containsBytes(Markers.toolUse) ? .decode : .timestampOnly
        }
        if line.containsBytes(Markers.customTitle)
            || line.containsBytes(Markers.summary)
            || line.containsBytes(Markers.costState) {
            return .decode
        }
        return .skip
    }

    /// Reads `"timestamp":"…"` without decoding the line.
    static func quickTimestamp(in line: Data) -> Date? {
        guard let key = line.rangeOfBytes(Markers.timestampKey) else { return nil }
        let rest = line[key.upperBound...]
        guard let quote = rest.firstIndex(of: UInt8(ascii: "\"")), quote - key.upperBound <= 40 else { return nil }
        return ISODate.parse(String(decoding: rest[..<quote], as: UTF8.self))
    }

    private enum Markers {
        static let user = Data(#""type":"user""#.utf8)
        static let assistant = Data(#""type":"assistant""#.utf8)
        static let customTitle = Data(#""type":"custom-title""#.utf8)
        static let summary = Data(#""type":"summary""#.utf8)
        static let costState = Data(#""type":"cost-state""#.utf8)
        static let toolUseID = Data(#""tool_use_id""#.utf8)
        static let toolUse = Data(#""type":"tool_use""#.utf8)
        static let sidechain = Data(#""isSidechain":true"#.utf8)
        static let timestampKey = Data(#""timestamp":""#.utf8)
    }

    static func humanPrompt(in record: TranscriptLine) -> String? {
        guard record.type == "user", record.isSidechain != true, record.isMeta != true else { return nil }
        if let origin = record.originKind {
            guard origin == "human" else { return nil }
        } else if let turnOrigin = record.turnOrigin, turnOrigin != "human" {
            return nil
        }

        var texts: [String] = []
        var hasImage = false
        for part in record.content {
            switch part {
            case let .text(text): texts.append(text)
            case .image: hasImage = true
            case .toolUse, .other: break
            }
        }
        let text = cleanPrompt(texts.joined(separator: "\n"))
        if text.isEmpty { return hasImage ? "(shared an image)" : nil }
        if syntheticPrefixes.contains(where: text.hasPrefix) { return nil }
        return text
    }

    /// Drops harness-injected reminders and unwraps pasted blocks so the prompt reads naturally.
    static func cleanPrompt(_ text: String) -> String {
        var cleaned = text
        if cleaned.contains("<system-reminder>") {
            cleaned = cleaned.replacing(/<system-reminder>[\s\S]*?<\/system-reminder>/, with: "")
        }
        if cleaned.contains("<pasted_content") {
            cleaned = cleaned
                .replacing(/<pasted_content[^>]*>/, with: "[pasted] ")
                .replacing(/<\/pasted_content[^>]*>/, with: " ")
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A short label for a shell command: Claude's own description when it gave one,
    /// otherwise only commits and pushes are worth naming.
    static func actionLabel(command: String, description: String?) -> String? {
        if let description = description?.nilIfEmpty, isNotable(command: command) { return description }
        if let message = command.firstMatch(of: /git commit[^"']*-m\s+["'](?<message>[^"']+)["']/)?.output.message {
            return "Commit: \(message)"
        }
        if command.contains("git push") { return "Push to remote" }
        return nil
    }

    static func isNotable(command: String) -> Bool {
        let lowered = command.lowercased()
        return notableCommandPatterns.contains { lowered.contains($0) }
    }

    /// The folder that covers the most activity: each candidate scores the records in it
    /// or below it, so a session that `cd`s into subfolders still belongs to its root.
    /// Folders that still exist win over ones that were moved or deleted.
    static func primaryFolder(_ counts: [String: Int], exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String? {
        let existing = counts.keys.filter(exists)
        let candidates = existing.isEmpty ? Array(counts.keys) : existing
        func score(_ folder: String) -> Int {
            counts.reduce(0) { total, entry in
                entry.key == folder || entry.key.hasPrefix(folder + "/") ? total + entry.value : total
            }
        }
        return candidates.max { lhs, rhs in
            let (left, right) = (score(lhs), score(rhs))
            return left != right ? left < right : lhs.count > rhs.count
        }
    }

    static func relativePath(_ path: String, to cwd: String?) -> String {
        guard let cwd, path.hasPrefix(cwd + "/") else { return path }
        return String(path.dropFirst(cwd.count + 1))
    }

    /// Collapses `mcp__server__tool` into one bucket per server so counts stay readable.
    static func toolBucket(_ name: String) -> String {
        guard name.hasPrefix("mcp__") else { return name }
        let parts = name.split(separator: "_", omittingEmptySubsequences: true)
        return parts.count >= 2 ? "mcp:\(parts[1])" : "mcp"
    }

    private struct Accumulator {
        var sessionID: String?
        /// Records per working directory over the whole session (not just the window): the
        /// session's root folder is a property of the session, and `cd` or a project moved
        /// on disk make any single cwd unreliable.
        var cwdCounts: [String: Int] = [:]
        var lastCwd: String?
        var branch: String?
        var entrypoint: String?
        var title: String?
        var summaryTitle: String?
        var firstTimestampEver: Date?
        var start: Date?
        var end: Date?
        var prompts: [String] = []
        var promptCount = 0
        var files: [String] = []
        var toolCounts: [String: Int] = [:]
        var actions: [String] = []
        var linesAdded: Int?
        var linesRemoved: Int?
        var activityInWindow = false

        mutating func consume(_ record: TranscriptLine, period: Period) {
            if let id = record.sessionId { sessionID = sessionID ?? id }
            if let customTitle = record.customTitle?.nilIfEmpty { title = customTitle }
            if record.type == "summary", let summary = record.summary?.nilIfEmpty { summaryTitle = summary }
            if record.type == "cost-state" {
                linesAdded = record.totalLinesAdded
                linesRemoved = record.totalLinesRemoved
                return
            }
            if record.isSidechain != true, let value = record.cwd {
                cwdCounts[value, default: 0] += 1
                lastCwd = value
            }
            guard let timestamp = record.timestamp else { return }
            firstTimestampEver = min(firstTimestampEver ?? timestamp, timestamp)
            guard period.contains(timestamp) else { return }
            guard record.isSidechain != true else { return }

            activityInWindow = true
            start = min(start ?? timestamp, timestamp)
            end = max(end ?? timestamp, timestamp)
            if let value = record.gitBranch?.nilIfEmpty, value != "HEAD" { branch = value }
            if let value = record.entrypoint { entrypoint = value }

            if let prompt = ClaudeTranscriptParser.humanPrompt(in: record) {
                promptCount += 1
                prompts.append(prompt.condensed(limit: ClaudeTranscriptParser.promptLength))
                return
            }

            guard record.type == "assistant" else { return }
            for case let .toolUse(name, input) in record.content {
                toolCounts[ClaudeTranscriptParser.toolBucket(name), default: 0] += 1
                if ClaudeTranscriptParser.editingTools.contains(name), let path = input.filePath ?? input.notebookPath {
                    files.append(path)
                }
                if name == "Bash", let command = input.command,
                   let label = ClaudeTranscriptParser.actionLabel(command: command, description: input.description) {
                    actions.append(label.condensed(limit: 90))
                }
            }
        }

        /// Activity seen only through a timestamp (tool results, plain answers).
        mutating func touch(_ timestamp: Date, period: Period) {
            firstTimestampEver = min(firstTimestampEver ?? timestamp, timestamp)
            guard period.contains(timestamp), activityInWindow else { return }
            end = max(end ?? timestamp, timestamp)
        }

        func session(fallbackID: String) -> SessionFact? {
            guard activityInWindow, let start, let end,
                  let cwd = ClaudeTranscriptParser.primaryFolder(cwdCounts) ?? lastCwd
            else { return nil }
            // Only sessions with human input or real tool work are worth reporting.
            guard promptCount > 0 || !toolCounts.isEmpty else { return nil }

            let limit = ClaudeTranscriptParser.maxPrompts
            let keptPrompts = prompts.count > limit
                ? Array(prompts.prefix(6)) + Array(prompts.suffix(limit - 6))
                : prompts
            // Cumulative line counts only describe this window if the whole session is inside it.
            let sessionInsideWindow = (firstTimestampEver ?? start) >= start

            return SessionFact(
                sessionID: sessionID ?? fallbackID,
                cwd: cwd,
                title: title ?? summaryTitle ?? prompts.first?.condensed(limit: 80),
                branch: branch,
                startedAt: start,
                endedAt: end,
                promptCount: promptCount,
                prompts: keptPrompts,
                filesEdited: Array(
                    files.map { ClaudeTranscriptParser.relativePath($0, to: cwd) }
                        .uniqued(by: { $0 })
                        .prefix(ClaudeTranscriptParser.maxFiles)
                ),
                toolCounts: toolCounts,
                actions: Array(actions.uniqued(by: { $0 }).prefix(ClaudeTranscriptParser.maxActions)),
                linesAdded: sessionInsideWindow ? linesAdded : nil,
                linesRemoved: sessionInsideWindow ? linesRemoved : nil,
                entrypoint: entrypoint
            )
        }
    }
}

// MARK: - Lenient transcript model

/// One JSONL record. Every field is optional and decoded leniently: Claude Code's format
/// evolves, and one unexpected field must never drop a whole line.
struct TranscriptLine: Decodable {
    enum Part {
        case text(String)
        case image
        case toolUse(name: String, input: ToolInput)
        case other
    }

    struct ToolInput: Decodable {
        var filePath: String?
        var notebookPath: String?
        var command: String?
        var description: String?

        enum CodingKeys: String, CodingKey {
            case filePath = "file_path", notebookPath = "notebook_path", command, description
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            filePath = try? c.decodeIfPresent(String.self, forKey: .filePath)
            notebookPath = try? c.decodeIfPresent(String.self, forKey: .notebookPath)
            command = try? c.decodeIfPresent(String.self, forKey: .command)
            description = try? c.decodeIfPresent(String.self, forKey: .description)
        }

        init() {}
    }

    var type: String?
    var timestamp: Date?
    var sessionId: String?
    var cwd: String?
    var gitBranch: String?
    var entrypoint: String?
    var isSidechain: Bool?
    var isMeta: Bool?
    var originKind: String?
    var turnOrigin: String?
    var customTitle: String?
    var summary: String?
    var totalLinesAdded: Int?
    var totalLinesRemoved: Int?
    var content: [Part] = []

    enum CodingKeys: String, CodingKey {
        case type, timestamp, sessionId, cwd, gitBranch, entrypoint, isSidechain, isMeta
        case origin, turnOrigin, customTitle, summary, totalLinesAdded, totalLinesRemoved, message
    }

    private enum OriginKeys: String, CodingKey { case kind }
    private enum MessageKeys: String, CodingKey { case content }
    private enum BlockKeys: String, CodingKey { case type, text, name, input }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try? c.decodeIfPresent(String.self, forKey: .type)
        timestamp = (try? c.decodeIfPresent(String.self, forKey: .timestamp)).flatMap { $0.flatMap(ISODate.parse) }
        sessionId = try? c.decodeIfPresent(String.self, forKey: .sessionId)
        cwd = try? c.decodeIfPresent(String.self, forKey: .cwd)
        gitBranch = try? c.decodeIfPresent(String.self, forKey: .gitBranch)
        entrypoint = try? c.decodeIfPresent(String.self, forKey: .entrypoint)
        isSidechain = try? c.decodeIfPresent(Bool.self, forKey: .isSidechain)
        isMeta = try? c.decodeIfPresent(Bool.self, forKey: .isMeta)
        turnOrigin = try? c.decodeIfPresent(String.self, forKey: .turnOrigin)
        customTitle = try? c.decodeIfPresent(String.self, forKey: .customTitle)
        summary = try? c.decodeIfPresent(String.self, forKey: .summary)
        totalLinesAdded = try? c.decodeIfPresent(Int.self, forKey: .totalLinesAdded)
        totalLinesRemoved = try? c.decodeIfPresent(Int.self, forKey: .totalLinesRemoved)

        if let origin = try? c.nestedContainer(keyedBy: OriginKeys.self, forKey: .origin) {
            originKind = try? origin.decodeIfPresent(String.self, forKey: .kind)
        } else {
            originKind = try? c.decodeIfPresent(String.self, forKey: .origin)
        }

        guard let message = try? c.nestedContainer(keyedBy: MessageKeys.self, forKey: .message) else { return }
        if let text = try? message.decode(String.self, forKey: .content) {
            content = [.text(text)]
        } else if var blocks = try? message.nestedUnkeyedContainer(forKey: .content) {
            while !blocks.isAtEnd {
                guard let block = try? blocks.nestedContainer(keyedBy: BlockKeys.self) else {
                    _ = try? blocks.decode(DiscardedValue.self)
                    continue
                }
                switch (try? block.decodeIfPresent(String.self, forKey: .type)) ?? nil {
                case "text":
                    content.append(.text((try? block.decodeIfPresent(String.self, forKey: .text)) ?? nil ?? ""))
                case "image":
                    content.append(.image)
                case "tool_use":
                    let name = ((try? block.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? "?"
                    let input = ((try? block.decodeIfPresent(ToolInput.self, forKey: .input)) ?? nil) ?? ToolInput()
                    content.append(.toolUse(name: name, input: input))
                default:
                    content.append(.other)
                }
            }
        }
    }
}

/// Swallows any JSON value so an unkeyed container can advance past it.
private struct DiscardedValue: Decodable {
    init(from decoder: any Decoder) throws {}
}

extension Data {
    /// `memmem`-backed search; much faster than the generic `Collection` search on long lines.
    func rangeOfBytes(_ needle: Data) -> Range<Index>? {
        guard !needle.isEmpty, needle.count <= count else { return nil }
        let offset: Int? = withUnsafeBytes { haystack in
            needle.withUnsafeBytes { pattern in
                guard let base = haystack.baseAddress,
                      let found = memmem(base, haystack.count, pattern.baseAddress, pattern.count)
                else { return nil }
                return base.distance(to: UnsafeRawPointer(found))
            }
        }
        return offset.map { (startIndex + $0)..<(startIndex + $0 + needle.count) }
    }

    func containsBytes(_ needle: Data) -> Bool { rangeOfBytes(needle) != nil }
}
