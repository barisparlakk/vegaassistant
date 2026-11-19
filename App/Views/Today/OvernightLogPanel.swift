import MorningKit
import SwiftUI

/// One project's overnight activity.
struct OvernightGroup: Identifiable {
    enum Entry: Identifiable {
        case session(SessionFact)
        case commit(CommitFact)

        var id: String {
            switch self {
            case let .session(session): session.id
            case let .commit(commit): commit.id
            }
        }

        var date: Date {
            switch self {
            case let .session(session): session.endedAt
            case let .commit(commit): commit.authoredAt
            }
        }
    }

    let id: String
    let name: String
    let project: ProjectFact?
    let summary: String
    let entries: [Entry]
    let status: StatusTag.Kind

    var latest: Date { entries.first?.date ?? .distantPast }

    static func make(from facts: BriefingFacts, summary: GeneratedBriefing.Section?) -> [OvernightGroup] {
        var ids = (facts.sessions.compactMap(\.projectID) + facts.commits.map(\.projectID)).uniqued()
        let unassigned = facts.sessions.filter { $0.projectID == nil }
        if !unassigned.isEmpty { ids.append("other") }

        return ids.map { id in
            let sessions = id == "other" ? unassigned : facts.sessions(for: id)
            let commits = id == "other" ? [] : facts.commits(for: id)
            let project = facts.project(id)
            let item = summary?.items.first { $0.projectID == id }
            let entries = (sessions.map(Entry.session) + commits.map(Entry.commit)).sorted { $0.date > $1.date }
            let fallback = [
                sessions.count > 0 ? Format.plural(sessions.count, "session") : nil,
                commits.count > 0 ? Format.plural(commits.count, "commit") : nil,
            ].compactMap { $0 }.joined(separator: ", ")
            return OvernightGroup(
                id: id,
                name: project?.name ?? (id == "other" ? "chats" : id),
                project: project,
                summary: item?.title ?? sessions.first?.title ?? fallback,
                entries: entries,
                status: status(for: id, facts: facts)
            )
        }
        .sorted { $0.latest > $1.latest }
    }

    /// FAILED on failing checks; NEEDS_YOU when work is left uncommitted, unpushed or
    /// waiting on review changes; DONE otherwise.
    static func status(for projectID: String, facts: BriefingFacts) -> StatusTag.Kind {
        let flags = facts.attention.filter { $0.projectID == projectID }.map(\.kind)
        if flags.contains(.failingChecks) { return .failed }
        let needsYou: Set<AttentionFact.Kind> = [.uncommittedChanges, .unpushedCommits, .changesRequested, .upstreamGone, .behindRemote]
        return flags.contains(where: needsYou.contains) ? .needsYou : .done
    }
}

