import Foundation
import MorningKit
import SwiftUI

/// Live state of one generation run, folded from `GenerationEvent`s.
@MainActor
@Observable
final class GenerationProgress {
    enum StepState: Equatable { case pending, running, done, skipped, failed }

    struct Step: Identifiable, Equatable {
        let id: String
        let title: String
        let symbol: String
        var state: StepState = .pending
        var detail: String?
    }

    var steps: [Step]
    var phase: String = "Reading your activity"
    let startedAt = Date.now

    init() {
        steps = CollectorKind.allCases.map { kind in
            Step(id: kind.rawValue, title: kind.shortName, symbol: kind.symbolName)
        } + [
            Step(id: "claude", title: "Claude", symbol: "sparkles"),
            Step(id: "save", title: "Save", symbol: "tray.and.arrow.down"),
        ]
    }

    var completedFraction: Double {
        let finished = steps.filter { [.done, .skipped, .failed].contains($0.state) }.count
        return Double(finished) / Double(max(steps.count, 1))
    }

    /// `collecting git · github…` / `claude ▸ writing 23s` for the status bar.
    func consoleLine(now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(startedAt))
        if let claude = steps.first(where: { $0.id == "claude" }), claude.state == .running {
            return "claude ▸ writing \(seconds)s"
        }
        let running = steps.filter { $0.state == .running }.map { $0.title.lowercased() }
        if running.isEmpty { return "\(phase.lowercased()) \(seconds)s" }
        return "collecting \(running.prefix(3).joined(separator: " · "))\(running.count > 3 ? "…" : "") \(seconds)s"
    }

    func apply(_ event: GenerationEvent) {
        withAnimation(DS.Motion.fast) {
            switch event {
            case let .collecting(.started(kind)):
                update(kind.rawValue) { $0.state = .running }
            case let .collecting(.finished(report)):
                update(report.kind.rawValue) {
                    $0.state = switch report.status {
                    case .ok: .done
                    case .skipped: .skipped
                    case .failed: .failed
                    }
                    $0.detail = report.status == .ok ? "\(report.itemCount)" : nil
                }
            case .collecting:
                break
            case let .collected(projects, sessions, commits, _):
                phase = "Found \(sessions) sessions and \(commits) commits across \(projects) projects"
            case let .askingClaude(attempt):
                phase = attempt == 1 ? "Claude is writing your briefing" : "Claude is taking another pass"
                update("claude") { $0.state = .running }
            case .retrying:
                phase = "The first answer didn't check out — asking again"
            case .fellBackToMarkdown:
                update("claude") { $0.state = .failed }
            case .saved:
                update("claude") { if $0.state == .running { $0.state = .done } }
                update("save") { $0.state = .done }
                phase = "Done"
            }
        }
    }

    private func update(_ id: String, _ change: (inout Step) -> Void) {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
        change(&steps[index])
    }

    /// Mid-run snapshot for previews.
    static var preview: GenerationProgress {
        let progress = GenerationProgress()
        for kind in [CollectorKind.claudeSessions, .sessionLog, .git, .notes] {
            progress.apply(.collecting(.finished(CollectorReport(kind: kind, status: .ok, itemCount: 4))))
        }
        progress.apply(.collecting(.started(.github)))
        progress.apply(.collecting(.started(.calendar)))
        progress.apply(.collecting(.finished(CollectorReport(kind: .reminders, status: .skipped))))
        return progress
    }
}

extension CollectorKind {
    var shortName: String {
        switch self {
        case .claudeSessions: "Sessions"
        case .sessionLog: "Hook log"
        case .git: "Git"
        case .github: "GitHub"
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        case .notes: "Notes"
        case .news: "News"
        }
    }
}
