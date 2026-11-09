import Foundation

// MARK: - Facts
//
// Facts are what the collectors observed: they are never written by the model.
// The UI renders timelines, agendas, sparklines and action buttons from facts,
// so hashes, times and URLs are always real. The model only *refers* to facts by id.

public struct Period: Codable, Sendable, Hashable {
    public var from: Date
    public var to: Date

    public init(from: Date, to: Date) {
        self.from = from
        self.to = to
    }

    public func contains(_ date: Date) -> Bool { date >= from && date <= to }
}

public struct BriefingFacts: Codable, Sendable, Hashable {
    public var period: Period
    public var collectedAt: Date
    public var projects: [ProjectFact]
    public var sessions: [SessionFact]
    public var hookEvents: [HookEventFact]
    public var commits: [CommitFact]
    public var events: [EventFact]
    public var reminders: [ReminderFact]
    public var github: GitHubFacts
    public var attention: [AttentionFact]
    public var notes: [NoteFact]

    public init(
        period: Period,
        collectedAt: Date = .now,
        projects: [ProjectFact] = [],
        sessions: [SessionFact] = [],
        hookEvents: [HookEventFact] = [],
        commits: [CommitFact] = [],
        events: [EventFact] = [],
        reminders: [ReminderFact] = [],
        github: GitHubFacts = GitHubFacts(),
        attention: [AttentionFact] = [],
        notes: [NoteFact] = []
    ) {
        self.period = period
        self.collectedAt = collectedAt
        self.projects = projects
        self.sessions = sessions
        self.hookEvents = hookEvents
        self.commits = commits
        self.events = events
        self.reminders = reminders
        self.github = github
        self.attention = attention
        self.notes = notes
    }

    /// Appends everything another collector produced.
    public mutating func merge(_ other: BriefingFacts) {
        projects += other.projects
        sessions += other.sessions
        hookEvents += other.hookEvents
        commits += other.commits
        events += other.events
        reminders += other.reminders
        github.merge(other.github)
        attention += other.attention
        notes += other.notes
    }

    /// Every id the model is allowed to reference.
    public var referenceableIDs: Set<String> {
        var ids = Set<String>()
        ids.formUnion(projects.map(\.id))
        ids.formUnion(sessions.map(\.id))
        ids.formUnion(commits.map(\.id))
        ids.formUnion(events.map(\.id))
        ids.formUnion(reminders.map(\.id))
        ids.formUnion(github.authoredPRs.map(\.id))
        ids.formUnion(github.reviewRequests.map(\.id))
        ids.formUnion(github.assignedIssues.map(\.id))
        ids.formUnion(attention.map(\.id))
        ids.formUnion(notes.map(\.id))
        for project in projects {
            ids.formUnion(project.branches.map { FactID.branch(project.id, $0.name) })
        }
        return ids
    }

    public func project(_ id: String?) -> ProjectFact? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }
}

// MARK: - Projects

public struct ProjectFact: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable { case repo, folder }

    public var id: String
    public var name: String
    public var path: String
    public var kind: Kind
    public var branch: String?
    public var defaultBranch: String?
    public var githubSlug: String?
    public var webURL: String?
    public var changedFiles: Int
    public var untrackedFiles: Int
    public var ahead: Int
    public var behind: Int
    public var hasUpstream: Bool
    public var lastCommitAt: Date?
    public var lastActivityAt: Date?
    /// Commits per local day, oldest first, always 14 entries for repos.
    public var commitsLast14Days: [Int]
    public var branches: [BranchFact]

    public var isDirty: Bool { changedFiles + untrackedFiles > 0 }

    public init(
        id: String,
        name: String,
        path: String,
        kind: Kind,
        branch: String? = nil,
        defaultBranch: String? = nil,
        githubSlug: String? = nil,
        webURL: String? = nil,
        changedFiles: Int = 0,
        untrackedFiles: Int = 0,
        ahead: Int = 0,
        behind: Int = 0,
        hasUpstream: Bool = false,
        lastCommitAt: Date? = nil,
        lastActivityAt: Date? = nil,
        commitsLast14Days: [Int] = [],
        branches: [BranchFact] = []
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.kind = kind
        self.branch = branch
        self.defaultBranch = defaultBranch
        self.githubSlug = githubSlug
        self.webURL = webURL
        self.changedFiles = changedFiles
        self.untrackedFiles = untrackedFiles
        self.ahead = ahead
        self.behind = behind
        self.hasUpstream = hasUpstream
        self.lastCommitAt = lastCommitAt
        self.lastActivityAt = lastActivityAt
        self.commitsLast14Days = commitsLast14Days
        self.branches = branches
    }
}

public struct BranchFact: Codable, Sendable, Hashable {
    public var name: String
    public var lastCommitAt: Date?
    public var upstream: String?
    public var upstreamGone: Bool
    public var ahead: Int
    public var behind: Int
    public var isCurrent: Bool
    public var isMerged: Bool
    public var isStale: Bool

    public init(
        name: String,
        lastCommitAt: Date? = nil,
        upstream: String? = nil,
        upstreamGone: Bool = false,
        ahead: Int = 0,
        behind: Int = 0,
        isCurrent: Bool = false,
        isMerged: Bool = false,
        isStale: Bool = false
    ) {
        self.name = name
        self.lastCommitAt = lastCommitAt
        self.upstream = upstream
        self.upstreamGone = upstreamGone
        self.ahead = ahead
        self.behind = behind
        self.isCurrent = isCurrent
        self.isMerged = isMerged
        self.isStale = isStale
    }
}

// MARK: - Activity

public struct SessionFact: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var sessionID: String
    public var projectID: String?
    public var cwd: String
    public var title: String?
    public var branch: String?
    public var startedAt: Date
    public var endedAt: Date
    public var promptCount: Int
    /// Human prompts in the window, truncated.
    public var prompts: [String]
    /// Paths relative to `cwd` when possible.
    public var filesEdited: [String]
    public var toolCounts: [String: Int]
    /// Short descriptions of notable shell actions ("Run test suite", "Push to origin").
    public var actions: [String]
    public var linesAdded: Int?
    public var linesRemoved: Int?
    public var entrypoint: String?

    public init(
        sessionID: String,
        projectID: String? = nil,
        cwd: String,
        title: String? = nil,
        branch: String? = nil,
        startedAt: Date,
        endedAt: Date,
        promptCount: Int = 0,
        prompts: [String] = [],
        filesEdited: [String] = [],
        toolCounts: [String: Int] = [:],
        actions: [String] = [],
        linesAdded: Int? = nil,
        linesRemoved: Int? = nil,
        entrypoint: String? = nil
    ) {
        self.id = FactID.session(sessionID)
        self.sessionID = sessionID
        self.projectID = projectID
        self.cwd = cwd
        self.title = title
        self.branch = branch
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.promptCount = promptCount
        self.prompts = prompts
        self.filesEdited = filesEdited
        self.toolCounts = toolCounts
        self.actions = actions
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
        self.entrypoint = entrypoint
    }
}

public struct HookEventFact: Codable, Sendable, Hashable {
    public var timestamp: Date
    public var event: String
    public var sessionID: String?
    public var cwd: String?
    public var projectID: String?

    public init(timestamp: Date, event: String, sessionID: String? = nil, cwd: String? = nil, projectID: String? = nil) {
        self.timestamp = timestamp
        self.event = event
        self.sessionID = sessionID
        self.cwd = cwd
        self.projectID = projectID
    }
}

public struct CommitFact: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var hash: String
    public var projectID: String
    public var subject: String
    public var author: String
    public var authoredAt: Date
    public var branch: String?
    public var files: [String]
    public var insertions: Int
    public var deletions: Int

    public var shortHash: String { String(hash.prefix(7)) }

    public init(
        hash: String,
        projectID: String,
        subject: String,
        author: String,
        authoredAt: Date,
        branch: String? = nil,
        files: [String] = [],
        insertions: Int = 0,
        deletions: Int = 0
    ) {
        self.id = FactID.commit(hash)
        self.hash = hash
        self.projectID = projectID
        self.subject = subject
        self.author = author
        self.authoredAt = authoredAt
        self.branch = branch
        self.files = files
        self.insertions = insertions
        self.deletions = deletions
    }
}

// MARK: - Calendar

public struct EventFact: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var calendar: String
    public var colorHex: String?
    public var location: String?
    public var url: String?
    public var notes: String?
    public var attendeeCount: Int

    public init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        calendar: String,
        colorHex: String? = nil,
        location: String? = nil,
        url: String? = nil,
        notes: String? = nil,
        attendeeCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendar = calendar
        self.colorHex = colorHex
        self.location = location
        self.url = url
        self.notes = notes
        self.attendeeCount = attendeeCount
    }
}

public struct ReminderFact: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var due: Date?
    /// EventKit priority: 0 none, 1–4 high, 5 medium, 6–9 low.
    public var priority: Int
    public var list: String
    public var isOverdue: Bool
    public var notes: String?

    public init(id: String, title: String, due: Date? = nil, priority: Int = 0, list: String, isOverdue: Bool = false, notes: String? = nil) {
        self.id = id
        self.title = title
        self.due = due
        self.priority = priority
        self.list = list
        self.isOverdue = isOverdue
        self.notes = notes
    }
}

// MARK: - GitHub

public struct GitHubFacts: Codable, Sendable, Hashable {
    public var login: String?
    public var authoredPRs: [PullRequestFact]
    public var reviewRequests: [PullRequestFact]
    public var assignedIssues: [IssueFact]

    public init(login: String? = nil, authoredPRs: [PullRequestFact] = [], reviewRequests: [PullRequestFact] = [], assignedIssues: [IssueFact] = []) {
        self.login = login
        self.authoredPRs = authoredPRs
        self.reviewRequests = reviewRequests
        self.assignedIssues = assignedIssues
    }

    public var isEmpty: Bool { authoredPRs.isEmpty && reviewRequests.isEmpty && assignedIssues.isEmpty }

    mutating func merge(_ other: GitHubFacts) {
        login = login ?? other.login
        authoredPRs += other.authoredPRs
        reviewRequests += other.reviewRequests
        assignedIssues += other.assignedIssues
    }
}

public struct PullRequestFact: Codable, Sendable, Hashable, Identifiable {
    public enum ChecksState: String, Codable, Sendable { case success, failure, pending, none }

    public var id: String
    public var number: Int
    public var title: String
    public var url: String
    public var repo: String
    public var projectID: String?
    public var author: String?
    public var isDraft: Bool
    public var createdAt: Date?
    public var updatedAt: Date
    public var headRef: String?
    /// APPROVED, CHANGES_REQUESTED, REVIEW_REQUIRED, or nil.
    public var reviewDecision: String?
    public var checks: ChecksState

    public init(
        number: Int,
        title: String,
        url: String,
        repo: String,
        projectID: String? = nil,
        author: String? = nil,
        isDraft: Bool = false,
        createdAt: Date? = nil,
        updatedAt: Date,
        headRef: String? = nil,
        reviewDecision: String? = nil,
        checks: ChecksState = .none
    ) {
        self.id = FactID.pullRequest(repo, number)
        self.number = number
        self.title = title
        self.url = url
        self.repo = repo
        self.projectID = projectID
        self.author = author
        self.isDraft = isDraft
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.headRef = headRef
        self.reviewDecision = reviewDecision
        self.checks = checks
    }
}

public struct IssueFact: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var number: Int
    public var title: String
    public var url: String
    public var repo: String
    public var projectID: String?
    public var updatedAt: Date
    public var labels: [String]

    public init(number: Int, title: String, url: String, repo: String, projectID: String? = nil, updatedAt: Date, labels: [String] = []) {
        self.id = FactID.issue(repo, number)
        self.number = number
        self.title = title
        self.url = url
        self.repo = repo
        self.projectID = projectID
        self.updatedAt = updatedAt
        self.labels = labels
    }
}

// MARK: - Attention & notes

public enum Severity: String, Codable, Sendable, Hashable, Comparable, CaseIterable {
    case high, medium, low

    private var rank: Int {
        switch self {
        case .high: 0
        case .medium: 1
        case .low: 2
        }
    }

    public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rank < rhs.rank }
}

public struct AttentionFact: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case failingChecks, changesRequested, reviewRequested, readyToMerge, openPullRequest
        case assignedIssue
        case uncommittedChanges, unpushedCommits, behindRemote, staleBranch, upstreamGone
    }

    public var id: String
    public var kind: Kind
    public var severity: Severity
    public var projectID: String?
    public var title: String
    public var detail: String
    public var refs: [String]
    /// Local folder for "Open in Terminal / VS Code".
    public var path: String?
    /// Web page for "Open on GitHub".
    public var url: String?
    public var since: Date?

    public init(
        id: String,
        kind: Kind,
        severity: Severity,
        projectID: String? = nil,
        title: String,
        detail: String,
        refs: [String] = [],
        path: String? = nil,
        url: String? = nil,
        since: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.severity = severity
        self.projectID = projectID
        self.title = title
        self.detail = detail
        self.refs = refs
        self.path = path
        self.url = url
        self.since = since
    }
}

public struct NoteFact: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var projectID: String
    public var file: String
    public var path: String
    public var openItems: [String]
    public var excerpt: String?
    public var modifiedAt: Date?

    public init(projectID: String, file: String, path: String, openItems: [String], excerpt: String? = nil, modifiedAt: Date? = nil) {
        self.id = FactID.note(projectID, file)
        self.projectID = projectID
        self.file = file
        self.path = path
        self.openItems = openItems
        self.excerpt = excerpt
        self.modifiedAt = modifiedAt
    }
}

// MARK: - IDs

/// Stable, human-readable ids the model uses to reference facts.
public enum FactID {
    public static func repo(_ name: String) -> String { "repo:\(name)" }
    public static func folder(_ name: String) -> String { "dir:\(name)" }
    public static func session(_ id: String) -> String { "session:\(id.prefix(8))" }
    public static func commit(_ hash: String) -> String { "commit:\(hash.prefix(10))" }
    public static func branch(_ projectID: String, _ name: String) -> String {
        "branch:\(projectID.split(separator: ":", maxSplits: 1).last ?? "")/\(name)"
    }
    public static func pullRequest(_ repo: String, _ number: Int) -> String { "pr:\(repo)#\(number)" }
    public static func issue(_ repo: String, _ number: Int) -> String { "issue:\(repo)#\(number)" }
    public static func note(_ projectID: String, _ file: String) -> String {
        "note:\(projectID.split(separator: ":", maxSplits: 1).last ?? "")/\(file)"
    }
}
