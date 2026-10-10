import Foundation

// The list of projects the user can pick from. Cached on disk and refreshed,
// per owner, at most once a day unless the user asks.

struct ProjectCatalogCache: Codable {
    var owners: [CachedOwner]
    var fetchedAt: Date?

    struct CachedOwner: Codable {
        var login: String
        var kind: OwnerKind
        var projects: [ProjectSummary]
        var fetchedAt: Date?
    }
}

final class ProjectCatalog {
    static let changed = Notification.Name("ProjectCatalogChanged")
    static let maxAge: TimeInterval = 24 * 3600

    private(set) var owners: [(login: String, kind: OwnerKind)] = []
    private(set) var byOwner: [String: [ProjectSummary]] = [:]
    private(set) var fetchedAt: [String: Date] = [:]
    private(set) var status: [String: OwnerFetch] = [:]
    private(set) var listingOwners = false
    private(set) var listError: String?
    private var pending = 0
    private var ticket: [String: Int] = [:]
    private let api: ProjectAPI
    private let path: String
    private let fetchQ: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 3
        q.qualityOfService = .userInitiated
        return q
    }()

    init(api: ProjectAPI, path: String) {
        self.api = api
        self.path = path
        guard let data = FileManager.default.contents(atPath: path),
              let c = try? JSONDecoder().decode(ProjectCatalogCache.self, from: data) else { return }
        owners = c.owners.map { ($0.login, $0.kind) }
        for o in c.owners {
            byOwner[o.login.lowercased()] = o.projects
            fetchedAt[o.login.lowercased()] = o.fetchedAt
        }
    }

    var refreshing: Bool { listingOwners || pending > 0 }
    var isStale: Bool {
        guard !owners.isEmpty else { return true }
        return owners.contains { fetchedAt[$0.login.lowercased()].map { -$0.timeIntervalSinceNow > ProjectCatalog.maxAge } ?? true }
    }

    func projects(of owner: String) -> [ProjectSummary] { byOwner[owner.lowercased()] ?? [] }
    func fetch(_ owner: String) -> OwnerFetch { status[owner.lowercased()] ?? .idle }

    // Explicit picks plus every open project of the owners picked as a whole.
    func resolve(_ cfg: ProjectsConfig) -> [ProjectSummary] {
        var seen = Set<String>()
        var out: [ProjectSummary] = []
        let all = Set(cfg.allOf.map { $0.lowercased() })
        for owner in owners {
            for p in projects(of: owner.login) where !p.closed {
                let wanted = all.contains(owner.login.lowercased()) || cfg.picked.contains(p.ref.key)
                if wanted && seen.insert(p.ref.key.lowercased()).inserted { out.append(p) }
            }
        }
        // A pick whose owner has not been fetched yet still has a key. Skip it until the catalog has it.
        return cfg.sorted(out)
    }

    func refreshIfStale() { if isStale { refreshAll() } }

    func refreshAll(force: Bool = false) {
        guard force || !refreshing else { return }
        listingOwners = true
        notify()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = self?.api.viewerOwners()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.listingOwners = false
                switch result {
                case .success(let list):
                    self.listError = nil
                    self.owners = list
                    self.fetchProjects(list)
                case .failure(let e):
                    self.listError = e.message
                    self.notify()
                case .none:
                    self.notify()
                }
            }
        }
    }

    // One request for every owner. A click on Refresh starts a new request even if
    // the previous one is still marked loading.
    func refresh(owner login: String, force: Bool = false) {
        let key = login.lowercased()
        if !force, case .loading = fetch(login) { return }
        let kind = owners.first { $0.login.lowercased() == key }?.kind ?? .org
        fetchProjects([(login, kind)])
    }

    private func fetchProjects(_ list: [(login: String, kind: OwnerKind)]) {
        guard !list.isEmpty else { notify(); return }
        var mine: [String: Int] = [:]
        for o in list {
            let key = o.login.lowercased()
            let n = (ticket[key] ?? 0) + 1
            ticket[key] = n
            mine[key] = n
            status[key] = .loading
        }
        pending += 1
        notify()
        fetchQ.addOperation { [weak self] in
            let result = self?.api.projects(owners: list) ?? .failure(.gh("Catalog gone"))
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.pending = max(0, self.pending - 1)
                switch result {
                case .success(let byKey):
                    for (key, res) in byKey {
                        guard self.ticket[key] == mine[key] else { continue }
                        switch res {
                        case .success(let projects):
                            self.status[key] = .idle
                            self.byOwner[key] = projects
                            self.fetchedAt[key] = Date()
                        case .failure(let e):
                            self.status[key] = .failed(e.message)
                        }
                    }
                case .failure(let e):
                    for (key, n) in mine where self.ticket[key] == n {
                        self.status[key] = .failed(e.message)
                    }
                }
                self.save()
                self.notify()
            }
        }
    }

    private func save() {
        let cached = owners.map { o in
            ProjectCatalogCache.CachedOwner(login: o.login, kind: o.kind,
                                            projects: byOwner[o.login.lowercased()] ?? [],
                                            fetchedAt: fetchedAt[o.login.lowercased()])
        }
        let c = ProjectCatalogCache(owners: cached, fetchedAt: Date())
        guard let data = try? JSONEncoder().encode(c) else { return }
        try? FileManager.default.createDirectory(atPath: CONFIG_DIR, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private func notify() { NotificationCenter.default.post(name: ProjectCatalog.changed, object: self) }
}
