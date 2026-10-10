import Foundation

// ─── GitHub Projects (v2) via `gh api graphql` ───────────────────────────────

enum ProjectAPIError: Error, Equatable {
    case missingScope(String), notFound, gh(String)

    var message: String {
        switch self {
        case .missingScope(let s): return "Cat Eye needs the \(s) scope."
        case .notFound: return "Project not found."
        case .gh(let s): return s
        }
    }
}

final class ProjectAPI {
    func viewerOwners() -> Result<[(login: String, kind: OwnerKind)], ProjectAPIError> {
        let q = "query { viewer { login organizations(first: 100) { nodes { login } } } }"
        return graphql(q).flatMap { data in
            guard let viewer = data["viewer"] as? [String: Any], let login = viewer["login"] as? String else {
                return .failure(.gh("Could not read the GitHub user"))
            }
            var out: [(String, OwnerKind)] = [(login, .user)]
            let orgs = ((viewer["organizations"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
            for o in orgs {
                if let l = o["login"] as? String { out.append((l, .org)) }
            }
            return .success(out)
        }
    }

    func projects(owner: String, kind: OwnerKind) -> Result<[ProjectSummary], ProjectAPIError> {
        let root = kind == .org ? "organization" : "user"
        let q = """
        query($login: String!) {
          \(root)(login: $login) {
            projectsV2(first: 100) {
              nodes { id number title url closed items { totalCount } }
            }
          }
        }
        """
        return graphql(q, ["login": owner]).flatMap { data in
            guard let node = data[root] as? [String: Any] else { return .failure(.notFound) }
            let nodes = ((node["projectsV2"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
            let list = nodes.compactMap { n -> ProjectSummary? in
                guard let id = n["id"] as? String, let number = n["number"] as? Int,
                      let title = n["title"] as? String else { return nil }
                let count = ((n["items"] as? [String: Any])?["totalCount"] as? Int) ?? 0
                return ProjectSummary(ref: ProjectRef(owner: owner, number: number), nodeId: id, title: title,
                                      url: n["url"] as? String ?? "https://github.com/\(kind == .org ? "orgs/" : "")\(owner)/projects/\(number)",
                                      closed: n["closed"] as? Bool ?? false, itemCount: count, ownerKind: kind)
            }
            return .success(list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
        }
    }

    // Pages of 100 until `limit` items or the list ends.
    func snapshot(_ ref: ProjectRef, kind: OwnerKind, limit: Int) -> Result<ProjectSnapshot, ProjectAPIError> {
        let root = kind == .org ? "organization" : "user"
        let q = """
        query($login: String!, $number: Int!) {
          \(root)(login: $login) {
            projectV2(number: $number) { id number title url closed items { totalCount } }
          }
        }
        """
        return graphql(q, ["login": ref.owner, "number": ref.number]).flatMap { data in
            guard let owner = data[root] as? [String: Any], let n = owner["projectV2"] as? [String: Any],
                  let id = n["id"] as? String else { return .failure(.notFound) }
            let count = ((n["items"] as? [String: Any])?["totalCount"] as? Int) ?? 0
            let summary = ProjectSummary(ref: ref, nodeId: id, title: n["title"] as? String ?? "Project",
                                         url: n["url"] as? String ?? "", closed: n["closed"] as? Bool ?? false,
                                         itemCount: count, ownerKind: kind)
            return items(nodeId: id, limit: max(1, limit)).map { page in
                ProjectSnapshot(summary: summary, statusFieldId: page.fieldId, statusOptions: page.options,
                                items: page.items, fetchedAt: Date())
            }
        }
    }

    func timeline(contentId: String, last: Int) -> Result<[ActivityEntry], ProjectAPIError> {
        let n = min(max(last, 1), 50)
        let q = """
        query($id: ID!) {
          node(id: $id) {
            ... on Issue { url timelineItems(last: \(n)) { nodes { \(timelineFields) } } }
            ... on PullRequest { url timelineItems(last: \(n)) { nodes { \(timelineFields) } } }
          }
        }
        """
        return graphql(q, ["id": contentId]).map { data in
            let node = data["node"] as? [String: Any] ?? [:]
            let url = node["url"] as? String ?? ""
            let nodes = ((node["timelineItems"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
            return nodes.compactMap { parseTimeline($0, url: url) }
        }
    }

    func setStatus(projectId: String, itemId: String, fieldId: String, optionId: String) -> Result<Void, ProjectAPIError> {
        let q = """
        mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
          updateProjectV2ItemFieldValue(input: {
            projectId: $projectId, itemId: $itemId, fieldId: $fieldId,
            value: { singleSelectOptionId: $optionId }
          }) { projectV2Item { id } }
        }
        """
        return graphql(q, ["projectId": projectId, "itemId": itemId, "fieldId": fieldId, "optionId": optionId]).map { _ in () }
    }

    func comment(contentId: String, body: String) -> Result<Void, ProjectAPIError> {
        let q = """
        mutation($id: ID!, $body: String!) {
          addComment(input: { subjectId: $id, body: $body }) { commentEdge { node { id } } }
        }
        """
        return graphql(q, ["id": contentId, "body": body]).map { _ in () }
    }

    // Classic OAuth scopes from `gh api -i user`. Empty when the header is absent
    // (fine-grained tokens). The caller then trusts the GraphQL error instead.
    func scopes() -> Set<String> {
        guard let r = try? ghRun(["api", "-i", "user"]), !r.out.isEmpty || !r.err.isEmpty else { return [] }
        let text = String(decoding: r.out, as: UTF8.self)
        for line in text.split(separator: "\n") {
            let s = String(line)
            guard s.lowercased().hasPrefix("x-oauth-scopes:") else { continue }
            let value = s.split(separator: ":", maxSplits: 1).dropFirst().joined()
            return Set(value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
        }
        return []
    }

    // MARK: GraphQL

    private func graphql(_ query: String, _ variables: [String: Any] = [:]) -> Result<[String: Any], ProjectAPIError> {
        guard FileManager.default.isExecutableFile(atPath: GH) else {
            return .failure(.gh("GitHub CLI not found at \(GH)"))
        }
        let body: [String: Any] = ["query": query, "variables": variables]
        guard let input = try? JSONSerialization.data(withJSONObject: body) else {
            return .failure(.gh("Could not encode the query"))
        }
        guard let res = try? ghRun(["api", "graphql", "--input", "-"], input: input) else {
            return .failure(.gh("gh failed to start"))
        }
        guard let obj = try? JSONSerialization.jsonObject(with: res.out) as? [String: Any] else {
            let msg = res.err.isEmpty ? "Empty GraphQL response" : String(res.err.prefix(160))
            return .failure(classify(msg))
        }
        if let errors = obj["errors"] as? [[String: Any]], let msg = errors.first?["message"] as? String {
            return .failure(classify(msg))
        }
        guard let data = obj["data"] as? [String: Any] else {
            return .failure(.gh(String((res.err.isEmpty ? "GraphQL failed" : res.err).prefix(160))))
        }
        return .success(data)
    }

    private func classify(_ msg: String) -> ProjectAPIError {
        let low = msg.lowercased()
        if low.contains("scope") || low.contains("resource not accessible") || low.contains("insufficient") {
            return .missingScope("project")
        }
        if low.contains("could not resolve") || low.contains("not found") { return .notFound }
        return .gh(String(msg.prefix(160)))
    }

    private struct ItemPage {
        var fieldId: String?
        var options: [StatusOption]
        var items: [ProjectItem]
    }

    private func items(nodeId: String, limit: Int) -> Result<ItemPage, ProjectAPIError> {
        let q = """
        query($id: ID!, $after: String) {
          node(id: $id) {
            ... on ProjectV2 {
              field(name: "Status") {
                ... on ProjectV2SingleSelectField { id options { id name color } }
              }
              items(first: 100, after: $after) {
                pageInfo { hasNextPage endCursor }
                nodes {
                  id updatedAt
                  content { \(contentFields) }
                  fieldValues(first: 20) { nodes { \(fieldValueFields) } }
                }
              }
            }
          }
        }
        """
        var after: String? = nil
        var page = ItemPage(fieldId: nil, options: [], items: [])
        var guardPages = 0
        while page.items.count < limit && guardPages < 8 {
            guardPages += 1
            var vars: [String: Any] = ["id": nodeId]
            if let after = after { vars["after"] = after }
            switch graphql(q, vars) {
            case .failure(let e): return .failure(e)
            case .success(let data):
                guard let node = data["node"] as? [String: Any] else { return .failure(.notFound) }
                if page.options.isEmpty, let field = node["field"] as? [String: Any] {
                    page.fieldId = field["id"] as? String
                    let opts = field["options"] as? [[String: Any]] ?? []
                    page.options = opts.compactMap { o in
                        guard let id = o["id"] as? String, let name = o["name"] as? String else { return nil }
                        return StatusOption(id: id, name: name, color: (o["color"] as? String) ?? "GRAY")
                    }
                }
                let items = node["items"] as? [String: Any] ?? [:]
                let nodes = items["nodes"] as? [[String: Any]] ?? []
                for n in nodes where page.items.count < limit {
                    page.items.append(parseItem(n, options: page.options))
                }
                let info = items["pageInfo"] as? [String: Any] ?? [:]
                if info["hasNextPage"] as? Bool != true { return .success(page) }
                after = info["endCursor"] as? String
                if after == nil { return .success(page) }
            }
        }
        return .success(page)
    }

    private func parseItem(_ n: [String: Any], options: [StatusOption]) -> ProjectItem {
        let content = n["content"] as? [String: Any] ?? [:]
        let type = (content["__typename"] as? String) ?? ""
        let kind: ItemKind = type == "PullRequest" ? .pullRequest : type == "DraftIssue" ? .draft : .issue
        var fields: [String: String] = [:]
        var statusId: String?
        let values = ((n["fieldValues"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
        for v in values {
            let name = (v["field"] as? [String: Any])?["name"] as? String ?? ""
            guard !name.isEmpty else { continue }
            if let optionId = v["optionId"] as? String, name == "Status" {
                statusId = optionId
                continue
            }
            let text = (v["name"] as? String) ?? (v["text"] as? String) ?? (v["title"] as? String)
                ?? (v["date"] as? String) ?? (v["number"] as? NSNumber).map { $0.stringValue }
            if let text = text, !text.isEmpty { fields[name] = text }
        }
        let comments = content["comments"] as? [String: Any]
        let commentNodes = (comments?["nodes"] as? [[String: Any]]) ?? []
        let last = commentNodes.first.flatMap { parseComment($0) }
        let me = cachedLogin
        let body = (commentNodes.first?["body"] as? String) ?? ""
        let mentions = me.map { body.localizedCaseInsensitiveContains("@\($0)") } ?? false
        let assignees = (((content["assignees"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []).compactMap { $0["login"] as? String }
        let labels = (((content["labels"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
        return ProjectItem(id: n["id"] as? String ?? UUID().uuidString,
                           contentId: content["id"] as? String,
                           kind: kind,
                           title: content["title"] as? String ?? "Private item",
                           url: content["url"] as? String,
                           repo: (content["repository"] as? [String: Any])?["nameWithOwner"] as? String,
                           number: content["number"] as? Int,
                           state: content["state"] as? String,
                           statusOptionId: statusId,
                           fields: fields,
                           assignees: assignees,
                           labels: labels,
                           author: (content["author"] as? [String: Any])?["login"] as? String,
                           updatedAt: parseISO(n["updatedAt"] as? String) ?? Date(),
                           commentCount: comments?["totalCount"] as? Int ?? 0,
                           lastComment: last,
                           mentionsMe: mentions)
    }

    private func parseComment(_ n: [String: Any]) -> CommentRef? {
        guard let id = n["id"] as? String else { return nil }
        return CommentRef(id: id, author: (n["author"] as? [String: Any])?["login"] as? String,
                          createdAt: parseISO(n["createdAt"] as? String) ?? Date(),
                          url: n["url"] as? String ?? "")
    }

    private func parseTimeline(_ n: [String: Any], url: String) -> ActivityEntry? {
        let type = n["__typename"] as? String ?? ""
        let at = parseISO(n["createdAt"] as? String) ?? Date()
        let actor = (n["actor"] as? [String: Any])?["login"] as? String ?? (n["author"] as? [String: Any])?["login"] as? String
        let eventURL = n["url"] as? String ?? url
        let change: ItemChange
        switch type {
        case "IssueComment", "PullRequestReview", "PullRequestReviewComment":
            guard let c = parseComment(n) else { return nil }
            change = .comments(new: 1, last: c)
        case "AssignedEvent":
            let who = (n["assignee"] as? [String: Any])?["login"] as? String ?? "someone"
            change = .assigned(who)
        case "UnassignedEvent":
            let who = (n["assignee"] as? [String: Any])?["login"] as? String ?? "someone"
            change = .unassigned(who)
        case "ClosedEvent", "MergedEvent":
            change = .closed
        case "ReopenedEvent":
            change = .reopened
        default:
            return nil
        }
        return ActivityEntry.make(projectKey: "", itemId: "", change: change, actor: actor, url: eventURL, at: at)
    }

    private var cachedLogin: String? {
        if let s = _viewerLogin { return s }
        _viewerLogin = getGHUser()
        return _viewerLogin
    }
}

private var _viewerLogin: String?

private let contentFields = """
__typename
... on Issue {
  id title url number state
  author { login }
  assignees(first: 10) { nodes { login } }
  labels(first: 8) { nodes { name } }
  comments(last: 1) { totalCount nodes { id author { login } createdAt url body } }
  repository { nameWithOwner }
}
... on PullRequest {
  id title url number state
  author { login }
  assignees(first: 10) { nodes { login } }
  labels(first: 8) { nodes { name } }
  comments(last: 1) { totalCount nodes { id author { login } createdAt url body } }
  repository { nameWithOwner }
}
... on DraftIssue { id title assignees(first: 10) { nodes { login } } }
"""

private let fieldValueFields = """
... on ProjectV2ItemFieldSingleSelectValue { name optionId field { ... on ProjectV2FieldCommon { name } } }
... on ProjectV2ItemFieldTextValue { text field { ... on ProjectV2FieldCommon { name } } }
... on ProjectV2ItemFieldNumberValue { number field { ... on ProjectV2FieldCommon { name } } }
... on ProjectV2ItemFieldDateValue { date field { ... on ProjectV2FieldCommon { name } } }
... on ProjectV2ItemFieldIterationValue { title field { ... on ProjectV2FieldCommon { name } } }
"""

private let timelineFields = """
__typename
... on IssueComment { id author { login } createdAt url body }
... on PullRequestReview { id author { login } createdAt url body }
... on PullRequestReviewComment { id author { login } createdAt url body }
... on AssignedEvent { id actor { login } createdAt assignee { ... on User { login } } }
... on UnassignedEvent { id actor { login } createdAt assignee { ... on User { login } } }
... on ClosedEvent { id actor { login } createdAt }
... on ReopenedEvent { id actor { login } createdAt }
... on MergedEvent { id actor { login } createdAt }
"""
