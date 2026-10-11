import Foundation
import CryptoKit
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
    var ai: AIConfig?
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
    var hideDoneAfterDays = 1         // 0 = never hide, -1 = always hide
    var defaultView = ProjectView.board
    var menuDot = true
    var showTab = true
    var notifications = ProjectNotificationSettings()
    var order: [String] = []          // project keys, top to bottom
    var folded: [String] = []         // project keys that show only the header
    var capture = CaptureConfig()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        picked = try c.decodeIfPresent([String].self, forKey: .picked) ?? []
        allOf = try c.decodeIfPresent([String].self, forKey: .allOf) ?? []
        pollMinutes = min(30, max(2, try c.decodeIfPresent(Int.self, forKey: .pollMinutes) ?? 5))
        itemsPerProject = try c.decodeIfPresent(Int.self, forKey: .itemsPerProject) ?? 10
        hideDoneAfterDays = try c.decodeIfPresent(Int.self, forKey: .hideDoneAfterDays) ?? 1
        defaultView = try c.decodeIfPresent(ProjectView.self, forKey: .defaultView) ?? .board
        menuDot = try c.decodeIfPresent(Bool.self, forKey: .menuDot) ?? true
        showTab = try c.decodeIfPresent(Bool.self, forKey: .showTab) ?? true
        notifications = try c.decodeIfPresent(ProjectNotificationSettings.self, forKey: .notifications) ?? ProjectNotificationSettings()
        order = try c.decodeIfPresent([String].self, forKey: .order) ?? []
        folded = try c.decodeIfPresent([String].self, forKey: .folded) ?? []
        capture = try c.decodeIfPresent(CaptureConfig.self, forKey: .capture) ?? CaptureConfig()
    }

    // Keys in `order` come first. Projects not in it follow by owner, then title.
    func sorted(_ projects: [ProjectSummary]) -> [ProjectSummary] {
        var rank: [String: Int] = [:]
        for (i, k) in order.enumerated() where rank[k.lowercased()] == nil { rank[k.lowercased()] = i }
        return projects.sorted { a, b in
            let ra = rank[a.ref.key.lowercased()] ?? .max, rb = rank[b.ref.key.lowercased()] ?? .max
            if ra != rb { return ra < rb }
            if a.ref.owner.caseInsensitiveCompare(b.ref.owner) != .orderedSame {
                return a.ref.owner.localizedCaseInsensitiveCompare(b.ref.owner) == .orderedAscending
            }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }

    func isFolded(_ key: String) -> Bool { folded.contains { $0.caseInsensitiveCompare(key) == .orderedSame } }

    mutating func setFolded(_ key: String, _ on: Bool) {
        folded.removeAll { $0.caseInsensitiveCompare(key) == .orderedSame }
        if on { folded.append(key) }
    }
}

// Global shortcut that opens the New item sheet. Carbon key code and modifier flags.
struct CaptureConfig: Codable, Equatable {
    var enabled = true
    var keyCode: UInt32 = 45            // N
    var modifiers: UInt32 = 0x1800      // control + option
    var pasteClipboard = true
    var aiTitle = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        keyCode = try c.decodeIfPresent(UInt32.self, forKey: .keyCode) ?? 45
        modifiers = try c.decodeIfPresent(UInt32.self, forKey: .modifiers) ?? 0x1800
        pasteClipboard = try c.decodeIfPresent(Bool.self, forKey: .pasteClipboard) ?? true
        aiTitle = try c.decodeIfPresent(Bool.self, forKey: .aiTitle) ?? true
    }
}

enum AIFormat: String, Codable { case openai, anthropic }

// The API key is in the Keychain, not here.
struct AIConfig: Codable, Equatable {
    var format = AIFormat.openai
    var baseURL = ""
    var model = ""
    var effort = "low"                  // OpenAI only. "none" leaves out the field.
    var maxTokens = 1024                // Anthropic only
    var extraContext = ""
    var enabled = false
    var verified = ""                   // fingerprint of the last passed test
    var titleAndFields = true
    var tidy = true
    var pickProject = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(AIFormat.self, forKey: .format) ?? .openai
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        effort = try c.decodeIfPresent(String.self, forKey: .effort) ?? "low"
        maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens) ?? 1024
        extraContext = try c.decodeIfPresent(String.self, forKey: .extraContext) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        verified = try c.decodeIfPresent(String.self, forKey: .verified) ?? ""
        titleAndFields = try c.decodeIfPresent(Bool.self, forKey: .titleAndFields) ?? true
        tidy = try c.decodeIfPresent(Bool.self, forKey: .tidy) ?? true
        pickProject = try c.decodeIfPresent(Bool.self, forKey: .pickProject) ?? true
    }

    func fingerprint(key: String) -> String {
        let raw = "\(format.rawValue)|\(baseURL)|\(model)|\(key)"
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func isOn(key: String?) -> Bool {
        guard enabled, let key, !key.isEmpty, !verified.isEmpty else { return false }
        return verified == fingerprint(key: key)
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
var AI_CFG = AIConfig()
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
    if let a = c.ai { AI_CFG = a }
}

func saveConfig() {
    try? FileManager.default.createDirectory(atPath: CONFIG_DIR, withIntermediateDirectories: true)
    let c = AppConfig(repos: PICKED_REPOS.filter { isValidRepo($0) },
                      orgs: PICKED_ORGS.isEmpty ? nil : PICKED_ORGS, pollInterval: POLL_NORMAL,
                      pollActiveInterval: POLL_ACTIVE, runsPerRepo: RUNS_PER_REPO,
                      filterDefaultBranches: FILTER_DEFAULT_BRANCHES, sortByRecent: SORT_BY_RECENT,
                      oneRowPerWorkflow: ONE_ROW_PER_WORKFLOW,
                      repoColors: REPO_COLORS.isEmpty ? nil : REPO_COLORS, autoUpdate: AUTO_UPDATE,
                      relay: RELAY, notifications: NOTIFICATIONS, tabs: TABS, projects: PROJECTS_CFG, ai: AI_CFG)
    if let data = try? JSONEncoder().encode(c) {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let pretty = try? JSONSerialization.data(withJSONObject: json as Any, options: .prettyPrinted) {
            try? pretty.write(to: URL(fileURLWithPath: CONFIG_PATH))
        }
    }
}
