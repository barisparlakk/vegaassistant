import Foundation

/// Reads `~/.morning/log.jsonl`, appended to by the Claude Code Stop hook.
/// Each line is `{"ts": "<ISO8601>", "event": <hook stdin JSON>}`.
public struct SessionLogCollector: Collector {
    public let kind = CollectorKind.sessionLog

    public init() {}

    public func collect(_ context: CollectionContext) async throws -> CollectorOutput {
        let file = context.paths.hookLog
        guard let data = try? Data(contentsOf: file) else {
            throw CollectorSkipped("Stop hook not installed yet (no \(context.paths.abbreviate(file.path)))")
        }
        var fragment = BriefingFacts.fragment(context)
        fragment.hookEvents = Self.parse(data, period: context.period)
        return CollectorOutput(facts: fragment)
    }

    static func parse(_ data: Data, period: Period) -> [HookEventFact] {
        let decoder = JSONDecoder()
        return data.split(separator: UInt8(ascii: "\n")).compactMap { line -> HookEventFact? in
            guard let entry = try? decoder.decode(Entry.self, from: line),
                  let timestamp = ISODate.parse(entry.ts),
                  period.contains(timestamp)
            else { return nil }
            return HookEventFact(
                timestamp: timestamp,
                event: entry.event?.hookEventName ?? "Stop",
                sessionID: entry.event?.sessionID,
                cwd: entry.event?.cwd
            )
        }
    }

    private struct Entry: Decodable {
        let ts: String
        let event: HookPayload?
    }

    private struct HookPayload: Decodable {
        let sessionID: String?
        let cwd: String?
        let hookEventName: String?

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id", cwd, hookEventName = "hook_event_name"
        }
    }
}
