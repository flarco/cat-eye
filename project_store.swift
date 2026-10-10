import Foundation

// Last snapshots, the activity feed, and unread state. Fetches run off the main
// queue. The first snapshot of a project creates no activity, so launch is quiet.

final class ProjectStore {
    static let changed = Notification.Name("ProjectStoreChanged")

    private(set) var snapshots: [String: ProjectSnapshot] = [:]
    private(set) var refreshing: Set<String> = []
    private(set) var lastError: String?
    private(set) var tracked: [ProjectSummary] = []
    private(set) var liveKeys: Set<String> = []

    private let api: ProjectAPI
    private let notifier: ProjectNotifier
    private let statePath: String
    private let activityPath: String
    private let q = DispatchQueue(label: "com.flarco.cat-eye.projects", qos: .utility)
    private var timer: Timer?
    private var readActivity = Set<String>()
    private var readItems = Set<String>()
    private var activityCache: [ActivityEntry] = []
    private var timelineCache: [String: (stamp: String, entries: [ActivityEntry])] = [:]
    private var timelineFlight = Set<String>()
    private var issueIndex: [String: Set<String>] = [:]   // "repo#number" lowercased → project keys
    private var suppressNotify = Set<String>()
    var relayIsLive: () -> Bool = { false }
    var onChange: (() -> Void)?

    init(api: ProjectAPI, notifier: ProjectNotifier, statePath: String, activityPath: String) {
        self.api = api
        self.notifier = notifier
        self.statePath = statePath
        self.activityPath = activityPath
        load()
    }

    func track(_ projects: [ProjectSummary], live: Set<String>) {
        tracked = projects
        liveKeys = live
        restartTimer()
        let keys = projects.map { $0.ref.key }
        refresh(keys, force: false) { _ in }
    }

    func restartTimer() {
        timer?.invalidate()
        let minutes = min(30, max(2, PROJECTS_CFG.pollMinutes))
        let interval = TimeInterval(minutes * 60)
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.poll() }
        t.tolerance = interval * 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func poll() {
        let liveRelay = relayIsLive()
        let keys = tracked.map(\.ref.key).filter { key in
            if liveKeys.contains(key) { return !liveRelay }
            return true
        }
        refresh(keys, force: false) { _ in }
    }

    func refresh(_ keys: [String], force: Bool, done: @escaping (Bool) -> Void) {
        let todo = keys.filter { force || !refreshing.contains($0) }
        guard !todo.isEmpty else { done(true); return }
        for k in todo { refreshing.insert(k) }
        publish()
        let projects = tracked.filter { todo.contains($0.ref.key) }
        let limit = snapshotLimit
        q.async { [weak self] in
            guard let self = self else { return }
            var fresh: [ProjectSnapshot] = []
            var failed = false
            var scopeError: String?
            for p in projects {
                switch self.api.snapshot(p.ref, kind: p.ownerKind, limit: limit) {
                case .success(let s): fresh.append(s)
                case .failure(let e):
                    failed = true
                    if case .missingScope = e { scopeError = e.message }
                }
            }
            DispatchQueue.main.async {
                for k in todo { self.refreshing.remove(k) }
                if let scopeError = scopeError { self.lastError = scopeError }
                else if !failed { self.lastError = nil }
                for snap in fresh { self.absorb(snap) }
                self.save()
                self.publish()
                done(!failed)
            }
        }
    }

    func refreshForEvents(projectNodeIds: [String], issues: [(repo: String, number: Int)], done: @escaping (Bool) -> Void) {
        var keys = Set<String>()
        let ids = Set(projectNodeIds)
        for (key, snap) in snapshots where ids.contains(snap.summary.nodeId) { keys.insert(key) }
        for issue in issues {
            let k = "\(issue.repo.lowercased())#\(issue.number)"
            keys.formUnion(issueIndex[k] ?? [])
        }
        if projectNodeIds.isEmpty && issues.isEmpty {
            keys.formUnion(tracked.map(\.ref.key))
        }
        if keys.isEmpty { done(true); return }
        refresh(Array(keys), force: true, done: done)
    }

    func timeline(itemId: String, done: @escaping ([ActivityEntry]) -> Void) {
        guard let found = item(itemId), let content = found.item.contentId else { done([]); return }
        let stamp = isoFmt.string(from: found.item.updatedAt)
        let cacheKey = content + "|" + stamp
        if let hit = timelineCache[cacheKey] { done(hit.entries); return }
        guard !timelineFlight.contains(cacheKey) else { return }
        timelineFlight.insert(cacheKey)
        let projectKey = found.key
        q.async { [weak self] in
            let result = self?.api.timeline(contentId: content, last: 20) ?? .failure(.gh("gone"))
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.timelineFlight.remove(cacheKey)
                let entries: [ActivityEntry]
                if case .success(let list) = result {
                    entries = list.map { e in
                        var c = e
                        c.projectKey = projectKey
                        c.itemId = itemId
                        c.unread = !self.readActivity.contains(c.id) && !self.readItems.contains(itemId)
                        return c
                    }
                    self.timelineCache[cacheKey] = (stamp, entries)
                } else {
                    entries = []
                }
                done(entries)
                self.publish()
            }
        }
    }

    func activity(limit: Int, project: String?) -> [ActivityEntry] {
        let rows = activityCache.filter { project == nil || $0.projectKey == project }
            .sorted { $0.at > $1.at }
        return Array(rows.prefix(limit)).map { e in
            var c = e
            c.unread = !readActivity.contains(e.id) && !readItems.contains(e.itemId)
            return c
        }
    }

    func unreadCount() -> Int {
        activity(limit: 500, project: nil).filter(\.unread).count
    }

    func isUnread(itemId: String) -> Bool {
        activity(limit: 500, project: nil).contains { $0.itemId == itemId && $0.unread }
    }

    func markRead(itemId: String) {
        readItems.insert(itemId)
        save()
        publish()
    }

    func markActivityRead(_ id: String) {
        readActivity.insert(id)
        save()
        publish()
    }

    func setStatus(itemId: String, optionId: String, done: @escaping (Bool) -> Void) {
        guard let found = item(itemId), let field = found.snap.statusFieldId else { done(false); return }
        suppressNotify.insert(itemId)
        let projectId = found.snap.summary.nodeId
        q.async { [weak self] in
            let ok = self?.api.setStatus(projectId: projectId, itemId: itemId, fieldId: field, optionId: optionId).isOk ?? false
            DispatchQueue.main.async {
                guard let self = self else { return }
                if !ok { self.suppressNotify.remove(itemId); self.lastError = "Could not change the status" }
                self.refresh([found.key], force: true) { done($0 && ok) }
            }
        }
    }

    func comment(itemId: String, body: String, done: @escaping (Bool) -> Void) {
        guard let found = item(itemId), let content = found.item.contentId else { done(false); return }
        suppressNotify.insert(itemId)
        q.async { [weak self] in
            let ok = self?.api.comment(contentId: content, body: body).isOk ?? false
            DispatchQueue.main.async {
                guard let self = self else { return }
                if !ok { self.suppressNotify.remove(itemId); self.lastError = "Could not post the comment" }
                self.timelineCache = self.timelineCache.filter { !$0.key.hasPrefix(content) }
                self.refresh([found.key], force: true) { done($0 && ok) }
            }
        }
    }

    func item(_ id: String) -> (key: String, snap: ProjectSnapshot, item: ProjectItem)? {
        for (key, snap) in snapshots {
            if let item = snap.items.first(where: { $0.id == id }) { return (key, snap, item) }
        }
        return nil
    }

    var snapshotLimit: Int {
        let n = PROJECTS_CFG.itemsPerProject
        return min(300, max(100, n == 0 ? 200 : n))
    }

    // MARK: Diff

    static func diff(_ old: ProjectSnapshot?, _ new: ProjectSnapshot) -> [(itemId: String, ItemChange)] {
        guard let old = old else { return [] }
        var out: [(String, ItemChange)] = []
        let oldById = Dictionary(old.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let newIds = Set(new.items.map(\.id))
        for item in new.items {
            guard let prev = oldById[item.id] else {
                out.append((item.id, .added))
                if item.mentionsMe { out.append((item.id, .mention)) }
                continue
            }
            if prev.statusOptionId != item.statusOptionId {
                out.append((item.id, .status(from: old.statusName(prev.statusOptionId), to: new.statusName(item.statusOptionId))))
            }
            let wasDone = old.option(prev.statusOptionId)?.category == .done || prev.isClosedState
            let isDone = new.option(item.statusOptionId)?.category == .done || item.isClosedState
            if isDone && !wasDone { out.append((item.id, .closed)) }
            if wasDone && !isDone && !item.isClosedState { out.append((item.id, .reopened)) }
            let names = Set(prev.fields.keys).union(item.fields.keys).subtracting(["Status"])
            for name in names.sorted() where prev.fields[name] != item.fields[name] {
                out.append((item.id, .field(name: name, from: prev.fields[name], to: item.fields[name])))
            }
            let oldA = Set(prev.assignees), newA = Set(item.assignees)
            for a in newA.subtracting(oldA).sorted() { out.append((item.id, .assigned(a))) }
            for a in oldA.subtracting(newA).sorted() { out.append((item.id, .unassigned(a))) }
            if let last = item.lastComment, last.id != prev.lastComment?.id || item.commentCount > prev.commentCount {
                let n = max(1, item.commentCount - prev.commentCount)
                out.append((item.id, .comments(new: n, last: last)))
                if item.mentionsMe { out.append((item.id, .mention)) }
            }
        }
        for item in old.items where !newIds.contains(item.id) {
            out.append((item.id, .removed))
        }
        return out
    }

    // MARK: Private

    private func absorb(_ snap: ProjectSnapshot) {
        let key = snap.summary.ref.key
        let old = snapshots[key]
        let changes = ProjectStore.diff(old, snap)
        snapshots[key] = snap
        rebuildIndex()
        guard old != nil, !changes.isEmpty else { return }
        let at = snap.fetchedAt
        let entries = changes.map { pair -> ActivityEntry in
            let item = snap.items.first { $0.id == pair.itemId } ?? old?.items.first { $0.id == pair.itemId }
            return ActivityEntry.make(projectKey: key, itemId: pair.itemId, change: pair.1,
                                      actor: pair.1.commentAuthor,
                                      url: item?.paneURL(projectURL: snap.summary.url) ?? item?.url ?? snap.summary.url, at: at)
        }
        append(entries)
        let filtered = changes.filter { !suppressNotify.contains($0.itemId) }
        suppressNotify.subtract(changes.map(\.itemId))
        notifier.handle(filtered, in: snap, settings: PROJECTS_CFG.notifications)
    }

    private func rebuildIndex() {
        issueIndex = [:]
        for (key, snap) in snapshots {
            for item in snap.items {
                guard let repo = item.repo, let n = item.number else { continue }
                issueIndex["\(repo.lowercased())#\(n)", default: []].insert(key)
            }
        }
    }

    private func append(_ entries: [ActivityEntry]) {
        let known = Set(activityCache.map(\.id))
        let fresh = entries.filter { !known.contains($0.id) }
        guard !fresh.isEmpty else { return }
        activityCache.append(contentsOf: fresh)
        let cutoff = Date().addingTimeInterval(-14 * 86400)
        activityCache.removeAll { $0.at < cutoff }
        let text = activityCache.compactMap { e -> String? in
            guard let d = try? JSONEncoder().encode(e) else { return nil }
            return String(data: d, encoding: .utf8)
        }.joined(separator: "\n") + "\n"
        try? FileManager.default.createDirectory(atPath: CONFIG_DIR, withIntermediateDirectories: true)
        try? text.write(toFile: activityPath, atomically: true, encoding: .utf8)
    }

    private struct Disk: Codable {
        var snapshots: [String: ProjectSnapshot]
        var readActivity: [String]
        var readItems: [String]
    }

    private func load() {
        if let data = FileManager.default.contents(atPath: statePath),
           let disk = try? JSONDecoder().decode(Disk.self, from: data) {
            snapshots = disk.snapshots
            readActivity = Set(disk.readActivity)
            readItems = Set(disk.readItems)
            rebuildIndex()
        }
        let raw = (try? String(contentsOfFile: activityPath, encoding: .utf8)) ?? ""
        let dec = JSONDecoder()
        activityCache = raw.split(separator: "\n").compactMap {
            guard let d = $0.data(using: .utf8) else { return nil }
            return try? dec.decode(ActivityEntry.self, from: d)
        }
    }

    private func save() {
        let disk = Disk(snapshots: snapshots, readActivity: Array(readActivity), readItems: Array(readItems))
        guard let data = try? JSONEncoder().encode(disk) else { return }
        try? FileManager.default.createDirectory(atPath: CONFIG_DIR, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: statePath), options: .atomic)
    }

    private func publish() {
        onChange?()
        NotificationCenter.default.post(name: ProjectStore.changed, object: self)
    }
}

private extension Result {
    var isOk: Bool { if case .success = self { return true }; return false }
}
