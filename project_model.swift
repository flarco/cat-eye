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

// GitHub's side pane uses the item's numeric id, not the issue URL. The node id
// is a msgpack array whose last value is that number, so a cached item still copies
// the right link before the next fetch stores `databaseId`.
func projectItemDatabaseId(nodeId: String, stored: String? = nil) -> String? {
    if let stored, !stored.isEmpty { return stored }
    guard nodeId.hasPrefix("PVTI_") else { return nil }
    var raw = String(nodeId.dropFirst("PVTI_".count))
    raw = raw.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    raw += String(repeating: "=", count: (4 - raw.count % 4) % 4)
    guard let data = Data(base64Encoded: raw), let first = data.first, first & 0xF0 == 0x90 else { return nil }
    let count = Int(first & 0x0F)
    var i = 1
    var last: UInt64?
    for _ in 0..<count {
        guard i < data.count else { return nil }
        let tag = data[i]
        i += 1
        if tag <= 0x7F {
            last = UInt64(tag)
        } else if tag == 0xCC, i < data.count {
            last = UInt64(data[i]); i += 1
        } else if tag == 0xCD, i + 1 < data.count {
            last = UInt64(data[i]) << 8 | UInt64(data[i + 1]); i += 2
        } else if tag == 0xCE, i + 3 < data.count {
            last = UInt64(data[i]) << 24 | UInt64(data[i + 1]) << 16 | UInt64(data[i + 2]) << 8 | UInt64(data[i + 3])
            i += 4
        } else if tag == 0xCF, i + 7 < data.count {
            var v: UInt64 = 0
            for b in data[i..<(i + 8)] { v = (v << 8) | UInt64(b) }
            last = v
            i += 8
        } else {
            return nil
        }
    }
    return last.map { String($0) }
}

func projectItemURL(projectURL: String, nodeId: String, databaseId: String?) -> String? {
    guard let id = projectItemDatabaseId(nodeId: nodeId, stored: databaseId), !projectURL.isEmpty else { return nil }
    var base = projectURL
    if let i = base.firstIndex(of: "?") { base = String(base[..<i]) }
    if let i = base.firstIndex(of: "#") { base = String(base[..<i]) }
    while base.hasSuffix("/") { base.removeLast() }
    return "\(base)/views/1?pane=issue&itemId=\(id)"
}

struct CommentRef: Codable, Hashable {
    let id: String
    let author: String?
    let createdAt: Date
    let url: String
    var body: String? = nil
}

struct ProjectItem: Codable, Hashable {
    let id: String
    let contentId: String?
    let kind: ItemKind
    let title: String
    let url: String?
    // Numeric ProjectV2Item id used in the side-pane link. Nil on snapshots fetched before it was stored.
    let databaseId: String?
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
    var body: String? = nil

    // https://github.com/users/flarco/projects/3/views/1?pane=issue&itemId=268087835
    func paneURL(projectURL: String) -> String? {
        projectItemURL(projectURL: projectURL, nodeId: id, databaseId: databaseId)
    }

    func isMine(_ login: String?) -> Bool {
        guard let me = login?.lowercased(), !me.isEmpty else { return false }
        if author?.lowercased() == me { return true }
        return assignees.contains { $0.lowercased() == me }
    }

    var isClosedState: Bool {
        let s = (state ?? "").uppercased()
        return s == "CLOSED" || s == "MERGED"
    }

    // Markdown for a coding agent: title, facts, link, description, comments (oldest first).
    func agentMarkdown(snap: ProjectSnapshot, comments: [CommentRef]) -> String {
        var facts = ["Project: \(snap.summary.ref.owner)/\(snap.summary.title)"]
        facts.append("Status: \(snap.statusName(statusOptionId) ?? "None")")
        if let repo, let number { facts.append("Issue: \(repo)#\(number)") }
        if kind == .draft { facts.append("Draft") }
        for (k, v) in fields.sorted(by: { $0.key < $1.key }) where k != "Status" && k != "Title" { facts.append("\(k): \(v)") }
        if !assignees.isEmpty { facts.append("Assignees: " + assignees.map { "@" + $0 }.joined(separator: ", ")) }
        var out = "# \(title)\n\n" + facts.joined(separator: " · ") + "\n"
        if let link = paneURL(projectURL: snap.summary.url) ?? url { out += link + "\n" }
        let text = (body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        out += "\n" + (text.isEmpty ? "_No description_" : text) + "\n\n## Comments\n"
        if comments.isEmpty { return out + "_None_\n" }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "yyyy-MM-dd"
        for c in comments.sorted(by: { $0.createdAt < $1.createdAt }) {
            let lines = (c.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
            out += "- @\(c.author ?? "ghost") (\(df.string(from: c.createdAt))): " + lines.joined(separator: "\n  ") + "\n"
        }
        return out
    }

    // Case-insensitive match on the title and the body. An empty query matches all.
    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return true }
        return title.localizedCaseInsensitiveContains(q) || (body ?? "").localizedCaseInsensitiveContains(q)
    }
}

// A single-select field of a project, such as Status, Size or Priority.
struct ProjectField: Codable, Hashable {
    let id: String
    let name: String
    let options: [StatusOption]
}

struct ProjectSnapshot: Codable {
    let summary: ProjectSummary
    let statusFieldId: String?
    let statusOptions: [StatusOption]
    let items: [ProjectItem]
    let fetchedAt: Date
    var fields: [ProjectField]? = nil

    // The number on a folded header.
    var notDoneCount: Int { items.filter { option($0.statusOptionId)?.category != .done }.count }

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
