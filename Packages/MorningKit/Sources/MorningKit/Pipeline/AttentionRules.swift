import Foundation

/// Turns raw repo and GitHub state into a ranked list of things that need a decision.
/// Deterministic on purpose: the model may re-prioritise, but never invents these.
public enum AttentionRules {
    public static func derive(from facts: BriefingFacts, now: Date, staleDays: Int) -> [AttentionFact] {
        var items: [AttentionFact] = []
        let projectsBySlug = Dictionary(
            facts.projects.compactMap { project in project.githubSlug.map { ($0.lowercased(), project) } },
            uniquingKeysWith: { first, _ in first }
        )

        for pr in facts.github.authoredPRs {
            items.append(attention(for: pr, project: projectsBySlug[pr.repo.lowercased()], now: now))
        }

        for pr in facts.github.reviewRequests {
            let waiting = age(from: pr.createdAt ?? pr.updatedAt, to: now)
            items.append(AttentionFact(
                id: "attn:review:\(pr.repo)#\(pr.number)",
                kind: .reviewRequested,
                severity: .high,
                projectID: pr.projectID,
                title: "Review requested: \(pr.title)",
                detail: "\(pr.repo)#\(pr.number)" + (pr.author.map { " by @\($0)" } ?? "") + " · waiting \(waiting)",
                refs: [pr.id] + (pr.projectID.map { [$0] } ?? []),
                path: projectsBySlug[pr.repo.lowercased()]?.path,
                url: pr.url,
                since: pr.createdAt ?? pr.updatedAt
            ))
        }

        for issue in facts.github.assignedIssues {
            let isBug = issue.labels.contains { $0.lowercased().contains("bug") }
            items.append(AttentionFact(
                id: "attn:issue:\(issue.repo)#\(issue.number)",
                kind: .assignedIssue,
                severity: isBug ? .medium : .low,
                projectID: issue.projectID,
                title: issue.title,
                detail: "\(issue.repo)#\(issue.number) assigned to you"
                    + (issue.labels.isEmpty ? "" : " · " + issue.labels.joined(separator: ", ")),
                refs: [issue.id] + (issue.projectID.map { [$0] } ?? []),
                path: projectsBySlug[issue.repo.lowercased()]?.path,
                url: issue.url,
                since: issue.updatedAt
            ))
        }

        for project in facts.projects where project.kind == .repo {
            items += attention(for: project, now: now, staleDays: staleDays)
        }

        return items.sorted {
            ($0.severity, $1.since ?? .distantPast) < ($1.severity, $0.since ?? .distantPast)
        }
    }

    private static func attention(for pr: PullRequestFact, project: ProjectFact?, now: Date) -> AttentionFact {
        let (kind, severity, headline): (AttentionFact.Kind, Severity, String) =
            if pr.checks == .failure {
                (.failingChecks, .high, "Checks failing")
            } else if pr.reviewDecision == "CHANGES_REQUESTED" {
                (.changesRequested, .high, "Changes requested")
            } else if pr.reviewDecision == "APPROVED", pr.checks != .pending, !pr.isDraft {
                (.readyToMerge, .medium, "Approved — ready to merge")
            } else if pr.isDraft {
                (.openPullRequest, .low, "Draft")
            } else {
                (.openPullRequest, .low, "Awaiting review")
            }
        return AttentionFact(
            id: "attn:pr:\(pr.repo)#\(pr.number)",
            kind: kind,
            severity: severity,
            projectID: pr.projectID,
            title: pr.title,
            detail: "\(headline) · \(pr.repo)#\(pr.number) · updated \(age(from: pr.updatedAt, to: now)) ago",
            refs: [pr.id] + (pr.projectID.map { [$0] } ?? []),
            path: project?.path,
            url: pr.url,
            since: pr.updatedAt
        )
    }

    private static func attention(for project: ProjectFact, now: Date, staleDays: Int) -> [AttentionFact] {
        var items: [AttentionFact] = []
        let branch = project.branch ?? "HEAD"

        if project.isDirty {
            // Uncommitted work that's been sitting a while is riskier than today's edits.
            let lingering = (project.lastActivityAt.map { now.timeIntervalSince($0) > 86_400 } ?? true)
            var parts: [String] = []
            if project.changedFiles > 0 { parts.append("\(project.changedFiles) modified") }
            if project.untrackedFiles > 0 { parts.append("\(project.untrackedFiles) untracked") }
            items.append(AttentionFact(
                id: "attn:dirty:\(project.id)",
                kind: .uncommittedChanges,
                severity: lingering ? .medium : .low,
                projectID: project.id,
                title: "Uncommitted changes in \(project.name)",
                detail: parts.joined(separator: ", ") + " on \(branch)",
                refs: [project.id],
                path: project.path,
                url: project.webURL,
                since: project.lastActivityAt
            ))
        }

        for candidate in project.branches where candidate.ahead > 0 {
            items.append(AttentionFact(
                id: "attn:unpushed:\(project.id)/\(candidate.name)",
                kind: .unpushedCommits,
                severity: candidate.isCurrent ? .medium : .low,
                projectID: project.id,
                title: "\(candidate.ahead) unpushed commit\(candidate.ahead == 1 ? "" : "s") in \(project.name)",
                detail: "\(candidate.name) is ahead of \(candidate.upstream ?? "its upstream")",
                refs: [project.id, FactID.branch(project.id, candidate.name)],
                path: project.path,
                url: project.webURL,
                since: candidate.lastCommitAt
            ))
        }

        if project.behind > 0 {
            items.append(AttentionFact(
                id: "attn:behind:\(project.id)",
                kind: .behindRemote,
                severity: .low,
                projectID: project.id,
                title: "\(project.name) is \(project.behind) behind",
                detail: "\(branch) is behind its upstream as of the last fetch",
                refs: [project.id],
                path: project.path,
                url: project.webURL
            ))
        }

        for candidate in project.branches where candidate.upstreamGone && !candidate.isMerged {
            items.append(AttentionFact(
                id: "attn:gone:\(project.id)/\(candidate.name)",
                kind: .upstreamGone,
                severity: .low,
                projectID: project.id,
                title: "\(candidate.name) lost its remote branch",
                detail: "In \(project.name): the upstream was deleted but the branch isn't merged",
                refs: [project.id, FactID.branch(project.id, candidate.name)],
                path: project.path,
                url: project.webURL,
                since: candidate.lastCommitAt
            ))
        }

        let stale = project.branches.filter(\.isStale)
        if !stale.isEmpty {
            let names = stale.prefix(4).map(\.name).joined(separator: ", ") + (stale.count > 4 ? " +\(stale.count - 4)" : "")
            items.append(AttentionFact(
                id: "attn:stale:\(project.id)",
                kind: .staleBranch,
                severity: .low,
                projectID: project.id,
                title: "\(stale.count) stale branch\(stale.count == 1 ? "" : "es") in \(project.name)",
                detail: "No commits for \(staleDays)+ days and not merged: \(names)",
                refs: [project.id] + stale.map { FactID.branch(project.id, $0.name) },
                path: project.path,
                url: project.webURL,
                since: stale.compactMap(\.lastCommitAt).max()
            ))
        }
        return items
    }

    /// "5 min", "3 h", "2 days".
    static func age(from date: Date, to now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<3600: return "\(max(1, Int(seconds / 60))) min"
        case ..<86_400: return "\(Int(seconds / 3600)) h"
        default:
            let days = Int(seconds / 86_400)
            return "\(days) day\(days == 1 ? "" : "s")"
        }
    }
}
