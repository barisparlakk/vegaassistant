import Foundation

/// Open PRs I authored, PRs waiting for my review, and issues assigned to me —
/// fetched in one GraphQL call through the `gh` CLI (so it reuses gh's login).
public struct GitHubCollector: Collector {
    public let kind = CollectorKind.github

    public init() {}

    static let query = """
    query {
      viewer { login }
      authored: search(query: "is:open is:pr author:@me archived:false sort:updated-desc", type: ISSUE, first: 30) {
        nodes { ... on PullRequest {
          number title url isDraft createdAt updatedAt headRefName reviewDecision
          repository { nameWithOwner }
          commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
        } }
      }
      reviews: search(query: "is:open is:pr review-requested:@me archived:false sort:updated-desc", type: ISSUE, first: 30) {
        nodes { ... on PullRequest {
          number title url isDraft createdAt updatedAt headRefName
          author { login }
          repository { nameWithOwner }
        } }
      }
      issues: search(query: "is:open is:issue assignee:@me archived:false sort:updated-desc", type: ISSUE, first: 30) {
        nodes { ... on Issue {
          number title url updatedAt
          labels(first: 6) { nodes { name } }
          repository { nameWithOwner }
        } }
      }
    }
    """

    public func collect(_ context: CollectionContext) async throws -> CollectorOutput {
        guard let gh = context.tools.gh else { throw CollectorSkipped("GitHub CLI (gh) not installed") }

        let result = try await Shell.run(gh, ["api", "graphql", "-f", "query=\(Self.query)"], timeout: .seconds(30))
        guard result.succeeded else {
            let message = result.errorOutput
            if message.contains("gh auth login") || message.contains("not logged") {
                throw CollectorSkipped("gh is not logged in — run `gh auth login`")
            }
            throw ShellError.failed(command: "gh api graphql", status: result.status, stderr: message)
        }

        var fragment = BriefingFacts.fragment(context)
        fragment.github = try Self.parse(result.stdout)
        return CollectorOutput(facts: fragment)
    }

    static func parse(_ data: Data) throws -> GitHubFacts {
        let response = try JSONCoding.decoder.decode(Response.self, from: data)
        guard let payload = response.data else {
            let message = response.errors?.map(\.message).joined(separator: "; ") ?? "empty response"
            throw ShellError.failed(command: "gh api graphql", status: 1, stderr: message)
        }

        let authored = payload.authored.nodes.compactMap { node -> PullRequestFact? in
            guard let node else { return nil }
            let state = node.commits?.nodes.last??.commit.statusCheckRollup?.state
            return node.fact(author: payload.viewer.login, checks: checksState(state))
        }
        let reviews = payload.reviews.nodes.compactMap { node in node?.fact(author: node?.author?.login, checks: .none) }
        let issues = payload.issues.nodes.compactMap { node -> IssueFact? in
            guard let node, let number = node.number, let url = node.url, let repo = node.repository?.nameWithOwner,
                  let updatedAt = node.updatedAt
            else { return nil }
            return IssueFact(
                number: number,
                title: node.title ?? "#\(number)",
                url: url,
                repo: repo,
                updatedAt: updatedAt,
                labels: node.labels?.nodes.compactMap { $0?.name } ?? []
            )
        }
        return GitHubFacts(login: payload.viewer.login, authoredPRs: authored, reviewRequests: reviews, assignedIssues: issues)
    }

    static func checksState(_ raw: String?) -> PullRequestFact.ChecksState {
        switch raw {
        case "SUCCESS": .success
        case "FAILURE", "ERROR": .failure
        case "PENDING", "EXPECTED": .pending
        default: .none
        }
    }

    // MARK: - Response model

    private struct Response: Decodable {
        let data: Payload?
        let errors: [GraphQLError]?
    }

    private struct GraphQLError: Decodable { let message: String }

    private struct Payload: Decodable {
        let viewer: Viewer
        let authored: Connection<PullRequestNode>
        let reviews: Connection<PullRequestNode>
        let issues: Connection<IssueNode>
    }

    private struct Viewer: Decodable { let login: String }

    private struct Connection<Node: Decodable>: Decodable { let nodes: [Node?] }

    private struct Login: Decodable { let login: String }
    private struct Repository: Decodable { let nameWithOwner: String }
    private struct Label: Decodable { let name: String }

    private struct CommitNode: Decodable {
        struct Commit: Decodable {
            struct Rollup: Decodable { let state: String? }
            let statusCheckRollup: Rollup?
        }
        let commit: Commit
    }

    private struct PullRequestNode: Decodable {
        let number: Int?
        let title: String?
        let url: String?
        let isDraft: Bool?
        let createdAt: Date?
        let updatedAt: Date?
        let headRefName: String?
        let reviewDecision: String?
        let author: Login?
        let repository: Repository?
        let commits: Connection<CommitNode>?

        func fact(author: String?, checks: PullRequestFact.ChecksState) -> PullRequestFact? {
            guard let number, let url, let repo = repository?.nameWithOwner, let updatedAt else { return nil }
            return PullRequestFact(
                number: number,
                title: title ?? "#\(number)",
                url: url,
                repo: repo,
                author: author,
                isDraft: isDraft ?? false,
                createdAt: createdAt,
                updatedAt: updatedAt,
                headRef: headRefName,
                reviewDecision: reviewDecision,
                checks: checks
            )
        }
    }

    private struct IssueNode: Decodable {
        let number: Int?
        let title: String?
        let url: String?
        let updatedAt: Date?
        let labels: Connection<Label>?
        let repository: Repository?
    }
}
