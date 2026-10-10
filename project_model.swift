import Foundation

// ─── Project model ───────────────────────────────────────────────────────────
// Snapshots are local. GitHub's GraphQL API has no item history, so the store
// diffs two snapshots to build the activity feed.

struct ProjectRef: Codable, Hashable {
    let owner: String
    let number: Int
    var key: String

    init(owner: String, number: Int) {
        self.owner = owner
        self.number = number
        self.key = "\(owner)/\(number)"
    }
}

enum OwnerKind: String, Codable { case user, org }

struct ProjectSummary: Codable, Hashable {
    let ref: ProjectRef
    let nodeId: String
    let title: String
    let url: String
    let closed: Bool
    let itemCount: Int
    let ownerKind: OwnerKind
}

enum StatusCategory: String, Codable, CaseIterable {
    case todo, progress, review, blocked, done

    var label: String {
        switch self {
        case .todo: return "Todo"
        case .progress: return "In progress"
        case .review: return "In review"
        case .blocked: return "Blocked"
        case .done: return "Done"
        }
    }
}

struct StatusOption: Codable, Hashable {
    let id: String
    let name: String
    let color: String

    // Name match. Custom names still get a color from `color`.
    var category: StatusCategory {
        let n = name.lowercased()
        if n.contains("done") || n.contains("closed") || n.contains("shipped") { return .done }
        if n.contains("block") { return .blocked }
        if n.contains("review") { return .review }
        if n.contains("progress") || n.contains("doing") { return .progress }
        return .todo
    }
}

enum ItemKind: String, Codable { case issue, pullRequest, draft }

struct CommentRef: Codable, Hashable {
    let id: String
    let author: String?
    let createdAt: Date
    let url: String
}

struct ProjectItem: Codable, Hashable {
    let id: String
    let contentId: String?
    let kind: ItemKind
    let title: String
    let url: String?
    let repo: String?
    let number: Int?
    let state: String?
    let statusOptionId: String?
    let fields: [String: String]
    let assignees: [String]
    let labels: [String]
    let author: String?
    let updatedAt: Date
    let commentCount: Int
    let lastComment: CommentRef?
    var mentionsMe: Bool

    func isMine(_ login: String?) -> Bool {
        guard let me = login?.lowercased(), !me.isEmpty else { return false }
        if author?.lowercased() == me { return true }
        return assignees.contains { $0.lowercased() == me }
    }

    var isClosedState: Bool {
        let s = (state ?? "").uppercased()
        return s == "CLOSED" || s == "MERGED"
    }
}

struct ProjectSnapshot: Codable {
    let summary: ProjectSummary
    let statusFieldId: String?
    let statusOptions: [StatusOption]
    let items: [ProjectItem]
    let fetchedAt: Date

    var counts: [StatusCategory: Int] {
        var c: [StatusCategory: Int] = [:]
        for item in items {
            let cat = statusOptions.first { $0.id == item.statusOptionId }?.category ?? .todo
            c[cat, default: 0] += 1
        }
        return c
    }

    func option(_ id: String?) -> StatusOption? { statusOptions.first { $0.id == id } }
    func statusName(_ id: String?) -> String? { option(id)?.name }
}

enum ItemChange: Codable, Hashable {
    case added, removed, closed, reopened, mention
    case status(from: String?, to: String?)
    case field(name: String, from: String?, to: String?)
    case assigned(String), unassigned(String)
    case comments(new: Int, last: CommentRef)

    var text: String {
        switch self {
        case .added: return "Added"
        case .removed: return "Removed"
        case .closed: return "Closed"
        case .reopened: return "Reopened"
        case .mention: return "Mentioned you"
        case .status(let from, let to): return "Status: \(from ?? "none") → \(to ?? "none")"
        case .field(let name, let from, let to): return "\(name): \(from ?? "none") → \(to ?? "none")"
        case .assigned(let u): return "Assigned \(u)"
        case .unassigned(let u): return "Unassigned \(u)"
        case .comments(let n, let last):
            let who = last.author ?? "someone"
            return n == 1 ? "New comment by \(who)" : "\(n) new comments"
        }
    }

    // Comment author, when the change itself names one. Used to skip the user's own comments.
    var commentAuthor: String? {
        if case .comments(_, let last) = self { return last.author }
        return nil
    }
}

struct ActivityEntry: Codable, Hashable {
    let id: String
    var projectKey: String
    var itemId: String
    let change: ItemChange
    let actor: String?
    let text: String
    let url: String
    let at: Date
    var unread: Bool

    static func make(projectKey: String, itemId: String, change: ItemChange, actor: String?, url: String, at: Date) -> ActivityEntry {
        let id = "\(projectKey)|\(itemId)|\(change.text)|\(Int(at.timeIntervalSince1970))"
        return ActivityEntry(id: id, projectKey: projectKey, itemId: itemId, change: change,
                             actor: actor, text: change.text, url: url, at: at, unread: true)
    }
}
