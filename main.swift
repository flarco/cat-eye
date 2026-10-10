import Cocoa
import QuartzCore
import UserNotifications
import os


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
func ghRun(_ args: [String], input: Data? = nil, timeout: TimeInterval? = nil) throws -> GHResult {
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
    if let timeout = timeout {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
            guard proc.isRunning else { return }
            proc.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                if proc.isRunning { kill(proc.processIdentifier, SIGKILL) }
            }
        }
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

struct RunJobStep: Decodable {
    let name: String
    let status: String?
    let conclusion: String?
    let startedAt: String?
    let completedAt: String?
}
struct RunJob: Decodable {
    let id: Int
    let name: String
    let status: String?
    let conclusion: String?
    let url: String?
    let startedAt: String?
    let completedAt: String?
    let runnerName: String?
    let steps: [RunJobStep]?
}
struct CheckAnnotation: Decodable {
    let message: String?
    let path: String?
    let startLine: Int?
    let annotationLevel: String?
}

// Lazily-fetched run detail data. Main-thread access only.
var commitMsgCache: [String: String] = [:]       // head sha → full commit message
var failureCache: [Int: [RunFailure]] = [:]      // run id → failure summaries (stable once completed)
var jobsCache: [Int: (updatedAt: String, jobs: [RunJob])] = [:]  // run id → jobs at that run update
var detailFetchInFlight = Set<String>()

func fetchCommitMessage(repo: String, sha: String) -> String? {
    guard !sha.isEmpty,
          let data = ghShell("api", "repos/\(repo)/commits/\(sha)", "--jq", ".commit.message"),
          let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !s.isEmpty else { return nil }
    return s
}

func fetchRunJobs(repo: String, runId: Int) -> [RunJob]? {
    let step = "{name, status, conclusion, startedAt: .started_at, completedAt: .completed_at}"
    let jq = "[.jobs[] | {id, name, status, conclusion, url: .html_url, startedAt: .started_at, " +
        "completedAt: .completed_at, runnerName: .runner_name, steps: [.steps[]? | \(step)]}]"
    guard let data = ghShell("api", "repos/\(repo)/actions/runs/\(runId)/jobs?per_page=100", "--jq", jq) else { return nil }
    return try? JSONDecoder().decode([RunJob].self, from: data)
}

// The failure message GitHub shows in its annotations box: for each failed job, pull its
// check-run annotations (a job's id IS its check-run id) plus the name of the step that failed.
func fetchRunFailures(repo: String, jobs: [RunJob]) -> [RunFailure] {
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
    // A failure counts until a newer run of the same workflow on the same branch replaces it.
    let failed = g.flatMap { latestPerWorkflow($0.1) }.contains { $0.isFailure && !IGNORED.contains($0) }
    if failed { return (C_FAILURE, "xmark.circle.fill", "Run failed") }
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
// A running or queued run is active now. A finished run was last active when it completed.
func lastActivity(_ r: Run) -> Date {
    if r.status != "completed" { return Date() }
    return parseISO(r.updatedAt) ?? parseISO(r.createdAt) ?? .distantPast
}

// Newest first. Active runs come first.
func newerActivity(_ a: Run, _ b: Run) -> Bool {
    let aActive = a.status != "completed", bActive = b.status != "completed"
    if aActive != bActive { return aActive }
    if aActive { return (parseISO(a.createdAt) ?? .distantPast) > (parseISO(b.createdAt) ?? .distantPast) }
    return lastActivity(a) > lastActivity(b)
}

func byLastActivity(_ runs: [Run]) -> [Run] { runs.sorted(by: newerActivity) }

// The newest run of each workflow on each branch. `runs` is newest first, as the API returns it.
func latestPerWorkflow(_ runs: [Run]) -> [Run] {
    var seen = Set<String>()
    return runs.filter { seen.insert("\($0.workflowName ?? $0.name)|\($0.headBranch)").inserted }
}

func sortedByRecent(_ g: [(String, [Run])]) -> [(String, [Run])] {
    func latest(_ runs: [Run]) -> Date { visibleRuns(runs).map(lastActivity).max() ?? .distantPast }
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
    func passed(_ wf: String) -> Run {
        Run(id: 5, name: wf, displayTitle: "t", status: "completed", conclusion: "success", headBranch: "main",
            headSha: "s", event: "push", url: "u/selftest-\(wf)", updatedAt: "", createdAt: "", startedAt: nil,
            number: 3, workflowName: wf, actorLogin: nil)
    }
    let other = passed("deploy")
    check(overallStatus([("o/a", [other]), ("o/r", [passed("ci"), bad])]).color == C_SUCCESS, "a newer pass of the workflow clears the failure")
    check(overallStatus([("o/a", [other]), ("o/r", [bad])]).color == C_FAILURE, "a failure in any repo turns the icon red")
    check(Badge("main", maxChars: 15).subviews.compactMap { $0 as? NSTextField }.first?.stringValue == "main", "short branch is not cut")
    check(Badge("dependabot/npm/lodash-4.17", maxChars: 15).subviews.compactMap { $0 as? NSTextField }.first?.stringValue == "dependa\u{2026}sh-4.17", "long branch keeps both ends")
    func dispatch(_ wf: String, _ sha: String) -> Run {
        Run(id: 3, name: wf, displayTitle: "t", status: "completed", conclusion: "success",
            headBranch: "main", headSha: sha, event: "workflow_dispatch", url: "u/\(wf)/\(sha)",
            updatedAt: "", createdAt: "", startedAt: nil, number: 1, workflowName: wf, actorLogin: "a")
    }
    let rows = groupRuns([dispatch("Deploy", "s2"), dispatch("Deploy", "s1"), dispatch("Deploy", "s1"), dispatch("Build", "s1")])
    check(rows.map(\.count) == [1, 1, 2], "dispatches on other commits or of the same workflow get their own row")
    func done(_ wf: String, _ created: String, _ updated: String) -> Run {
        Run(id: 4, name: wf, displayTitle: "t", status: "completed", conclusion: "success",
            headBranch: "main", headSha: "s", event: "push", url: "u/\(wf)",
            updatedAt: updated, createdAt: created, startedAt: nil, number: 1, workflowName: wf, actorLogin: nil)
    }
    let order = byLastActivity([done("old", "2026-10-01T10:00:00Z", "2026-10-01T12:00:00Z"),
                                done("new", "2026-10-01T11:00:00Z", "2026-10-01T11:30:00Z"),
                                run("main", "in_progress")])
    check(order.map { $0.workflowName ?? "" } == ["ci", "old", "new"], "recent first sorts by completion time, active on top")
    let latest = latestPerWorkflow([dispatch("Deploy", "s2"), dispatch("Deploy", "s1"), dispatch("Build", "s1")])
    check(latest.map(\.headSha) == ["s2", "s1"], "one row per workflow keeps the newest run")
    let chipJob = RunJob(id: 1, name: "release-linux-amd64", status: "completed", conclusion: "success", url: nil,
                         startedAt: nil, completedAt: nil, runnerName: nil, steps: nil)
    check((JobChip(job: chipJob, notes: [], maxW: 400).subviews.first as? NSTextField)?.stringValue == "release\u{2026}x-amd64",
          "long job names keep both ends")
    let log = "2026-10-01T23:14:09.48Z FAIL\tpkg\t300s\n2026-10-01T23:14:11.29Z ##[error]Process completed with exit code 1.\n" +
        "2026-10-01T23:14:11.32Z Post job cleanup.\n"
    check(JobLogs.errorSnippet(log) == "FAIL\tpkg\t300s\n##[error]Process completed with exit code 1.", "log snippet ends at the error")
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
    check(rl?.footerLabel == "REST 72% · GQL 2%", "footer shows REST and GraphQL \(rl?.footerLabel ?? "")")
    check(RelayDeployer.unhooked(repos, hooked: ["o/hooked", "o/denied"], statuses: sts) == ["O/Bare", "O/Denied"],
          "unhooked repos")
    REPO_COLORS = ["o/a": 3, "o/b": 0]
    check(repoColor("o/a") == REPO_PALETTE[3], "repo color keeps its slot")

    check(StatusOption(id: "1", name: "Done", color: "GREEN").category == .done, "done category")
    check(StatusOption(id: "1", name: "Closed", color: "GREEN").category == .done, "closed category")
    check(StatusOption(id: "1", name: "Shipped", color: "GREEN").category == .done, "shipped category")
    check(StatusOption(id: "1", name: "Blocked", color: "RED").category == .blocked, "blocked category")
    check(StatusOption(id: "1", name: "In review", color: "PURPLE").category == .review, "review category")
    check(StatusOption(id: "1", name: "In progress", color: "YELLOW").category == .progress, "progress category")
    check(StatusOption(id: "1", name: "Doing", color: "YELLOW").category == .progress, "doing category")
    check(StatusOption(id: "1", name: "Backlog", color: "GRAY").category == .todo, "todo category")

    func projectItem(_ id: String, status: String?, fields: [String: String] = [:], assignees: [String] = [],
                     author: String? = "bea", comments: Int = 0, last: CommentRef? = nil) -> ProjectItem {
        ProjectItem(id: id, contentId: "C\(id)", kind: .issue, title: "Item \(id)", url: "https://example/\(id)",
                    databaseId: nil, repo: "o/r", number: 1, state: "OPEN", statusOptionId: status, fields: fields,
                    assignees: assignees, labels: [], author: author, updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    commentCount: comments, lastComment: last, mentionsMe: false)
    }
    let todoOpt = StatusOption(id: "s1", name: "Todo", color: "GRAY")
    let doingOpt = StatusOption(id: "s2", name: "In progress", color: "YELLOW")
    func projectSnap(_ items: [ProjectItem]) -> ProjectSnapshot {
        let summary = ProjectSummary(ref: ProjectRef(owner: "acme", number: 4), nodeId: "PVT_1", title: "Board",
                                     url: "https://github.com/orgs/acme/projects/4", closed: false,
                                     itemCount: items.count, ownerKind: .org)
        return ProjectSnapshot(summary: summary, statusFieldId: "F", statusOptions: [todoOpt, doingOpt],
                               items: items, fetchedAt: Date(timeIntervalSince1970: 1_700_000_100))
    }
    check(ProjectStore.diff(nil, projectSnap([projectItem("a", status: "s1")])).isEmpty, "first snapshot is quiet")
    let before = projectSnap([projectItem("a", status: "s1", fields: ["Priority": "Low"], assignees: ["ada"])])
    let comment = CommentRef(id: "c1", author: "grace", createdAt: Date(timeIntervalSince1970: 1_700_000_050), url: "https://example/c1")
    let after = projectSnap([
        projectItem("a", status: "s2", fields: ["Priority": "High"], assignees: ["ada", "grace"], comments: 2, last: comment),
        projectItem("b", status: "s1"),
    ])
    let changes = ProjectStore.diff(before, after)
    func changed(_ id: String, _ match: (ItemChange) -> Bool) -> Bool {
        changes.contains { $0.itemId == id && match($0.1) }
    }
    check(changed("b") { if case .added = $0 { return true }; return false }, "diff added")
    check(changed("a") { if case .status(let from, let to) = $0 { return from == "Todo" && to == "In progress" }; return false }, "diff status")
    check(changed("a") { if case .field(let name, let from, let to) = $0 { return name == "Priority" && from == "Low" && to == "High" }; return false }, "diff field")
    check(changed("a") { if case .assigned(let who) = $0 { return who == "grace" }; return false }, "diff assigned")
    check(changed("a") { if case .comments(let n, let last) = $0 { return n == 2 && last.id == "c1" }; return false }, "diff comments")
    let removed = ProjectStore.diff(after, projectSnap([projectItem("b", status: "s1")]))
    check(removed.contains { $0.itemId == "a" && $0.1 == .removed }, "diff removed")

    var notes: [(title: String, subtitle: String, body: String, id: String)] = []
    let notifier = ProjectNotifier(me: { "ada" }, post: { notes.append(($0, $1, $2, $3)) })
    var clock = Date(timeIntervalSince1970: 1_000_000)
    notifier.now = { clock }
    let mine = projectSnap([projectItem("a", status: "s1", assignees: ["ada"])])
    let theirs = projectSnap([projectItem("b", status: "s1", assignees: ["bea"])])
    let settings = ProjectNotificationSettings()
    notifier.handle([("a", .mention)], in: mine, settings: settings)
    notifier.handle([("b", .mention)], in: theirs, settings: settings)
    check(notes.count == 1 && notes[0].id == "project:a", "mention only on my items")
    notes = []
    notifier.handle([("b", .status(from: "Todo", to: "Done"))], in: theirs, settings: settings)
    notifier.handle([("a", .status(from: "Todo", to: "Done"))], in: mine, settings: settings)
    check(notes.count == 1, "status notifies my items only by default")
    notes = []
    notifier.handle([("b", .added)], in: theirs, settings: settings)
    check(notes.count == 1, "added notifies any item")
    notes = []
    clock = clock.addingTimeInterval(180)
    notifier.handle([("b", .assigned("Ada"))], in: theirs, settings: settings)
    notifier.handle([("b", .assigned("bea"))], in: theirs, settings: settings)
    check(notes.count == 1 && notes[0].body == "Assigned Ada", "assigned notifies only me")
    notes = []
    let own = ItemChange.comments(new: 1, last: CommentRef(id: "c", author: "Ada", createdAt: clock, url: "u"))
    notifier.handle([("a", own)], in: mine, settings: settings)
    check(notes.isEmpty, "own comments are skipped")
    notifier.handle([("a", .field(name: "Priority", from: "Low", to: "High"))], in: mine, settings: settings)
    check(notes.isEmpty, "other fields stay quiet")
    notes = []
    notifier.handle([("a", .status(from: "Todo", to: "In progress"))], in: mine, settings: settings)
    clock = clock.addingTimeInterval(60)
    notifier.handle([("a", .closed)], in: mine, settings: settings)
    check(notes.count == 2 && notes[0].id == notes[1].id, "grouped notification keeps one id")
    check(notes[1].body.contains("Status") && notes[1].body.contains("Closed"), "grouped body \(notes[1].body)")
    clock = clock.addingTimeInterval(180)
    notifier.handle([("a", .reopened)], in: mine, settings: settings)
    check(notes[2].body == "Reopened", "a new window after 2 minutes")

    func relayEvent(_ json: String) -> RelayEvent {
        try! JSONDecoder().decode(RelayEvent.self, from: Data(json.utf8))
    }
    let plan = relayApplyPlan([
        relayEvent(#"{"seq":1,"deliveryId":"a","repo":"o/kept","kind":"workflow_run","action":"completed","runId":9}"#),
        relayEvent(#"{"seq":2,"deliveryId":"b","repo":"","kind":"projects_v2_item","projectId":"PVT_1","itemId":"PVTI_1"}"#),
        relayEvent(#"{"seq":3,"deliveryId":"c","repo":"acme/app","kind":"issues","issueNumber":4}"#),
        relayEvent(#"{"seq":4,"deliveryId":"d","repo":"o/other","kind":"pull_request","prNumber":3}"#),
    ], knownRepos: ["O/Kept"])
    check(plan.repos == ["O/Kept"] && plan.completedRuns.count == 1
            && plan.completedRuns[0].0 == "O/Kept" && plan.completedRuns[0].1 == 9, "relay plan keeps known repos")
    check(plan.includePRs, "pull request events refresh PRs")
    check(plan.projectNodeIds == ["PVT_1"] && plan.issues.count == 1
            && plan.issues[0].repo == "acme/app" && plan.issues[0].number == 4, "relay plan splits project events")

    let nodes: [Any] = [
        NSNull(),
        ["id": "PVT_1", "number": NSNumber(value: 3), "title": "Fritz Tasks", "url": "https://github.com/users/flarco/projects/3",
         "closed": false, "items": ["totalCount": 1]],
    ]
    let parsed = projectSummaries(from: nodes, owner: "flarco", kind: .user)
    check(parsed.count == 1 && parsed[0].title == "Fritz Tasks" && parsed[0].ref.number == 3, "null project nodes are skipped")
    check(projectItemDatabaseId(nodeId: "PVTI_lAHOAHUM4s4BmgROzg_6shs") == "268087835", "item id from node")
    check(projectItemURL(projectURL: "https://github.com/users/flarco/projects/3/", nodeId: "PVTI_x", databaseId: "268087835")
            == "https://github.com/users/flarco/projects/3/views/1?pane=issue&itemId=268087835", "item pane url")

    let oldConfig = #"{"repos":["o/r"],"pollInterval":30}"#.data(using: .utf8)!
    let decoded = try? JSONDecoder().decode(AppConfig.self, from: oldConfig)
    check(decoded?.projects == nil && decoded?.repos == ["o/r"], "old config without projects decodes")

    // Projects: order, fold, filter.
    let oldProjects = try? JSONDecoder().decode(ProjectsConfig.self, from: Data(#"{"picked":["a/1"],"pollMinutes":5}"#.utf8))
    check(oldProjects?.order == [] && oldProjects?.folded == [] && oldProjects?.capture == CaptureConfig()
            && oldProjects?.picked == ["a/1"], "old projects config gets the new defaults")
    func summary(_ owner: String, _ n: Int, _ title: String) -> ProjectSummary {
        ProjectSummary(ref: ProjectRef(owner: owner, number: n), nodeId: "N\(n)", title: title, url: "", closed: false,
                       itemCount: 0, ownerKind: .org)
    }
    var orderCfg = ProjectsConfig()
    orderCfg.order = ["zed/9", "ACME/2", "gone/7"]
    let ordered = orderCfg.sorted([summary("acme", 1, "Beta"), summary("acme", 2, "Alpha"), summary("zed", 9, "Zed"),
                                   summary("bolt", 3, "Bolt"), summary("acme", 4, "Aardvark")]).map(\.ref.key)
    check(ordered == ["zed/9", "acme/2", "acme/4", "acme/1", "bolt/3"], "project order \(ordered)")
    orderCfg.setFolded("acme/1", true)
    check(orderCfg.isFolded("ACME/1"), "fold is case-insensitive")
    orderCfg.setFolded("acme/1", false)
    check(orderCfg.folded.isEmpty, "unfold")
    let nextOpt = StatusOption(id: "s3", name: "Next", color: "BLUE")
    let reviewOpt = StatusOption(id: "s4", name: "In review", color: "PURPLE")
    let doneOpt = StatusOption(id: "s5", name: "Done", color: "GREEN")
    let foldSnap = ProjectSnapshot(summary: summary("acme", 4, "Board"), statusFieldId: "F",
                                   statusOptions: [todoOpt, nextOpt, reviewOpt, doneOpt],
                                   items: [projectItem("1", status: "s3"), projectItem("2", status: "s4"),
                                           projectItem("3", status: "s5"), projectItem("4", status: nil)],
                                   fetchedAt: Date())
    check(foldSnap.notDoneCount == 3, "fold count is items not done")
    var bodyItem = projectItem("9", status: nil)
    bodyItem.body = "The Relay drops events"
    check(bodyItem.matches("relay") && bodyItem.matches("ITEM 9") && bodyItem.matches("  ") && !bodyItem.matches("nope"),
          "filter matches title and body")

    // AI dialects, without network.
    var aiCfg = AIConfig()
    aiCfg.baseURL = "https://llm.example.com/v1/"
    aiCfg.model = "m1"
    let aiReq = AIRequest(system: "SYS", user: "USER", maxTokens: 300)
    func jsonBody(_ r: URLRequest?) -> [String: Any] {
        (r?.httpBody).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }
    let oa = try? OpenAIDialect().urlRequest(aiReq, cfg: aiCfg, key: "k1")
    check(oa?.url?.absoluteString == "https://llm.example.com/v1/chat/completions", "openai url \(oa?.url?.absoluteString ?? "")")
    check(oa?.value(forHTTPHeaderField: "Authorization") == "Bearer k1", "openai bearer")
    check(jsonBody(oa)["reasoning_effort"] as? String == "low" && jsonBody(oa)["model"] as? String == "m1", "openai effort")
    check((jsonBody(oa)["messages"] as? [[String: Any]])?.first?["role"] as? String == "system", "openai system message")
    aiCfg.baseURL = "https://llm.example.com/v1"
    aiCfg.effort = "none"
    let oaNone = try? OpenAIDialect().urlRequest(aiReq, cfg: aiCfg, key: "k1")
    check(oaNone?.url?.absoluteString == "https://llm.example.com/v1/chat/completions", "openai url without slash")
    check(jsonBody(oaNone)["reasoning_effort"] == nil, "effort none leaves out the field")
    aiCfg.format = .anthropic
    aiCfg.baseURL = "https://api.anthropic.com/"
    let an = try? AnthropicDialect().urlRequest(aiReq, cfg: aiCfg, key: "k2")
    check(an?.url?.absoluteString == "https://api.anthropic.com/v1/messages", "anthropic url")
    check(an?.value(forHTTPHeaderField: "x-api-key") == "k2" && an?.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01",
          "anthropic headers")
    check(jsonBody(an)["max_tokens"] as? Int == 300 && jsonBody(an)["system"] as? String == "SYS", "anthropic body")
    check(AnthropicDialect.endpoint("https://proxy.example/v1") == "https://proxy.example/v1/messages", "anthropic url with /v1")
    let oaReply = Data(#"{"choices":[{"message":{"role":"assistant","content":"Hello"}}]}"#.utf8)
    check((try? OpenAIDialect().text(from: oaReply, status: 200)) == "Hello", "openai reply")
    let anReply = Data(#"{"content":[{"type":"thinking","thinking":"x"},{"type":"text","text":"Hi"},{"type":"text","text":"!"}]}"#.utf8)
    check((try? AnthropicDialect().text(from: anReply, status: 200)) == "Hi!", "anthropic reply")
    let errBody = Data(#"{"error":{"message":"Invalid API key\nmore","type":"auth"}}"#.utf8)
    do { _ = try OpenAIDialect().text(from: errBody, status: 401); check(false, "401 must throw") }
    catch { check(error as? AIError == .http(401, "Invalid API key"), "http error \(error)") }

    // Suggestion parsing.
    let sizeField = ProjectField(id: "FS", name: "Size", options: [StatusOption(id: "o1", name: "S", color: "GRAY"),
                                                                   StatusOption(id: "o2", name: "L", color: "GRAY")])
    let draftCtx = DraftContext(projects: [("flarco/3", "Fritz Tasks"), ("acme/1", "Board")], fields: [sizeField])
    let reply = """
    Sure! Here it is:
    ```json
    {"title": "  \(String(repeating: "x", count: 80)).", "alternatives": ["Other", "Third"],
     "fields": {"size": "l", "Priority": "P0", "Size2": "S"}, "project": "FLARCO/3", "reason": "personal"}
    ```
    """
    let sug = DraftSuggestion.parse(reply, ctx: draftCtx)
    check(sug?.title.count == 70 && sug?.alternatives == ["Other", "Third"], "suggestion title and alternatives")
    check(sug?.fields == ["Size": "L"], "unknown fields and options are dropped \(sug?.fields ?? [:])")
    check(sug?.project == "flarco/3" && sug?.reason == "personal", "project key is normalized")
    check(DraftSuggestion.parse(#"{"title":"Fix it","project":"nope/1"}"#, ctx: draftCtx)?.project == nil, "unknown project dropped")
    check(DraftSuggestion.parse("no json here", ctx: draftCtx) == nil, "no JSON gives nil")
    check(unfenced("```markdown\n## Context\nText\n```") == "## Context\nText", "fence removed")

    // The AI switch needs a test that passed for the current values.
    var gate = AIConfig()
    gate.baseURL = "https://a"; gate.model = "m"; gate.enabled = true
    gate.verified = gate.fingerprint(key: "k")
    check(gate.isOn(key: "k") && !gate.isOn(key: "k2") && !gate.isOn(key: nil), "ai on only with the tested key")
    var changed = gate; changed.model = "m2"
    check(!changed.isOn(key: "k"), "model change turns ai off")
    changed = gate; changed.baseURL = "https://b"
    check(!changed.isOn(key: "k"), "url change turns ai off")
    changed = gate; changed.format = .anthropic
    check(!changed.isOn(key: "k"), "format change turns ai off")
    changed = gate; changed.enabled = false
    check(!changed.isOn(key: "k"), "disabled ai is off")
    check(changed.extraContext == "" && (try? JSONDecoder().decode(AIConfig.self, from: Data("{}".utf8)))?.effort == "low",
          "ai config defaults")

    // Copy for agent.
    let agentSnap = ProjectSnapshot(summary: ProjectSummary(ref: ProjectRef(owner: "flarco", number: 3), nodeId: "P",
                                                            title: "Fritz Tasks", url: "https://github.com/users/flarco/projects/3",
                                                            closed: false, itemCount: 2, ownerKind: .user),
                                    statusFieldId: "F", statusOptions: [todoOpt, doingOpt], items: [], fetchedAt: Date())
    let draftItem = ProjectItem(id: "PVTI_x", contentId: "DI_1", kind: .draft, title: "Add quick capture", url: nil,
                                databaseId: "42", repo: nil, number: nil, state: nil, statusOptionId: "s1",
                                fields: ["Size": "L", "Title": "Add quick capture"], assignees: [], labels: [], author: nil,
                                updatedAt: Date(), commentCount: 0, lastComment: nil, mentionsMe: false, body: "Use ⌃⌥N.\n")
    check(draftItem.agentMarkdown(snap: agentSnap, comments: []) == """
    # Add quick capture

    Project: flarco/Fritz Tasks · Status: Todo · Draft · Size: L
    https://github.com/users/flarco/projects/3/views/1?pane=issue&itemId=42

    Use ⌃⌥N.

    ## Comments
    _None_

    """, "agent markdown for a draft")
    let issueItem = ProjectItem(id: "PVTI_y", contentId: "I_1", kind: .issue, title: "Fix login", url: "https://github.com/o/r/issues/5",
                                databaseId: "43", repo: "o/r", number: 5, state: "OPEN", statusOptionId: "s2",
                                fields: [:], assignees: ["ada"], labels: [], author: "bea", updatedAt: Date(),
                                commentCount: 2, lastComment: nil, mentionsMe: false, body: nil)
    let c1 = CommentRef(id: "c1", author: "bea", createdAt: Date(timeIntervalSince1970: 1_700_000_000), url: "", body: "First\nline two")
    let c2 = CommentRef(id: "c2", author: "ada", createdAt: Date(timeIntervalSince1970: 1_700_100_000), url: "", body: "Done?")
    check(issueItem.agentMarkdown(snap: agentSnap, comments: [c2, c1]) == """
    # Fix login

    Project: flarco/Fritz Tasks · Status: In progress · Issue: o/r#5 · Assignees: @ada
    https://github.com/users/flarco/projects/3/views/1?pane=issue&itemId=43

    _No description_

    ## Comments
    - @bea (2023-11-14): First
      line two
    - @ada (2023-11-16): Done?

    """, "agent markdown for an issue with comments")

    // Quick capture shortcut label.
    check(CaptureConfig().shortcutLabel == "⌃⌥N", "default shortcut label")
    var cap = CaptureConfig()
    cap.keyCode = 40; cap.modifiers = CaptureConfig.carbonModifiers([.command, .shift])
    check(cap.shortcutLabel == "⇧⌘K", "shortcut label \(cap.shortcutLabel)")
    cap.modifiers = 0
    check(cap.shortcutLabel == "None" && !cap.hasShortcut, "cleared shortcut")

    print("SELFTEST OK — \(ins.count) insights, report \(md.count) chars")
}


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
func statusBadgedIcon(_ base: NSImage?, color: NSColor, badge: String?, dot: Bool = false) -> NSImage {
    guard let base = base else { return NSImage() }
    let sz = base.size
    let img = NSImage(size: sz, flipped: false) { rect in
        base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        color.set()
        rect.fill(using: .sourceAtop)
        if let name = badge, let sym = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
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
        }
        // A blue dot for unread project items. The CI color keeps priority; the dot only adds information.
        if dot {
            let d: CGFloat = 5
            let dRect = NSRect(x: sz.width - d - 0.5, y: sz.height - d - 0.5, width: d, height: d)
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.saveGState()
                ctx.setBlendMode(.destinationOut)
                NSColor.black.set()
                NSBezierPath(ovalIn: dRect.insetBy(dx: -1.2, dy: -1.2)).fill()
                ctx.restoreGState()
            }
            C_RUNNING.setFill()
            NSBezierPath(ovalIn: dRect).fill()
        }
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

    // REST and GraphQL sit side by side. The colour still follows the fuller bucket.
    var footerLabel: String {
        buckets.map { name, bucket in
            let short = name == "GraphQL" ? "GQL" : name
            return "\(short) \(Int((bucket.fraction * 100).rounded()))%"
        }.joined(separator: " · ")
    }

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


// ─── Tab View ────────────────────────────────────────────────────────────────

enum Tab: Int, CaseIterable {
    case actions, prs, projects, insights

    var title: String {
        switch self {
        case .actions: return "Actions"
        case .prs: return "PRs"
        case .projects: return "Projects"
        case .insights: return "Insights"
        }
    }

    var isVisible: Bool {
        switch self {
        case .actions: return TABS.actions
        case .prs: return TABS.prs
        case .projects: return PROJECTS_CFG.showTab
        case .insights: return TABS.insights
        }
    }

    static var visible: [Tab] {
        let tabs = allCases.filter(\.isVisible)
        return tabs.isEmpty ? [.actions] : tabs
    }
}

let TAB_H: CGFloat = 36
let SUB_H: CGFloat = 32

class TabVC: NSViewController {
    var grouped: [(String, [Run])]
    var prGrouped: [(String, [PR])]
    var updated: Date
    var loading: Bool
    var selectedTab: Tab
    var selectedRepo: String?
    var expandedPR: String?
    var expandedRun: String?
    var expandedItem: String?
    var projectView: ProjectView = PROJECTS_CFG.defaultView
    var assignedOnly = false
    var unreadOnly = false
    var statusFilter: [String: String] = [:]
    var showAllProjects: Set<String> = []
    var selectedProject: String?
    var projectError: String?
    var timelineCache: [String: [ActivityEntry]] = [:]
    var projectQuery = ""
    var projectNotice: String?
    var editingItem: String?
    var itemEdit: ItemEdit?
    var bodyExpanded: Set<String> = []
    var sheet: NewItemSheet?
    var searchField: NSSearchField?
    var keyMonitor: Any?
    var dragLine: NSView?
    var dragTarget: Int?
    var scrollView: NSScrollView!
    var doc: Flipped!
    var footerView: NSView!

    var showsSubBar: Bool { selectedTab == .actions || selectedTab == .projects }
    var chrome: CGFloat { TAB_H + (showsSubBar ? SUB_H : 0) }

    init(grouped: [(String, [Run])], prGrouped: [(String, [PR])], updated: Date, loading: Bool,
         tab: Tab, repo: String?, expandedPR: String? = nil) {
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

        // ── Top bar: tabs + repo or project filter ──
        let topBar = NSView(frame: NSRect(x: 0, y: 0, width: w, height: TAB_H))
        topBar.wantsLayer = true
        topBar.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.9).cgColor

        let tabs = Tab.visible
        let unread = (NSApp.delegate as? GHActionsBar)?.projectStore.unreadCount() ?? 0
        let labels = tabs.map { tab -> String in
            if tab == .projects && unread > 0 { return "Projects \(unread)" }
            return tab.title
        }
        let seg = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: self, action: #selector(tabChanged(_:)))
        seg.selectedSegment = tabs.firstIndex(of: selectedTab) ?? 0
        seg.frame = NSRect(x: 8, y: 6, width: min(420, w - 200), height: 24)
        seg.font = .systemFont(ofSize: 11, weight: .medium)
        topBar.addSubview(seg)
        buildFilterPopup(in: topBar, w: w)
        container.addSubview(topBar)
        if showsSubBar { container.addSubview(subBar(w)) }

        // ── Footer (fixed at bottom) ──
        let footer = Footer(w, updated: updated)

        // ── Scroll content ──
        let scrollH = POP_MAX_H - chrome - FTR_H
        scrollView = NSScrollView(frame: NSRect(x: 0, y: chrome, width: w, height: scrollH))
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

    // Shows fresh data in the open panel. Keeps the expanded row and the scroll position.
    func update(grouped: [(String, [Run])], prGrouped: [(String, [PR])], updated: Date, loading: Bool) {
        self.grouped = grouped; self.prGrouped = prGrouped
        self.updated = updated; self.loading = loading
        guard isViewLoaded else { return }
        (footerView as? Footer)?.showUpdated(updated)
        // A rebuild would take the focus from the editor.
        if editingItem != nil || dragLine != nil { return }
        let origin = scrollView.contentView.bounds.origin
        JobSummary.close()  // the rebuild removes its chip
        rebuildContent()
        let maxY = max(0, doc.frame.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: origin.x, y: min(origin.y, maxY)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func rebuildContent() {
        NSApp.withPinnedAppearance {
            doc.subviews.forEach { $0.removeFromSuperview() }
            let w = POP_W
            var rows: [NSView] = []

            switch selectedTab {
            case .projects:
                rows = buildProjectsContent(w)
            case .actions where REPOS.isEmpty, .prs where REPOS.isEmpty, .insights where REPOS.isEmpty:
                rows.append(EmptyRow("No repos configured. Open Settings to get started.", w: w, icon: "gearshape"))
            case .actions:
                rows = buildActionsContent(w)
            case .prs:
                rows = buildPRContent(w)
            case .insights:
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
        let scrollHMax = POP_MAX_H - chrome - FTR_H
        let visScrollH = min(doc.frame.height, scrollHMax)
        scrollView.frame.origin.y = chrome
        scrollView.frame.size.height = visScrollH
        footerView.frame.origin.y = chrome + visScrollH
        var totalH = chrome + visScrollH + FTR_H
        if let sheet {
            totalH = max(totalH, sheet.cardHeight)
            sheet.frame = NSRect(x: 0, y: 0, width: POP_W, height: totalH)
        }
        view.frame.size.height = totalH
        preferredContentSize = NSSize(width: POP_W, height: totalH)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.window == self.view.window, self.sheet == nil, self.selectedTab == .projects else { return e }
            let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if self.editingItem != nil {
                if e.keyCode == 53 { self.endEdit(); return nil }
                if e.keyCode == 36 && mods.contains(.command) { self.saveEdit(); return nil }
                return e
            }
            if e.keyCode == 53, self.view.window?.firstResponder === self.searchField?.currentEditor(), !self.projectQuery.isEmpty {
                self.searchField?.stringValue = ""
                self.projectQuery = ""
                (NSApp.delegate as? GHActionsBar)?.projectQuery = ""
                self.rebuildContent()
                return nil
            }
            guard mods == .command else { return e }
            switch e.charactersIgnoringModifiers?.lowercased() {
            case "n": self.presentNewItem(target: self.selectedProject, prefill: nil); return nil
            case "f": self.view.window?.makeFirstResponder(self.searchField); return nil
            default: return e
            }
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    // ⌘N or "+": the sheet sits over the list. `target` nil lets AI pick the project.
    func presentNewItem(target: String?, prefill: String?, suggest: Bool = false) {
        guard let app = NSApp.delegate as? GHActionsBar else { return }
        let projects = app.projectCatalog.resolve(PROJECTS_CFG).filter { app.projectStore.snapshots[$0.ref.key] != nil }
        guard !projects.isEmpty else { return }
        sheet?.removeFromSuperview()
        let s = NewItemSheet(store: app.projectStore, projects: projects, repoCatalog: app.catalog,
                             target: target, prefill: prefill, w: POP_W)
        s.onClose = { [weak self] key, notice in self?.closeNewItem(key: key, notice: notice) }
        s.onResize = { [weak self] in self?.relayout() }
        view.addSubview(s)
        sheet = s
        app.popover.behavior = .semitransient
        relayout()
        s.focus()
        if suggest && s.aiDraft && !s.body.isEmpty { s.suggest() }
    }

    func closeNewItem(key: String?, notice: String?) {
        sheet?.removeFromSuperview()
        sheet = nil
        let app = NSApp.delegate as? GHActionsBar
        app?.popover.behavior = expandedItem != nil ? .semitransient : .transient
        if let key, PROJECTS_CFG.isFolded(key) {
            PROJECTS_CFG.setFolded(key, false)
            saveConfig()
        }
        if let notice {
            projectNotice = notice
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self, self.projectNotice == notice else { return }
                self.projectNotice = nil
                self.rebuildContent()
            }
        }
        rebuildContent()
    }


    func buildFilterPopup(in topBar: NSView, w: CGFloat) {
        let popup = NSPopUpButton(frame: NSRect(x: w - 188, y: 6, width: 176, height: 24), pullsDown: false)
        popup.font = .systemFont(ofSize: 11)
        if selectedTab == .projects {
            popup.addItem(withTitle: "All projects")
            let projects = (NSApp.delegate as? GHActionsBar)?.projectCatalog.resolve(PROJECTS_CFG) ?? []
            var lastOwner = ""
            for p in projects {
                if p.ref.owner.caseInsensitiveCompare(lastOwner) != .orderedSame {
                    let head = NSMenuItem(title: p.ref.owner, action: nil, keyEquivalent: "")
                    head.isEnabled = false
                    popup.menu?.addItem(head)
                    lastOwner = p.ref.owner
                }
                let item = NSMenuItem(title: "  " + p.title, action: nil, keyEquivalent: "")
                item.representedObject = p.ref.key
                popup.menu?.addItem(item)
                if selectedProject == p.ref.key { popup.select(item) }
            }
            if selectedProject == nil { popup.selectItem(at: 0) }
            popup.action = #selector(projectChanged(_:))
        } else {
            popup.addItem(withTitle: "All Repos")
            for repo in REPOS { popup.addItem(withTitle: repo) }
            if let sel = selectedRepo, let idx = REPOS.firstIndex(of: sel) { popup.selectItem(at: idx + 1) }
            else { popup.selectItem(at: 0) }
            popup.action = #selector(repoChanged(_:))
        }
        popup.target = self
        topBar.addSubview(popup)
    }

    func subBar(_ w: CGFloat) -> NSView {
        let bar = NSView(frame: NSRect(x: 0, y: TAB_H, width: w, height: SUB_H))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.75).cgColor
        if selectedTab == .actions {
            let cb = NSButton(checkboxWithTitle: "Default only", target: self, action: #selector(toggleBranchFilter(_:)))
            cb.font = .systemFont(ofSize: 11)
            cb.state = FILTER_DEFAULT_BRANCHES ? .on : .off
            cb.frame = NSRect(x: 12, y: 6, width: 110, height: 20)
            cb.toolTip = "Hide workflow runs from branches other than main or develop"
            bar.addSubview(cb)
            let sortCB = NSButton(checkboxWithTitle: "Recent first", target: self, action: #selector(toggleSortByRecent(_:)))
            sortCB.font = .systemFont(ofSize: 11)
            sortCB.state = SORT_BY_RECENT ? .on : .off
            sortCB.frame = NSRect(x: 130, y: 6, width: 110, height: 20)
            sortCB.toolTip = "Show each run in its own row, newest first. Turn off to group the workflows of one commit."
            bar.addSubview(sortCB)
        } else {
            let seg = NSSegmentedControl(labels: ["By project", "Activity"], trackingMode: .selectOne,
                                         target: self, action: #selector(projectViewChanged(_:)))
            seg.selectedSegment = projectView == .activity ? 1 : 0
            seg.font = .systemFont(ofSize: 11)
            seg.frame = NSRect(x: 8, y: 4, width: 180, height: 24)
            bar.addSubview(seg)
            let mine = NSButton(checkboxWithTitle: "Assigned to me", target: self, action: #selector(toggleAssigned(_:)))
            mine.font = .systemFont(ofSize: 11)
            mine.state = assignedOnly ? .on : .off
            mine.frame = NSRect(x: 200, y: 6, width: 120, height: 20)
            bar.addSubview(mine)
            let unread = NSButton(checkboxWithTitle: "Unread only", target: self, action: #selector(toggleUnread(_:)))
            unread.font = .systemFont(ofSize: 11)
            unread.state = unreadOnly ? .on : .off
            unread.frame = NSRect(x: 326, y: 6, width: 104, height: 20)
            bar.addSubview(unread)
            let search = NSSearchField(frame: NSRect(x: 436, y: 5, width: w - 436 - 40, height: 22))
            search.placeholderString = "Filter  ⌘F"
            search.font = .systemFont(ofSize: 11)
            search.stringValue = projectQuery
            search.sendsSearchStringImmediately = true
            search.target = self; search.action = #selector(queryChanged(_:))
            search.isEnabled = projectView == .board
            bar.addSubview(search)
            searchField = search
            let add = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: "New item")!,
                               target: self, action: #selector(newItem))
            add.bezelStyle = .rounded
            add.isBordered = true
            add.bezelColor = .controlAccentColor
            add.contentTintColor = .white
            add.symbolConfiguration = .init(pointSize: 11, weight: .bold)
            add.frame = NSRect(x: w - 34, y: 4, width: 26, height: 24)
            add.toolTip = "New item (⌘N)"
            bar.addSubview(add)
        }
        return bar
    }

    @objc func tabChanged(_ sender: NSSegmentedControl) {
        let tabs = Tab.visible
        let idx = min(max(0, sender.selectedSegment), tabs.count - 1)
        selectedTab = tabs[idx]
        // Reassigning contentViewController is what NSPopover observes at show time;
        // calling loadView() alone leaves stale tab body visible in an already-shown popover.
        let appDel = NSApp.delegate as? GHActionsBar
        rememberProjectUI()
        appDel?.selectedTab = selectedTab
        appDel?.selectedRepo = selectedRepo
        expandedPR = nil
        expandedRun = nil
        appDel?.applySystemAppearance()
        appDel?.buildWithAppearance { appDel?.popover.contentViewController = appDel?.makeTabVC() }
    }

    func rememberProjectUI() {
        let app = NSApp.delegate as? GHActionsBar
        app?.projectView = projectView
        app?.projectAssignedOnly = assignedOnly
        app?.projectUnreadOnly = unreadOnly
        app?.expandedItem = expandedItem
        app?.selectedProject = selectedProject
        app?.projectStatusFilter = statusFilter
        app?.projectShowAll = showAllProjects
    }

    @objc func projectViewChanged(_ sender: NSSegmentedControl) {
        projectView = sender.selectedSegment == 1 ? .activity : .board
        rememberProjectUI()
        rebuildContent()
    }
    @objc func queryChanged(_ sender: NSSearchField) {
        projectQuery = sender.stringValue
        (NSApp.delegate as? GHActionsBar)?.projectQuery = projectQuery
        rebuildContent()
    }
    @objc func newItem() { presentNewItem(target: selectedProject, prefill: nil) }
    @objc func toggleAssigned(_ sender: NSButton) {
        assignedOnly = sender.state == .on
        rememberProjectUI()
        rebuildContent()
    }
    @objc func toggleUnread(_ sender: NSButton) {
        unreadOnly = sender.state == .on
        rememberProjectUI()
        rebuildContent()
    }
    @objc func projectChanged(_ sender: NSPopUpButton) {
        selectedProject = sender.selectedItem?.representedObject as? String
        rememberProjectUI()
        expandedItem = nil
        rebuildContent()
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


// ─── App ─────────────────────────────────────────────────────────────────────

class GHActionsBar: NSObject, NSApplicationDelegate, NSPopoverDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var timer: Timer?
    var fallbackTimer: Timer?
    var lastFallbackPRRefresh = Date.distantPast
    var isPulsing = false
    struct IconKey: Equatable { let color: NSColor; let badge: String?; let active: Bool; let dot: Bool }
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
    var selectedTab: Tab = .actions
    var selectedRepo: String? = nil
    var selectedProject: String?
    var projectView: ProjectView = .board
    var projectAssignedOnly = false
    var projectUnreadOnly = false
    var expandedItem: String?
    var projectStatusFilter: [String: String] = [:]
    var projectShowAll: Set<String> = []
    var projectQuery = ""
    var pendingProjectItem: String?
    var lastSettingsTab: SettingsTab = .general
    var lastSyncedOrgs: [String] = []
    var ghScopes = Set<String>()
    var scopesKnown = false
    var viewerLogin: String?
    var appearanceObs: NSKeyValueObservation?
    var warnedStatusItemMissing = false
    var statusItemRecheckDone = false
    let relayDeployer = RelayDeployer()
    let catalog = RepoCatalog(path: REPO_CACHE_PATH)
    let projectCatalog = ProjectCatalog(api: ProjectAPI(), path: PROJECT_CACHE_PATH)
    lazy var projectNotifier: ProjectNotifier = {
        ProjectNotifier(me: { [weak self] in self?.viewerLogin }, post: { [weak self] title, subtitle, body, id in
            self?.notify(title: title, subtitle: subtitle, body: body, id: id)
        })
    }()
    lazy var projectStore: ProjectStore = {
        let s = ProjectStore(api: ProjectAPI(), notifier: projectNotifier,
                             statePath: PROJECT_STATE_PATH, activityPath: PROJECT_ACTIVITY_PATH)
        s.relayIsLive = { [weak self] in self?.relay.state == .live }
        s.onChange = { [weak self] in
            self?.updateIcon()
            self?.reloadList()
        }
        return s
    }()
    var catalogTimer: Timer?
    var captureHotKey: GlobalHotKey?
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
        installEditMenu()
        REPOS = catalog.resolve(picked: PICKED_REPOS, orgs: PICKED_ORGS)
        assignRepoColors(REPOS)
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
            self?.projectCatalog.refreshIfStale()
        }
        projectStore.track(projectCatalog.resolve(PROJECTS_CFG), live: liveProjectKeys())
        syncProjectOrgs()
        projectCatalog.refreshIfStale()
        applyCaptureHotKey()
        NotificationCenter.default.addObserver(forName: ProjectCatalog.changed, object: projectCatalog, queue: .main) { [weak self] _ in
            guard let self = self, !self.projectCatalog.refreshing else { return }
            self.projectStore.track(self.projectCatalog.resolve(PROJECTS_CFG), live: self.liveProjectKeys())
            self.syncProjectOrgs()
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let scopes = ProjectAPI().scopes()
            let login = getGHUser()
            DispatchQueue.main.async {
                self?.ghScopes = scopes
                self?.scopesKnown = true
                self?.viewerLogin = login
            }
        }
    }

    // Registers the quick capture shortcut again. Settings → Projects calls it after a save.
    @discardableResult
    func applyCaptureHotKey() -> Bool {
        captureHotKey?.unregister()
        captureHotKey = nil
        let c = PROJECTS_CFG.capture
        guard c.enabled, c.hasShortcut, PROJECTS_CFG.showTab else { return true }
        captureHotKey = GlobalHotKey(keyCode: c.keyCode, modifiers: c.modifiers) { [weak self] in self?.quickCapture() }
        if captureHotKey == nil { log.warning("Quick capture shortcut \(c.shortcutLabel) is not available") }
        return captureHotKey != nil
    }

    func suspendCaptureHotKey(_ on: Bool) {
        if on { captureHotKey?.unregister(); captureHotKey = nil } else { applyCaptureHotKey() }
    }

    // Opens the Projects tab with the New item sheet, from any app.
    func quickCapture() {
        guard PROJECTS_CFG.showTab else { return }
        let c = PROJECTS_CFG.capture
        let clip = c.pasteClipboard
            ? NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        selectedTab = .projects
        if popover.isShown {
            if let vc = popover.contentViewController as? TabVC, vc.selectedTab == .projects {
                if vc.sheet != nil { return }
            } else {
                showList()
            }
        } else {
            closeTime = .distantPast
            popover.contentViewController = nil
            toggle()
        }
        NSApp.activate(ignoringOtherApps: true)
        (popover.contentViewController as? TabVC)?.presentNewItem(target: nil, prefill: clip, suggest: c.aiTitle)
    }

    // The app has no visible menu bar, but text fields need the Edit key equivalents (⌘C, ⌘V, ⌘Z).
    func installEditMenu() {
        let main = NSMenu()
        let item = NSMenuItem()
        main.addItem(item)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        item.submenu = edit
        NSApp.mainMenu = main
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
                self.reloadList()
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
                self.reloadList()
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
        assignRepoColors(REPOS)
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
            syncProjectOrgs()
        }
    }

    func trackedOrgLogins() -> [String] {
        var seen = Set<String>()
        return projectCatalog.resolve(PROJECTS_CFG).compactMap { p -> String? in
            guard p.ownerKind == .org, seen.insert(p.ref.owner.lowercased()).inserted else { return nil }
            return p.ref.owner
        }
    }

    func liveProjectKeys() -> Set<String> {
        Set(projectCatalog.resolve(PROJECTS_CFG).filter { p in
            guard p.ownerKind == .org else { return false }
            switch relayDeployer.hooks.statuses["org:\(p.ref.owner)"] {
            case .live, .waiting: return true
            default: return false
            }
        }.map(\.ref.key))
    }

    func applyProjectSelection() {
        projectStore.track(projectCatalog.resolve(PROJECTS_CFG), live: liveProjectKeys())
        projectStore.restartTimer()
        syncProjectOrgs()
        updateIcon()
        if popover.isShown, popover.contentViewController is ProjectSettingsVC {
            showList()
        }
    }

    func syncProjectOrgs() {
        guard !RELAY.deviceID.isEmpty, !RELAY.workerURL.isEmpty else { return }
        let orgs = trackedOrgLogins()
        let removed = lastSyncedOrgs.filter { old in !orgs.contains { $0.caseInsensitiveCompare(old) == .orderedSame } }
        lastSyncedOrgs = orgs
        relayDeployer.registerRepos()
        if !removed.isEmpty { relayDeployer.pruneOrgHooks(removed: removed) }
        guard !orgs.isEmpty else { return }
        let d = relayDeployer
        d.perform("Install org webhooks", { d.installOrgHooks(orgs: orgs) }) { [weak self] _ in
            self?.projectStore.track(self?.projectCatalog.resolve(PROJECTS_CFG) ?? [], live: self?.liveProjectKeys() ?? [])
        }
    }

    var needsProjectScope: Bool {
        guard scopesKnown, !ghScopes.isEmpty else {
            return projectStore.lastError?.localizedCaseInsensitiveContains("scope") == true
        }
        return !ghScopes.contains("project") && !ghScopes.contains("read:project")
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
        let dot = PROJECTS_CFG.menuDot && projectStore.unreadCount() > 0
        let key = IconKey(color: color, badge: badge, active: active, dot: dot)
        guard key != iconKey else { return }
        iconKey = key
        statusItem.button?.image = statusBadgedIcon(ghIcon, color: color, badge: badge, dot: dot)
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
                    self.refreshRepos([repo], includePRs: false, completedRuns: []) { _ in }
                }
            }
        }
    }

    func setIgnored(_ runs: [Run], ignored: Bool) {
        IGNORED.set(runs, ignored: ignored)
        updateIcon()
        (popover.contentViewController as? TabVC)?.rebuildContent()
    }

    func reloadList() {
        guard popover.isShown, let vc = popover.contentViewController as? TabVC else { return }
        vc.update(grouped: grouped, prGrouped: prGrouped, updated: lastUpdate, loading: firstLoad)
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
                    if NOTIFICATIONS.started {
                        notify(title: repo, subtitle: "\u{25B6}\u{FE0F} Action Started", body: "\(wf) on \(run.headBranch)", id: "start-\(run.url)")
                    }
                }
                if run.status == "completed" && (old == "in_progress" || old == "queued") {
                    log.info("Transition: \(wf) on \(run.headBranch) → \(run.conclusion ?? "unknown") (was \(old ?? "new"))")
                    if let ending = notificationEnding(run) {
                        notify(title: repo, subtitle: ending,
                               body: "\(wf) on \(run.headBranch) \u{2014} \(runDuration(run))", id: "end-\(run.url)")
                    }
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

    // Returns nil when the user has disabled notifications for this conclusion.
    func notificationEnding(_ run: Run) -> String? {
        switch run.conclusion ?? "" {
        case "success":
            return NOTIFICATIONS.succeeded ? "\u{2705} Action Passed" : nil
        case "failure", "timed_out", "startup_failure":
            return NOTIFICATIONS.failed ? "\u{274C} Action Failed" : nil
        case "cancelled":
            return NOTIFICATIONS.cancelled ? "\u{1F6AB} Action Cancelled" : nil
        default:
            return NOTIFICATIONS.other ? "\u{26AA} Action Completed" : nil
        }
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
        let id = response.notification.request.identifier
        DispatchQueue.main.async {
            self.closeTime = .distantPast
            if id.hasPrefix("project:") {
                self.pendingProjectItem = String(id.dropFirst("project:".count))
                self.selectedTab = .projects
                self.expandedItem = self.pendingProjectItem
                if self.popover.isShown { self.popover.close() }
            }
            self.toggle()
        }
        handler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
        handler([.banner, .sound])
    }

    // MARK: - Popover

    func makeTabVC() -> TabVC {
        let vc = TabVC(grouped: grouped, prGrouped: prGrouped, updated: lastUpdate, loading: firstLoad,
                       tab: selectedTab, repo: selectedRepo)
        vc.projectView = projectView
        vc.assignedOnly = projectAssignedOnly
        vc.unreadOnly = projectUnreadOnly
        vc.expandedItem = pendingProjectItem ?? expandedItem
        vc.selectedProject = selectedProject
        vc.statusFilter = projectStatusFilter
        vc.showAllProjects = projectShowAll
        vc.projectQuery = projectQuery
        if pendingProjectItem != nil { selectedTab = .projects; vc.selectedTab = .projects }
        pendingProjectItem = nil
        return vc
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
            let wasSettings = self.popover.contentViewController is GeneralSettingsVC
                || self.popover.contentViewController is ActionsSettingsVC
                || self.popover.contentViewController is ProjectSettingsVC
                || self.popover.contentViewController is RelaySettingsVC
                || self.popover.contentViewController is AISettingsVC
            let settingsTab = self.lastSettingsTab
            let wasShown = self.popover.isShown
            self.popover.close()
            self.popover.contentViewController = nil
            if wasShown {
                self.closeTime = .distantPast
                if wasSettings { self.showSettings(settingsTab) }
                else { self.toggle() }
            }
        }
    }

    @objc func showSettings() { showSettings(lastSettingsTab) }

    func showSettings(_ tab: SettingsTab) {
        lastSettingsTab = tab
        popover.behavior = tab == .live ? .semitransient : .transient
        applySystemAppearance()
        buildWithAppearance {
            switch tab {
            case .general:
                self.popover.contentViewController = GeneralSettingsVC(catalog: self.catalog, updater: self.updater)
            case .actions:
                self.popover.contentViewController = ActionsSettingsVC(catalog: self.catalog, picked: Set(PICKED_REPOS), orgs: Set(PICKED_ORGS))
            case .projects:
                self.popover.contentViewController = ProjectSettingsVC(catalog: self.projectCatalog, store: self.projectStore, cfg: PROJECTS_CFG)
            case .ai:
                self.popover.contentViewController = AISettingsVC()
            case .live:
                self.popover.contentViewController = RelaySettingsVC(deployer: self.relayDeployer, client: self.relay)
            }
        }
        if !popover.isShown {
            closeTime = .distantPast
            toggle()
        }
    }

    @objc func showRelaySettings() { showSettings(.live) }

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
        refreshRepos(REPOS, includePRs: true, completedRuns: []) { ok in
            self.projectStore.refresh(self.projectStore.tracked.map(\.ref.key), force: true) { projectOK in
                done(ok && projectOK)
            }
        }
    }

    func relayProjectRefresh(projectNodeIds: [String], issues: [(repo: String, number: Int)], done: @escaping (Bool) -> Void) {
        projectStore.refreshForEvents(projectNodeIds: projectNodeIds, issues: issues, done: done)
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
