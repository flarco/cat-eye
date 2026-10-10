import Foundation
import os

// ─── Configuration ───────────────────────────────────────────────────────────

struct AppConfig: Codable {
    var repos: [String]
    var orgs: [String]?
    var pollInterval: TimeInterval?
    var pollActiveInterval: TimeInterval?
    var runsPerRepo: Int?
    var filterDefaultBranches: Bool?
    var sortByRecent: Bool?
    var oneRowPerWorkflow: Bool?
    var repoColors: [String: Int]?
    var autoUpdate: Bool?
    var relay: RelayConfig?
    var notifications: NotificationSettings?
    var tabs: TabVisibility?
    var projects: ProjectsConfig?
}

// Which transition events create macOS notifications. Omitted legacy config
// fields keep the previous behavior: notify for every start and completion.
struct NotificationSettings: Codable {
    var started = true
    var succeeded = true
    var failed = true
    var cancelled = true
    var other = true

    init() {}

    // Hand-written config files may omit individual switches.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        started = try c.decodeIfPresent(Bool.self, forKey: .started) ?? true
        succeeded = try c.decodeIfPresent(Bool.self, forKey: .succeeded) ?? true
        failed = try c.decodeIfPresent(Bool.self, forKey: .failed) ?? true
        cancelled = try c.decodeIfPresent(Bool.self, forKey: .cancelled) ?? true
        other = try c.decodeIfPresent(Bool.self, forKey: .other) ?? true
    }
}

// One column of the project notification matrix. Omitted switches keep the defaults.
struct NotifyScope: Codable {
    var any: Bool
    var mine: Bool
}

struct ProjectNotificationSettings: Codable {
    var mention = true
    var comment = NotifyScope(any: false, mine: true)
    var status = NotifyScope(any: false, mine: true)
    var added = NotifyScope(any: true, mine: true)
    var assigned = true
    var closed = NotifyScope(any: false, mine: true)
    var otherFields = NotifyScope(any: false, mine: false)

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mention = try c.decodeIfPresent(Bool.self, forKey: .mention) ?? true
        comment = try c.decodeIfPresent(NotifyScope.self, forKey: .comment) ?? NotifyScope(any: false, mine: true)
        status = try c.decodeIfPresent(NotifyScope.self, forKey: .status) ?? NotifyScope(any: false, mine: true)
        added = try c.decodeIfPresent(NotifyScope.self, forKey: .added) ?? NotifyScope(any: true, mine: true)
        assigned = try c.decodeIfPresent(Bool.self, forKey: .assigned) ?? true
        closed = try c.decodeIfPresent(NotifyScope.self, forKey: .closed) ?? NotifyScope(any: false, mine: true)
        otherFields = try c.decodeIfPresent(NotifyScope.self, forKey: .otherFields) ?? NotifyScope(any: false, mine: false)
    }
}

enum ProjectView: String, Codable { case board, activity }

struct ProjectsConfig: Codable {
    var picked: [String] = []
    var allOf: [String] = []
    var pollMinutes = 5
    var itemsPerProject = 10          // 0 = all
    var hideDoneAfterDays = 7         // 0 = never hide
    var defaultView = ProjectView.board
    var menuDot = true
    var showTab = true
    var notifications = ProjectNotificationSettings()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        picked = try c.decodeIfPresent([String].self, forKey: .picked) ?? []
        allOf = try c.decodeIfPresent([String].self, forKey: .allOf) ?? []
        pollMinutes = min(30, max(2, try c.decodeIfPresent(Int.self, forKey: .pollMinutes) ?? 5))
        itemsPerProject = try c.decodeIfPresent(Int.self, forKey: .itemsPerProject) ?? 10
        hideDoneAfterDays = try c.decodeIfPresent(Int.self, forKey: .hideDoneAfterDays) ?? 7
        defaultView = try c.decodeIfPresent(ProjectView.self, forKey: .defaultView) ?? .board
        menuDot = try c.decodeIfPresent(Bool.self, forKey: .menuDot) ?? true
        showTab = try c.decodeIfPresent(Bool.self, forKey: .showTab) ?? true
        notifications = try c.decodeIfPresent(ProjectNotificationSettings.self, forKey: .notifications) ?? ProjectNotificationSettings()
    }
}

// Which main tabs are shown. Projects uses ProjectsConfig.showTab.
struct TabVisibility: Codable {
    var actions = true
    var prs = true
    var insights = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        actions = try c.decodeIfPresent(Bool.self, forKey: .actions) ?? true
        prs = try c.decodeIfPresent(Bool.self, forKey: .prs) ?? true
        insights = try c.decodeIfPresent(Bool.self, forKey: .insights) ?? true
    }
}

let CONFIG_DIR  = NSString(string: "~/.config/cat-eye").expandingTildeInPath
let CONFIG_PATH = (CONFIG_DIR as NSString).appendingPathComponent("config.json")
let REPO_CACHE_PATH = (CONFIG_DIR as NSString).appendingPathComponent("repo-cache.json")
let PROJECT_CACHE_PATH = (CONFIG_DIR as NSString).appendingPathComponent("project-cache.json")
let PROJECT_STATE_PATH = (CONFIG_DIR as NSString).appendingPathComponent("project-state.json")
let PROJECT_ACTIVITY_PATH = (CONFIG_DIR as NSString).appendingPathComponent("project-activity.jsonl")

// REPOS is what the app tracks: PICKED_REPOS plus every repo of PICKED_ORGS.
var REPOS: [String] = []
var PICKED_REPOS: [String] = []
var PICKED_ORGS: [String] = []
var POLL_NORMAL: TimeInterval = 30
var POLL_ACTIVE: TimeInterval = 10
var RUNS_PER_REPO: Int = 10
var FILTER_DEFAULT_BRANCHES: Bool = false
var SORT_BY_RECENT: Bool = true
var ONE_ROW_PER_WORKFLOW: Bool = true
var REPO_COLORS: [String: Int] = [:]
var AUTO_UPDATE: Bool = true
var NOTIFICATIONS = NotificationSettings()
var TABS = TabVisibility()
var PROJECTS_CFG = ProjectsConfig()
let DEFAULT_BRANCHES: Set<String> = ["main", "develop"]

let repoPattern = try! NSRegularExpression(pattern: "^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$")

let log = Logger(subsystem: "com.flarco.cat-eye", category: "app")

func isValidRepo(_ s: String) -> Bool {
    repoPattern.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
}

func loadConfig() {
    guard let data = FileManager.default.contents(atPath: CONFIG_PATH),
          let c = try? JSONDecoder().decode(AppConfig.self, from: data) else { return }
    PICKED_REPOS = c.repos.filter { isValidRepo($0) }
    PICKED_ORGS = c.orgs ?? []
    REPOS = PICKED_REPOS
    POLL_NORMAL = max(5, c.pollInterval ?? 30)
    POLL_ACTIVE = max(5, c.pollActiveInterval ?? 10)
    RUNS_PER_REPO = min(max(1, c.runsPerRepo ?? 10), 100)
    FILTER_DEFAULT_BRANCHES = c.filterDefaultBranches ?? false
    SORT_BY_RECENT = c.sortByRecent ?? true
    ONE_ROW_PER_WORKFLOW = c.oneRowPerWorkflow ?? true
    REPO_COLORS = c.repoColors ?? [:]
    AUTO_UPDATE = c.autoUpdate ?? true
    if let n = c.notifications { NOTIFICATIONS = n }
    if let r = c.relay { RELAY = r }
    if let t = c.tabs { TABS = t }
    if let p = c.projects { PROJECTS_CFG = p }
}

func saveConfig() {
    try? FileManager.default.createDirectory(atPath: CONFIG_DIR, withIntermediateDirectories: true)
    let c = AppConfig(repos: PICKED_REPOS.filter { isValidRepo($0) },
                      orgs: PICKED_ORGS.isEmpty ? nil : PICKED_ORGS, pollInterval: POLL_NORMAL,
                      pollActiveInterval: POLL_ACTIVE, runsPerRepo: RUNS_PER_REPO,
                      filterDefaultBranches: FILTER_DEFAULT_BRANCHES, sortByRecent: SORT_BY_RECENT,
                      oneRowPerWorkflow: ONE_ROW_PER_WORKFLOW,
                      repoColors: REPO_COLORS.isEmpty ? nil : REPO_COLORS, autoUpdate: AUTO_UPDATE,
                      relay: RELAY, notifications: NOTIFICATIONS, tabs: TABS, projects: PROJECTS_CFG)
    if let data = try? JSONEncoder().encode(c) {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let pretty = try? JSONSerialization.data(withJSONObject: json as Any, options: .prettyPrinted) {
            try? pretty.write(to: URL(fileURLWithPath: CONFIG_PATH))
        }
    }
}
