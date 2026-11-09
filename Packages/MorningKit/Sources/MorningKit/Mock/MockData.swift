import Foundation

/// Realistic sample data for SwiftUI previews, the app's demo mode and tests.
/// Times are relative to `now` so agendas and "now" indicators look right whenever it's rendered.
public enum MockData {
    public static func briefing(now: Date = .now, calendar: Calendar = .current) -> Briefing {
        let facts = facts(now: now, calendar: calendar)
        return Briefing(
            id: Briefing.id(for: now, calendar: calendar),
            generatedAt: at(7, 0, on: now, calendar),
            trigger: .scheduled,
            model: "sonnet",
            durationMs: 11_400,
            attempts: 1,
            facts: facts,
            content: .structured(generated),
            diagnostics: [
                CollectorReport(kind: .claudeSessions, status: .ok, durationMs: 590, itemCount: 4),
                CollectorReport(kind: .sessionLog, status: .ok, durationMs: 3, itemCount: 11),
                CollectorReport(kind: .git, status: .ok, durationMs: 740, itemCount: 18),
                CollectorReport(kind: .github, status: .ok, durationMs: 1420, itemCount: 3),
                CollectorReport(kind: .notes, status: .ok, durationMs: 6, itemCount: 2),
                CollectorReport(kind: .calendar, status: .ok, durationMs: 40, itemCount: 5),
                CollectorReport(kind: .reminders, status: .ok, durationMs: 55, itemCount: 3),
            ]
        )
    }

    /// The same day, shown as text because validation failed twice.
    public static func fallbackBriefing(now: Date = .now) -> Briefing {
        var briefing = briefing(now: now)
        briefing.attempts = 2
        briefing.content = .markdown(BriefingMarkdown.render(generated, facts: briefing.facts)
            + "\n\n---\n_Shown as text because the answer didn't pass validation: focus.projectId \"repo:day-base\" is not a project id from CONTEXT._")
        return briefing
    }

    /// Two weeks of history rows.
    public static func summaries(now: Date = .now, calendar: Calendar = .current) -> [BriefingSummary] {
        let headlines: [(String, String, String)] = [
            ("Merge the daybase agent branches into feat/rival-features before anything new", "repo:daybase", "daybase"),
            ("Ship the CashDiff landing page and point the domain at Vercel", "repo:Cashdiff", "Cashdiff"),
            ("Get the Qwen3-VL eval numbers on val-mini before the design review", "repo:thermground", "thermground"),
            ("Rebuild the GitHub profile README to match the new website", "repo:barisparlakk", "barisparlakk"),
            ("Fix the Colab tile cache so the parsel-seg data cell stops taking 50 minutes", "repo:parsel-seg", "parsel-seg"),
            ("Untangle Notary's integration branch before it drifts further behind", "repo:Notary", "Notary"),
            ("Finish the passenger linked list for the data structures project", "repo:Veri_Yapilari_Proje", "Veri_Yapilari_Proje"),
            ("Get thermground's MLX adapter tests green", "repo:thermground", "thermground"),
            ("Plan the daybase rival feature list", "repo:daybase", "daybase"),
            ("Write the Morning collectors and CLI", "dir:brief", "brief"),
        ]
        return headlines.enumerated().map { offset, entry in
            let day = calendar.date(byAdding: .day, value: -offset, to: now) ?? now
            return BriefingSummary(
                id: Briefing.id(for: day, calendar: calendar),
                generatedAt: at(7, offset % 3 == 2 ? 41 : 0, on: day, calendar),
                trigger: offset % 4 == 3 ? .manual : .scheduled,
                headline: entry.0,
                focusProjectID: entry.1,
                focusProjectName: entry.2,
                isFallback: offset == 6
            )
        }
    }

    // MARK: - Facts

    public static func facts(now: Date = .now, calendar: Calendar = .current) -> BriefingFacts {
        let from = calendar.date(byAdding: .day, value: -1, to: at(7, 0, on: now, calendar)) ?? now
        func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }
        func today(_ hour: Int, _ minute: Int = 0) -> Date { at(hour, minute, on: now, calendar) }

        var facts = BriefingFacts(period: Period(from: from, to: now), collectedAt: now)
        facts.projects = [
            ProjectFact(
                id: "repo:daybase", name: "daybase", path: "/Users/me/Desktop/daybase", kind: .repo,
                branch: "feat/rival-features", defaultBranch: "main", githubSlug: "barisparlakk/daybase",
                webURL: "https://github.com/barisparlakk/daybase", untrackedFiles: 3, hasUpstream: false,
                lastCommitAt: ago(4.2), lastActivityAt: ago(4.1),
                commitsLast14Days: [0, 2, 0, 0, 5, 3, 0, 0, 0, 4, 0, 0, 23, 28],
                branches: [
                    BranchFact(name: "feat/rival-features", lastCommitAt: ago(4.2), isCurrent: true),
                    BranchFact(name: "main", lastCommitAt: ago(30), upstream: "origin/main"),
                ]
            ),
            ProjectFact(
                id: "repo:thermground", name: "thermground", path: "/Users/me/Projects/thermground", kind: .repo,
                branch: "main", defaultBranch: "main", githubSlug: "barisparlakk/thermground",
                webURL: "https://github.com/barisparlakk/thermground", ahead: 1, hasUpstream: true,
                lastCommitAt: ago(4.4), lastActivityAt: ago(4.3),
                commitsLast14Days: [0, 0, 0, 0, 0, 0, 3, 8, 6, 0, 0, 0, 6, 1],
                branches: [BranchFact(name: "main", lastCommitAt: ago(4.4), upstream: "origin/main", ahead: 1, isCurrent: true)]
            ),
            ProjectFact(
                id: "dir:brief", name: "brief", path: "/Users/me/Desktop/brief", kind: .folder,
                lastActivityAt: ago(0.6)
            ),
            ProjectFact(
                id: "repo:barisparlakk", name: "barisparlakk", path: "/Users/me/Desktop/barisparlakk", kind: .repo,
                branch: "main", defaultBranch: "main", githubSlug: "barisparlakk/barisparlakk",
                webURL: "https://github.com/barisparlakk/barisparlakk", changedFiles: 1, hasUpstream: true,
                lastCommitAt: ago(17.8), lastActivityAt: ago(17.7),
                commitsLast14Days: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0]
            ),
            ProjectFact(
                id: "repo:Cashdiff", name: "Cashdiff", path: "/Users/me/Desktop/Cashdiff", kind: .repo,
                branch: "main", defaultBranch: "main", githubSlug: "barisparlakk/Cashdiff",
                webURL: "https://github.com/barisparlakk/Cashdiff", hasUpstream: true,
                lastCommitAt: ago(35), lastActivityAt: ago(35),
                commitsLast14Days: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0]
            ),
            ProjectFact(
                id: "repo:Notary", name: "Notary", path: "/Users/me/Desktop/Notary", kind: .repo,
                branch: "integration", defaultBranch: "main", githubSlug: "barisparlakk/Notary",
                webURL: "https://github.com/barisparlakk/Notary", changedFiles: 31, untrackedFiles: 31, behind: 76, hasUpstream: true,
                lastCommitAt: ago(35 * 24), lastActivityAt: ago(35 * 24),
                commitsLast14Days: Array(repeating: 0, count: 14),
                branches: [
                    BranchFact(name: "integration", lastCommitAt: ago(35 * 24), upstream: "origin/integration", behind: 76, isCurrent: true),
                    BranchFact(name: "feat/v2-pda", lastCommitAt: ago(41 * 24), isStale: true),
                ]
            ),
            ProjectFact(
                id: "repo:parsel-seg", name: "parsel-seg", path: "/Users/me/dev/parsel-seg", kind: .repo,
                branch: "main", defaultBranch: "main", githubSlug: "barisparlakk/parsel-seg",
                webURL: "https://github.com/barisparlakk/parsel-seg", hasUpstream: true,
                lastCommitAt: ago(44), lastActivityAt: ago(44),
                commitsLast14Days: [0, 0, 3, 0, 0, 1, 0, 1, 0, 2, 0, 1, 0, 0]
            ),
        ]

        facts.sessions = [
            SessionFact(
                sessionID: "490dd704-1b2c", projectID: "repo:daybase", cwd: "/Users/me/Desktop/daybase",
                title: "Rival features with subagents", branch: "feat/rival-features",
                startedAt: ago(12.5), endedAt: ago(4.1), promptCount: 3,
                prompts: ["Look for what's missing in our app that the biggest rivals have", "Add some other features too, use subagents", "stop"],
                filesEdited: ["src/db/schema/ai.ts", "src/db/schema/body.ts", "src/app/today/actions.ts", "src/app/settings/measurements.ts", "src/lib/fasting.ts"],
                toolCounts: ["Bash": 41, "Edit": 18, "Write": 9, "Agent": 6],
                actions: ["Commit: feat(db): add body measurements", "Commit: feat(db): add intermittent fasts", "Run the test suite"],
                linesAdded: 4120, linesRemoved: 88, entrypoint: "claude-desktop"
            ),
            SessionFact(
                sessionID: "632cddc7-9e8f", projectID: "repo:thermground", cwd: "/Users/me/Projects/thermground",
                title: "MLX adapter for Qwen3-VL", branch: "main",
                startedAt: ago(12.8), endedAt: ago(4.3), promptCount: 4,
                prompts: ["Add the MLX VLM adapter", "I'm approving it, do it", "Run the eval on val-mini", "continue"],
                filesEdited: ["src/thermground/models/mlx_vlm.py", "src/thermground/models/registry.py", "tests/test_models.py", "configs/qwen3_vl_2b.yaml"],
                toolCounts: ["Bash": 22, "Edit": 7, "Write": 3],
                actions: ["Add mlx extra, lock, install, verify import", "Lint and run the test suite including model tests"],
                linesAdded: 412, linesRemoved: 19, entrypoint: "claude-desktop"
            ),
            SessionFact(
                sessionID: "e215a012-4f6d", projectID: "dir:brief", cwd: "/Users/me/Desktop/brief",
                title: "Morning macOS briefing app", startedAt: ago(4.0), endedAt: ago(0.6), promptCount: 6,
                prompts: ["Build a personal macOS app called Morning", "Approved, start (a)", "Start (c)"],
                filesEdited: ["Packages/MorningKit/Sources/MorningKit/Generator/BriefingGenerator.swift", "App/DesignSystem/Tokens.swift", "project.yml"],
                toolCounts: ["Bash": 64, "Write": 31, "Edit": 6],
                actions: ["Build and run all tests", "Generate a real briefing with the subscription"],
                entrypoint: "claude-desktop"
            ),
            SessionFact(
                sessionID: "b563fcbe-3a1d", projectID: "repo:barisparlakk", cwd: "/Users/me/Desktop/barisparlakk",
                title: "Profile README refresh", startedAt: ago(18.1), endedAt: ago(17.7), promptCount: 3,
                prompts: ["Check barisparlak.com and update the README based on my new website", "Commit and push"],
                filesEdited: ["README.md", "scripts/build_assets.py"],
                toolCounts: ["Bash": 12, "Edit": 4],
                actions: ["Commit: Match profile README to barisparlak.com", "Push to remote"],
                entrypoint: "claude-desktop"
            ),
        ]

        let daybaseCommits: [(String, String, Double, Int, Int)] = [
            ("e58bcc4c6c11", "feat(today): add queries and actions to start and stop fasts", 4.2, 196, 0),
            ("31f934f82990", "feat(today): add the askCoach action with today's context", 4.25, 150, 0),
            ("87bc5dab5012", "feat(settings): validate Health import payloads from Shortcuts", 4.3, 172, 0),
            ("c87270e5aa31", "feat(settings): leave days out of the measured TDEE", 4.35, 175, 2),
            ("0f0fa0206d77", "feat(db): add intermittent fasts", 4.6, 2932, 0),
            ("0498622c0e19", "feat(db): add body measurements", 4.7, 2577, 0),
        ]
        facts.commits = daybaseCommits.map { hash, subject, hours, plus, minus in
            CommitFact(hash: hash, projectID: "repo:daybase", subject: subject, author: "Barış Parlak", authoredAt: ago(hours), branch: "feat/rival-features", files: ["src/app/today/actions.ts", "src/lib/fasting.ts"], insertions: plus, deletions: minus)
        } + [
            CommitFact(hash: "f5190b17482a", projectID: "repo:thermground", subject: "Confirm Qwen3-VL box format and raise point token limit", author: "Barış Parlak", authoredAt: ago(4.4), branch: "main", files: ["src/thermground/models/mlx_vlm.py", "configs/qwen3_vl_2b.yaml"], insertions: 4, deletions: 4),
            CommitFact(hash: "f64b43b0a1c2", projectID: "repo:thermground", subject: "Add MLX adapter tests", author: "Barış Parlak", authoredAt: ago(12.3), branch: "main", files: ["tests/test_models.py"], insertions: 88),
            CommitFact(hash: "35fe84143c9d", projectID: "repo:thermground", subject: "Add MLX VLM model adapter", author: "Barış Parlak", authoredAt: ago(12.35), branch: "main", files: ["src/thermground/models/mlx_vlm.py"], insertions: 45),
            CommitFact(hash: "6172627d2811", projectID: "repo:barisparlakk", subject: "Match profile README to barisparlak.com", author: "Barış Parlak", authoredAt: ago(17.8), branch: "main", files: ["README.md", "assets/header.svg", "assets/stack.svg"], insertions: 604, deletions: 603),
        ]

        facts.events = [
            EventFact(id: "event:allday-eval", title: "Thermground eval week", start: today(0), end: today(23, 59), isAllDay: true, calendar: "Projects", colorHex: "#8E6CEF"),
            EventFact(id: "event:standup", title: "Team standup", start: today(9, 30), end: today(9, 45), calendar: "Work", colorHex: "#3B82F6", url: "https://meet.google.com/abc-defg-hij", attendeeCount: 6),
            EventFact(id: "event:focus", title: "Focus block — daybase", start: today(10, 0), end: today(12, 0), calendar: "Personal", colorHex: "#F59E0B"),
            EventFact(id: "event:review", title: "Design review: Morning", start: today(14, 0), end: today(14, 45), calendar: "Work", colorHex: "#3B82F6", location: "Studio 2", attendeeCount: 4),
            EventFact(id: "event:gym", title: "Gym", start: today(18, 30), end: today(19, 30), calendar: "Personal", colorHex: "#10B981"),
        ]

        facts.reminders = [
            ReminderFact(id: "reminder:invoice", title: "Send the Cashdiff invoice", due: ago(20), priority: 1, list: "Work", isOverdue: true),
            ReminderFact(id: "reminder:domain", title: "Renew barisparlak.com", due: today(12), priority: 5, list: "Personal"),
            ReminderFact(id: "reminder:call", title: "Call the bank about the card", priority: 1, list: "Personal"),
        ]

        facts.github = GitHubFacts(
            login: "barisparlakk",
            authoredPRs: [
                PullRequestFact(number: 42, title: "Rival features: fasting, measurements, coach limits", url: "https://github.com/barisparlakk/daybase/pull/42", repo: "barisparlakk/daybase", projectID: "repo:daybase", author: "barisparlakk", createdAt: ago(4), updatedAt: ago(3.9), headRef: "feat/rival-features", reviewDecision: "REVIEW_REQUIRED", checks: .failure),
            ],
            reviewRequests: [
                PullRequestFact(number: 18, title: "Mobile nav: fix overlap with the footer", url: "https://github.com/fylexcon/ieeeinu/pull/18", repo: "fylexcon/ieeeinu", author: "fylexcon", createdAt: ago(50), updatedAt: ago(26)),
            ],
            assignedIssues: [
                IssueFact(number: 7, title: "Landing page CLS on slow connections", url: "https://github.com/barisparlakk/Cashdiff/issues/7", repo: "barisparlakk/Cashdiff", projectID: "repo:Cashdiff", updatedAt: ago(30), labels: ["bug", "web"]),
            ]
        )

        facts.notes = [
            NoteFact(projectID: "repo:daybase", file: "TODO.md", path: "/Users/me/Desktop/daybase/TODO.md", openItems: ["Wire fasting widget into Today", "Coach chat rate limit UI", "Health import onboarding copy"], modifiedAt: ago(30)),
            NoteFact(projectID: "repo:thermground", file: "NOTES.md", path: "/Users/me/Projects/thermground/NOTES.md", openItems: [], excerpt: "Qwen3-VL-2B: boxes are [x1,y1,x2,y2] in 0–1000 space. val-mini baseline mAP 0.41.", modifiedAt: ago(5)),
        ]

        facts.attention = AttentionRules.derive(from: facts, now: now, staleDays: 14)
        return facts
    }

    // MARK: - Model output

    public static let generated = GeneratedBriefing(
        headline: "Fix the failing checks on daybase #42 and land the rival features",
        focus: .init(
            projectID: "repo:daybase",
            reason: "Overnight, subagents landed 28 commits on feat/rival-features and opened #42, but its checks are failing and three new files are still untracked. Finishing this now turns yesterday's momentum into a mergeable branch.",
            confidence: .high,
            tasks: [
                .init(id: "t1", title: "Fix the failing checks on #42", detail: "Start with the fasting actions — they're the newest code on the branch.", estimateMinutes: 45, refs: ["pr:barisparlakk/daybase#42", "commit:e58bcc4c6c"]),
                .init(id: "t2", title: "Commit or ignore the 3 untracked files", detail: "They sit next to the new settings code; decide before the merge.", estimateMinutes: 10, refs: ["attn:dirty:repo:daybase"]),
                .init(id: "t3", title: "Wire the fasting widget into Today", detail: "The first open item in TODO.md and the last piece the actions need.", estimateMinutes: 60, refs: ["note:daybase/TODO.md"]),
            ]
        ),
        sections: [
            .init(kind: .overnight, title: "Overnight", items: [
                .init(title: "daybase gained fasting, body measurements and coach limits", detail: "Six subagent branches merged into feat/rival-features; PR #42 opened.", priority: .high, projectID: "repo:daybase", refs: ["session:490dd704", "commit:0f0fa0206d", "commit:0498622c0e"]),
                .init(title: "thermground can run Qwen3-VL through MLX", detail: "Adapter, configs and tests are in; box format confirmed. One commit isn't pushed.", priority: .medium, projectID: "repo:thermground", refs: ["session:632cddc7", "commit:f5190b1748"]),
                .init(title: "Morning's collectors, generator and CLI work end to end", detail: "First real briefings generated on the subscription.", priority: .medium, projectID: "dir:brief", refs: ["session:e215a012"]),
                .init(title: "GitHub profile README now matches barisparlak.com", priority: .low, projectID: "repo:barisparlakk", refs: ["commit:6172627d28"]),
            ]),
            .init(kind: .agenda, title: "Today", summary: "Standup at 09:30, then a two-hour focus block that fits the #42 fix. The design review at 14:00 is the only other fixed point.", items: [
                .init(title: "Send the Cashdiff invoice — overdue since yesterday", priority: .high, refs: ["reminder:invoice"], estimateMinutes: 10),
                .init(title: "Prep two screenshots of Morning for the 14:00 review", priority: .medium, refs: ["event:review"], estimateMinutes: 15),
            ]),
            .init(kind: .attention, title: "Needs attention", items: [
                .init(title: "Review fylexcon's mobile nav fix", detail: "Waiting on you for two days; it's a small diff.", priority: .high, refs: ["attn:review:fylexcon/ieeeinu#18"], estimateMinutes: 15),
                .init(title: "Push thermground's last commit", detail: "main is one ahead of origin.", priority: .medium, projectID: "repo:thermground", refs: ["attn:unpushed:repo:thermground/main"], estimateMinutes: 5),
                .init(title: "Decide what to do with Notary's integration branch", detail: "62 uncommitted files, 76 commits behind, and feat/v2-pda is stale. Stash, pull, then delete the old branch.", priority: .medium, projectID: "repo:Notary", refs: ["attn:dirty:repo:Notary", "attn:behind:repo:Notary", "attn:stale:repo:Notary"], estimateMinutes: 30),
            ]),
        ],
        nextTasks: [
            .init(title: "Fix the landing page layout shift", projectID: "repo:Cashdiff", priority: .medium, estimateMinutes: 40, reason: "Assigned issue #7 is the only thing blocking the launch tweet."),
            .init(title: "Commit the README tweak", projectID: "repo:barisparlakk", priority: .low, estimateMinutes: 5, reason: "One modified file left after yesterday's push."),
        ]
    )

    private static func at(_ hour: Int, _ minute: Int, on day: Date, _ calendar: Calendar) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}
