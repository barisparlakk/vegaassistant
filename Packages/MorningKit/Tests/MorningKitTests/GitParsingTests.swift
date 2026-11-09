import Foundation
import Testing
@testable import MorningKit

@Suite("Git output parsing")
struct GitParsingTests {
    @Test func statusWithTracking() {
        let status = GitParsing.parseStatus("""
        ## main...origin/main [ahead 2, behind 1]
         M Sources/App.swift
        A  Sources/New.swift
        ?? notes.txt
        ?? scratch/
        """)
        #expect(status.branch == "main")
        #expect(status.upstream == "origin/main")
        #expect(status.ahead == 2)
        #expect(status.behind == 1)
        #expect(status.changed == 2)
        #expect(status.untracked == 2)
    }

    @Test func statusWithoutUpstreamOrCommits() {
        #expect(GitParsing.parseStatus("## feature/x").branch == "feature/x")
        #expect(GitParsing.parseStatus("## feature/x").upstream == nil)
        #expect(GitParsing.parseStatus("## No commits yet on main\n?? a").branch == "main")
        #expect(GitParsing.parseStatus("## HEAD (no branch)").branch == nil)
    }

    @Test func track() {
        #expect(GitParsing.parseTrack("ahead 3").ahead == 3)
        #expect(GitParsing.parseTrack("behind 4").behind == 4)
        #expect(GitParsing.parseTrack("gone").gone)
        #expect(!GitParsing.parseTrack("").gone)
    }

    @Test func refs() {
        let output = [
            "main\u{1f}1762600000\u{1f}origin/main\u{1f}\u{1f}*",
            "old\u{1f}1700000000\u{1f}origin/old\u{1f}gone\u{1f} ",
            "wip\u{1f}1762500000\u{1f}\u{1f}\u{1f} ",
        ].joined(separator: "\n")
        let refs = GitParsing.parseRefs(output)
        #expect(refs.count == 3)
        #expect(refs[0].isCurrent)
        #expect(refs[0].upstream == "origin/main")
        #expect(refs[1].upstreamGone)
        #expect(refs[2].upstream == nil)
        #expect(refs[2].lastCommitAt == Date(timeIntervalSince1970: 1_762_500_000))
    }

    @Test func log() {
        let output = "\u{1e}abcdef1234567890\u{1f}Barış\u{1f}1762600000\u{1f}refs/heads/main\u{1f}Fix the thing\n\n3\t1\tSources/A.swift\n-\t-\tAssets/logo.png\n"
            + "\u{1e}0123456789abcdef\u{1f}Barış\u{1f}1762590000\u{1f}refs/heads/feat\u{1f}Add feature\n"
        let commits = GitParsing.parseLog(output, projectID: "repo:app")
        #expect(commits.count == 2)
        #expect(commits[0].id == "commit:abcdef1234")
        #expect(commits[0].shortHash == "abcdef1")
        #expect(commits[0].files == ["Sources/A.swift", "Assets/logo.png"])
        #expect(commits[0].insertions == 3)
        #expect(commits[0].deletions == 1)
        #expect(commits[0].branch == "main")
        #expect(commits[1].subject == "Add feature")
        #expect(commits[1].files.isEmpty)
    }

    @Test func histogramBucketsByLocalDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Istanbul"))
        let now = try #require(ISODate.parse("2026-11-09T05:00:00Z")) // 08:00 local
        let stamps = [
            try #require(ISODate.parse("2026-11-09T01:00:00Z")), // today
            try #require(ISODate.parse("2026-11-08T22:30:00Z")), // 01:30 local → today
            try #require(ISODate.parse("2026-11-08T20:00:00Z")), // 23:00 local → yesterday
            try #require(ISODate.parse("2026-10-01T12:00:00Z")), // out of range
        ]
        let buckets = GitParsing.histogram(timestamps: stamps, endingAt: now, calendar: calendar)
        #expect(buckets.count == 14)
        #expect(buckets[13] == 2)
        #expect(buckets[12] == 1)
        #expect(buckets.reduce(0, +) == 3)
    }

    @Test(arguments: [
        ("git@github.com:owner/repo.git", "owner/repo"),
        ("https://github.com/owner/repo", "owner/repo"),
        ("https://github.com/owner/repo.git", "owner/repo"),
        ("ssh://git@github.com/owner/repo.git", "owner/repo"),
    ])
    func githubSlug(remote: String, slug: String) {
        #expect(GitParsing.githubSlug(fromRemote: remote) == slug)
    }

    @Test func nonGitHubRemotes() {
        #expect(GitParsing.githubSlug(fromRemote: "git@gitlab.com:team/app.git") == nil)
        #expect(GitParsing.webURL(fromRemote: "git@gitlab.com:team/app.git") == "https://gitlab.com/team/app")
    }

    @Test func defaultBranch() {
        #expect(GitParsing.defaultBranch(originHead: "origin/develop\n", localBranches: ["develop", "main"], current: "x") == "develop")
        #expect(GitParsing.defaultBranch(originHead: nil, localBranches: ["master", "x"], current: "x") == "master")
        #expect(GitParsing.defaultBranch(originHead: nil, localBranches: ["x"], current: "x") == "x")
    }

    @Test func gitDateIsUTCWithOffset() throws {
        let date = try #require(ISODate.parse("2026-11-08T07:05:09Z"))
        #expect(GitParsing.gitDate(date) == "2026-11-08 07:05:09 +0000")
    }
}
