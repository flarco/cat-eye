import Cocoa
import QuartzCore
import UserNotifications
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
    var autoUpdate: Bool?
    var relay: RelayConfig?
}

let CONFIG_DIR  = NSString(string: "~/.config/cat-eye").expandingTildeInPath
let CONFIG_PATH = (CONFIG_DIR as NSString).appendingPathComponent("config.json")
let REPO_CACHE_PATH = (CONFIG_DIR as NSString).appendingPathComponent("repo-cache.json")

// REPOS is what the app tracks: PICKED_REPOS plus every repo of PICKED_ORGS.
var REPOS: [String] = []
var PICKED_REPOS: [String] = []
var PICKED_ORGS: [String] = []
var POLL_NORMAL: TimeInterval = 30
var POLL_ACTIVE: TimeInterval = 10
var RUNS_PER_REPO: Int = 10
var FILTER_DEFAULT_BRANCHES: Bool = false
var SORT_BY_RECENT: Bool = true
var AUTO_UPDATE: Bool = true
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
    AUTO_UPDATE = c.autoUpdate ?? true
    if let r = c.relay { RELAY = r }
}

func saveConfig() {
    try? FileManager.default.createDirectory(atPath: CONFIG_DIR, withIntermediateDirectories: true)
    let c = AppConfig(repos: PICKED_REPOS.filter { isValidRepo($0) },
                      orgs: PICKED_ORGS.isEmpty ? nil : PICKED_ORGS, pollInterval: POLL_NORMAL,
                      pollActiveInterval: POLL_ACTIVE, runsPerRepo: RUNS_PER_REPO,
                      filterDefaultBranches: FILTER_DEFAULT_BRANCHES, sortByRecent: SORT_BY_RECENT,
                      autoUpdate: AUTO_UPDATE, relay: RELAY)
    if let data = try? JSONEncoder().encode(c) {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let pretty = try? JSONSerialization.data(withJSONObject: json as Any, options: .prettyPrinted) {
            try? pretty.write(to: URL(fileURLWithPath: CONFIG_PATH))
        }
    }
}

// Find gh CLI — hardcoded trusted paths only
let GH: String = {
    let trusted = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
    for p in trusted {
        if FileManager.default.isExecutableFile(atPath: p) { return p }
    }
    return trusted[0] // Will show "gh not found" error on first fetch
}()

// Minimal env for gh CLI — PATH, HOME, LANG + gh auth/config vars
let ghEnv: [String: String] = {
    let env = ProcessInfo.processInfo.environment
    let allow = ["PATH", "HOME", "LANG", "SHELL",
                 "GH_TOKEN", "GITHUB_TOKEN", "GH_CONFIG_DIR",
                 "XDG_CONFIG_HOME", "XDG_DATA_HOME",
                 "GNUPGHOME", "SSH_AUTH_SOCK"]
    var result: [String: String] = [:]
    for key in allow { if let v = env[key] { result[key] = v } }
    if result["PATH"] == nil { result["PATH"] = "/usr/bin:/bin:/opt/homebrew/bin" }
    if result["HOME"] == nil { result["HOME"] = NSHomeDirectory() }
    return result
}()

let POP_W: CGFloat = 660
let POP_MAX_H: CGFloat = 700
let ROW_H: CGFloat = 56
let HDR_H: CGFloat = 32
let FTR_H: CGFloat = 40
let PAD: CGFloat = 12
let ICON_SZ: CGFloat = 20
let TEXT_X: CGFloat = 42     // PAD + ICON_SZ + 10

let GH_ICON_B64 = "iVBORw0KGgoAAAANSUhEUgAAACQAAAAkCAYAAADhAJiYAAAABGdBTUEAALGPC/xhBQAAACBjSFJNAAB6JgAAgIQAAPoAAACA6AAAdTAAAOpgAAA6mAAAF3CculE8AAAAeGVYSWZNTQAqAAAACAAEARoABQAAAAEAAAA+ARsABQAAAAEAAABGASgAAwAAAAEAAgAAh2kABAAAAAEAAABOAAAAAAAAAEgAAAABAAAASAAAAAEAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAJKADAAQAAAABAAAAJAAAAAAZgdfLAAAACXBIWXMAAAsTAAALEwEAmpwYAAAEkUlEQVRYCbWYTYyNVxjH5/pWE0NKqI9LlFawqCDtQiZWIsFOWSBIdWdj126mkerSx6IhkQjx0W5KSOxI2liw8LXoYDBhYoj4iJoxPovb3+/2vjfnnnnvuDPzzj/5zXve5zznOc8973nPOe/k6nqhQqEwGvdGWADzYDZMhQZQHdAOLdAMl+BsLpfr5JqdSCQPO6EFOuAVvIV38AESWdZmnT5dcB9sm+9XRgTIwXhognvwHOystzLJTjCGsYyZ61VyNBgGc+AEtENWMpYxjT2spqRwrIf5sAOeQdYyprHtoz5OalBowMGsZ8FKWA/JZKWYmYxpbPv4otRn9+BUDAKH0uwfQaJ/KbwAr33Vexo6B98EAezDvuyzYmCK2WF0sh2H8DEZ6DochSvg5DQxJ6ry6kTXlpDUYSrWmUgr7IHzJRuXouzLPsd3GyKMvgHxBHZkNiTOlFfBX/APmMBjuAx/BjykbJ2v/QVYFbRfwr1LQSj7bEp8ilcMefC1jOWv+yp05t5JP1FCe1hO6vWN7NOxOcqx7Lu4TiXPbisN0yZwAburb6gX3DwqEdrDsvUPQd9aZN/mUOdEdjtYDaM0RBrM/dehjW2gAB8ktIflUr1+/qBQU7hJWxRHYl9mLo5QI5hh7Pge2wNwX8pKbQQyprFD+cM/g0YTWghDINYrDKehLa7ox/0T2h6DlykxhmNbYEJzIZlLoZ+NTjLsz0Jjf8rEek3738CY8eN0lOaZiEcIb0Lp3AXnQmMWZZL6mziO1LsonjnMNqGpEI/QG2wPaJztOYagJTmP7CNUMRf/pL3uoeNAlJ8TNB4h+2mIR2YgOk+L6VKT9iIVH1W88BlgBExmXRio0fuS+BWruJ2iDkeoHdIWuU+wL4JMxY80prFjmUO7CbnwxQuVzq7c31rIWMuJl5aQObSY0FVIGyEXqsX8om+4ZiJiuQ0tBadELBNqNqGL4IIVy0k3E9YSaBrEW0vsX/XetjAZh3XgJ5Qn01gmdKkOx9Hg503yRfGa8lN4Ap5r1C6YAQ0wElLfkLAHfAbDCLCNx45tUE0e6jyC+Paxhv/foWcfdRZ+gI1wFZJE71L+BdbAXEgb9iSeiXwOy+FnaIaeZN+7io1LCYUHNE+DZ8DjgK/+FYjlsXZ7OUBUsA70qVXlA1o5FC09wlqhfFTXwKGWO+D5OtFBChUnyXIgCtbBAahF9tmUtA/nwl6M88EFywVxEmyCbbACNsM4aAOPJW6S1WTd3WqVgd1F+QLYd6XI0tNj+BnkRPO7XNsQGAufgi+BS0KPwucn6Empn0HlEWJnN4FWejkCZr4FJsAh+ANug5uik/kGXIO+6jENf4VT0GrfSaByQhqo8L8Wtyjq6GP7Dlw3PKt4aHe9Ggq/Q18T8sceBvu4aZ9cy6pISCsOfjc1U9wP02AhxBPY594X3afRRTC2I1ORjAFdqbtJR3AE1sJuMFAXxMdOTFWlr4/CFdhHbYx98D1cT0sGe21ixPKwE5zkfuj9+LGW+GwFv0rdBWyb/1gb63u1PxHUpV26+IUe1KsK3zFU1kMnvjUfhf8D2aXnxu16TasAAAAASUVORK5CYII="

// ─── Model ───────────────────────────────────────────────────────────────────

struct Run: Decodable {
    let id: Int
    let name: String
    let displayTitle: String
    let status: String
    let conclusion: String?
    let headBranch: String
    let headSha: String
    let event: String
    let url: String
    let updatedAt: String
    let createdAt: String
    let startedAt: String?
    let number: Int
    let workflowName: String?
    let actorLogin: String?
    var attempt: Int? = nil

    var isFailure: Bool { status == "completed" && conclusion == "failure" }
}

// Failed runs the user chose to ignore. They do not turn the menu bar icon red.
// The key holds the attempt, so a re-run that fails again shows red again.
final class IgnoredFailures {
    private let defaultsKey = "ignoredFailures"
    private var keys: [String]

    init() { keys = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [] }

    static func key(_ r: Run) -> String { "\(r.url)#\(r.attempt ?? 1)" }

    func contains(_ r: Run) -> Bool { keys.contains(IgnoredFailures.key(r)) }

    func set(_ runs: [Run], ignored: Bool) {
        let ks = runs.map(IgnoredFailures.key)
        keys.removeAll { ks.contains($0) }
        if ignored { keys += ks }
        keys = Array(keys.suffix(500))
        UserDefaults.standard.set(keys, forKey: defaultsKey)
    }
}

let IGNORED = IgnoredFailures()

// Puts the workflows of one trigger (same commit, branch, event, actor) into one row.
// A second run of a workflow already in a row starts a new row. This keeps repeat dispatches apart.
func groupRuns(_ runs: [Run]) -> [[Run]] {
    var groups: [[Run]] = []
    var indexByKey: [String: Int] = [:]
    for run in runs {
        let key = "\(run.displayTitle)|\(run.headSha)|\(run.headBranch)|\(run.event)|\(run.actorLogin ?? "")"
        if let i = indexByKey[key], !groups[i].contains(where: { $0.workflowName == run.workflowName }) {
            groups[i].append(run)
        } else {
            indexByKey[key] = groups.count; groups.append([run])
        }
    }
    return groups
}

struct PRAuthor: Decodable { let login: String }
struct PRLabel: Decodable { let name: String; let color: String? }
struct PR: Decodable {
    let number: Int
    let title: String
    let state: String
    let author: PRAuthor
    let headRefName: String
    let baseRefName: String
    let url: String
    let createdAt: String
    let updatedAt: String
    let reviewDecision: String?
    let additions: Int
    let deletions: Int
    let isDraft: Bool
    let labels: [PRLabel]
    let body: String?
}

enum PRAction: CustomStringConvertible {
    case approve(String?)
    case requestChanges(String)
    case comment(String)
    case merge(String)   // "-m", "-r", "-s"
    case close

    var description: String {
        switch self {
        case .approve: return "approve"
        case .requestChanges: return "request-changes"
        case .comment: return "comment"
        case .merge(let m): return "merge(\(m))"
        case .close: return "close"
        }
    }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

private let _fetchErrQ = DispatchQueue(label: "com.flarco.cat-eye.fetchErr")
private var _lastFetchError: String? = nil
var lastFetchError: String? {
    get { _fetchErrQ.sync { _lastFetchError } }
    set { _fetchErrQ.sync { _lastFetchError = newValue } }
}

struct GHResult {
    let status: Int32
    let out: Data
    let err: String
    var ok: Bool { status == 0 }
}

// Runs gh with optional stdin, so request bodies with secrets never appear in argv.
func ghRun(_ args: [String], input: Data? = nil) throws -> GHResult {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: GH)
    proc.arguments = args
    proc.environment = ghEnv
    let outPipe = Pipe()
    let errPipe = Pipe()
    proc.standardOutput = outPipe
    proc.standardError = errPipe
    let inPipe = input.map { _ in Pipe() }
    if let p = inPipe { proc.standardInput = p } else { proc.standardInput = FileHandle.nullDevice }
    try proc.run()
    if let inPipe = inPipe, let input = input {
        inPipe.fileHandleForWriting.write(input)
        try? inPipe.fileHandleForWriting.close()
    }
    // Drain both pipes BEFORE waiting: a child that fills a 64KB pipe buffer
    // would otherwise block forever inside waitUntilExit, stranding a worker
    // thread per poll while new refreshes keep stacking up.
    var errData = Data()
    let errDone = DispatchSemaphore(value: 0)
    DispatchQueue.global(qos: .utility).async {
        errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        errDone.signal()
    }
    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
    errDone.wait()
    proc.waitUntilExit()
    let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return GHResult(status: proc.terminationStatus, out: outData, err: errStr)
}

func ghShell(_ args: String...) -> Data? {
    guard FileManager.default.isExecutableFile(atPath: GH) else {
        let msg = "GitHub CLI not found at \(GH)"
        log.error("\(msg)")
        lastFetchError = msg
        return nil
    }
    do {
        let res = try ghRun(args)
        guard res.ok else {
            let errStr = res.err
            // Public on purpose: os_log redacts interpolated strings by default,
            // which turned every one of these into "gh <private> exited 1:
            // <private>" and made a whole night of failures undiagnosable.
            // Only the first two args: "api repos/x/y/actions/runs" or "pr review"
            // is all the diagnosis needs, and it keeps a `pr review -b <body>`
            // out of a log any process on the machine can read.
            log.warning("gh \(args.prefix(2).joined(separator: " "), privacy: .public) exited \(res.status): \(errStr, privacy: .public)")
            let low = errStr.lowercased()
            // Order matters: gh's unauthenticated 403 reads "API rate limit
            // exceeded ... Authenticated requests get a higher rate limit",
            // so the auth test would swallow it if it ran first.
            if low.contains("rate limit") {
                lastFetchError = "GitHub API rate limit hit — retries resume after the reset"
            } else if low.contains("auth") || low.contains("login") || low.contains("bad credentials") {
                lastFetchError = "Not authenticated. Run: gh auth login"
            } else if low.contains("404") || low.contains("could not resolve to a repository") {
                // GitHub answers 404, not 401, for a private repo when the token
                // is expired or lost a scope — so a bare 404 is an auth problem
                // far more often than a wrong repo name. Say both. `gh pr list`
                // goes through GraphQL, which words the same case as
                // "Could not resolve to a Repository".
                lastFetchError = "No access — run: gh auth login (or check the repo name)"
            } else if !errStr.isEmpty {
                lastFetchError = String(errStr.prefix(120))
            }
            return nil
        }
        lastFetchError = nil
        return res.out
    } catch {
        log.error("Failed to launch gh: \(error.localizedDescription)")
        lastFetchError = "Failed to run gh: \(error.localizedDescription)"
        return nil
    }
}

func ghStr(_ args: String...) -> String? {
    guard FileManager.default.isExecutableFile(atPath: GH) else {
        let msg = "GitHub CLI not found at \(GH)"
        log.error("\(msg)"); lastFetchError = msg
        return nil
    }
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: GH)
    proc.arguments = Array(args)
    proc.environment = ghEnv
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice
    do {
        try proc.run()
        // Read to EOF before waiting so large outputs can't deadlock the pipe.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let s = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s?.isEmpty == false ? s : nil
    } catch { return nil }
}

let RUN_JQ = "{id, name, displayTitle: .display_title, status, conclusion, headBranch: .head_branch, headSha: .head_sha, event, url: .html_url, updatedAt: .updated_at, createdAt: .created_at, startedAt: .run_started_at, number: .run_number, workflowName: .name, actorLogin: .actor.login, attempt: .run_attempt}"

// nil means the fetch failed, which a targeted refresh must not treat as "no runs".
func fetchRuns(repo: String) -> [Run]? {
    guard let data = ghShell("api", "repos/\(repo)/actions/runs?per_page=\(RUNS_PER_REPO)", "--jq", "[.workflow_runs[] | \(RUN_JQ)]")
    else { return nil }
    return (try? JSONDecoder().decode([Run].self, from: data)) ?? []
}

func fetchRun(repo: String, id: Int) -> Run? {
    guard let data = ghShell("api", "repos/\(repo)/actions/runs/\(id)", "--jq", RUN_JQ) else { return nil }
    return try? JSONDecoder().decode(Run.self, from: data)
}

// ─── Run Detail Fetching ─────────────────────────────────────────────────────

struct RunFailure {
    let job: String
    let step: String?
    let messages: [String]   // exact annotation messages from the checks API
}

struct RunJobStep: Decodable { let name: String; let conclusion: String? }
struct RunJob: Decodable { let id: Int; let name: String; let conclusion: String?; let steps: [RunJobStep]? }
struct CheckAnnotation: Decodable {
    let message: String?
    let path: String?
    let startLine: Int?
    let annotationLevel: String?
}

// Lazily-fetched run detail data. Main-thread access only.
var commitMsgCache: [String: String] = [:]       // head sha → full commit message
var failureCache: [Int: [RunFailure]] = [:]      // run id → failure summaries (stable once completed)
var detailFetchInFlight = Set<String>()

func fetchCommitMessage(repo: String, sha: String) -> String? {
    guard !sha.isEmpty,
          let data = ghShell("api", "repos/\(repo)/commits/\(sha)", "--jq", ".commit.message"),
          let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !s.isEmpty else { return nil }
    return s
}

// The failure message GitHub shows in its annotations box: list the run's jobs,
// and for each failed job pull its check-run annotations (a job's id IS its
// check-run id) plus the name of the step that failed.
func fetchRunFailures(repo: String, runId: Int) -> [RunFailure] {
    let jq = "[.jobs[] | {id, name, conclusion, steps: [.steps[]? | {name, conclusion}]}]"
    guard let data = ghShell("api", "repos/\(repo)/actions/runs/\(runId)/jobs?per_page=50", "--jq", jq),
          let jobs = try? JSONDecoder().decode([RunJob].self, from: data) else { return [] }
    var out: [RunFailure] = []
    for job in jobs where job.conclusion == "failure" {
        if out.count >= 3 { break }
        let step = job.steps?.first(where: { $0.conclusion == "failure" })?.name
        var msgs: [String] = []
        let ajq = "[.[] | {message, path, startLine: .start_line, annotationLevel: .annotation_level}]"
        if let aData = ghShell("api", "repos/\(repo)/check-runs/\(job.id)/annotations", "--jq", ajq),
           let anns = try? JSONDecoder().decode([CheckAnnotation].self, from: aData) {
            for a in anns where a.annotationLevel == "failure" {
                guard var m = a.message?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty else { continue }
                if m.count > 400 { m = String(m.prefix(400)) + "\u{2026}" }
                if let p = a.path, !p.isEmpty, p != ".github", let ln = a.startLine {
                    m = "\(p):\(ln)\n\(m)"
                }
                msgs.append(m)
                if msgs.count >= 3 { break }
            }
        }
        out.append(RunFailure(job: job.name, step: step, messages: msgs))
    }
    return out
}

func fetchPRs(repo: String) -> [PR] {
    let fields = "number,title,state,author,headRefName,baseRefName,url,createdAt,updatedAt,reviewDecision,additions,deletions,isDraft,labels,body"
    guard let data = ghShell("pr", "list", "--repo", repo, "--limit", "20", "--state", "open",
                             "--search", "review-requested:@me", "--json", fields)
    else { return [] }
    return (try? JSONDecoder().decode([PR].self, from: data)) ?? []
}

func executePRAction(repo: String, number: Int, action: PRAction, completion: @escaping () -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let n = "\(number)", r = repo
        var ok = true
        switch action {
        case .approve(let body):
            if let b = body, !b.isEmpty {
                ok = ghShell("pr", "review", "--approve", "-b", b, "-R", r, n) != nil
            } else {
                ok = ghShell("pr", "review", "--approve", "-R", r, n) != nil
            }
        case .requestChanges(let body):
            ok = ghShell("pr", "review", "--request-changes", "-b", body, "-R", r, n) != nil
        case .comment(let body):
            ok = ghShell("pr", "comment", "-b", body, "-R", r, n) != nil
        case .merge(let method):
            ok = ghShell("pr", "merge", method, "-R", r, n) != nil
        case .close:
            ok = ghShell("pr", "close", "-R", r, n) != nil
        }
        // ghShell sets lastFetchError on failure; surface it via the PR tab's error banner.
        if !ok {
            log.warning("PR action \(action) for \(r)#\(number) failed: \(lastFetchError ?? "unknown")")
        }
        DispatchQueue.main.async { completion() }
    }
}

func getGHUser() -> String? { ghStr("api", "user", "--jq", ".login") }

let isoFmt: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
}()
let isoFmtFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
}()

func parseISO(_ s: String?) -> Date? {
    guard let s = s, !s.isEmpty else { return nil }
    return isoFmtFrac.date(from: s) ?? isoFmt.date(from: s)
}

let timestampFmt: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "MMM d, h:mm a"; return f
}()

func fmtTimestamp(_ iso: String) -> String {
    guard let d = parseISO(iso) else { return "" }
    return timestampFmt.string(from: d)
}

func fmtDuration(_ secs: TimeInterval) -> String {
    let s = Int(max(0, secs))
    if s < 60 { return "\(s)s" }
    if s < 3600 { return "\(s/60)m \(s%60)s" }
    return "\(s/3600)h \(s/60%60)m"
}

func runDuration(_ r: Run) -> String {
    guard let s = parseISO(r.startedAt) ?? parseISO(r.createdAt),
          let e = parseISO(r.updatedAt) else { return "" }
    return fmtDuration(e.timeIntervalSince(s))
}

func runElapsed(_ r: Run) -> TimeInterval {
    guard let s = parseISO(r.startedAt) ?? parseISO(r.createdAt) else { return 0 }
    return -s.timeIntervalSinceNow
}

func estimatedTotal(for run: Run, history: [Run]) -> TimeInterval? {
    let wf = run.workflowName ?? run.name
    // Rolling 3-day window of completed runs of the same workflow.
    let cutoff = Date().addingTimeInterval(-3 * 24 * 3600)
    let completed = history.filter { r in
        guard (r.workflowName ?? r.name) == wf, r.status == "completed",
              let s = parseISO(r.startedAt) ?? parseISO(r.createdAt) else { return false }
        return s >= cutoff
    }
    let durs = completed.compactMap { r -> TimeInterval? in
        guard let s = parseISO(r.startedAt) ?? parseISO(r.createdAt),
              let e = parseISO(r.updatedAt) else { return nil }
        let d = e.timeIntervalSince(s); return d > 0 ? d : nil
    }
    guard !durs.isEmpty else { return nil }
    return durs.reduce(0, +) / Double(durs.count)
}

let startedFmt: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
}()

// "Started 11:56 am" / "Started yesterday 3:04 pm" / "Started May 12, 9:01 am"
func fmtStartedAt(_ iso: String?) -> String {
    guard let d = parseISO(iso) else { return "" }
    let cal = Calendar.current
    if cal.isDateInToday(d) { return "Started \(startedFmt.string(from: d))" }
    if cal.isDateInYesterday(d) { return "Started yesterday \(startedFmt.string(from: d))" }
    return "Started \(timestampFmt.string(from: d))"
}

// Colour-blind-safe status palette (Okabe-Ito). Hues separate on the blue–yellow
// axis so they stay distinguishable under deutan/protan/tritan vision; shape and
// text carry the state as well, colour is never the only signal.
let C_SUCCESS = NSColor(srgbRed: 0.00, green: 0.62, blue: 0.45, alpha: 1)  // bluish green
let C_FAILURE = NSColor(srgbRed: 0.84, green: 0.37, blue: 0.00, alpha: 1)  // vermillion
let C_RUNNING = NSColor(srgbRed: 0.34, green: 0.71, blue: 0.91, alpha: 1)  // sky blue
let C_QUEUED  = NSColor(srgbRed: 0.90, green: 0.62, blue: 0.00, alpha: 1)  // amber

func statusText(_ r: Run) -> String {
    switch r.status {
    case "in_progress": return "In progress"
    case "queued", "waiting", "pending": return "Queued"
    case "completed":
        switch r.conclusion ?? "" {
        case "success": return "Succeeded"
        case "failure": return "Failed"
        case "cancelled": return "Cancelled"
        case "skipped": return "Skipped"
        default: return "Completed"
        }
    default: return r.status
    }
}

func sfName(_ r: Run) -> String {
    switch r.status {
    case "in_progress": return "hourglass.circle.fill"
    case "queued", "waiting", "pending": return "clock.fill"
    case "completed":
        switch r.conclusion ?? "" {
        case "success": return "checkmark.circle.fill"
        case "failure": return "xmark.circle.fill"
        case "cancelled": return "minus.circle.fill"
        case "skipped": return "forward.fill"
        default: return "questionmark.circle"
        }
    default: return "questionmark.circle"
    }
}

func sfColor(_ r: Run) -> NSColor {
    switch r.status {
    case "in_progress": return C_RUNNING
    case "queued", "waiting", "pending": return C_QUEUED
    case "completed":
        switch r.conclusion ?? "" {
        case "success": return C_SUCCESS
        case "failure": return C_FAILURE
        default: return .systemGray
        }
    default: return .secondaryLabelColor
    }
}

// Overall state for the menu bar: tint colour + badge glyph + readable label.
// The glyph shape carries the state so the icon works without colour perception.
func overallStatus(_ g: [(String, [Run])]) -> (color: NSColor, badge: String?, label: String) {
    let all = g.flatMap { $0.1 }
    if all.isEmpty { return (.secondaryLabelColor, nil, "No runs") }
    if all.contains(where: { $0.status == "in_progress" || $0.status == "queued" }) {
        return (C_RUNNING, "hourglass.circle.fill", "Run in progress")
    }
    let key = all.filter {
        let wf = ($0.workflowName ?? $0.name).lowercased()
        return wf.contains("deploy") || wf.contains("smoke")
    }
    if let top = (key.isEmpty ? all : key).first, top.isFailure, !IGNORED.contains(top) {
        return (C_FAILURE, "xmark.circle.fill", "Run failed")
    }
    return (C_SUCCESS, "checkmark.circle.fill", "All runs passing")
}

func hasActive(_ g: [(String, [Run])]) -> Bool {
    g.flatMap { $0.1 }.contains { $0.status == "in_progress" || $0.status == "queued" }
}

// The rows the Actions list actually renders. The menu bar icon must agree with this,
// or it pulses for runs the user can't see (feature-branch runs under "Main/develop only").
func visibleRuns(_ runs: [Run]) -> [Run] {
    FILTER_DEFAULT_BRANCHES ? runs.filter { DEFAULT_BRANCHES.contains($0.headBranch) } : runs
}

// Every consumer of "is anything running" must go through this. The poll cadence
// included: a hidden feature-branch run polling every 10s behind an idle-looking
// icon is exactly the drain the render-server pulse rewrite set out to remove.
func visibleGrouped(_ g: [(String, [Run])]) -> [(String, [Run])] {
    g.map { ($0.0, visibleRuns($0.1)) }
}

// Repos with an active run come first, then by newest visible run. Repos without runs go last.
func sortedByRecent(_ g: [(String, [Run])]) -> [(String, [Run])] {
    func latest(_ runs: [Run]) -> Date {
        visibleRuns(runs).compactMap { parseISO($0.createdAt) }.max() ?? .distantPast
    }
    let keyed = g.map { (repo: $0, active: hasActive([($0.0, visibleRuns($0.1))]), latest: latest($0.1)) }
    return keyed.sorted { a, b in
        if a.active != b.active { return a.active }
        return a.latest > b.latest
    }.map { $0.repo }
}

// Replaces the entries of the refreshed repos and keeps the order of `order`.
func mergeGrouped<T>(_ old: [(String, [T])], _ fresh: [(String, [T])], order: [String]) -> [(String, [T])] {
    var byRepo = Dictionary(old.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
    for (repo, items) in fresh { byRepo[repo] = items }
    return order.map { ($0, byRepo[$0] ?? []) }
}

// ─── Deploy Log & Weekly Report ──────────────────────────────────────────────
// Append-only history of every completed workflow run we witness while polling.
// Costs no extra gh calls — it reuses data already fetched each refresh. Feeds the
// Insights tab (last-7-days vs prior-7 stats + heuristics) and a markdown export
// you can paste into an AI agent to act on.

let DEPLOY_LOG_PATH = (CONFIG_DIR as NSString).appendingPathComponent("deploys.jsonl")

struct DeployRecord: Codable {
    let repo: String
    let workflow: String
    let title: String
    let branch: String
    let event: String
    let conclusion: String
    let actor: String
    let url: String
    let number: Int
    let startedAt: String?
    let completedAt: String
    let durationSec: Double
    let loggedAt: String
}

func isDeployWorkflow(_ name: String) -> Bool {
    let n = name.lowercased()
    return n.contains("deploy") || n.contains("release") || n.contains("smoke")
}

final class DeployLog {
    static let shared = DeployLog()
    private let q = DispatchQueue(label: "com.flarco.cat-eye.deploylog")
    private var seen = Set<String>()
    private var loaded = false

    // Dedup on url+conclusion so a re-run that flips failure→success logs both events
    // (honest for flakiness insights) while stable polls of the same result don't dup.
    private func key(_ url: String, _ conclusion: String) -> String { "\(url)|\(conclusion)" }

    private func readRaw() -> String {
        (try? String(contentsOfFile: DEPLOY_LOG_PATH, encoding: .utf8)) ?? ""
    }

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        for r in DeployLog.parse(readRaw()) { seen.insert(key(r.url, r.conclusion)) }
    }

    static func parse(_ raw: String) -> [DeployRecord] {
        let dec = JSONDecoder()
        return raw.split(separator: "\n").compactMap {
            guard let d = $0.data(using: .utf8) else { return nil }
            return try? dec.decode(DeployRecord.self, from: d)
        }
    }

    // Append newly-seen completed runs. Safe to call every refresh.
    func record(_ grouped: [(String, [Run])]) {
        q.async {
            self.ensureLoaded()
            let now = isoFmt.string(from: Date())
            let enc = JSONEncoder()
            var lines: [String] = []
            for (repo, runs) in grouped {
                for r in runs where r.status == "completed" {
                    let concl = r.conclusion ?? "unknown"
                    let k = self.key(r.url, concl)
                    if self.seen.contains(k) { continue }
                    self.seen.insert(k)
                    var dur = 0.0
                    if let s = parseISO(r.startedAt) ?? parseISO(r.createdAt),
                       let e = parseISO(r.updatedAt) { dur = max(0, e.timeIntervalSince(s)) }
                    let rec = DeployRecord(repo: repo, workflow: r.workflowName ?? r.name,
                        title: r.displayTitle, branch: r.headBranch, event: r.event,
                        conclusion: concl, actor: r.actorLogin ?? "", url: r.url, number: r.number,
                        startedAt: r.startedAt, completedAt: r.updatedAt, durationSec: dur, loggedAt: now)
                    if let d = try? enc.encode(rec), let s = String(data: d, encoding: .utf8) {
                        lines.append(s)
                    }
                }
            }
            guard !lines.isEmpty else { return }
            try? FileManager.default.createDirectory(atPath: CONFIG_DIR, withIntermediateDirectories: true)
            let text = lines.joined(separator: "\n") + "\n"
            if let h = FileHandle(forWritingAtPath: DEPLOY_LOG_PATH) {
                h.seekToEndOfFile()
                if let d = text.data(using: .utf8) { h.write(d) }
                try? h.close()
            } else {
                try? text.write(toFile: DEPLOY_LOG_PATH, atomically: true, encoding: .utf8)
            }
            log.info("DeployLog: appended \(lines.count) record(s)")
        }
    }

    func all() -> [DeployRecord] { DeployLog.parse(q.sync { readRaw() }) }
}
// ponytail: log file + in-memory seen-set grow unbounded; fine for a personal tool
// (~300B/record). Add rotation/pruning only if it ever gets large.

struct WFStat {
    let workflow: String
    var isDeploy = false
    var total = 0
    var success = 0
    var failure = 0
    var durations: [Double] = []
    var failRate: Double { total > 0 ? Double(failure) / Double(total) : 0 }
    var avgDuration: Double? { durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count) }
}

struct WindowStats {
    var total = 0, success = 0, failure = 0, cancelled = 0, other = 0
    var durations: [Double] = []
    var deployTotal = 0, deploySuccess = 0, deployFailure = 0
    var deployDurations: [Double] = []
    var byWorkflow: [String: WFStat] = [:]
    var branchFailures: [String: Int] = [:]

    var passRate: Double? { let d = success + failure; return d > 0 ? Double(success) / Double(d) : nil }
    var deployPassRate: Double? { let d = deploySuccess + deployFailure; return d > 0 ? Double(deploySuccess) / Double(d) : nil }
    var avgDuration: Double? { durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count) }
}

func recordsInWindow(_ recs: [DeployRecord], from: Date, to: Date) -> [DeployRecord] {
    recs.filter {
        guard let d = parseISO($0.completedAt) else { return false }
        return d >= from && d < to
    }
}

func computeWindow(_ recs: [DeployRecord]) -> WindowStats {
    var s = WindowStats()
    for r in recs {
        s.total += 1
        let dep = isDeployWorkflow(r.workflow)
        if dep { s.deployTotal += 1 }
        switch r.conclusion {
        case "success":
            s.success += 1; if dep { s.deploySuccess += 1 }
        case "failure":
            s.failure += 1; if dep { s.deployFailure += 1 }
            s.branchFailures[r.branch, default: 0] += 1
        case "cancelled": s.cancelled += 1
        default: s.other += 1
        }
        if r.durationSec > 0 {
            s.durations.append(r.durationSec)
            if dep { s.deployDurations.append(r.durationSec) }
        }
        var wf = s.byWorkflow[r.workflow] ?? WFStat(workflow: r.workflow)
        wf.isDeploy = dep
        wf.total += 1
        if r.conclusion == "success" { wf.success += 1 }
        if r.conclusion == "failure" { wf.failure += 1 }
        if r.durationSec > 0 { wf.durations.append(r.durationSec) }
        s.byWorkflow[r.workflow] = wf
    }
    return s
}

func pct(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }

func generateInsights(this t: WindowStats, last l: WindowStats) -> [String] {
    var out: [String] = []
    if let p = t.passRate {
        var s = "Pass rate \(pct(p)) (\(t.success)/\(t.success + t.failure) runs)"
        if let lp = l.passRate {
            let d = (p - lp) * 100
            if abs(d) >= 1 { s += String(format: ", %@%.0f pts vs prior week", d >= 0 ? "up " : "down ", abs(d)) }
        }
        out.append(s + ".")
    }
    let failing = t.byWorkflow.values.filter { $0.total >= 3 && $0.failure > 0 }.sorted { $0.failRate > $1.failRate }
    if let w = failing.first, w.failRate >= 0.2 {
        out.append("\(w.workflow) failed \(pct(w.failRate)) of \(w.total) runs — your top failure source. Look at flaky steps, add retries, or gate it.")
    }
    let slow = t.byWorkflow.values.filter { ($0.avgDuration ?? 0) > 0 }.max { ($0.avgDuration ?? 0) < ($1.avgDuration ?? 0) }
    if let w = slow, let a = w.avgDuration, a > 300 {
        out.append("\(w.workflow) is your slowest at \(fmtDuration(a)) avg — consider caching dependencies or splitting jobs.")
    }
    if t.failure >= 3, let top = t.branchFailures.max(by: { $0.value < $1.value }), top.value >= 2 {
        let share = Double(top.value) / Double(t.failure)
        if share >= 0.5 { out.append("\(pct(share)) of failures were on `\(top.key)` (\(top.value) of \(t.failure)).") }
    }
    if l.total > 0 {
        let d = t.total - l.total
        out.append("\(t.total) runs this week (\(d >= 0 ? "+" : "")\(d) vs prior).")
    }
    if let a = t.avgDuration, let b = l.avgDuration, abs(a - b) >= 5 {
        out.append("Avg run time \(fmtDuration(a)) (\(a <= b ? "down " : "up ")\(fmtDuration(abs(a - b))) vs prior).")
    }
    if out.isEmpty { out.append("Not enough history yet — keep Cat Eye running and check back after a few days.") }
    return out
}

func buildAIReport(this t: WindowStats, last l: WindowStats, insights: [String], thisRecs: [DeployRecord]) -> String {
    func cell(_ s: String?) -> String { s ?? "—" }
    var md = "# Cat Eye — Weekly Deploy Report\n\nWindow: last 7 days vs the 7 days before.\n\n## Summary\n\n"
    md += "| Metric | This week | Prior week |\n|---|---|---|\n"
    md += "| Runs | \(t.total) | \(l.total) |\n"
    md += "| Pass rate | \(cell(t.passRate.map(pct))) | \(cell(l.passRate.map(pct))) |\n"
    md += "| Failures | \(t.failure) | \(l.failure) |\n"
    md += "| Avg duration | \(cell(t.avgDuration.map(fmtDuration))) | \(cell(l.avgDuration.map(fmtDuration))) |\n"
    md += "| Deploy/smoke runs | \(t.deployTotal) | \(l.deployTotal) |\n"
    md += "| Deploy pass rate | \(cell(t.deployPassRate.map(pct))) | \(cell(l.deployPassRate.map(pct))) |\n\n"
    md += "## Per-workflow (this week)\n\n| Workflow | Runs | Failures | Fail % | Avg duration |\n|---|---|---|---|---|\n"
    for w in t.byWorkflow.values.sorted(by: { $0.total > $1.total }) {
        md += "| \(w.workflow)\(w.isDeploy ? " (deploy)" : "") | \(w.total) | \(w.failure) | \(pct(w.failRate)) | \(cell(w.avgDuration.map(fmtDuration))) |\n"
    }
    md += "\n## Insights\n\n"
    for i in insights { md += "- \(i)\n" }
    let fails = thisRecs.filter { $0.conclusion == "failure" }
    if !fails.isEmpty {
        md += "\n## Failed runs (this week)\n\n"
        for f in fails.prefix(50) { md += "- \(f.workflow) on `\(f.branch)` (\(f.event)) — \(f.url)\n" }
    }
    md += "\n---\nTask for the agent: analyze the above and propose concrete, prioritized changes to the CI/CD config, tooling, or code that would cut failures and speed up runs. Favor high-impact, low-effort fixes.\n"
    return md
}

func textHeight(_ s: String, font: NSFont, width: CGFloat) -> CGFloat {
    let r = (s as NSString).boundingRect(
        with: NSSize(width: width, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: [.font: font])
    return ceil(r.height)
}

// Runnable check: `cat-eye --selftest` exercises the report math without a UI.
func runSelfTest() {
    func check(_ cond: Bool, _ msg: String) {
        if !cond { FileHandle.standardError.write(("SELFTEST FAIL: " + msg + "\n").data(using: .utf8)!); exit(1) }
    }
    func rec(_ wf: String, _ concl: String, _ dur: Double, _ branch: String = "main", ago: Double) -> DeployRecord {
        let iso = isoFmt.string(from: Date().addingTimeInterval(-ago))
        return DeployRecord(repo: "o/r", workflow: wf, title: "t", branch: branch, event: "push",
            conclusion: concl, actor: "me", url: "u/\(wf)/\(concl)/\(ago)", number: 1,
            startedAt: iso, completedAt: iso, durationSec: dur, loggedAt: iso)
    }
    let day = 86400.0
    let recs = [
        rec("deploy", "success", 120, ago: 1 * day),
        rec("deploy", "failure", 100, ago: 2 * day),
        rec("deploy", "failure", 90, ago: 3 * day),
        rec("test", "success", 600, ago: 1 * day),
        rec("deploy", "success", 130, ago: 9 * day),
        rec("deploy", "success", 140, ago: 10 * day),
    ]
    let now = Date()
    let thisR = recordsInWindow(recs, from: now.addingTimeInterval(-7 * day), to: now.addingTimeInterval(1))
    let lastR = recordsInWindow(recs, from: now.addingTimeInterval(-14 * day), to: now.addingTimeInterval(-7 * day))
    check(thisR.count == 4, "this window count \(thisR.count)")
    check(lastR.count == 2, "last window count \(lastR.count)")
    let tw = computeWindow(thisR)
    check(tw.total == 4 && tw.success == 2 && tw.failure == 2, "counts")
    check(tw.deployTotal == 3 && tw.deployFailure == 2, "deploy counts")
    check(abs((tw.passRate ?? 0) - 0.5) < 0.001, "pass rate \(tw.passRate ?? -1)")
    check(tw.branchFailures["main"] == 2, "branch failures")
    let ins = generateInsights(this: tw, last: computeWindow(lastR))
    check(ins.contains { $0.contains("slowest") }, "slowest insight present")
    check(ins.contains { $0.contains("failure source") }, "failure insight present")
    let md = buildAIReport(this: tw, last: computeWindow(lastR), insights: ins, thisRecs: thisR)
    check(md.contains("Weekly Deploy Report") && md.contains("Failed runs"), "markdown")

    // The visibility rule the icon AND the poll cadence both depend on.
    func run(_ branch: String, _ status: String) -> Run {
        Run(id: 1, name: "ci", displayTitle: "t", status: status, conclusion: nil,
            headBranch: branch, headSha: "s", event: "push", url: "u/\(branch)",
            updatedAt: "", createdAt: "", startedAt: nil, number: 1,
            workflowName: "ci", actorLogin: nil)
    }
    let bad = Run(id: 2, name: "ci", displayTitle: "t", status: "completed",
                  conclusion: "failure", headBranch: "main", headSha: "s", event: "push", url: "u/selftest-ignore",
                  updatedAt: "", createdAt: "", startedAt: nil, number: 2, workflowName: "ci", actorLogin: nil, attempt: 1)
    check(overallStatus([("o/r", [bad])]).color == C_FAILURE, "failed run turns the icon red")
    IGNORED.set([bad], ignored: true)
    check(overallStatus([("o/r", [bad])]).color == C_SUCCESS, "ignored failure does not turn the icon red")
    var again = bad; again.attempt = 2
    check(!IGNORED.contains(again), "a new attempt is not ignored")
    IGNORED.set([bad], ignored: false)
    check(Badge("main", maxChars: 15).subviews.compactMap { $0 as? NSTextField }.first?.stringValue == "main", "short branch is not cut")
    check(Badge("dependabot/npm/lodash-4.17", maxChars: 15).subviews.compactMap { $0 as? NSTextField }.first?.stringValue == "dependa\u{2026}sh-4.17", "long branch keeps both ends")
    func dispatch(_ wf: String, _ sha: String) -> Run {
        Run(id: 3, name: wf, displayTitle: "t", status: "completed", conclusion: "success",
            headBranch: "main", headSha: sha, event: "workflow_dispatch", url: "u/\(wf)/\(sha)",
            updatedAt: "", createdAt: "", startedAt: nil, number: 1, workflowName: wf, actorLogin: "a")
    }
    let rows = groupRuns([dispatch("Deploy", "s2"), dispatch("Deploy", "s1"), dispatch("Deploy", "s1"), dispatch("Build", "s1")])
    check(rows.map(\.count) == [1, 1, 2], "dispatches on other commits or of the same workflow get their own row")
    let g = [("o/r", [run("feature-x", "in_progress"), run("main", "completed")])]
    FILTER_DEFAULT_BRANCHES = false
    check(hasActive(visibleGrouped(g)), "unfiltered: feature-branch run is active")
    FILTER_DEFAULT_BRANCHES = true
    check(visibleGrouped(g)[0].1.count == 1, "filtered: only default-branch rows visible")
    check(!hasActive(visibleGrouped(g)), "filtered: hidden run must not force the fast poll")
    FILTER_DEFAULT_BRANCHES = false

    func runAt(_ created: String, _ status: String = "completed") -> Run {
        Run(id: 1, name: "ci", displayTitle: "t", status: status, conclusion: nil,
            headBranch: "main", headSha: "s", event: "push", url: "u",
            updatedAt: created, createdAt: created, startedAt: nil, number: 1,
            workflowName: "ci", actorLogin: nil)
    }
    let unsorted = [("o/old", [runAt("2026-01-01T00:00:00Z")]),
                    ("o/none", []),
                    ("o/new", [runAt("2026-03-01T00:00:00Z")]),
                    ("o/busy", [runAt("2025-01-01T00:00:00Z", "in_progress")])]
    check(sortedByRecent(unsorted).map { $0.0 } == ["o/busy", "o/new", "o/old", "o/none"], "recent sort order")

    // Live updates: partial refresh merge keeps the other repos and the REPOS order.
    let oldG = [("o/a", [runAt("2026-01-01T00:00:00Z")]), ("o/b", [runAt("2026-01-02T00:00:00Z")])]
    let merged = mergeGrouped(oldG, [("o/b", [])], order: ["o/a", "o/b", "o/c"])
    check(merged.map { $0.0 } == ["o/a", "o/b", "o/c"], "merge order")
    check(merged[0].1.count == 1 && merged[1].1.isEmpty && merged[2].1.isEmpty, "merge replaces only refreshed repos")

    // detectTransitions(partial:) keeps the statuses of repos it did not refresh.
    func runURL(_ url: String, _ status: String) -> Run {
        Run(id: 1, name: "ci", displayTitle: "t", status: status, conclusion: "success",
            headBranch: "main", headSha: "s", event: "push", url: url,
            updatedAt: "", createdAt: "", startedAt: nil, number: 1, workflowName: "ci", actorLogin: nil)
    }
    let bar = GHActionsBar()
    bar.grouped = [("o/a", [runURL("a1", "completed")]), ("o/b", [runURL("b1", "completed")])]
    bar.detectTransitions(bar.grouped)
    bar.firstLoad = false
    bar.detectTransitions([("o/a", [runURL("a2", "completed")])], partial: true)
    check(bar.prevStatuses["b1"] == "completed", "partial transitions keep other repos")
    check(bar.prevStatuses["a2"] == "completed" && bar.prevStatuses["a1"] == nil, "partial transitions replace refreshed repo")

    var ids = RecentIDs(capacity: 2)
    ids.insert("x"); ids.insert("y"); ids.insert("x"); ids.insert("z")
    check(!ids.contains("x") && ids.contains("y") && ids.contains("z"), "dedupe buffer evicts oldest")

    var bo = Backoff()
    let delays = (0..<8).map { _ in bo.next(jitter: 0) }
    check(delays == [1, 2, 4, 8, 16, 32, 60, 60], "backoff \(delays)")
    bo.reset()
    check(bo.next(jitter: 0.2) == 1.2, "backoff jitter")

    let deployOut = """
    Total Upload: 13.02 KiB / gzip: 4.28 KiB
    Uploaded cat-eye-relay (3.1 sec)
    Deployed cat-eye-relay triggers (0.4 sec)
      https://cat-eye-relay.fritz-1.workers.dev
    Current Version ID: 0f1e
    """
    check(RelayDeployer.parseWorkerURL(deployOut) == "https://cat-eye-relay.fritz-1.workers.dev", "deploy URL parser")
    check(RelayDeployer.parseWorkerURL("no url") == nil, "deploy URL parser without URL")
    let who = RelayDeployer.parseWhoami("""
    {"loggedIn": true, "email": "me@x.dev", "accounts": [{"id": "abc", "name": "Mine"}, {"id": "def", "name": "Work"}]}
    """)
    check(who?.email == "me@x.dev" && who?.accounts.map { $0.id } == ["abc", "def"], "whoami parser")
    check(RelayDeployer.parseWhoami("{\"loggedIn\": false}") == nil, "whoami parser logged out")
    check(RelayDeployer.parseSecretNames("""
    [{"name": "DEVICE_AB12", "type": "secret_text"}, {"name": "WEBHOOK_SECRET", "type": "secret_text"}]
    """) == ["DEVICE_AB12", "WEBHOOK_SECRET"], "secret list parser")

    let token = String(repeating: "ab12", count: 16)
    check(maskSecrets("put \(token) done") == "put •••• done", "secret masking")
    check(maskSecrets("deploy abc123") == "deploy abc123", "masking leaves short hex")
    check(stripANSI("\u{1B}[32mok\u{1B}[0m") == "ok", "ANSI stripping")

    let noon = Date(timeIntervalSince1970: 86400 * 100 + 43200)
    let q = WriteQuota(rowsToday: 40_000, now: noon)
    check(q.projected == 80_000 && q.warn, "quota projection \(q.projected)")
    check(!WriteQuota(rowsToday: 1_000, now: noon).warn, "quota no warning")
    let repos = ["O/Hooked", "O/Bare", "O/Denied", "O/Waiting"]
    let sts: [String: HookStatus] = ["O/Denied": .pollingOnly("x"), "O/Waiting": .waiting]
    check(RelayDeployer.unhooked(repos, hooked: nil, statuses: sts).isEmpty, "unhooked unknown before health")
    let rl = try? JSONDecoder().decode(RateLimit.self, from: Data("""
        {"resources":{"core":{"limit":5000,"used":3600,"remaining":1400,"reset":1},
        "graphql":{"limit":5000,"used":100,"reset":1},"search":{"limit":30,"used":30,"reset":1}}}
        """.utf8))
    check(rl?.percent == 72 && rl?.color == C_QUEUED, "rate limit uses the fullest of REST and GraphQL")
    check(RelayDeployer.unhooked(repos, hooked: ["o/hooked", "o/denied"], statuses: sts) == ["O/Bare", "O/Denied"],
          "unhooked repos")

    print("SELFTEST OK — \(ins.count) insights, report \(md.count) chars")
}

// ─── PR Helpers ──────────────────────────────────────────────────────────────

func prReviewIcon(_ pr: PR) -> String {
    if pr.isDraft { return "pencil.circle" }
    switch pr.reviewDecision ?? "" {
    case "APPROVED": return "checkmark.circle.fill"
    case "CHANGES_REQUESTED": return "xmark.circle.fill"
    case "REVIEW_REQUIRED": return "circle.badge.questionmark"
    default: return "circle.dashed"
    }
}

func prReviewColor(_ pr: PR) -> NSColor {
    if pr.isDraft { return .systemGray }
    switch pr.reviewDecision ?? "" {
    case "APPROVED": return C_SUCCESS
    case "CHANGES_REQUESTED": return C_FAILURE
    case "REVIEW_REQUIRED": return C_QUEUED
    default: return .secondaryLabelColor
    }
}

func prRelativeTime(_ iso: String) -> String {
    guard let d = parseISO(iso) else { return "" }
    return relativeTime(d)
}

func relativeTime(_ d: Date) -> String {
    let secs = -d.timeIntervalSinceNow
    if secs < 60 { return "just now" }
    if secs < 3600 { return "\(Int(secs/60))m ago" }
    if secs < 86400 { return "\(Int(secs/3600))h ago" }
    return "\(Int(secs/86400))d ago"
}

let PR_ROW_H: CGFloat = 56

// ─── Icon ────────────────────────────────────────────────────────────────────

func loadGHIcon() -> NSImage? {
    guard let data = Data(base64Encoded: GH_ICON_B64), let img = NSImage(data: data) else { return nil }
    img.isTemplate = true
    img.size = NSSize(width: 18, height: 18)
    return img
}

func tintedIcon(_ base: NSImage?, _ color: NSColor) -> NSImage {
    guard let base = base else { return NSImage() }
    let img = NSImage(size: base.size, flipped: false) { rect in
        base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        color.set()
        rect.fill(using: .sourceAtop)
        return true
    }
    img.isTemplate = false
    return img
}

// Menu bar icon with a small status glyph (check / cross / hourglass) punched into
// the bottom-right corner — the shape conveys state independently of the tint colour.
func statusBadgedIcon(_ base: NSImage?, color: NSColor, badge: String?) -> NSImage {
    guard let base = base else { return NSImage() }
    let sz = base.size
    let img = NSImage(size: sz, flipped: false) { rect in
        base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        color.set()
        rect.fill(using: .sourceAtop)
        guard let name = badge,
              let sym = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return true }
        let b: CGFloat = 10
        let bRect = NSRect(x: sz.width - b, y: 0, width: b, height: b)
        // Punch a clear ring so the badge separates from the cat silhouette.
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.saveGState()
            ctx.setBlendMode(.destinationOut)
            NSColor.black.set()
            NSBezierPath(ovalIn: bRect.insetBy(dx: -1.5, dy: -1.5)).fill()
            ctx.restoreGState()
        }
        let tinted = NSImage(size: bRect.size, flipped: false) { r in
            sym.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1.0)
            color.set()
            r.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: bRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        return true
    }
    img.isTemplate = false
    return img
}

// ─── GitHub rate limit ───────────────────────────────────────────────────────

struct RateLimit: Decodable {
    struct Bucket: Decodable {
        let limit: Int, used: Int, reset: TimeInterval
        var fraction: Double { limit > 0 ? Double(used) / Double(limit) : 0 }
    }
    let resources: [String: Bucket]

    // Runs use REST and PRs use GraphQL. Show the bucket nearest its limit.
    var buckets: [(name: String, bucket: Bucket)] {
        [("REST", resources["core"]), ("GraphQL", resources["graphql"])].compactMap { n, b in b.map { (n, $0) } }
    }
    var fraction: Double { buckets.map { $0.bucket.fraction }.max() ?? 0 }
    var percent: Int { Int((fraction * 100).rounded()) }
    var color: NSColor { fraction >= 0.9 ? C_FAILURE : fraction >= 0.7 ? C_QUEUED : .secondaryLabelColor }

    var tooltip: String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        let lines = buckets.map { n, b in
            "\(n): \(b.used) / \(b.limit) (\(Int((b.fraction * 100).rounded()))%), resets \(f.string(from: Date(timeIntervalSince1970: b.reset)))"
        }
        return (["GitHub API quota used this hour"] + lines).joined(separator: "\n")
    }
}

// Reads the quota every 10 minutes. The rate_limit endpoint does not count against it.
final class RateLimitMonitor {
    private(set) var latest: RateLimit?
    var onChange: (() -> Void)?
    private var timer: Timer?

    func start() {
        fetch()
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in self?.fetch() }
        timer?.tolerance = 60
    }

    func fetch() {
        DispatchQueue.global(qos: .utility).async {
            guard let r = try? ghRun(["api", "rate_limit"]), r.status == 0,
                  let rl = try? JSONDecoder().decode(RateLimit.self, from: r.out) else { return }
            DispatchQueue.main.async { self.latest = rl; self.onChange?() }
        }
    }
}

// ─── Run Row View ────────────────────────────────────────────────────────────

class RunRow: NSView {
    let urlStr: String
    let repo: String
    let group: [Run]
    let expanded: Bool
    var onToggle: (() -> Void)?
    var trackingArea: NSTrackingArea?

    init(repo: String, group: [Run], history: [Run], w: CGFloat, expanded: Bool = false) {
        let primary = RunRow.pickPrimary(group)
        self.urlStr = primary.url
        self.repo = repo
        self.group = group
        self.expanded = expanded
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: ROW_H))
        wantsLayer = true
        layer?.backgroundColor = restingColor
        build(group: group, primary: primary, history: history, w: w)
    }
    required init?(coder: NSCoder) { fatalError() }

    var restingColor: CGColor? {
        expanded ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.1).cgColor : nil
    }

    // Pick the run that drives the status icon, click target, and elapsed/ETA.
    // Priority: in_progress (longest-running) > queued > completed-failure > anything else.
    static func pickPrimary(_ group: [Run]) -> Run {
        let inProg = group.filter { $0.status == "in_progress" }
        if let r = inProg.max(by: { runElapsed($0) < runElapsed($1) }) { return r }
        if let r = group.first(where: { $0.status == "queued" }) { return r }
        if let r = group.first(where: { $0.isFailure && !IGNORED.contains($0) }) { return r }
        return group[0]
    }

    func build(group: [Run], primary: Run, history: [Run], w: CGFloat) {
        let pad: CGFloat = 12, iconSz: CGFloat = 20
        let textX = pad + iconSz + 10, linkW: CGFloat = 28, copyW: CGFloat = 28
        let rightW: CGFloat = 165          // fixed allocation for start time + duration
        let rightX = w - rightW - linkW - copyW - 8
        let textW = rightX - textX - 8     // leave 8px gap before the right column

        let iv = NSImageView(frame: NSRect(x: pad, y: (ROW_H - iconSz) / 2, width: iconSz, height: iconSz))
        let ignored = IGNORED.contains(primary)
        let statusDesc = statusText(primary) + (ignored ? " (ignored)" : "")
        if let img = NSImage(systemSymbolName: sfName(primary), accessibilityDescription: statusDesc) {
            iv.image = img; iv.contentTintColor = ignored ? .systemGray : sfColor(primary)
            iv.symbolConfiguration = .init(pointSize: 14, weight: .semibold)
        }
        iv.toolTip = statusDesc
        addSubview(iv)

        let title = lbl(primary.displayTitle, .systemFont(ofSize: 12.5, weight: .semibold))
        title.frame = NSRect(x: textX, y: ROW_H - 24, width: textW, height: 18)
        title.lineBreakMode = .byTruncatingTail
        title.toolTip = primary.displayTitle
        addSubview(title)

        // Subtitle: branch badge + event + actor. For groups, the workflow list collapses to
        // "N workflows" and a small stack chip with a (done/total) progress counter sits at the front.
        let actor = primary.actorLogin.map { " by \($0)" } ?? ""
        var subX = textX
        var subRemaining = textW

        if group.count > 1 {
            let done = group.filter { $0.status == "completed" }.count
            let chip = makeGroupChip(done: done, total: group.count)
            chip.frame.origin = NSPoint(x: subX, y: 6)
            addSubview(chip)
            subX += chip.frame.width + 6
            subRemaining -= chip.frame.width + 6
        }

        if !primary.headBranch.isEmpty {
            // Branch gets its own badge. Names over 15 characters keep both ends,
            // and the tooltip shows the full name.
            let bb = Badge(primary.headBranch, maxChars: 15)
            bb.frame.origin = NSPoint(x: subX, y: 4)
            addSubview(bb)
            subX += bb.frame.width + 6
            subRemaining -= bb.frame.width + 6
        }

        let wf = primary.workflowName ?? primary.name
        let prefix = group.count > 1
            ? "\(group.count) workflows"
            : "\(wf) #\(primary.number)"
        let sub = lbl("\(prefix) \u{00B7} \(primary.event)\(actor)",
                      .systemFont(ofSize: 11), .secondaryLabelColor)
        sub.frame = NSRect(x: subX, y: 6, width: subRemaining, height: 16)
        sub.lineBreakMode = .byTruncatingTail
        sub.toolTip = sub.stringValue
        addSubview(sub)

        // Time column. For groups: earliest start, longest elapsed (driven by primary).
        let groupStart = group.compactMap { parseISO($0.startedAt) ?? parseISO($0.createdAt) }.min()
        let startedISO: String? = groupStart.map { isoFmt.string(from: $0) } ?? (primary.startedAt ?? primary.createdAt)

        let anyActive = group.contains { $0.status == "in_progress" || $0.status == "queued" }
        if anyActive {
            let elapsed = runElapsed(primary)
            let started = lbl(fmtStartedAt(startedISO), .systemFont(ofSize: 10.5), .secondaryLabelColor)
            started.alignment = .right
            started.frame = NSRect(x: rightX, y: ROW_H - 23, width: rightW, height: 14)
            addSubview(started)

            let el = lbl("\(fmtDuration(elapsed)) elapsed",
                         .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium), C_RUNNING)
            el.alignment = .right
            el.frame = NSRect(x: rightX, y: 22, width: rightW, height: 14)
            addSubview(el)

            var etaText = "estimating..."
            if let est = estimatedTotal(for: primary, history: history) {
                let rem = max(0, est - elapsed)
                etaText = rem > 0 ? "~\(fmtDuration(rem)) remaining" : "finishing..."
            }
            let eta = lbl(etaText, .systemFont(ofSize: 10), .secondaryLabelColor)
            eta.alignment = .right
            eta.frame = NSRect(x: rightX, y: 6, width: rightW, height: 14)
            addSubview(eta)
        } else {
            let started = lbl(fmtStartedAt(startedISO), .systemFont(ofSize: 10.5), .secondaryLabelColor)
            started.alignment = .right
            started.frame = NSRect(x: rightX, y: ROW_H - 23, width: rightW, height: 14)
            addSubview(started)

            // For groups: total wall-clock from earliest start to latest end.
            let durText: String
            if group.count > 1,
               let s = groupStart,
               let e = group.compactMap({ parseISO($0.updatedAt) }).max() {
                durText = fmtDuration(e.timeIntervalSince(s))
            } else {
                durText = runDuration(primary)
            }
            // Spell out non-success outcomes so state is readable without colour.
            let concl = primary.conclusion ?? ""
            let word: String? = ignored ? "Ignored" : ["failure": "Failed", "cancelled": "Cancelled", "skipped": "Skipped"][concl]
            let failed = concl == "failure" && !ignored
            let dur = lbl(word.map { "\($0) \u{00B7} \(durText)" } ?? durText,
                          .systemFont(ofSize: 10, weight: failed ? .semibold : .regular),
                          failed ? C_FAILURE : .secondaryLabelColor)
            dur.alignment = .right
            dur.frame = NSRect(x: rightX, y: 6, width: rightW, height: 14)
            addSubview(dur)
        }

        let lk = NSButton(frame: NSRect(x: w - linkW - copyW - 4, y: (ROW_H - 24) / 2, width: linkW, height: 24))
        if let img = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: "Open in GitHub") { lk.image = img }
        lk.bezelStyle = .recessed; lk.isBordered = false; lk.imagePosition = .imageOnly
        lk.target = self; lk.action = #selector(openURL); lk.toolTip = "Open run on GitHub"
        addSubview(lk)

        let cp = NSButton(frame: NSRect(x: w - copyW - 4, y: (ROW_H - 24) / 2, width: copyW, height: 24))
        if let img = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy URL") { cp.image = img }
        cp.bezelStyle = .recessed; cp.isBordered = false; cp.imagePosition = .imageOnly
        cp.target = self; cp.action = #selector(copyURL(_:)); cp.toolTip = "Copy run URL"
        addSubview(cp)

        let sep = NSView(frame: NSRect(x: textX, y: 0, width: w - textX - pad, height: 0.5))
        sep.wantsLayer = true; sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        addSubview(sep)
    }

    @objc func openURL() { if let u = URL(string: urlStr) { NSWorkspace.shared.open(u) } }

    // Right-click menu. Only completed runs can be re-run.
    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        let done = group.filter { $0.status == "completed" }
        let failed = group.filter { $0.isFailure }
        func item(_ title: String, _ action: Selector, _ runs: [Run], into menu: NSMenu? = nil) {
            let i = NSMenuItem(title: title, action: runs.isEmpty ? nil : action, keyEquivalent: "")
            i.target = self; i.representedObject = runs
            (menu ?? m).addItem(i)
        }
        if group.count > 1 {
            item("Re-run all workflows", #selector(rerun(_:)), done)
            item("Re-run failed jobs", #selector(rerunFailed(_:)), failed)
            let one = NSMenu()
            for r in group {
                let wf = r.workflowName ?? r.name
                item("\(wf) #\(r.number)", #selector(rerun(_:)), r.status == "completed" ? [r] : [], into: one)
                if r.isFailure { item("\(wf) #\(r.number): failed jobs", #selector(rerunFailed(_:)), [r], into: one) }
            }
            let sub = NSMenuItem(title: "Re-run one workflow", action: nil, keyEquivalent: "")
            sub.submenu = one
            m.addItem(sub)
        } else {
            item("Re-run workflow", #selector(rerun(_:)), done)
            item("Re-run failed jobs", #selector(rerunFailed(_:)), failed)
        }
        m.addItem(.separator())
        let allIgnored = !failed.isEmpty && failed.allSatisfy { IGNORED.contains($0) }
        item(allIgnored ? "Stop ignoring failure" : "Ignore failure", #selector(toggleIgnore(_:)), failed)
        m.addItem(.separator())
        item("Open on GitHub", #selector(openURL), group)
        item("Copy URL", #selector(copyURL(_:)), group)
        return m
    }

    @objc func rerun(_ sender: NSMenuItem) { app?.rerun(repo: repo, runs: sender.representedObject as? [Run] ?? [], failedOnly: false) }
    @objc func rerunFailed(_ sender: NSMenuItem) { app?.rerun(repo: repo, runs: sender.representedObject as? [Run] ?? [], failedOnly: true) }
    @objc func toggleIgnore(_ sender: NSMenuItem) {
        let runs = sender.representedObject as? [Run] ?? []
        app?.setIgnored(runs, ignored: !runs.allSatisfy { IGNORED.contains($0) })
    }
    var app: GHActionsBar? { NSApp.delegate as? GHActionsBar }

    func lbl(_ text: String, _ font: NSFont, _ color: NSColor = .labelColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = font; l.textColor = color; l.maximumNumberOfLines = 1
        l.cell?.truncatesLastVisibleLine = true; return l
    }

    // Subtle "stack + (done/total)" indicator for grouped workflow runs.
    func makeGroupChip(done: Int, total: Int) -> NSView {
        let countText = "\(done)/\(total)"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        let textW = (countText as NSString).size(withAttributes: [.font: font]).width
        let iconW: CGFloat = 11, gap: CGFloat = 3, padX: CGFloat = 5
        let w = padX + iconW + gap + textW + padX
        let chip = NSView(frame: NSRect(x: 0, y: 0, width: w, height: 16))

        let iv = NSImageView(frame: NSRect(x: padX, y: 2, width: iconW, height: 11))
        if let img = NSImage(systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: "\(total) workflows") {
            iv.image = img; iv.contentTintColor = .secondaryLabelColor
            iv.symbolConfiguration = .init(pointSize: 9, weight: .medium)
        }
        chip.addSubview(iv)

        let l = NSTextField(labelWithString: countText)
        l.font = font; l.textColor = .secondaryLabelColor
        l.frame = NSRect(x: padX + iconW + gap, y: 0, width: textW + 1, height: 14)
        chip.addSubview(l)
        chip.toolTip = "\(done) of \(total) workflows complete"
        return chip
    }

    @objc func copyURL(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlStr, forType: .string)
        if let btn = sender as? NSButton,
           let img = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil) {
            let orig = btn.image; btn.image = img; btn.contentTintColor = C_SUCCESS
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { btn.image = orig; btn.contentTintColor = nil }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(trackingArea!)
    }
    // Scrolling moves rows under a still pointer, so hover follows the real pointer position.
    override func mouseEntered(with event: NSEvent) { animateHover() }
    override func mouseExited(with event: NSEvent) { animateHover() }
    func animateHover() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15; ctx.allowsImplicitAnimation = true; syncHover()
        }
    }
    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.25).cgColor
    }
    override func mouseUp(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15; ctx.allowsImplicitAnimation = true; layer?.backgroundColor = restingColor
        }
        let loc = convert(event.locationInWindow, from: nil)
        guard bounds.contains(loc) else { return }
        for sub in subviews where sub is NSButton { if sub.frame.contains(loc) { return } }
        onToggle?()
    }

    func syncHover() {
        guard let win = window else { return }
        // visibleRect can extend past the row, so intersect it with bounds.
        let inside = bounds.intersection(visibleRect).contains(convert(win.mouseLocationOutsideOfEventStream, from: nil))
        layer?.backgroundColor = inside ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.15).cgColor : restingColor
    }

    // Keyboard accessibility
    override var acceptsFirstResponder: Bool { true }
    override var focusRingType: NSFocusRingType {
        get { .exterior }
        set {}
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 { // Return or Space
            onToggle?()
        } else { super.keyDown(with: event) }
    }
}

// ─── Run Detail View ─────────────────────────────────────────────────────────

// Inline expansion under a run row. Renders synchronously from the detail caches;
// TabVC kicks off background fetches and rebuilds when data lands.
class RunDetailView: Flipped {
    let urlStr: String

    init(group: [Run], primary: Run, repo: String, history: [Run], w: CGFloat) {
        self.urlStr = primary.url
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        let pad: CGFloat = 42, rPad: CGFloat = 16
        let contentW = w - pad - rPad
        var y: CGFloat = 10

        func wrapped(_ text: String, _ font: NSFont, _ color: NSColor, maxH: CGFloat, indent: CGFloat = 0) {
            let rect = (text as NSString).boundingRect(
                with: NSSize(width: contentW - indent, height: maxH),
                options: [.usesLineFragmentOrigin], attributes: [.font: font])
            let h = min(ceil(rect.height) + 2, maxH)
            let l = NSTextField(wrappingLabelWithString: text)
            l.font = font; l.textColor = color
            l.frame = NSRect(x: pad + indent, y: y, width: contentW - indent, height: h)
            l.isSelectable = true
            addSubview(l)
            y += h + 4
        }

        func infoLine(_ name: String, _ value: String, _ valueColor: NSColor = .labelColor) {
            let n = NSTextField(labelWithString: name)
            n.font = .systemFont(ofSize: 10.5); n.textColor = .tertiaryLabelColor
            n.frame = NSRect(x: pad, y: y, width: 80, height: 15)
            addSubview(n)
            let v = NSTextField(labelWithString: value)
            v.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium); v.textColor = valueColor
            v.frame = NSRect(x: pad + 84, y: y, width: contentW - 84, height: 15)
            v.isSelectable = true
            addSubview(v)
            y += 17
        }

        func divider() {
            let s = NSView(frame: NSRect(x: pad, y: y, width: contentW, height: 0.5))
            s.wantsLayer = true; s.layer?.backgroundColor = NSColor.separatorColor.cgColor
            addSubview(s); y += 7
        }

        // ── Full commit message ──
        let cachedMsg = commitMsgCache[primary.headSha]
        wrapped(cachedMsg ?? "Loading commit message\u{2026}",
                .systemFont(ofSize: 11.5),
                cachedMsg == nil ? .tertiaryLabelColor : .labelColor, maxH: 170)
        y += 3
        divider()

        // ── Timing ──
        let groupStart = group.compactMap { parseISO($0.startedAt) ?? parseISO($0.createdAt) }.min()
        let allDone = group.allSatisfy { $0.status == "completed" }
        let groupEnd = group.compactMap { parseISO($0.updatedAt) }.max()
        if let s = groupStart { infoLine("Started", timestampFmt.string(from: s)) }
        if allDone, let e = groupEnd {
            infoLine("Completed", timestampFmt.string(from: e))
            if let s = groupStart { infoLine("Duration", fmtDuration(e.timeIntervalSince(s))) }
        } else {
            infoLine("Elapsed", fmtDuration(runElapsed(primary)), C_RUNNING)
        }
        if let est = estimatedTotal(for: primary, history: history) {
            infoLine("Expected", "~\(fmtDuration(est))")
        }
        y += 3
        divider()

        // ── Workflows ──
        for run in group.prefix(8) {
            let iv = NSImageView(frame: NSRect(x: pad, y: y + 1, width: 13, height: 13))
            if let img = NSImage(systemSymbolName: sfName(run), accessibilityDescription: statusText(run)) {
                iv.image = img; iv.contentTintColor = sfColor(run)
                iv.symbolConfiguration = .init(pointSize: 9.5, weight: .semibold)
            }
            iv.toolTip = statusText(run)
            addSubview(iv)
            let name = NSTextField(labelWithString: "\(run.workflowName ?? run.name) #\(run.number)")
            name.font = .systemFont(ofSize: 11); name.textColor = .labelColor
            name.lineBreakMode = .byTruncatingTail; name.maximumNumberOfLines = 1
            name.frame = NSRect(x: pad + 19, y: y, width: contentW - 19 - 155, height: 15)
            addSubview(name)
            let stText: String
            switch run.status {
            case "completed": stText = "\(statusText(run)) \u{00B7} \(runDuration(run))"
            case "in_progress": stText = "\(fmtDuration(runElapsed(run))) elapsed"
            default: stText = statusText(run)
            }
            let st = NSTextField(labelWithString: stText)
            st.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            st.textColor = run.conclusion == "failure" ? C_FAILURE : .secondaryLabelColor
            st.alignment = .right
            st.frame = NSRect(x: pad + contentW - 150, y: y, width: 150, height: 15)
            addSubview(st)
            y += 18
        }
        if group.count > 8 {
            wrapped("+ \(group.count - 8) more workflows", .systemFont(ofSize: 10), .tertiaryLabelColor, maxH: 14)
        }

        // ── Failure details ──
        let failedRuns = group.filter { $0.conclusion == "failure" }
        if !failedRuns.isEmpty {
            y += 2
            divider()
            let hdr = NSTextField(labelWithString: "WHY IT FAILED")
            hdr.font = .systemFont(ofSize: 9.5, weight: .bold); hdr.textColor = C_FAILURE
            hdr.frame = NSRect(x: pad, y: y, width: contentW, height: 13)
            addSubview(hdr); y += 18
            for run in failedRuns.prefix(3) {
                if group.count > 1 {
                    wrapped(run.workflowName ?? run.name, .systemFont(ofSize: 10.5, weight: .semibold),
                            .labelColor, maxH: 16)
                }
                if let fails = failureCache[run.id] {
                    if fails.isEmpty {
                        wrapped("No failure annotations \u{2014} open the run on GitHub for full logs.",
                                .systemFont(ofSize: 10.5), .secondaryLabelColor, maxH: 30)
                    }
                    for f in fails {
                        let head = f.step.map { "\(f.job) \u{00B7} \($0)" } ?? f.job
                        wrapped(head, .systemFont(ofSize: 10.5, weight: .semibold), C_FAILURE, maxH: 32)
                        if f.messages.isEmpty {
                            wrapped("No annotation message \u{2014} see logs on GitHub.",
                                    .systemFont(ofSize: 10), .secondaryLabelColor, maxH: 14, indent: 10)
                        }
                        for m in f.messages {
                            wrapped(m, .monospacedSystemFont(ofSize: 10, weight: .regular),
                                    .labelColor, maxH: 110, indent: 10)
                        }
                    }
                } else {
                    wrapped("Fetching failure details\u{2026}", .systemFont(ofSize: 10.5),
                            .tertiaryLabelColor, maxH: 16)
                }
            }
        }

        // ── GitHub link ──
        y += 4
        let gh = NSButton(title: "View on GitHub", target: self, action: #selector(openGH))
        gh.bezelStyle = .inline; gh.font = .systemFont(ofSize: 11, weight: .medium)
        gh.contentTintColor = .linkColor
        gh.frame = NSRect(x: pad, y: y, width: 130, height: 22)
        addSubview(gh)
        y += 32

        frame = NSRect(x: 0, y: 0, width: w, height: y)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc func openGH() { if let u = URL(string: urlStr) { NSWorkspace.shared.open(u) } }
}

// ─── PR Row View ─────────────────────────────────────────────────────────────

class PRRow: NSView {
    let urlStr: String
    let expanded: Bool
    var onToggle: (() -> Void)?
    var trackingArea: NSTrackingArea?

    init(_ pr: PR, repo: String, w: CGFloat, expanded: Bool) {
        self.urlStr = pr.url
        self.expanded = expanded
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: PR_ROW_H))
        wantsLayer = true
        layer?.backgroundColor = restingColor
        build(pr, repo: repo, w: w)
    }
    required init?(coder: NSCoder) { fatalError() }

    var restingColor: CGColor? {
        expanded ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.1).cgColor : nil
    }

    func build(_ pr: PR, repo: String, w: CGFloat) {
        let pad: CGFloat = 12, iconSz: CGFloat = 20
        let textX = pad + iconSz + 10, linkW: CGFloat = 28, copyW: CGFloat = 28
        let rightW: CGFloat = 140
        let textW = w - textX - rightW - linkW - copyW

        // Review status icon
        let iv = NSImageView(frame: NSRect(x: pad, y: (PR_ROW_H - iconSz) / 2, width: iconSz, height: iconSz))
        let reviewDesc = pr.isDraft ? "Draft" : (pr.reviewDecision ?? "Pending review")
        if let img = NSImage(systemSymbolName: prReviewIcon(pr), accessibilityDescription: reviewDesc) {
            iv.image = img; iv.contentTintColor = prReviewColor(pr)
            iv.symbolConfiguration = .init(pointSize: 14, weight: .semibold)
        }
        iv.toolTip = reviewDesc
        addSubview(iv)

        // Title
        let title = lbl(pr.title, .systemFont(ofSize: 12.5, weight: .semibold))
        title.frame = NSRect(x: textX, y: PR_ROW_H - 24, width: textW, height: 18)
        title.lineBreakMode = .byTruncatingTail
        title.toolTip = pr.title
        addSubview(title)

        // Subtitle: #number by author + branch (bold number)
        let sub = NSTextField(labelWithString: "")
        let subAttr = NSMutableAttributedString()
        subAttr.append(NSAttributedString(string: "#\(pr.number)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]))
        subAttr.append(NSAttributedString(string: " by \(pr.author.login)", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        sub.attributedStringValue = subAttr
        sub.frame = NSRect(x: textX, y: 6, width: textW * 0.5, height: 16)
        sub.lineBreakMode = .byTruncatingTail; sub.maximumNumberOfLines = 1
        addSubview(sub)

        // Branch badge: names over 15 characters keep both ends, the tooltip shows the full name
        let badge = Badge(pr.headRefName, maxChars: 15, maxWidth: textW * 0.5 - 8)
        badge.frame.origin = NSPoint(x: textX + textW * 0.5, y: 8)
        addSubview(badge)

        // Right side: +/- and time
        let rX = w - rightW - linkW - copyW
        let diffText = "+\(pr.additions) -\(pr.deletions)"
        let diffLabel = lbl(diffText, .monospacedDigitSystemFont(ofSize: 10, weight: .medium), .secondaryLabelColor)
        diffLabel.alignment = .right
        diffLabel.frame = NSRect(x: rX, y: PR_ROW_H - 22, width: rightW - 4, height: 14)
        addSubview(diffLabel)

        let timeLabel = lbl(prRelativeTime(pr.updatedAt), .systemFont(ofSize: 10), .secondaryLabelColor)
        timeLabel.alignment = .right
        timeLabel.frame = NSRect(x: rX, y: 6, width: rightW - 4, height: 14)
        addSubview(timeLabel)

        // Draft badge
        if pr.isDraft {
            let draft = lbl("Draft", .systemFont(ofSize: 9, weight: .medium), .systemGray)
            draft.frame = NSRect(x: rX, y: PR_ROW_H / 2 - 6, width: 32, height: 12)
            addSubview(draft)
        }

        // Open in GitHub button
        let linkBtn = NSButton(frame: NSRect(x: w - linkW - copyW - 4, y: (PR_ROW_H - 24) / 2, width: linkW, height: 24))
        if let img = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: "Open in GitHub") { linkBtn.image = img }
        linkBtn.bezelStyle = .recessed; linkBtn.isBordered = false; linkBtn.imagePosition = .imageOnly
        linkBtn.target = self; linkBtn.action = #selector(openURL)
        addSubview(linkBtn)

        // Copy URL button
        let cpBtn = NSButton(frame: NSRect(x: w - copyW - 4, y: (PR_ROW_H - 24) / 2, width: copyW, height: 24))
        if let img = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy URL") { cpBtn.image = img }
        cpBtn.bezelStyle = .recessed; cpBtn.isBordered = false; cpBtn.imagePosition = .imageOnly
        cpBtn.target = self; cpBtn.action = #selector(copyURL); cpBtn.toolTip = "Copy PR URL"
        addSubview(cpBtn)

        // Separator
        let sep = NSView(frame: NSRect(x: textX, y: 0, width: w - textX - pad, height: 0.5))
        sep.wantsLayer = true; sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        addSubview(sep)
    }

    func lbl(_ text: String, _ font: NSFont, _ color: NSColor = .labelColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = font; l.textColor = color; l.maximumNumberOfLines = 1
        l.cell?.truncatesLastVisibleLine = true; return l
    }

    @objc func openURL() { if let u = URL(string: urlStr) { NSWorkspace.shared.open(u) } }
    @objc func copyURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlStr, forType: .string)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(trackingArea!)
    }
    override func mouseEntered(with event: NSEvent) { animateHover() }
    override func mouseExited(with event: NSEvent) { animateHover() }
    func animateHover() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15; ctx.allowsImplicitAnimation = true; syncHover()
        }
    }
    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.25).cgColor
    }
    override func mouseUp(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15; ctx.allowsImplicitAnimation = true; layer?.backgroundColor = restingColor
        }
        let loc = convert(event.locationInWindow, from: nil)
        guard bounds.contains(loc) else { return }
        for sub in subviews where sub is NSButton { if sub.frame.contains(loc) { return } }
        onToggle?()
    }

    func syncHover() {
        guard let win = window else { return }
        // visibleRect can extend past the row, so intersect it with bounds.
        let inside = bounds.intersection(visibleRect).contains(convert(win.mouseLocationOutsideOfEventStream, from: nil))
        layer?.backgroundColor = inside ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.15).cgColor : restingColor
    }

    // Keyboard accessibility
    override var acceptsFirstResponder: Bool { true }
    override var focusRingType: NSFocusRingType {
        get { .exterior }
        set {}
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 { onToggle?() }
        else { super.keyDown(with: event) }
    }
}

// ─── PR Detail View ──────────────────────────────────────────────────────────

class PRDetailView: NSView {
    var onAction: ((PRAction) -> Void)?
    var confirmingClose = false
    var commentField: NSTextField!

    init(_ pr: PR, repo: String, w: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        // Inverse-of-background tint so the expanded panel is distinct from the doc bg in both modes.
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        let pad: CGFloat = 42, rPad: CGFloat = 16
        let contentW = w - pad - rPad
        var y: CGFloat = 8

        // Body text
        let bodyText = String((pr.body ?? "No description.").prefix(500))
        let bodyAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11.5)]
        let bodyRect = (bodyText as NSString).boundingRect(
            with: NSSize(width: contentW, height: 100),
            options: [.usesLineFragmentOrigin], attributes: bodyAttrs)
        let bodyH = min(ceil(bodyRect.height) + 4, 100)
        let bodyLabel = NSTextField(wrappingLabelWithString: bodyText)
        bodyLabel.font = .systemFont(ofSize: 11.5); bodyLabel.textColor = .secondaryLabelColor
        bodyLabel.frame = NSRect(x: pad, y: y, width: contentW, height: bodyH)
        bodyLabel.maximumNumberOfLines = 6
        addSubview(bodyLabel)
        y += bodyH + 8

        // Labels
        if !pr.labels.isEmpty {
            var lx: CGFloat = pad
            for label in pr.labels.prefix(5) {
                let lb = Badge(label.name)
                lb.frame.origin = NSPoint(x: lx, y: y)
                addSubview(lb)
                lx += lb.frame.width + 6
            }
            y += 24
        }

        // Separator
        let sep1 = NSView(frame: NSRect(x: pad, y: y, width: contentW, height: 0.5))
        sep1.wantsLayer = true; sep1.layer?.backgroundColor = NSColor.separatorColor.cgColor
        addSubview(sep1); y += 8

        // Action buttons row
        let btnH: CGFloat = 24
        var bx: CGFloat = pad

        let approveBtn = makeBtn("Approve", color: C_SUCCESS, x: bx, y: y, h: btnH)
        approveBtn.target = self; approveBtn.action = #selector(doApprove)
        addSubview(approveBtn); bx += approveBtn.frame.width + 6

        let changesBtn = makeBtn("Changes", color: C_QUEUED, x: bx, y: y, h: btnH)
        changesBtn.target = self; changesBtn.action = #selector(doRequestChanges)
        addSubview(changesBtn); bx += changesBtn.frame.width + 6

        let mergePopup = NSPopUpButton(frame: NSRect(x: bx, y: y, width: 130, height: btnH), pullsDown: false)
        mergePopup.addItems(withTitles: ["Merge commit", "Rebase", "Squash"])
        mergePopup.font = .systemFont(ofSize: 11)
        addSubview(mergePopup); mergePopup.tag = 100; bx += 136

        let mergeBtn = makeBtn("Merge", color: .systemPurple, x: bx, y: y, h: btnH)
        mergeBtn.target = self; mergeBtn.action = #selector(doMerge)
        addSubview(mergeBtn); bx += mergeBtn.frame.width + 6

        let closeBtn = makeBtn("Close", color: C_FAILURE, x: bx, y: y, h: btnH)
        closeBtn.target = self; closeBtn.action = #selector(doClose(_:))
        closeBtn.tag = 200
        addSubview(closeBtn)
        y += btnH + 10

        // Comment field + submit
        let sep2 = NSView(frame: NSRect(x: pad, y: y, width: contentW, height: 0.5))
        sep2.wantsLayer = true; sep2.layer?.backgroundColor = NSColor.separatorColor.cgColor
        addSubview(sep2); y += 8

        let cf = NSTextField(frame: NSRect(x: pad, y: y, width: contentW - 80, height: 24))
        cf.placeholderString = "Leave a comment..."
        cf.font = .systemFont(ofSize: 11.5)
        addSubview(cf); commentField = cf

        let submitBtn = makeBtn("Comment", color: .linkColor, x: pad + contentW - 72, y: y, h: 24)
        submitBtn.target = self; submitBtn.action = #selector(doComment)
        addSubview(submitBtn)
        y += 32

        self.frame = NSRect(x: 0, y: 0, width: w, height: y)
    }
    required init?(coder: NSCoder) { fatalError() }

    func makeBtn(_ title: String, color: NSColor, x: CGFloat, y: CGFloat, h: CGFloat) -> NSButton {
        let b = NSButton(title: title, target: nil, action: nil)
        b.bezelStyle = .inline; b.font = .systemFont(ofSize: 11, weight: .medium)
        b.contentTintColor = color
        let tw = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium)]).width
        b.frame = NSRect(x: x, y: y, width: tw + 20, height: h)
        return b
    }

    func disableActions(_ message: String) {
        for sub in subviews where sub is NSButton {
            (sub as! NSButton).isEnabled = false
        }
        commentField.isEnabled = false
        commentField.stringValue = ""
        commentField.placeholderString = message
    }

    @objc func doApprove() {
        let body = commentField.stringValue.isEmpty ? nil : commentField.stringValue
        disableActions("Approving...")
        onAction?(.approve(body))
    }
    @objc func doRequestChanges() {
        let body = commentField.stringValue
        guard !body.isEmpty else { commentField.placeholderString = "Required: describe changes needed"; return }
        disableActions("Submitting review...")
        onAction?(.requestChanges(body))
    }
    @objc func doComment() {
        let body = commentField.stringValue
        guard !body.isEmpty else { return }
        disableActions("Posting comment...")
        onAction?(.comment(body))
    }
    @objc func doMerge() {
        let popup = subviews.compactMap { $0 as? NSPopUpButton }.first(where: { $0.tag == 100 })
        let methods = ["-m", "-r", "-s"]
        let method = methods[popup?.indexOfSelectedItem ?? 0]
        disableActions("Merging...")
        onAction?(.merge(method))
    }
    @objc func doClose(_ sender: NSButton) {
        if confirmingClose {
            onAction?(.close)
        } else {
            confirmingClose = true
            sender.title = "Sure?"; sender.contentTintColor = .white
            sender.layer?.backgroundColor = C_FAILURE.cgColor; sender.layer?.cornerRadius = 4
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self = self, self.confirmingClose else { return }
                self.confirmingClose = false
                sender.title = "Close"; sender.contentTintColor = C_FAILURE
                sender.layer?.backgroundColor = nil
            }
        }
    }
}

// ─── Shared Views ────────────────────────────────────────────────────────────

class Badge: NSView {
    /// Text longer than `maxChars` keeps its first and last characters around an ellipsis.
    init(_ text: String, maxChars: Int = .max, maxWidth: CGFloat = .greatestFiniteMagnitude) {
        let half = (maxChars - 1) / 2
        let shown = text.count > maxChars ? "\(text.prefix(half))\u{2026}\(text.suffix(half))" : text
        let l = NSTextField(labelWithString: shown)
        l.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        l.textColor = .secondaryLabelColor
        l.alignment = .center
        l.lineBreakMode = .byTruncatingMiddle
        l.maximumNumberOfLines = 1
        // The label cell needs a few points more than its intrinsic width, or it truncates.
        let sz = l.intrinsicContentSize
        let textW = ceil(sz.width) + 4
        let w = min(textW + 14, maxWidth)
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: 20))
        l.frame = NSRect(x: 7, y: (20 - sz.height) / 2, width: w - 14, height: sz.height)
        addSubview(l)
        toolTip = text
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let p = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        // Inverse-of-background fill so the badge is visible in both modes:
        // dark fill in light mode, light fill in dark mode.
        NSColor.labelColor.withAlphaComponent(0.08).setFill(); p.fill()
        NSColor.separatorColor.setStroke(); p.lineWidth = 0.5; p.stroke()
    }
}

class Header: NSView {
    init(_ repo: String, w: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: HDR_H))
        wantsLayer = true; layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.9).cgColor
        let short = repo.components(separatedBy: "/").last ?? repo
        let l = NSTextField(labelWithString: short.uppercased())
        l.font = .systemFont(ofSize: 11, weight: .bold); l.textColor = .secondaryLabelColor
        l.frame = NSRect(x: 12, y: 6, width: w - 150, height: 20)
        addSubview(l)
        let reload = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh \(short)")!,
                              target: nil, action: nil)
        reload.isBordered = false; reload.contentTintColor = .secondaryLabelColor
        reload.symbolConfiguration = .init(pointSize: 10, weight: .semibold)
        reload.frame = NSRect(x: w - 132, y: 6, width: 20, height: 20)
        reload.toolTip = "Get the latest runs from GitHub"
        reload.target = self; reload.action = #selector(refreshRepo(_:))
        addSubview(reload)
        let link = NSTextField(labelWithString: "Open Actions")
        link.font = .systemFont(ofSize: 10, weight: .medium); link.textColor = .linkColor
        link.frame = NSRect(x: w - 105, y: 8, width: 93, height: 16); link.alignment = .right
        addSubview(link)
        let click = Clicker("https://github.com/\(repo)/actions")
        click.frame = NSRect(x: w - 110, y: 0, width: 110, height: HDR_H)
        addSubview(click)
        self.repo = repo
    }
    required init?(coder: NSCoder) { fatalError() }

    private var repo = ""

    // Polls GitHub for this repo at once, so a missed relay event does not hide new runs.
    @objc func refreshRepo(_ sender: NSButton) {
        guard let app = NSApp.delegate as? GHActionsBar else { return }
        sender.isEnabled = false
        app.refreshRepos([repo], includePRs: true, completedRuns: []) { _ in app.reloadList() }
    }
}

class Clicker: NSView {
    let url: String
    init(_ url: String) { self.url = url; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

class EmptyRow: NSView {
    init(_ text: String, w: CGFloat, icon: String? = nil) {
        let h: CGFloat = icon != nil ? 52 : 36
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: h))
        if let iconName = icon {
            let iv = NSImageView(frame: NSRect(x: 16, y: (h - 20) / 2, width: 20, height: 20))
            if let img = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
                iv.image = img; iv.contentTintColor = .secondaryLabelColor
                iv.symbolConfiguration = .init(pointSize: 14, weight: .regular)
            }
            addSubview(iv)
        }
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 12); l.textColor = .secondaryLabelColor
        l.frame = NSRect(x: 42, y: (h - 20) / 2, width: w - 54, height: 20)
        addSubview(l)
    }
    required init?(coder: NSCoder) { fatalError() }
}

class Flipped: NSView { override var isFlipped: Bool { true } }

class LoadingRow: NSView {
    init(w: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: 48))
        let spinner = NSProgressIndicator(frame: NSRect(x: 16, y: 14, width: 20, height: 20))
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        addSubview(spinner)
        let l = NSTextField(labelWithString: "Loading...")
        l.font = .systemFont(ofSize: 12); l.textColor = .secondaryLabelColor
        l.frame = NSRect(x: 44, y: 14, width: w - 56, height: 20)
        addSubview(l)
    }
    required init?(coder: NSCoder) { fatalError() }
}

// ─── Footer ──────────────────────────────────────────────────────────────────

// ─── Insights tab views ──────────────────────────────────────────────────────

class TitleRow: NSView {
    init(_ text: String, w: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: 34))
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 12, weight: .semibold); l.textColor = .labelColor
        l.frame = NSRect(x: 12, y: 8, width: w - 24, height: 18)
        addSubview(l)
    }
    required init?(coder: NSCoder) { fatalError() }
}

class SectionLabel: NSView {
    init(_ text: String, w: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: HDR_H))
        wantsLayer = true; layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.9).cgColor
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 11, weight: .bold); l.textColor = .secondaryLabelColor
        l.frame = NSRect(x: 12, y: 6, width: w - 24, height: 20)
        addSubview(l)
    }
    required init?(coder: NSCoder) { fatalError() }
}

class StatTile: NSView {
    init(frame: NSRect, title: String, value: String, sub: String, subColor: NSColor) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
        layer?.cornerRadius = 8
        let t = NSTextField(labelWithString: title.uppercased())
        t.font = .systemFont(ofSize: 9, weight: .semibold); t.textColor = .tertiaryLabelColor
        t.frame = NSRect(x: 10, y: frame.height - 22, width: frame.width - 20, height: 13)
        addSubview(t)
        let v = NSTextField(labelWithString: value)
        v.font = .monospacedDigitSystemFont(ofSize: 21, weight: .medium); v.textColor = .labelColor
        v.frame = NSRect(x: 10, y: frame.height - 50, width: frame.width - 20, height: 26)
        addSubview(v)
        if !sub.isEmpty {
            let s = NSTextField(labelWithString: sub)
            s.font = .systemFont(ofSize: 10, weight: .medium); s.textColor = subColor
            s.lineBreakMode = .byTruncatingTail
            s.frame = NSRect(x: 10, y: 8, width: frame.width - 20, height: 14)
            addSubview(s)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
}

class InsightsSummaryView: NSView {
    override var isFlipped: Bool { true }
    init(this t: WindowStats, last l: WindowStats, w: CGFloat) {
        let pad: CGFloat = 12, gap: CGFloat = 10, cols: CGFloat = 3
        let tileW = (w - pad * 2 - gap * (cols - 1)) / cols
        let tileH: CGFloat = 76
        let h = pad + tileH * 2 + gap + pad
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: h))

        // Returns ("▲ 12% vs prior", color) — green when the move is an improvement.
        func delta(_ a: Double?, _ b: Double?, higherBetter: Bool, fmt: (Double) -> String, suffix: String = "") -> (String, NSColor) {
            guard let a = a, let b = b else { return ("", .secondaryLabelColor) }
            let d = a - b
            if abs(d) < 0.0001 { return ("no change", .secondaryLabelColor) }
            let up = d > 0
            let good = (up == higherBetter)
            return ("\(up ? "▲" : "▼") \(fmt(abs(d)))\(suffix) vs prior", good ? .systemGreen : .systemRed)
        }
        let intFmt: (Double) -> String = { String(Int($0)) }
        let ptsFmt: (Double) -> String = { String(format: "%.0f", $0) }

        let tiles: [(String, String, (String, NSColor))] = [
            ("Runs", "\(t.total)", delta(Double(t.total), Double(l.total), higherBetter: true, fmt: intFmt)),
            ("Pass rate", t.passRate.map(pct) ?? "—",
             delta(t.passRate.map { $0 * 100 }, l.passRate.map { $0 * 100 }, higherBetter: true, fmt: ptsFmt, suffix: " pts")),
            ("Failures", "\(t.failure)", delta(Double(t.failure), Double(l.failure), higherBetter: false, fmt: intFmt)),
            ("Avg time", t.avgDuration.map(fmtDuration) ?? "—",
             delta(t.avgDuration, l.avgDuration, higherBetter: false, fmt: fmtDuration)),
            ("Deploys", "\(t.deployTotal)", delta(Double(t.deployTotal), Double(l.deployTotal), higherBetter: true, fmt: intFmt)),
            ("Deploy pass", t.deployPassRate.map(pct) ?? "—",
             delta(t.deployPassRate.map { $0 * 100 }, l.deployPassRate.map { $0 * 100 }, higherBetter: true, fmt: ptsFmt, suffix: " pts")),
        ]
        for (i, tile) in tiles.enumerated() {
            let col = CGFloat(i % 3), row = CGFloat(i / 3)
            let x = pad + col * (tileW + gap)
            let y = pad + row * (tileH + gap)
            addSubview(StatTile(frame: NSRect(x: x, y: y, width: tileW, height: tileH),
                                title: tile.0, value: tile.1, sub: tile.2.0, subColor: tile.2.1))
        }
    }
    required init?(coder: NSCoder) { fatalError() }
}

class InsightBulletRow: NSView {
    init(_ text: String, w: CGFloat) {
        let x: CGFloat = 14
        let textW = w - x - 14
        let font = NSFont.systemFont(ofSize: 12)
        let h = textHeight("•  " + text, font: font, width: textW) + 14
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: h))
        let l = NSTextField(wrappingLabelWithString: "•  " + text)
        l.font = font; l.textColor = .labelColor
        l.frame = NSRect(x: x, y: 7, width: textW, height: h - 14)
        addSubview(l)
    }
    required init?(coder: NSCoder) { fatalError() }
}

class WorkflowStatRow: NSView {
    init(_ s: WFStat, w: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: 30))
        let name = NSTextField(labelWithString: s.workflow)
        name.font = .systemFont(ofSize: 12, weight: .medium); name.textColor = .labelColor
        name.lineBreakMode = .byTruncatingTail
        name.frame = NSRect(x: 14, y: 6, width: w - 250, height: 18)
        addSubview(name)
        let stats = "\(s.total) runs   \(pct(s.failRate)) fail   \(s.avgDuration.map(fmtDuration) ?? "—")"
        let r = NSTextField(labelWithString: stats)
        r.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        r.textColor = s.failRate >= 0.2 ? .systemRed : .secondaryLabelColor
        r.alignment = .right
        r.frame = NSRect(x: w - 230, y: 7, width: 216, height: 16)
        addSubview(r)
    }
    required init?(coder: NSCoder) { fatalError() }
}

class CopyReportRow: NSView {
    let markdown: String
    init(this t: WindowStats, last l: WindowStats, insights: [String], thisRecs: [DeployRecord], w: CGFloat) {
        self.markdown = buildAIReport(this: t, last: l, insights: insights, thisRecs: thisRecs)
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: 52))
        let btn = NSButton(title: "Copy report for AI", target: self, action: #selector(copyIt(_:)))
        btn.bezelStyle = .rounded; btn.font = .systemFont(ofSize: 12, weight: .medium)
        btn.frame = NSRect(x: 12, y: 12, width: 170, height: 28)
        addSubview(btn)
        let hint = NSTextField(labelWithString: "Copies a markdown report to paste into an AI agent.")
        hint.font = .systemFont(ofSize: 10); hint.textColor = .tertiaryLabelColor
        hint.frame = NSRect(x: 190, y: 17, width: w - 202, height: 16)
        addSubview(hint)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc func copyIt(_ sender: NSButton) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        sender.title = "Copied ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { sender.title = "Copy report for AI" }
    }
}

class Footer: NSView {
    init(_ w: CGFloat, updated: Date) {
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: FTR_H))
        wantsLayer = true; layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.9).cgColor
        let sep = NSView(frame: NSRect(x: 0, y: FTR_H - 0.5, width: w, height: 0.5))
        sep.wantsLayer = true; sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        addSubview(sep)

        let rb = NSButton(title: "Refresh", target: NSApp.delegate, action: #selector(GHActionsBar.doRefresh))
        rb.bezelStyle = .inline; rb.font = .systemFont(ofSize: 11)
        rb.frame = NSRect(x: 8, y: 8, width: 80, height: 24)
        addSubview(rb)

        quota.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        quota.frame = NSRect(x: 92, y: 11, width: 40, height: 16)
        addSubview(quota)
        showQuota((NSApp.delegate as? GHActionsBar)?.rateLimit.latest)

        let f = DateFormatter(); f.dateFormat = "h:mm:ss a"
        let version = (NSApp.delegate as? GHActionsBar).map { "v\($0.updater.current) · " } ?? ""
        let ts = NSTextField(labelWithString: "\(version)Updated \(f.string(from: updated))")
        ts.font = .systemFont(ofSize: 10); ts.textColor = .secondaryLabelColor; ts.alignment = .center
        ts.frame = NSRect(x: 134, y: 11, width: w - 274, height: 16)
        addSubview(ts)

        // Live updates: green = live, grey = polling, orange = relay error.
        if let (color, tip) = (NSApp.delegate as? GHActionsBar)?.relay.statusDot {
            let dot = Dot(color: color, frame: NSRect(x: w - 124, y: 15, width: 10, height: 10))
            dot.toolTip = tip
            addSubview(dot)
        }

        // Settings gear
        let gear = NSButton(frame: NSRect(x: w - 100, y: 8, width: 36, height: 24))
        if let img = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings") { gear.image = img }
        gear.bezelStyle = .inline; gear.imagePosition = .imageOnly
        gear.target = NSApp.delegate; gear.action = #selector(GHActionsBar.showSettings)
        gear.toolTip = "Settings"
        addSubview(gear)

        let qb = NSButton(title: "Quit", target: NSApp.delegate, action: #selector(GHActionsBar.quitApp))
        qb.bezelStyle = .inline; qb.font = .systemFont(ofSize: 11)
        qb.frame = NSRect(x: w - 56, y: 8, width: 48, height: 24)
        addSubview(qb)
    }
    required init?(coder: NSCoder) { fatalError() }

    let quota = NSTextField(labelWithString: "")

    func showQuota(_ rl: RateLimit?) {
        quota.stringValue = rl.map { "\($0.percent)%" } ?? ""
        quota.textColor = rl?.color ?? .secondaryLabelColor
        quota.toolTip = rl?.tooltip
    }
}

// ─── Tab View (Actions + PRs) ────────────────────────────────────────────────

let TAB_H: CGFloat = 36

class TabVC: NSViewController {
    let grouped: [(String, [Run])]
    let prGrouped: [(String, [PR])]
    let updated: Date
    let loading: Bool
    var selectedTab: Int
    var selectedRepo: String?
    var expandedPR: String?
    var expandedRun: String?
    var scrollView: NSScrollView!
    var doc: Flipped!
    var footerView: NSView!

    init(grouped: [(String, [Run])], prGrouped: [(String, [PR])], updated: Date, loading: Bool,
         tab: Int, repo: String?, expandedPR: String? = nil) {
        self.grouped = grouped; self.prGrouped = prGrouped
        self.updated = updated; self.loading = loading
        self.selectedTab = tab; self.selectedRepo = repo; self.expandedPR = expandedPR
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let w = POP_W
        let container = Flipped(frame: NSRect(x: 0, y: 0, width: w, height: POP_MAX_H))
        container.wantsLayer = true

        // ── Top bar: tabs + repo filter ──
        let topBar = NSView(frame: NSRect(x: 0, y: 0, width: w, height: TAB_H))
        topBar.wantsLayer = true
        topBar.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.9).cgColor

        let seg = NSSegmentedControl(labels: ["Actions", "PRs", "Insights"], trackingMode: .selectOne, target: self, action: #selector(tabChanged(_:)))
        seg.selectedSegment = selectedTab
        seg.frame = NSRect(x: 12, y: 6, width: 226, height: 24)
        seg.font = .systemFont(ofSize: 11, weight: .medium)
        topBar.addSubview(seg)

        // Main/develop-only checkbox (Actions tab only)
        if selectedTab == 0 {
            let cb = NSButton(checkboxWithTitle: "Default only",
                              target: self, action: #selector(toggleBranchFilter(_:)))
            cb.font = .systemFont(ofSize: 11)
            cb.state = FILTER_DEFAULT_BRANCHES ? .on : .off
            cb.frame = NSRect(x: 246, y: 8, width: 104, height: 20)
            cb.toolTip = "Hide workflow runs from branches other than main or develop"
            topBar.addSubview(cb)

            let sortCB = NSButton(checkboxWithTitle: "Recent first",
                                  target: self, action: #selector(toggleSortByRecent(_:)))
            sortCB.font = .systemFont(ofSize: 11)
            sortCB.state = SORT_BY_RECENT ? .on : .off
            sortCB.frame = NSRect(x: 352, y: 8, width: 100, height: 20)
            sortCB.toolTip = "Show repos with the newest runs at the top"
            topBar.addSubview(sortCB)
        }

        let repoFilter = NSPopUpButton(frame: NSRect(x: w - 200, y: 6, width: 188, height: 24), pullsDown: false)
        repoFilter.font = .systemFont(ofSize: 11)
        repoFilter.addItem(withTitle: "All Repos")
        for repo in REPOS { repoFilter.addItem(withTitle: repo) }
        if let sel = selectedRepo, let idx = REPOS.firstIndex(of: sel) { repoFilter.selectItem(at: idx + 1) }
        else { repoFilter.selectItem(at: 0) }
        repoFilter.target = self; repoFilter.action = #selector(repoChanged(_:))
        repoFilter.tag = 300
        topBar.addSubview(repoFilter)
        container.addSubview(topBar)

        // ── Footer (fixed at bottom) ──
        let footer = Footer(w, updated: updated)

        // ── Scroll content ──
        let scrollH = POP_MAX_H - TAB_H - FTR_H
        scrollView = NSScrollView(frame: NSRect(x: 0, y: TAB_H, width: w, height: scrollH))
        scrollView.hasVerticalScroller = true; scrollView.drawsBackground = false; scrollView.autohidesScrollers = true
        doc = Flipped(frame: NSRect(x: 0, y: 0, width: w, height: scrollH))
        doc.wantsLayer = true
        doc.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.85).cgColor
        scrollView.documentView = doc
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        container.addSubview(scrollView)

        container.addSubview(footer)
        footerView = footer
        self.view = container
        rebuildContent()
    }

    func rebuildContent() {
        NSApp.withPinnedAppearance {
            doc.subviews.forEach { $0.removeFromSuperview() }
            let w = POP_W
            var rows: [NSView] = []

            if REPOS.isEmpty {
                rows.append(EmptyRow("No repos configured. Open Settings to get started.", w: w, icon: "gearshape"))
            } else if selectedTab == 0 {
                rows = buildActionsContent(w)
            } else if selectedTab == 1 {
                rows = buildPRContent(w)
            } else {
                rows = buildInsightsContent(w)
            }

            var y: CGFloat = 0
            for row in rows { row.frame.origin = NSPoint(x: 0, y: y); doc.addSubview(row); y += row.frame.height }
            doc.frame.size.height = max(y, 60)
            relayout()
        }
    }

    // Resize the scroll area / footer / popover to fit the content, so inline
    // expansions grow the popover instead of forcing a scroll.
    func relayout() {
        guard footerView != nil else { return }
        let scrollHMax = POP_MAX_H - TAB_H - FTR_H
        let visScrollH = min(doc.frame.height, scrollHMax)
        scrollView.frame.size.height = visScrollH
        footerView.frame.origin.y = TAB_H + visScrollH
        let totalH = TAB_H + visScrollH + FTR_H
        view.frame.size.height = totalH
        preferredContentSize = NSSize(width: POP_W, height: totalH)
    }

    func filteredGrouped() -> [(String, [Run])] {
        let data = selectedRepo.map { sel in grouped.filter { $0.0 == sel } } ?? grouped
        return SORT_BY_RECENT ? sortedByRecent(data) : data
    }

    func filteredPRs() -> [(String, [PR])] {
        guard let sel = selectedRepo else { return prGrouped }
        return prGrouped.filter { $0.0 == sel }
    }

    func buildActionsContent(_ w: CGFloat) -> [NSView] {
        var rows: [NSView] = []
        let data = filteredGrouped()
        if let err = lastFetchError {
            rows.append(EmptyRow(err, w: w, icon: "exclamationmark.triangle"))
            return rows
        }
        if loading && data.isEmpty {
            rows.append(LoadingRow(w: w)); return rows
        }
        for (repo, runs) in data {
            rows.append(Header(repo, w: w))
            let visible = visibleRuns(runs)
            if visible.isEmpty {
                let msg = FILTER_DEFAULT_BRANCHES && !runs.isEmpty
                    ? "No recent runs on main or develop"
                    : "No recent runs"
                rows.append(EmptyRow(msg, w: w))
            } else {
                let sorted = visible.sorted { a, b in
                    let aActive = a.status == "in_progress" || a.status == "queued"
                    let bActive = b.status == "in_progress" || b.status == "queued"
                    if aActive != bActive { return aActive }
                    return false  // preserve API order otherwise
                }
                let groups = groupRuns(sorted)
                for group in groups {
                    let primary = RunRow.pickPrimary(group)
                    let key = primary.url
                    let isExpanded = expandedRun == key
                    let row = RunRow(repo: repo, group: group, history: visible, w: w, expanded: isExpanded)
                    row.onToggle = { [weak self] in
                        guard let self = self else { return }
                        self.expandedRun = self.expandedRun == key ? nil : key
                        self.rebuildContent()
                    }
                    rows.append(row)
                    if isExpanded {
                        ensureRunDetail(repo: repo, group: group, key: key)
                        rows.append(RunDetailView(group: group, primary: primary, repo: repo,
                                                  history: visible, w: w))
                    }
                }
            }
        }
        if rows.isEmpty { rows.append(EmptyRow("No actions to show", w: w)) }
        return rows
    }

    // Fetch commit message + failure annotations for an expanded run in the
    // background, then re-render. Results are cached so re-expanding is instant.
    func ensureRunDetail(repo: String, group: [Run], key: String) {
        let primary = RunRow.pickPrimary(group)
        let sha = primary.headSha
        let needMsg = !sha.isEmpty && commitMsgCache[sha] == nil
        let needFails = group.filter { $0.conclusion == "failure" && failureCache[$0.id] == nil }
        guard needMsg || !needFails.isEmpty else { return }
        guard !detailFetchInFlight.contains(key) else { return }
        detailFetchInFlight.insert(key)
        let fallbackMsg = primary.displayTitle
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let msg = needMsg ? fetchCommitMessage(repo: repo, sha: sha) : nil
            var fails: [(Int, [RunFailure])] = []
            for r in needFails { fails.append((r.id, fetchRunFailures(repo: repo, runId: r.id))) }
            DispatchQueue.main.async {
                if commitMsgCache.count > 300 { commitMsgCache.removeAll() }
                if failureCache.count > 200 { failureCache.removeAll() }
                if needMsg { commitMsgCache[sha] = msg ?? fallbackMsg }
                for (id, f) in fails { failureCache[id] = f }
                detailFetchInFlight.remove(key)
                guard let self = self, self.expandedRun == key else { return }
                self.rebuildContent()
            }
        }
    }

    func buildPRContent(_ w: CGFloat) -> [NSView] {
        var rows: [NSView] = []
        let data = filteredPRs()
        if let err = lastFetchError {
            rows.append(EmptyRow(err, w: w, icon: "exclamationmark.triangle"))
            return rows
        }
        let hasPRs = data.contains { !$0.1.isEmpty }
        if !hasPRs {
            rows.append(EmptyRow("No pull requests awaiting your review", w: w, icon: "checkmark.seal"))
            return rows
        }
        for (repo, prs) in data {
            if prs.isEmpty { continue }
            rows.append(Header(repo, w: w))
            for pr in prs {
                let key = "\(repo)#\(pr.number)"
                let isExpanded = expandedPR == key
                let row = PRRow(pr, repo: repo, w: w, expanded: isExpanded)
                row.onToggle = { [weak self] in
                    guard let self = self else { return }
                    self.expandedPR = self.expandedPR == key ? nil : key
                    // Semitransient when expanded (prevents accidental close while typing comment)
                    let appDel = NSApp.delegate as? GHActionsBar
                    appDel?.popover.behavior = self.expandedPR != nil ? .semitransient : .transient
                    self.rebuildContent()
                }
                rows.append(row)
                if isExpanded {
                    let detail = PRDetailView(pr, repo: repo, w: w)
                    detail.onAction = { [weak self] action in
                        self?.handlePRAction(repo: repo, pr: pr, action: action)
                    }
                    rows.append(detail)
                }
            }
        }
        return rows
    }

    func buildInsightsContent(_ w: CGFloat) -> [NSView] {
        var rows: [NSView] = []
        let recs = DeployLog.shared.all()
        if recs.isEmpty {
            rows.append(EmptyRow("No deploy history yet. Cat Eye logs every workflow run it sees — check back after a few runs complete.", w: w, icon: "chart.bar"))
            return rows
        }
        let now = Date()
        let day = 86400.0
        var thisR = recordsInWindow(recs, from: now.addingTimeInterval(-7 * day), to: now.addingTimeInterval(1))
        var lastR = recordsInWindow(recs, from: now.addingTimeInterval(-14 * day), to: now.addingTimeInterval(-7 * day))
        if let sel = selectedRepo {
            thisR = thisR.filter { $0.repo == sel }
            lastR = lastR.filter { $0.repo == sel }
        }
        let tw = computeWindow(thisR)
        let lw = computeWindow(lastR)
        let insights = generateInsights(this: tw, last: lw)

        rows.append(TitleRow("Last 7 days vs previous 7", w: w))
        rows.append(InsightsSummaryView(this: tw, last: lw, w: w))
        rows.append(SectionLabel("INSIGHTS", w: w))
        for i in insights { rows.append(InsightBulletRow(i, w: w)) }
        if !tw.byWorkflow.isEmpty {
            rows.append(SectionLabel("PER-WORKFLOW (7d)", w: w))
            for wf in tw.byWorkflow.values.sorted(by: { $0.total > $1.total }).prefix(12) {
                rows.append(WorkflowStatRow(wf, w: w))
            }
        }
        rows.append(CopyReportRow(this: tw, last: lw, insights: insights, thisRecs: thisR, w: w))
        return rows
    }

    func handlePRAction(repo: String, pr: PR, action: PRAction) {
        executePRAction(repo: repo, number: pr.number, action: action) {
            (NSApp.delegate as? GHActionsBar)?.doRefresh()
        }
    }

    @objc func tabChanged(_ sender: NSSegmentedControl) {
        selectedTab = sender.selectedSegment
        // Reassigning contentViewController is what NSPopover observes at show time;
        // calling loadView() alone leaves stale tab body visible in an already-shown popover.
        let appDel = NSApp.delegate as? GHActionsBar
        appDel?.selectedTab = selectedTab
        appDel?.selectedRepo = selectedRepo
        expandedPR = nil
        expandedRun = nil
        // A fresh TabVC also rebuilds the top bar, so the branch-filter checkbox
        // shows/hides with the tab.
        appDel?.applySystemAppearance()
        appDel?.buildWithAppearance { appDel?.popover.contentViewController = appDel?.makeTabVC() }
    }

    @objc func toggleBranchFilter(_ sender: NSButton) {
        FILTER_DEFAULT_BRANCHES = (sender.state == .on)
        saveConfig()
        rebuildContent()
        let appDel = NSApp.delegate as? GHActionsBar
        appDel?.updateIcon()
        // Cadence follows visibility too, so filtering a branch out stops the fast poll.
        appDel?.scheduleTimer()
    }

    @objc func scrolled(_ note: Notification) {
                for row in doc.subviews {
            (row as? RunRow)?.syncHover()
            (row as? PRRow)?.syncHover()
        }
    }

    @objc func toggleSortByRecent(_ sender: NSButton) {
        SORT_BY_RECENT = (sender.state == .on)
        saveConfig()
        rebuildContent()
    }

    @objc func repoChanged(_ sender: NSPopUpButton) {
        if sender.indexOfSelectedItem == 0 {
            selectedRepo = nil
        } else {
            let idx = sender.indexOfSelectedItem - 1
            if idx < REPOS.count { selectedRepo = REPOS[idx] }
        }
        (NSApp.delegate as? GHActionsBar)?.selectedRepo = selectedRepo
        expandedPR = nil
        expandedRun = nil
        rebuildContent()
    }
}

// ─── Settings View ───────────────────────────────────────────────────────────

class SettingsHeader: NSView {
    init(_ title: String, y: CGFloat, w: CGFloat) {
        super.init(frame: NSRect(x: 0, y: y, width: w, height: 28))
        wantsLayer = true; layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.7).cgColor
        let l = NSTextField(labelWithString: title)
        l.font = .systemFont(ofSize: 10, weight: .bold); l.textColor = .secondaryLabelColor
        l.frame = NSRect(x: 16, y: 6, width: w - 100, height: 16)
        addSubview(l)
    }
    required init?(coder: NSCoder) { fatalError() }
}

class SeparatorLine: NSView {
    init(y: CGFloat, w: CGFloat) {
        super.init(frame: NSRect(x: 0, y: y, width: w, height: 0.5))
        wantsLayer = true; layer?.backgroundColor = NSColor.separatorColor.cgColor
    }
    required init?(coder: NSCoder) { fatalError() }
}

// Back button plus the Repositories / Live updates tabs.
class SettingsNav: NSView {
    init(w: CGFloat, selected: Int) {
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: 44))
        wantsLayer = true; layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.9).cgColor
        let back = NSButton(title: "Back", target: NSApp.delegate, action: #selector(GHActionsBar.showList))
        back.bezelStyle = .inline; back.font = .systemFont(ofSize: 12)
        back.frame = NSRect(x: 8, y: 10, width: 70, height: 24)
        addSubview(back)
        let seg = NSSegmentedControl(labels: ["Repositories", "Live updates"], trackingMode: .selectOne,
                                     target: self, action: #selector(tabChanged(_:)))
        seg.selectedSegment = selected
        seg.font = .systemFont(ofSize: 11, weight: .medium)
        seg.frame = NSRect(x: w / 2 - 110, y: 10, width: 220, height: 24)
        addSubview(seg)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc func tabChanged(_ sender: NSSegmentedControl) {
        let app = NSApp.delegate as? GHActionsBar
        sender.selectedSegment == 1 ? app?.showRelaySettings() : app?.showSettings()
    }
}

// ─── App ─────────────────────────────────────────────────────────────────────

class GHActionsBar: NSObject, NSApplicationDelegate, NSPopoverDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var timer: Timer?
    var fallbackTimer: Timer?
    var lastFallbackPRRefresh = Date.distantPast
    var isPulsing = false
    struct IconKey: Equatable { let color: NSColor; let badge: String?; let active: Bool }
    var iconKey: IconKey?
    var refreshInFlight = false
    var pendingCompletion: (() -> Void)?
    var lastPRRefresh = Date.distantPast
    var grouped: [(String, [Run])] = []
    var prGrouped: [(String, [PR])] = []
    var lastUpdate = Date()
    var closeTime = Date.distantPast
    var firstLoad = true
    var ghIcon: NSImage?
    var prevStatuses: [String: String] = [:]
    var selectedTab: Int = 0
    var selectedRepo: String? = nil
    var appearanceObs: NSKeyValueObservation?
    var warnedStatusItemMissing = false
    var statusItemRecheckDone = false
    let relayDeployer = RelayDeployer()
    let catalog = RepoCatalog(path: REPO_CACHE_PATH)
    var catalogTimer: Timer?
    let rateLimit = RateLimitMonitor()
    let updater = Updater()
    lazy var relay: RelayClient = {
        let c = RelayClient(secrets: relayDeployer.secrets)
        c.sink = self
        return c
    }()
    // Targeted refreshes that arrive while another refresh runs.
    var pendingPartial: (repos: Set<String>, prs: Bool, runs: [(String, Int)], dones: [(Bool) -> Void])?

    func applicationDidFinishLaunching(_ note: Notification) {
        log.info("Cat Eye launching — repos: \(REPOS.count), poll: \(POLL_NORMAL)s/\(POLL_ACTIVE)s")
        loadConfig()
        REPOS = catalog.resolve(picked: PICKED_REPOS, orgs: PICKED_ORGS)
        log.info("Config loaded — tracking \(REPOS.count) repos: \(REPOS.joined(separator: ", "))")
        ghIcon = loadGHIcon()

        let nc = UNUserNotificationCenter.current()
        nc.delegate = self
        nc.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted { log.info("Notification permission granted") }
            else { log.warning("Notification permission denied: \(error?.localizedDescription ?? "user declined")") }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Give macOS a stable slot for the item. Anonymous `Item-0` positions can
        // survive monitor-layout changes with an off-screen x coordinate, leaving
        // the process alive but the app completely inaccessible.
        statusItem.autosaveName = "CatEyeStatusItem"
        statusItem.isVisible = true
        if let btn = statusItem.button {
            btn.image = tintedIcon(ghIcon, .secondaryLabelColor)
            btn.imagePosition = .imageOnly
            btn.target = self
            btn.action = #selector(toggle)
            // Re-render the cached tinted icon when the system flips light/dark.
            appearanceObs = btn.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.updateIcon() }
            }
        }

        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        applySystemAppearance()   // pins NSApp.appearance + popover.appearance from defaults

        // System-wide light/dark toggle. NSApp.effectiveAppearance is unreliable for
        // .accessory apps, so we listen for the canonical distributed notification.
        DistributedNotificationCenter.default.addObserver(
            self, selector: #selector(systemAppearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil)

        if REPOS.isEmpty {
            // First run: open popover with settings
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.closeTime = .distantPast
                self.showSettings()   // opens + shows the popover itself
            }
        } else {
            refresh()
        }
        scheduleTimer()
        if relay.canRun { relay.start() }
        rateLimit.onChange = { [weak self] in
            ((self?.popover.contentViewController as? TabVC)?.footerView as? Footer)?.showQuota(self?.rateLimit.latest)
        }
        rateLimit.start()
        updater.canRestart = { [weak self] in !(self?.popover.isShown ?? false) }
        updater.start()
        if let v = updater.takeUpdateNotice() {
            notify(title: "Cat Eye", subtitle: "Updated to v\(v)", body: "The new version is running.", id: "updated-\(v)")
        }

        // New repos of a whole-owner pick start to track after a catalog refresh.
        NotificationCenter.default.addObserver(forName: RepoCatalog.changed, object: catalog, queue: .main) { [weak self] _ in
            guard let self = self, !self.catalog.refreshing else { return }
            self.applyRepoSelection(reopen: false)
        }
        catalog.refreshIfStale()
        catalogTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.catalog.refreshIfStale()
        }
    }

    // True when macOS actually placed the status item in a menu bar. A screen left
    // of or below the built-in display has negative coordinates, so "x >= 0" would
    // wrongly call a perfectly good item unplaced — test against the real screens.
    var statusItemIsPlaced: Bool {
        guard let f = statusItem.button?.window?.frame, f.width > 0 else { return false }
        return NSScreen.screens.contains { $0.frame.intersects(f) }
    }

    // Cat Eye has no Dock icon or normal windows. When Finder, Spotlight, Raycast,
    // or `open` activates an already-running instance, macOS only forwards a reopen
    // event — without this callback nothing appears and the app looks dead.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.statusItemIsPlaced else { self.warnStatusItemMissing(); return }
            // A .transient popover closes the moment the app is not active, and a
            // reopen does not activate an .accessory app on its own.
            NSApp.activate(ignoringOtherApps: true)
            self.closeTime = .distantPast
            if !self.popover.isShown { self.toggle() }
        }
        return true
    }

    // macOS can refuse to place a status item for one bundle id, which leaves this
    // app running with no way in at all. Say so once instead of failing silently.
    func warnStatusItemMissing() {
        guard !warnedStatusItemMissing else { return }
        // Plugging or unplugging a display moves the item between menu bars, and the
        // screen list updates before the item does. Look again before crying wolf —
        // a false alarm here also burns the one warning we get.
        guard statusItemRecheckDone else {
            statusItemRecheckDone = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self = self, !self.statusItemIsPlaced else { return }
                self.warnStatusItemMissing()
            }
            return
        }
        warnedStatusItemMissing = true
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Cat Eye can't reach the menu bar"
        a.informativeText = "macOS refused to place Cat Eye's menu bar icon, so there is no way to open it. Changing the app's bundle identifier clears this."
        a.addButton(withTitle: "Quit Cat Eye")
        a.addButton(withTitle: "Keep Running")
        if a.runModal() == .alertFirstButtonReturn { NSApp.terminate(nil) }
    }

    // MARK: - Polling

    func scheduleTimer() {
        guard !REPOS.isEmpty else {
            timer?.invalidate(); fallbackTimer?.invalidate()
            return
        }
        // The fast cadence exists for the person reading the popover. With it shut,
        // the menu bar icon only has to be roughly right, and 10s polling through a
        // long CI run cost a measured 1,148 REST calls/hour — 23% of the GitHub
        // budget — that nobody was looking at.
        // A healthy relay pushes changes, so polling only reconciles.
        let interval: TimeInterval
        if relay.isHealthy {
            interval = RELAY.reconcileInterval ?? 600
        } else {
            interval = pollInterval(grouped)
        }
        // Each refresh calls this. Keep a timer with the same interval, or frequent
        // refreshes push the reconcile out forever.
        if timer?.isValid != true || timer?.timeInterval != interval {
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                self?.refresh()
                if self?.relay.isHealthy == true { self?.relay.sync() }
            }
            // Generous tolerance lets the system coalesce wakeups (and App Nap us)
            // instead of firing on an exact-deadline timer.
            timer?.tolerance = interval * 0.2
        }
        scheduleFallbackTimer()
    }

    func pollInterval(_ g: [(String, [Run])]) -> TimeInterval {
        (popover.isShown && hasActive(visibleGrouped(g))) ? POLL_ACTIVE : POLL_NORMAL
    }

    // Repos without a webhook get no relay events. Poll them at the normal cadence.
    func scheduleFallbackTimer() {
        let repos = relay.isHealthy ? relayDeployer.unhookedRepos(REPOS) : []
        guard !repos.isEmpty else {
            fallbackTimer?.invalidate(); fallbackTimer = nil
            return
        }
        let interval = pollInterval(grouped.filter { repos.contains($0.0) })
        guard fallbackTimer?.isValid != true || fallbackTimer?.timeInterval != interval else { return }
        fallbackTimer?.invalidate()
        log.info("Polling \(repos.count, privacy: .public) repos without a webhook every \(Int(interval), privacy: .public)s")
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let repos = self.relayDeployer.unhookedRepos(REPOS)
            guard !repos.isEmpty else { return }
            let prs = Date().timeIntervalSince(self.lastFallbackPRRefresh) >= POLL_NORMAL * 0.9
            if prs { self.lastFallbackPRRefresh = Date() }
            self.refreshRepos(repos, includePRs: prs, completedRuns: []) { _ in }
        }
        fallbackTimer?.tolerance = interval * 0.2
    }

    func refresh(force: Bool = false, completion: (() -> Void)? = nil) {
        guard !REPOS.isEmpty else { completion?(); return }
        // Never let refreshes overlap: a slow network poll that outlives the timer
        // interval would otherwise stack concurrent gh-process storms.
        // A coalesced refresh still owes its caller a callback once fresh data lands.
        // Firing it immediately reopened the popover on stale rows. Last one wins:
        // every caller's completion just reopens the popover, so running it once is right.
        guard !refreshInFlight else {
            if let c = completion { pendingCompletion = c }
            return
        }
        refreshInFlight = true
        let repos = REPOS  // snapshot on calling thread
        // PRs don't need the fast active-poll cadence — refresh them on the
        // normal interval (or on demand), halving subprocess spawns while runs
        // are in progress.
        let includePRs = force || Date().timeIntervalSince(lastPRRefresh) >= POLL_NORMAL * 0.9
        let start = Date()
        log.debug("Refresh starting for \(repos.count) repos")
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            var runRes = Array(repeating: (String, [Run])("", []), count: repos.count)
            var prRes = Array(repeating: (String, [PR])("", []), count: repos.count)
            let collectQ = DispatchQueue(label: "com.flarco.cat-eye.collect")
            var tasks: [() -> Void] = []
            for (i, repo) in repos.enumerated() {
                tasks.append {
                    let runs = fetchRuns(repo: repo) ?? []
                    collectQ.sync { runRes[i] = (repo, runs) }
                }
                if includePRs {
                    tasks.append {
                        let prs = fetchPRs(repo: repo)
                        collectQ.sync { prRes[i] = (repo, prs) }
                    }
                }
            }
            // concurrentPerform caps parallelism at the core count, so many repos
            // no longer launch an unbounded burst of simultaneous gh processes.
            DispatchQueue.concurrentPerform(iterations: tasks.count) { tasks[$0]() }
            let elapsed = Date().timeIntervalSince(start)
            let totalRuns = runRes.reduce(0) { $0 + $1.1.count }
            let totalPRs = prRes.reduce(0) { $0 + $1.1.count }
            log.info("Refresh done in \(String(format: "%.1f", elapsed), privacy: .public)s — \(totalRuns) runs, \(totalPRs) PRs")
            DispatchQueue.main.async {
                self.detectTransitions(runRes)
                DeployLog.shared.record(runRes)
                self.grouped = runRes
                if includePRs {
                    self.prGrouped = prRes
                    self.lastPRRefresh = Date()
                }
                self.lastUpdate = Date()
                self.firstLoad = false
                self.refreshInFlight = false
                self.updateIcon()
                self.scheduleTimer()
                completion?()
                let pending = self.pendingCompletion
                self.pendingCompletion = nil
                pending?()
                self.runPendingPartial()
            }
        }
    }

    // Refreshes only the given repos and merges them into the current data.
    // `done` gets false if a run fetch failed, so the relay does not ack those events.
    func refreshRepos(_ repos: [String], includePRs: Bool, completedRuns: [(String, Int)],
                      done: @escaping (Bool) -> Void) {
        guard !refreshInFlight else {
            var p = pendingPartial ?? (Set<String>(), false, [], [])
            p.repos.formUnion(repos); p.prs = p.prs || includePRs
            p.runs += completedRuns; p.dones.append(done)
            pendingPartial = p
            return
        }
        refreshInFlight = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var runRes = [(String, [Run])?](repeating: nil, count: repos.count)
            var prRes = [(String, [PR])?](repeating: nil, count: repos.count)
            let collectQ = DispatchQueue(label: "com.flarco.cat-eye.collect-partial")
            var tasks: [() -> Void] = []
            for (i, repo) in repos.enumerated() {
                tasks.append {
                    let runs = fetchRuns(repo: repo)
                    collectQ.sync { runRes[i] = runs.map { (repo, $0) } }
                }
                if includePRs {
                    tasks.append {
                        let prs = fetchPRs(repo: repo)
                        collectQ.sync { prRes[i] = (repo, prs) }
                    }
                }
            }
            DispatchQueue.concurrentPerform(iterations: tasks.count) { tasks[$0]() }
            let fresh = runRes.compactMap { $0 }
            // Insights backfill: a run that completed and already left the list.
            var backfill: [(String, [Run])] = []
            for (repo, id) in completedRuns {
                let listed = fresh.first { $0.0 == repo }?.1.contains { $0.id == id } ?? false
                if !listed, let run = fetchRun(repo: repo, id: id), run.status == "completed" {
                    backfill.append((repo, [run]))
                }
            }
            let ok = fresh.count == repos.count
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.detectTransitions(fresh, partial: true)
                DeployLog.shared.record(fresh + backfill)
                self.grouped = mergeGrouped(self.grouped, fresh, order: REPOS)
                if includePRs { self.prGrouped = mergeGrouped(self.prGrouped, prRes.compactMap { $0 }, order: REPOS) }
                self.lastUpdate = Date()
                self.refreshInFlight = false
                self.updateIcon()
                self.scheduleTimer()
                done(ok)
                let pending = self.pendingCompletion
                self.pendingCompletion = nil
                pending?()
                self.runPendingPartial()
            }
        }
    }

    func runPendingPartial() {
        guard let p = pendingPartial else { return }
        pendingPartial = nil
        let repos = REPOS.filter { p.repos.contains($0) }
        refreshRepos(repos, includePRs: p.prs, completedRuns: p.runs) { ok in p.dones.forEach { $0(ok) } }
    }

    // Resolves REPOS from the picks. `reopen` is for an explicit save from the settings.
    func applyRepoSelection(reopen: Bool) {
        let previous = REPOS
        REPOS = catalog.resolve(picked: PICKED_REPOS, orgs: PICKED_ORGS)
        if reopen { onConfigSaved(previous: previous); return }
        guard REPOS != previous else { return }
        log.info("Repo catalog changed the tracked repos: \(previous.count) -> \(REPOS.count)")
        syncRelayRepos(previous: previous)
        refresh(force: true)
        scheduleTimer()
    }

    func syncRelayRepos(previous: [String]) {
        if !RELAY.deviceID.isEmpty && !RELAY.workerURL.isEmpty {
            relayDeployer.registerRepos()
            let added = REPOS.filter { !previous.contains($0) }
            let removed = previous.filter { !REPOS.contains($0) }
            if !added.isEmpty {
                let d = relayDeployer
                d.perform("Install webhooks for new repos", { d.installHooks(repos: added) }) { [weak self] _ in
                    d.refreshHookedRepos { self?.scheduleTimer() }
                }
            }
            relayDeployer.pruneHooks(removed: removed)
        }
    }

    func onConfigSaved(previous: [String]) {
        syncRelayRepos(previous: previous)
        prevStatuses = [:]
        firstLoad = true
        grouped = []
        popover.close()
        refresh(force: true) { [weak self] in
            guard let self = self else { return }
            self.closeTime = .distantPast
            self.toggle()
        }
    }

    // MARK: - Icon

    func updateIcon() {
        let shown = visibleGrouped(grouped)
        let (color, badge, label) = overallStatus(shown)
        let active = hasActive(shown)
        statusItem.button?.toolTip = "Cat Eye \u{2014} \(label)"
        // Setting the image redraws the item on each display, which fires the appearance
        // observer again. Without this check the two loop and use a full CPU core.
        let key = IconKey(color: color, badge: badge, active: active)
        guard key != iconKey else { return }
        iconKey = key
        statusItem.button?.image = statusBadgedIcon(ghIcon, color: color, badge: badge)
        if active { startAnimation() } else { stopAnimation() }
    }

    func startAnimation() {
        guard let btn = statusItem.button else { return }
        guard !isPulsing else { return }
        isPulsing = true
        // Breathing pulse via Core Animation: runs entirely in the render server,
        // so the app never wakes per frame (the old 0.15s Timer redrew the status
        // item ~7×/sec for as long as any action was running).
        btn.wantsLayer = true
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.4
        pulse.duration = 1.0
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        btn.layer?.add(pulse, forKey: "cat-eye.pulse")
    }

    func stopAnimation() {
        guard isPulsing else { return }
        isPulsing = false
        statusItem.button?.layer?.removeAnimation(forKey: "cat-eye.pulse")
    }

    // MARK: - Run actions

    func rerun(repo: String, runs: [Run], failedOnly: Bool) {
        guard !runs.isEmpty else { return }
        let endpoint = failedOnly ? "rerun-failed-jobs" : "rerun"
        DispatchQueue.global(qos: .userInitiated).async {
            let errors = runs.compactMap { r -> String? in
                let res = try? ghRun(["api", "-X", "POST", "repos/\(repo)/actions/runs/\(r.id)/\(endpoint)"])
                return res?.ok == true ? nil : "\(r.workflowName ?? r.name): \(res?.err ?? "gh did not run")"
            }
            DispatchQueue.main.async {
                if errors.isEmpty {
                    log.info("Re-run (\(endpoint)) requested for \(runs.count) run(s) in \(repo)")
                } else {
                    log.error("Re-run failed in \(repo): \(errors.joined(separator: "; "))")
                    self.notify(title: repo, subtitle: "Re-run failed", body: errors.joined(separator: "\n"),
                                id: "rerun-\(UUID().uuidString)")
                }
                // GitHub queues the new attempt a moment after the request.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.refreshRepos([repo], includePRs: false, completedRuns: []) { _ in self.reloadList() }
                }
            }
        }
    }

    func setIgnored(_ runs: [Run], ignored: Bool) {
        IGNORED.set(runs, ignored: ignored)
        updateIcon()
        (popover.contentViewController as? TabVC)?.rebuildContent()
    }

    // The run list holds a snapshot of the data, so show fresh data with a new list.
    func reloadList() {
        guard popover.isShown, popover.contentViewController is TabVC else { return }
        buildWithAppearance { popover.contentViewController = makeTabVC() }
    }

    // MARK: - Notifications

    // `partial` means newGrouped holds only some repos: the others keep their entries.
    func detectTransitions(_ newGrouped: [(String, [Run])], partial: Bool = false) {
        guard !firstLoad else {
            for run in newGrouped.flatMap({ $0.1 }) { prevStatuses[run.url] = run.status }
            return
        }
        let newRuns = newGrouped.flatMap { $0.1 }
        for (repo, runs) in newGrouped {
            for run in runs {
                let old = prevStatuses[run.url]
                let wf = run.workflowName ?? run.name
                if run.status == "in_progress" && old != "in_progress" {
                    log.info("Transition: \(wf) on \(run.headBranch) → in_progress (was \(old ?? "new"))")
                    notify(title: repo, subtitle: "\u{25B6}\u{FE0F} Action Started", body: "\(wf) on \(run.headBranch)", id: "start-\(run.url)")
                }
                if run.status == "completed" && (old == "in_progress" || old == "queued") {
                    let ok = run.conclusion == "success"
                    log.info("Transition: \(wf) on \(run.headBranch) → \(run.conclusion ?? "unknown") (was \(old ?? "new"))")
                    notify(title: repo, subtitle: ok ? "\u{2705} Action Passed" : "\u{274C} Action Failed",
                           body: "\(wf) on \(run.headBranch) \u{2014} \(runDuration(run))", id: "end-\(run.url)")
                }
            }
        }
        if partial {
            let repos = Set(newGrouped.map { $0.0 })
            for (repo, runs) in grouped where repos.contains(repo) { for r in runs { prevStatuses[r.url] = nil } }
        } else {
            prevStatuses = [:]
        }
        for run in newRuns { prevStatuses[run.url] = run.status }
    }

    func notify(title: String, subtitle: String, body: String, id: String) {
        let c = UNMutableNotificationContent()
        c.title = title; c.subtitle = subtitle; c.body = body; c.sound = .default
        c.threadIdentifier = title
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler handler: @escaping () -> Void) {
        DispatchQueue.main.async { self.closeTime = .distantPast; self.toggle() }
        handler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
        handler([.banner, .sound])
    }

    // MARK: - Popover

    func makeTabVC() -> TabVC {
        TabVC(grouped: grouped, prGrouped: prGrouped, updated: lastUpdate, loading: firstLoad,
              tab: selectedTab, repo: selectedRepo)
    }

    @objc func toggle() {
        if popover.isShown { popover.close() }
        else if Date().timeIntervalSince(closeTime) > 0.3 {
            // Pin appearance BEFORE constructing the view tree so .cgColor resolves correctly.
            applySystemAppearance()
            if popover.contentViewController == nil || popover.contentViewController is TabVC {
                buildWithAppearance { self.popover.contentViewController = self.makeTabVC() }
            }
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: statusItem.button!.bounds, of: statusItem.button!, preferredEdge: .minY)
            // No refresh here. makeTabVC() snapshots `grouped` at build time and
            // never re-reads it, so a fetch started now lands in a view nobody is
            // looking at — and doRefresh()/onConfigSaved() already refresh before
            // they call toggle(), so it would double their cost.
            scheduleTimer()
        }
    }

    /// True if the system is currently in Dark Mode. Reads CFPreferences directly because
    /// UserDefaults.standard caches the value and serves stale results immediately after
    /// the user flips appearance.
    func isSystemDarkMode() -> Bool {
        let v = CFPreferencesCopyAppValue("AppleInterfaceStyle" as CFString,
                                          kCFPreferencesAnyApplication) as? String
        return v == "Dark"
    }

    func applySystemAppearance() {
        let appearance = NSAppearance(named: isSystemDarkMode() ? .darkAqua : .aqua)
        // NSApp.appearance pins how `NSColor.X.cgColor` resolves process-wide.
        NSApp.appearance = appearance
        popover.appearance = appearance
    }

    /// Construct views under the pinned appearance. The popover loads its view
    /// lazily at show time, so load it here or its CGColors bake in a stale appearance.
    func buildWithAppearance(_ block: () -> Void) {
        NSApp.withPinnedAppearance {
            block()
            _ = popover.contentViewController?.view
        }
    }

    @objc func systemAppearanceChanged() {
        // Distributed notifications can arrive on a background thread, and an Auto
        // appearance switch can post before AppleInterfaceStyle is written. Wait a bit.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            self.applySystemAppearance()
            self.iconKey = nil
            self.updateIcon()
            // Discard the stale view tree (its CGColors are baked in the OLD appearance).
            // Next show reconstructs under the new drawing context.
            let wasShownAsSettings = self.popover.contentViewController is SettingsVC
            let wasShownAsRelay = self.popover.contentViewController is RelaySettingsVC
            let wasShown = self.popover.isShown
            self.popover.close()
            self.popover.contentViewController = nil
            if wasShown {
                self.closeTime = .distantPast
                if wasShownAsSettings { self.showSettings() }
                else if wasShownAsRelay { self.showRelaySettings() }
                else { self.toggle() }
            }
        }
    }

    @objc func showSettings() {
        popover.behavior = .transient
        applySystemAppearance()
        buildWithAppearance { self.popover.contentViewController = SettingsVC(catalog: catalog, updater: updater, picked: Set(PICKED_REPOS), orgs: Set(PICKED_ORGS)) }
        if !popover.isShown {
            closeTime = .distantPast
            toggle()
        }
    }

    @objc func showRelaySettings() {
        applySystemAppearance()
        // Login and installs leave the app, which would close a transient popover.
        popover.behavior = .semitransient
        buildWithAppearance { self.popover.contentViewController = RelaySettingsVC(deployer: relayDeployer, client: relay) }
        if !popover.isShown {
            closeTime = .distantPast
            toggle()
        }
    }

    @objc func showList() {
        popover.behavior = .transient
        applySystemAppearance()
        buildWithAppearance { self.popover.contentViewController = self.makeTabVC() }
    }

    @objc func doRefresh() {
        popover.close()
        refresh(force: true) { [weak self] in
            guard let self = self else { return }
            self.closeTime = .distantPast
            self.toggle()
        }
    }

    @objc func quitApp() { log.info("Cat Eye quitting"); NSApp.terminate(nil) }

    func popoverDidClose(_ notification: Notification) {
        closeTime = Date()
        popover.behavior = .transient
        popover.contentViewController = nil  // Release settings view if open
        scheduleTimer()                      // nobody is watching: back to the slow cadence
        updater.installIfIdle()
    }
}

extension GHActionsBar: RelaySink {
    func relayRefresh(repos: [String], includePRs: Bool, completedRuns: [(String, Int)], done: @escaping (Bool) -> Void) {
        refreshRepos(repos, includePRs: includePRs, completedRuns: completedRuns, done: done)
    }

    // A gap in the log: refresh every repo.
    func relayFullRefresh(done: @escaping (Bool) -> Void) {
        refreshRepos(REPOS, includePRs: true, completedRuns: [], done: done)
    }

    func relayStateChanged() {
        scheduleTimer()
        if relay.state == .live { relayDeployer.refreshHookedRepos { [weak self] in self?.scheduleTimer() } }
        (popover?.contentViewController as? RelaySettingsVC)?.rebuild()
    }
}

extension NSApplication {
    /// Runs `block` with the pinned appearance as the drawing appearance, so every
    /// `NSColor.X.cgColor` read in it resolves to the right light/dark value.
    func withPinnedAppearance(_ block: () -> Void) {
        (appearance ?? effectiveAppearance).performAsCurrentDrawingAppearance(block)
    }
}

// ─── Main ────────────────────────────────────────────────────────────────────

if CommandLine.arguments.contains("--selftest") { runSelfTest(); exit(0) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = GHActionsBar()
app.delegate = delegate
app.run()
