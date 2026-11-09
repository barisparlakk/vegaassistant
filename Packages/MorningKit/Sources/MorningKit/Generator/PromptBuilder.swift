import Foundation

public struct BriefingPrompt: Sendable {
    public var system: String
    public var user: String
    public var schema: String

    /// Appends the validator's complaints so the second attempt can fix them.
    public func retry(problems: [String]) -> BriefingPrompt {
        var copy = self
        copy.user += "\n\nYour previous answer was rejected:\n"
            + problems.map { "- \($0)" }.joined(separator: "\n")
            + "\nReturn the corrected JSON object only."
        return copy
    }
}

/// Turns facts into a compact, id-tagged CONTEXT the model can reason over in one pass.
/// Everything is pre-digested (local times, relative ages, counts) so the model never has
/// to do date math, and long lists are capped to keep the prompt around 10–20k tokens.
public struct PromptBuilder: Sendable {
    public var calendar: Calendar
    public var paths: MorningPaths

    static let maxCommits = 80
    static let maxPromptsPerSession = 8
    static let maxFilesPerSession = 12
    static let activeWindowDays = 14.0

    public init(calendar: Calendar = .current, paths: MorningPaths = MorningPaths()) {
        // The prompt is English; weekday names must not follow the user's locale.
        var english = calendar
        english.locale = Locale(identifier: "en_US_POSIX")
        self.calendar = english
        self.paths = paths
    }

    public func build(facts: BriefingFacts, reports: [CollectorReport], settings: MorningSettings) -> BriefingPrompt {
        let context = makeContext(facts: facts, reports: reports)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let contextJSON = (try? encoder.encode(context)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"

        var user = "Write today's briefing."
        if let extra = settings.extraInstructions.nilIfEmpty {
            user += "\n\nAdditional instructions from the user (follow them unless they conflict with the ground rules):\n\(extra)"
        }
        user += "\n\nCONTEXT:\n\(contextJSON)"
        return BriefingPrompt(system: Self.systemPrompt, user: user, schema: BriefingSchema.json)
    }

    // MARK: - Context

    func makeContext(facts: BriefingFacts, reports: [CollectorReport]) -> PromptContext {
        let now = facts.period.to
        let attentionProjects = Set(facts.attention.compactMap(\.projectID))
        let activeIDs = Set(facts.sessions.compactMap(\.projectID) + facts.commits.map(\.projectID))
        let isActive: (ProjectFact) -> Bool = { project in
            activeIDs.contains(project.id)
                || attentionProjects.contains(project.id)
                || (project.lastActivityAt.map { now.timeIntervalSince($0) < Self.activeWindowDays * 86_400 } ?? false)
        }
        let openTodos = Dictionary(grouping: facts.notes, by: \.projectID).mapValues { $0.reduce(0) { $0 + $1.openItems.count } }

        let projects = facts.projects.filter(isActive).map { project in
            PromptContext.Project(
                id: project.id,
                name: project.name,
                kind: project.kind.rawValue,
                branch: project.branch,
                defaultBranch: project.defaultBranch == project.branch ? nil : project.defaultBranch,
                uncommitted: project.isDirty ? "\(project.changedFiles) modified, \(project.untrackedFiles) untracked" : nil,
                unpushed: project.ahead > 0 ? project.ahead : nil,
                behind: project.behind > 0 ? project.behind : nil,
                lastActivity: project.lastActivityAt.map { relative($0, to: now) },
                commitsLast14Days: project.kind == .repo ? project.commitsLast14Days.reduce(0, +) : nil,
                activeDaysLast14: project.kind == .repo ? project.commitsLast14Days.filter { $0 > 0 }.count : nil,
                staleBranches: project.branches.filter(\.isStale).map(\.name).nilIfEmpty,
                openTodos: openTodos[project.id]
            )
        }

        let sessions = facts.sessions.map { session in
            let tools = session.toolCounts.sorted { $0.value > $1.value }.prefix(5).map { "\($0.key)×\($0.value)" }
            let lines: String? = if let added = session.linesAdded, let removed = session.linesRemoved, added + removed > 0 {
                "+\(added)/−\(removed)"
            } else {
                nil
            }
            return PromptContext.Session(
                id: session.id,
                project: session.projectID ?? unassignedLabel(session.cwd),
                title: session.title,
                when: span(session.startedAt, session.endedAt),
                branch: session.branch,
                prompts: Self.sample(session.prompts, limit: Self.maxPromptsPerSession).map { $0.condensed(limit: 240) },
                filesEdited: Array(session.filesEdited.prefix(Self.maxFilesPerSession)).nilIfEmpty,
                actions: Array(session.actions.prefix(8)).nilIfEmpty,
                tools: tools.joined(separator: ", ").nilIfEmpty,
                lines: lines
            )
        }

        let defaultBranches = Dictionary(facts.projects.map { ($0.id, $0.defaultBranch) }, uniquingKeysWith: { first, _ in first })
        let commits = facts.commits.prefix(Self.maxCommits).map { commit in
            PromptContext.Commit(
                id: commit.id,
                project: commit.projectID,
                at: dayTime(commit.authoredAt),
                subject: commit.subject,
                branch: commit.branch == (defaultBranches[commit.projectID] ?? nil) ? nil : commit.branch,
                author: commit.author,
                change: "\(commit.files.count) files, +\(commit.insertions)/−\(commit.deletions)"
            )
        }
        var omittedCommits: [String: Int]?
        if facts.commits.count > Self.maxCommits {
            omittedCommits = Dictionary(grouping: facts.commits.dropFirst(Self.maxCommits), by: \.projectID).mapValues(\.count)
        }

        let events = facts.events.map { event in
            PromptContext.Event(
                id: event.id,
                title: event.title,
                when: event.isAllDay ? "all day" : "\(time(event.start))–\(time(event.end))",
                calendar: event.calendar,
                location: event.location,
                attendees: event.attendeeCount > 0 ? event.attendeeCount : nil,
                notes: event.notes
            )
        }

        let reminders = facts.reminders.map { reminder in
            PromptContext.Reminder(
                id: reminder.id,
                title: reminder.title,
                due: reminder.due.map { reminder.isOverdue ? "overdue since \(dayTime($0))" : time($0) },
                priority: Self.reminderPriority(reminder.priority),
                list: reminder.list
            )
        }

        let attention = facts.attention.map { item in
            PromptContext.Attention(id: item.id, kind: item.kind.rawValue, severity: item.severity.rawValue, project: item.projectID, title: item.title, detail: item.detail)
        }

        let pullRequests = (facts.github.authoredPRs.map { ($0, "mine") } + facts.github.reviewRequests.map { ($0, "review requested") })
            .map { pr, role in
                PromptContext.PullRequest(
                    id: pr.id,
                    project: pr.projectID,
                    title: pr.title,
                    role: role,
                    state: [pr.isDraft ? "draft" : nil, pr.reviewDecision?.lowercased(), pr.checks == .none ? nil : "checks \(pr.checks.rawValue)"]
                        .compactMap { $0 }.joined(separator: ", ").nilIfEmpty,
                    author: role == "mine" ? nil : pr.author,
                    updated: relative(pr.updatedAt, to: now)
                )
            }

        let issues = facts.github.assignedIssues.map {
            PromptContext.Issue(id: $0.id, project: $0.projectID, title: $0.title, labels: $0.labels.nilIfEmpty, updated: relative($0.updatedAt, to: now))
        }

        let notes = facts.notes.map {
            PromptContext.Note(id: $0.id, project: $0.projectID, file: $0.file, openItems: Array($0.openItems.prefix(8)).nilIfEmpty, excerpt: $0.excerpt?.condensed(limit: 300))
        }

        let unavailable = reports.filter { $0.status != .ok }.map { report in
            "\(report.kind.displayName): \(report.status == .failed ? "failed" : "unavailable")" + (report.message.map { " — \($0.condensed(limit: 120))" } ?? "")
        }

        let hookCounts = Dictionary(grouping: facts.hookEvents, by: { $0.projectID ?? "none" }).mapValues(\.count)
        let inactive = facts.projects.filter { !isActive($0) }.map(\.name)

        return PromptContext(
            now: "\(weekdayDate(now)) \(time(now)) (\(calendar.timeZone.identifier))",
            window: "since \(weekdayDate(facts.period.from)) \(time(facts.period.from)) (\(Int(now.timeIntervalSince(facts.period.from) / 3600)) h)",
            projects: projects,
            quietProjects: inactive.nilIfEmpty,
            sessions: sessions,
            commits: Array(commits),
            commitsOmitted: omittedCommits,
            claudeTurnsFinished: hookCounts.isEmpty ? nil : hookCounts,
            calendar: events,
            reminders: reminders,
            attention: attention,
            pullRequests: pullRequests,
            issues: issues,
            notes: notes,
            unavailableSources: unavailable.nilIfEmpty
        )
    }

    // MARK: - Formatting

    /// Keeps the first prompts (intent) and the last ones (where it ended).
    static func sample(_ prompts: [String], limit: Int) -> [String] {
        guard prompts.count > limit else { return prompts }
        let head = limit / 2
        return Array(prompts.prefix(head)) + ["… \(prompts.count - limit) more prompts …"] + Array(prompts.suffix(limit - head))
    }

    static func reminderPriority(_ value: Int) -> String? {
        switch value {
        case 1...4: "high"
        case 5: "medium"
        case 6...9: "low"
        default: nil
        }
    }

    private func time(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private func weekdayDate(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        let weekday = calendar.weekdaySymbols[(parts.weekday ?? 1) - 1]
        return String(format: "%@ %04d-%02d-%02d", weekday, parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func dayTime(_ date: Date) -> String {
        let weekday = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
        return "\(weekday) \(time(date))"
    }

    private func span(_ start: Date, _ end: Date) -> String {
        calendar.isDate(start, inSameDayAs: end)
            ? "\(dayTime(start))–\(time(end))"
            : "\(dayTime(start)) – \(dayTime(end))"
    }

    /// Sessions outside any project (e.g. Claude's scratch chats under ~/Library).
    private func unassignedLabel(_ cwd: String) -> String {
        cwd.hasPrefix(paths.home.appending(path: "Library").path) ? "none (general chat)" : "none (\(paths.abbreviate(cwd)))"
    }

    private func relative(_ date: Date, to now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 0 { return "in the future" }
        return "\(AttentionRules.age(from: date, to: now)) ago"
    }

    // MARK: - Instructions

    static let systemPrompt = """
    You are Morning, a chief of staff for one software developer. Every morning you turn raw activity data into a short, decisive briefing they can act on in two minutes.

    You receive CONTEXT as JSON: what happened since the last briefing (Claude Code sessions and git commits), today's calendar and reminders, repository state, GitHub items and TODO notes. Return one JSON object matching the provided schema. No markdown, no code fences, no commentary.

    Ground rules
    - Use only facts in CONTEXT. Never invent events, commits, numbers, people or links.
    - Refer to facts by their exact ids from CONTEXT (e.g. "repo:daybase", "commit:0f0fa02a1b", "pr:owner/repo#12", "attn:dirty:repo:Notary", "session:1f12ce81"). Put fact ids only in `refs` and project ids only in `projectId`. Never write URLs.
    - Text fields (headline, reason, title, detail, summary) are read by a person: never put ids in them. Write project names, 7-character commit hashes, PR numbers like #12 and branch names instead.
    - Sources listed in unavailableSources are unknown, not empty. When the calendar is unavailable, say nothing about meetings, free time or how open the day is.
    - Mention each piece of work once: a task in focus.tasks must not reappear in "attention" or nextTasks, and an "attention" item must not reappear in nextTasks.
    - Write in English unless the user's additional instructions say otherwise; prompts in CONTEXT may be in other languages. Be plain and specific, use 24-hour local times, no emojis, no exclamation marks, no praise or filler.

    headline: one short sentence (at most 100 characters, no semicolons) naming the one thing that matters most today. It is shown as a large title.

    focus: the single project where today's effort pays off most. Weigh, in order: things blocking others or broken (failing checks, requested changes, review requests); momentum (finishing what moved yesterday beats starting something new); risk of losing work (long-uncommitted or unpushed changes); open TODOs; the time actually free today given the calendar. `reason` states the evidence in 1–3 sentences. Use low confidence when the data is thin.

    focus.tasks: up to 3 ordered next actions for today on the focus project. Each starts with a verb, is finishable in one sitting and names the concrete thing (file, branch, PR, feature). `detail` says how or why in one sentence. `estimateMinutes` is honest. `refs` cite the supporting facts.

    sections, in this order, leaving out any with nothing useful to say:
    - "overnight": one item per project with activity. title = what was accomplished (the outcome, not "worked on X"); detail = notable specifics; refs = its session and commit ids; priority = how significant it was.
    - "agenda": only when there are events or reminders. Point out prep, conflicts, overdue reminders and the free blocks for focused work. refs = event and reminder ids.
    - "attention": things that need a decision, most urgent first. Fold routine hygiene (several dirty repos) into one item. Say what to do, not only what's wrong. refs = attention ids.
    - "notes": open TODO items relevant to today, only if any.

    nextTasks: up to 5 worthwhile tasks for projects that are neither the focus nor already covered by an "attention" item, each with its project id, priority, estimate and a one-line reason.
    """
}

// MARK: - Context model (encoded into the prompt)

struct PromptContext: Encodable {
    struct Project: Encodable {
        let id: String
        let name: String
        let kind: String
        let branch: String?
        let defaultBranch: String?
        let uncommitted: String?
        let unpushed: Int?
        let behind: Int?
        let lastActivity: String?
        let commitsLast14Days: Int?
        let activeDaysLast14: Int?
        let staleBranches: [String]?
        let openTodos: Int?
    }

    struct Session: Encodable {
        let id: String
        let project: String
        let title: String?
        let when: String
        let branch: String?
        let prompts: [String]
        let filesEdited: [String]?
        let actions: [String]?
        let tools: String?
        let lines: String?
    }

    struct Commit: Encodable {
        let id: String
        let project: String
        let at: String
        let subject: String
        let branch: String?
        let author: String
        let change: String
    }

    struct Event: Encodable {
        let id: String
        let title: String
        let when: String
        let calendar: String
        let location: String?
        let attendees: Int?
        let notes: String?
    }

    struct Reminder: Encodable {
        let id: String
        let title: String
        let due: String?
        let priority: String?
        let list: String
    }

    struct Attention: Encodable {
        let id: String
        let kind: String
        let severity: String
        let project: String?
        let title: String
        let detail: String
    }

    struct PullRequest: Encodable {
        let id: String
        let project: String?
        let title: String
        let role: String
        let state: String?
        let author: String?
        let updated: String
    }

    struct Issue: Encodable {
        let id: String
        let project: String?
        let title: String
        let labels: [String]?
        let updated: String
    }

    struct Note: Encodable {
        let id: String
        let project: String
        let file: String
        let openItems: [String]?
        let excerpt: String?
    }

    let now: String
    let window: String
    let projects: [Project]
    let quietProjects: [String]?
    let sessions: [Session]
    let commits: [Commit]
    let commitsOmitted: [String: Int]?
    let claudeTurnsFinished: [String: Int]?
    let calendar: [Event]
    let reminders: [Reminder]
    let attention: [Attention]
    let pullRequests: [PullRequest]
    let issues: [Issue]
    let notes: [Note]
    let unavailableSources: [String]?
}

extension Array {
    var nilIfEmpty: [Element]? { isEmpty ? nil : self }
}
