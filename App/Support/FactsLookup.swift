import MorningKit

/// Resolves the ids the model cites back to the facts they name.
extension BriefingFacts {
    enum Evidence: Identifiable {
        case session(SessionFact)
        case commit(CommitFact)
        case pullRequest(PullRequestFact)
        case issue(IssueFact)
        case attention(AttentionFact)
        case note(NoteFact)
        case event(EventFact)
        case reminder(ReminderFact)

        var id: String {
            switch self {
            case let .session(fact): fact.id
            case let .commit(fact): fact.id
            case let .pullRequest(fact): fact.id
            case let .issue(fact): fact.id
            case let .attention(fact): fact.id
            case let .note(fact): fact.id
            case let .event(fact): fact.id
            case let .reminder(fact): fact.id
            }
        }
    }

    func evidence(_ refs: [String]) -> [Evidence] {
        refs.compactMap(evidence(for:))
    }

    func evidence(for ref: String) -> Evidence? {
        if let fact = sessions.first(where: { $0.id == ref }) { return .session(fact) }
        if let fact = commits.first(where: { $0.id == ref }) { return .commit(fact) }
        if let fact = (github.authoredPRs + github.reviewRequests).first(where: { $0.id == ref }) { return .pullRequest(fact) }
        if let fact = github.assignedIssues.first(where: { $0.id == ref }) { return .issue(fact) }
        if let fact = attention.first(where: { $0.id == ref }) { return .attention(fact) }
        if let fact = notes.first(where: { $0.id == ref }) { return .note(fact) }
        if let fact = events.first(where: { $0.id == ref }) { return .event(fact) }
        if let fact = reminders.first(where: { $0.id == ref }) { return .reminder(fact) }
        return nil
    }

    func attentionFacts(_ refs: [String]) -> [AttentionFact] {
        refs.compactMap { ref in attention.first { $0.id == ref } }
    }

    func sessions(for projectID: String) -> [SessionFact] { sessions.filter { $0.projectID == projectID } }
    func commits(for projectID: String) -> [CommitFact] { commits.filter { $0.projectID == projectID } }

    /// Projects worth a card: touched in the last two weeks or needing attention.
    var activeProjects: [ProjectFact] {
        let flagged = Set(attention.compactMap(\.projectID))
        return projects.filter { project in
            flagged.contains(project.id)
                || (project.lastActivityAt.map { period.to.timeIntervalSince($0) < 14 * 86_400 } ?? false)
        }
    }
}

extension AttentionFact.Kind {
    var symbol: String {
        switch self {
        case .failingChecks: "xmark.octagon"
        case .changesRequested: "text.bubble"
        case .reviewRequested: "eye"
        case .readyToMerge: "checkmark.seal"
        case .openPullRequest: "arrow.triangle.pull"
        case .assignedIssue: "exclamationmark.circle"
        case .uncommittedChanges: "pencil.and.list.clipboard"
        case .unpushedCommits: "arrow.up.circle"
        case .behindRemote: "arrow.down.circle"
        case .staleBranch: "leaf"
        case .upstreamGone: "link.badge.plus"
        }
    }
}
