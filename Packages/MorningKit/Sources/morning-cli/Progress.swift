import Foundation
import MorningKit

/// One live status line on stderr while a briefing is collected and generated.
final class ProgressPrinter: @unchecked Sendable {
    private let enabled: Bool
    private let lock = NSLock()
    private var running = Set<String>()

    init(enabled: Bool) { self.enabled = enabled }

    func handle(_ event: GenerationEvent) {
        guard enabled else { return }
        lock.withLock {
            let line: String
            switch event {
            case let .collecting(collection):
                switch collection {
                case let .started(kind): running.insert(kind.displayName)
                case let .finished(report): running.remove(report.kind.displayName)
                case .resolvedTools, .discoveredProjects: break
                }
                line = running.isEmpty ? "" : "Collecting: " + running.sorted().joined(separator: ", ")
            case let .collected(projects, sessions, commits, events):
                line = "Collected \(projects) projects, \(sessions) sessions, \(commits) commits, \(events) events"
            case let .askingClaude(attempt):
                line = attempt == 1 ? "Asking Claude…" : "Asking Claude again (attempt \(attempt))…"
            case let .retrying(problems):
                write("\r\u{1B}[2KFirst answer rejected: \(problems.joined(separator: " "))\n")
                line = ""
            case .fellBackToMarkdown:
                line = "Answer didn't validate twice — saving it as text"
            case .saved:
                line = ""
            }
            write("\r\u{1B}[2K\(line)")
        }
    }

    func clear() {
        guard enabled else { return }
        write("\r\u{1B}[2K")
    }

    private func write(_ text: String) {
        FileHandle.standardError.write(Data(text.utf8))
    }
}
