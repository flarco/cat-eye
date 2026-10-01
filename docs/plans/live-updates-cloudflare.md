# Plan: Live updates through a Cloudflare relay

Status: implemented (rev 2) · Date: 2026-10-01 · Estimate: about 9 working days

Rev 2 changes: one relay for each Cloudflare account, shared by all Macs. The event store is a Durable Object log, not a Queue (see 2.2). The whole setup runs from a new Settings panel, including the Node and wrangler installation. Retention is 24 h by default and the user can change it. `workflow_job` events are in scope.

## 1. Goal

Cat Eye polls GitHub every 10–30 seconds. This plan adds an optional push path:

- GitHub sends signed webhooks to a Cloudflare Worker in the user's account.
- The Worker appends each event to a log in a Durable Object (DO). The log keeps events for a retention period that the user sets (default 24 h).
- The DO tells each connected Mac about new events over a WebSocket.
- Each Mac reads the log from its own cursor and refreshes only the affected repos. A Mac that was asleep or offline continues from its cursor, so it misses nothing inside the retention period.
- One relay serves all Macs of a Cloudflare account. Each Mac joins with its own token.
- Cat Eye does all setup from a new Settings panel: install, login, deploy, health, retention, webhooks and devices.

Polling stays as the fallback. When the relay is healthy, Cat Eye polls only at a slow reconcile interval.

### Non-goals

- No hosted service. Each user deploys their own relay.
- Events do not replace data. They only trigger targeted `gh` refreshes, so the display logic does not change.

## 2. Architecture

```
                 ┌──────────────── Cloudflare account ─────────────────────────┐
GitHub ─webhook─▶│ Worker "cat-eye-relay"                                      │
 HMAC-signed     │  POST /webhook ─ verify ─▶ Hub DO (single instance, SQLite)  │
                 │                              events  (seq, repo, kind, ids)  │
                 │                              devices (id, name, cursor, repos)│
                 │                              config  (retention_hours)       │
                 │                              alarm: delete old events        │
                 │  /v1/* (device token) ─────▶ Hub DO                          │
                 └───────────────▲──────────────────────────▲───────────────────┘
                                 │ WebSocket + HTTPS        │
                          Mac A (cursor 1041)        Mac B (cursor 998)
```

### 2.1 Delivery model

- The log is the source of truth. Each accepted webhook becomes one row with a growing `seq`.
- The WebSocket only carries pokes ("new events up to seq N").
- A Mac reads `GET /v1/events?after=<cursor>`, refreshes the repos, then sends `POST /v1/ack {seq}`. The DO stores the cursor for each device.
- The live path and the reconnect path are the same code. A lost poke costs nothing.
- Delivery is at least once. A repo refresh is idempotent, and the Mac also drops duplicate delivery IDs.

### 2.2 Why not a Queue (answer to "can several consumers read the same event?")

A Cloudflare Queue gives each message to **one** consumer. Other consumers never get a copy:

- When a consumer pulls, the message gets a lease (visibility timeout, at most 12 h). Then it is acked and deleted, or it comes back to the queue as a retry. A message that comes back is again delivered to only one consumer, and each return uses up one of at most 100 retries.
- Queues has no "peek", no fan-out and no cursor.
- For two Macs you would need one queue for each Mac. Queue bindings are static, so each new Mac needs a config change and a new deploy, and the pull API needs a Cloudflare API token on top.

A log with a cursor for each device has none of these problems. It is also cheaper, it works on the free plan, and it needs no Cloudflare API token. The Hub DO is SQLite-backed, which the free plan requires anyway.

### 2.3 Gap detection

If a device's cursor is older than the oldest kept event (the Mac was offline longer than the retention period), `/v1/events` returns `"truncated": true`. Cat Eye then does one full refresh of all repos, as it does today at startup. The user loses only the Insights backfill for that gap.

## 3. Cost check

Sources: Durable Objects pricing (developers.cloudflare.com, read 2026-10-01).

| SQLite DO | Free plan (per day) | Workers Paid ($5/month) |
|---|---|---|
| Requests (incl. WebSocket messages at 20:1, alarms) | 100k | 1M/month, then $0.15/M |
| Rows written (inserts, deletes, `setAlarm`) | 100k | 50M/month, then $1.00/M |
| Rows read | 5M | 25B/month |
| Storage | 5 GB | 5 GB-month, then $0.20/GB-month |

Each event costs about 4 written rows (insert + index, delete + index), 1 DO request, and 1–2 read rows for each device.

`workflow_job` adds events: a run with 5 jobs makes about 3 run events plus about 15 job events (queued, in_progress, completed). Plan for about 4 events per job.

| Average volume | Events/month | Rows written | Paid plan total | Free plan |
|---|---|---|---|---|
| 200 events/h | 144k | 0.6M | $5.00 | fits (~19k rows/day) |
| 1,000 events/h | 720k | 2.9M | $5.00 | at the limit (~96k rows/day) |
| 5,000 events/h | 3.6M | 14.4M | ≈ $5.39 (DO requests) | does not fit |

Storage: one event row is about 200 bytes. 5,000 events/h with 7 days of retention is 840k rows, about 170 MB.

**Conclusion:** it costs $0 on the free plan up to about 1,000 events per hour on average, and about $5–6 per month on Paid at 5,000 events per hour. Retention does not depend on the plan. Only the write quota does. The Settings panel shows the expected daily row writes, and warns at 70% of the free quota.

## 4. Cloudflare side

### 4.1 Files

```
worker/
  src/index.js        # router + Hub DO (~300 lines)
  wrangler.jsonc      # template
  test/index.test.js  # vitest + @cloudflare/vitest-pool-workers
  package.json        # wrangler + test dev dependencies
```

`build.sh` copies `worker/src`, `worker/wrangler.jsonc` and `worker/package.json` into `CatEye.app/Contents/Resources/worker/`. At setup time Cat Eye copies them to `~/.config/cat-eye/relay/`, the working folder for all wrangler commands.

### 4.2 `wrangler.jsonc`

```jsonc
{
  "name": "cat-eye-relay",
  "main": "src/index.js",
  "compatibility_date": "2026-09-01",
  "workers_dev": true,
  "observability": { "enabled": false },
  "durable_objects": { "bindings": [{ "name": "HUB", "class_name": "Hub" }] },
  "migrations": [{ "tag": "v1", "new_sqlite_classes": ["Hub"] }],
  "vars": { "RELAY_VERSION": "1" }
}
```

Secrets:

| Secret | Set by | Purpose |
|---|---|---|
| `WEBHOOK_SECRET` | the first Mac | GitHub HMAC key, and `config.secret` on each hook |
| `DEVICE_<id>` | each Mac, for itself | That Mac's bearer token. `<id>` is 16 hex characters. |

A Mac joins by writing its own `DEVICE_<id>` secret with `wrangler secret put`. Only someone logged in to the Cloudflare account can do this, so no pairing code is needed. The Worker accepts a bearer token if it matches any `DEVICE_*` value (constant-time compare of SHA-256 digests). A Worker can have up to 128 secrets, which is far more than needed.

### 4.3 DO schema

```sql
CREATE TABLE events (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  delivery_id TEXT NOT NULL UNIQUE,     -- X-GitHub-Delivery; drops GitHub redeliveries
  repo TEXT NOT NULL,
  kind TEXT NOT NULL,                   -- workflow_run | workflow_job | pull_request | pull_request_review
  action TEXT,
  run_id INTEGER, job_id INTEGER, pr_number INTEGER,
  received_at INTEGER NOT NULL          -- unix ms
);
CREATE INDEX events_received ON events(received_at);
CREATE TABLE devices (id TEXT PRIMARY KEY, name TEXT, cursor INTEGER NOT NULL DEFAULT 0,
                      repos TEXT NOT NULL DEFAULT '[]', last_seen INTEGER);
CREATE TABLE hooks   (repo TEXT PRIMARY KEY, hook_id INTEGER, last_delivery INTEGER);
CREATE TABLE config  (key TEXT PRIMARY KEY, value TEXT);   -- retention_hours (default 24)
```

The event row keeps no commit messages, branch names, titles, user names or payload. Cat Eye gets those from `gh`.

An alarm runs every hour: `DELETE FROM events WHERE received_at < now - retention`.

### 4.4 Routes

| Route | Auth | Behavior |
|---|---|---|
| `POST /webhook` | HMAC | Verify `X-Hub-Signature-256` over the raw body with `crypto.subtle.verify`. 401 on failure. `ping` → 200. Allowed events → insert a row (ignore a duplicate `delivery_id`), poke all sockets, 202. Other events → 204. |
| `GET /v1/connect` | device | WebSocket (hibernation API). Auto-response for `ping`/`pong`, so keepalives do not wake the DO. |
| `GET /v1/events?after=N&limit=500` | device | `{events:[…], head, oldest, truncated}`. Returns only events for the repos of that device. |
| `POST /v1/ack` | device | `{seq}`. Moves the cursor forward and sets `last_seen`. |
| `PUT /v1/devices/self` | device | `{name, repos}`. Register this device and its repos. |
| `DELETE /v1/devices/{id}` | device | Remove a device row. Settings also deletes its secret. |
| `GET /v1/health` | device | `{version, retentionHours, events, oldestAt, lastWebhookAt, rowsWrittenToday, devices:[{id,name,lastSeen,lag}], hooks:[{repo,lastDelivery}]}` |
| `PUT /v1/config` | device | `{retentionHours}` (1–720). Takes effect at once, with no new deploy. |
| `GET /v1/webhook-secret` | device | Lets a second Mac create hooks for its own repos. |
| `PUT /v1/hooks/{repo}` / `DELETE` | device | Record or remove the hook ID of a repo, so all Macs share one hook list. |
| `GET /` | none | `{"app":"cat-eye-relay"}` only. Used to find the relay. |

### 4.5 No payload logging

- No `console.log` of headers or bodies. The Worker logs only the route, the status and the event kind.
- `observability.enabled: false`.
- A test checks that the request body never reaches `console.*`.

## 5. Mac side

### 5.1 Files and types

Put the new code in `relay.swift` and `relay_settings.swift`, and change `build.sh` to compile `*.swift`.

| Type | Owns |
|---|---|
| `Toolchain` | Finds `node`, `npm`, `brew` (fixed paths, then `zsh -lc 'command -v …'` for nvm/asdf setups). Installs wrangler. Runs wrangler with an allowlisted env, optional stdin, and a line-by-line output callback for the log view. |
| `SecretStore` | Keychain items for `DEVICE_TOKEN` and the cached `WEBHOOK_SECRET`. |
| `RelayDeployer` | Login, deploy, join, secrets, retention, remove (5.3). |
| `HookManager` | GitHub hooks and delivery checks (5.4). |
| `RelayClient` | WebSocket, cursor sync, dedupe, debounce, health state (5.5). |
| `RelaySettingsVC` | The new panel (5.6). |

Config additions (no secrets in the file):

```swift
struct RelayConfig: Codable {
    var enabled: Bool
    var workerURL: String
    var deviceID: String            // 16 hex chars, made once for each Mac
    var accountID: String
    var reconcileInterval: TimeInterval?   // default 600 s
}
```

### 5.2 Changes to existing code

1. **Targeted refresh.** Add `refresh(repos:includePRs:)`. It merges the result into `grouped`/`prGrouped` by repo name and keeps the order of `REPOS`.
2. **`detectTransitions`.** Update only the entries of the refreshed repos. Today it rebuilds `prevStatuses` from the new runs only, which would wipe the other repos.
3. **Poll cadence.** If `RelayClient.isHealthy`, use `reconcileInterval` and skip the 10 s fast poll.
4. **Insights backfill.** For a `workflow_run`/`completed` event whose run is not in the list, fetch `repos/{repo}/actions/runs/{id}` and record it in `DeployLog`.
5. **Live ETA.** A `workflow_job` event on an in-progress run triggers a refresh of that repo, so the elapsed time and status stay current without the 10 s poll.
6. **`ghShell` with stdin** (`gh api --input -`), so that secrets never appear in `argv`.

### 5.3 Setup helper (`Toolchain` + `RelayDeployer`)

Each step has a status, a primary button, and output in the log view. Each step can safely run again. The panel runs the next step that is not done, so a single "Set up" button can walk through the whole list.

| # | Step | Check | Action |
|---|---|---|---|
| 1 | Node.js | `node --version` ≥ 20 | If Homebrew is there: **Install Node** runs `brew install node`. If not: open nodejs.org/download, then the user clicks **Check again**. |
| 2 | Wrangler | `~/.config/cat-eye/relay/node_modules/.bin/wrangler --version` | **Install wrangler** runs `npm install` in the relay folder (local install, as Cloudflare recommends; no sudo). **Update** runs `npm install wrangler@4`. |
| 3 | Cloudflare login | `wrangler whoami` | **Log in** runs `wrangler login`, which opens the browser. Read the account ID and name. If there are several accounts, show a picker and set `CLOUDFLARE_ACCOUNT_ID` for all later commands. **Log out** runs `wrangler logout`. |
| 4 | Relay | `wrangler deployments list --name cat-eye-relay` | Not found: **Deploy relay** → `wrangler deploy`, read the `workers.dev` URL, `secret put WEBHOOK_SECRET`. Found: **Join relay** (go to step 5). Found, but `RELAY_VERSION` is older than the bundled one: **Update relay** → `wrangler deploy`. If no `workers.dev` subdomain exists yet, show the one command to run in Terminal. |
| 5 | This Mac | `GET /v1/health` with this Mac's token | Make a device ID and token, `wrangler secret put DEVICE_<id>` (stdin), save the token in the Keychain, `PUT /v1/devices/self`. |
| 6 | Webhooks | for each repo, see 5.4 | **Install hooks** / **Repair**. |
| 7 | Live | the WebSocket is connected and the last sync is less than 2 min old | **Reconnect**. |

Other actions in the panel:

- **Retention**: a value and a unit (hours/days), 1 h to 30 days, default 24 h. Saving it calls `PUT /v1/config`, with no new deploy. Next to it, show the expected rows written per day against the free quota.
- **Devices list**: name, last seen, cursor lag. **Remove** runs `wrangler secret delete DEVICE_<id>` and `DELETE /v1/devices/{id}`.
- **Rotate webhook secret**: a new value, `secret put`, then `PATCH` of each hook in the shared hook list that this Mac can administer. Hooks it cannot reach are listed for the other Mac to repair.
- **Remove relay**: delete all hooks, `wrangler delete cat-eye-relay`, delete the Keychain items. Ask for confirmation first. This affects all Macs.

Open item for the spike: how to find the `workers.dev` URL of an existing relay without a new deploy. Candidates: the Cloudflare API `GET /accounts/{id}/workers/subdomain` with wrangler's OAuth token, or the output of `wrangler deploy --dry-run`. Fallback: a new deploy of the same version, which is harmless.

### 5.4 Webhooks (`HookManager`)

For each tracked repo of this Mac:

1. Look in the shared hook list (`/v1/health` → `hooks`), then in `gh api repos/{repo}/hooks`, for a hook whose `config.url` is `{workerURL}/webhook`.
2. If there is none: `POST repos/{repo}/hooks` with the body on stdin. If there is one: `PATCH` it to the same body.
   ```json
   { "name": "web", "active": true,
     "events": ["workflow_run", "workflow_job", "pull_request", "pull_request_review"],
     "config": { "url": "<workerURL>/webhook", "content_type": "json",
                 "secret": "<WEBHOOK_SECRET>", "insecure_ssl": "0" } }
   ```
3. `PUT /v1/hooks/{repo}`, then `POST …/hooks/{id}/pings`.
4. **Delivery check:** `gh api repos/{repo}/hooks/{id}/deliveries?per_page=5`. Show the last status code and time. Status 401 means the secrets do not match → **Repair**.
5. 403/404 from GitHub means that this user is not a repo admin → `Polling only`.

When a repo is removed from a Mac, delete its hook only if no other device lists that repo (`devices.repos` in the DO).

**Token scope:** the current `gh` token has `repo, workflow, read:org, gist`. Confirm in the spike that `repo` can create hooks. If not, the panel offers `gh auth refresh -s admin:repo_hook`.

### 5.5 `RelayClient`

- `URLSessionWebSocketTask` to `wss://…/v1/connect` with `Authorization: Bearer <device token>`.
- Keepalive ping every 30 s. If no pong comes back in 10 s, reconnect.
- Backoff of 1, 2, 4 … 60 s with jitter. Reconnect at once on `NSWorkspace.didWakeNotification` and on `NWPathMonitor` "satisfied".
- **Sync** on connect, on poke (debounced 500 ms) and on each reconcile tick:
  1. `GET /v1/events?after=cursor` until `head` is reached.
  2. If `truncated`: do a full refresh of all repos.
  3. Drop duplicate `delivery_id`s (keep the last 2,000 IDs).
  4. Group the events by repo → `refresh(repos:includePRs:)`. Backfill completed runs.
  5. If the refresh succeeded: `POST /v1/ack {seq: last}`. If not: no ack, and the next sync tries again.
- When the tracked repos change, call `PUT /v1/devices/self`.
- Old events after a long sleep only cause a refresh, and notifications fire only on real status changes. So a replay does not send old notifications.
- `isHealthy` drives the poll cadence and a status dot in the footer: green = live, grey = polling, orange = relay error.

### 5.6 Settings panel

Add a tab bar to Settings: **Repositories** (the current panel) and **Live updates** (new). Draft of the new panel:

```
┌ Live updates ─────────────────────────────────────────────────────┐
│ [x] Enable live updates                     Status: ● Live         │
│                                                                    │
│ SETUP                                                     [Set up] │
│  ✓ Node.js 22.19.0                                                 │
│  ✓ Wrangler 4.x (local)                               [Update]     │
│  ✓ Cloudflare: Fritz's account                        [Log out]    │
│  ✓ Relay v1  https://cat-eye-relay.x.workers.dev      [Redeploy]   │
│  ✓ This Mac: "Fritz MBP" joined                                    │
│  ! Webhooks: 7 live · 1 polling only · 1 error        [Repair]     │
│  ✓ Connected · last event 12 s ago                    [Reconnect]  │
│                                                                    │
│ HEALTH                                               [Check now]   │
│  Events kept: 4,812 · oldest 23 h · last webhook 12 s ago          │
│  Writes today: 18,300 / 100,000 (free plan)                        │
│                                                                    │
│ CONFIGURATION                                                      │
│  Keep events for  [ 24 ] [hours ▾]                          [Save] │
│  Reconcile poll every [ 10 ] min                                   │
│                                                                    │
│ DEVICES                                                            │
│  Fritz MBP (this Mac)   seen now      lag 0                        │
│  Fritz Studio           seen 3 h ago  lag 212            [Remove]  │
│                                                                    │
│ ▸ Log  (command output, secrets masked)                            │
│ [Rotate webhook secret]                        [Remove relay…]     │
└────────────────────────────────────────────────────────────────────┘
```

- Long steps run in the background, and their output streams into the Log area.
- Mask secret values in the log (any 64-hex string → `••••`).
- The panel refreshes Health when it opens, and also on **Check now**.

## 6. Security

| Threat | Control |
|---|---|
| Fake webhooks | HMAC-SHA256 over the raw body, constant-time verify |
| Unknown clients | A device token for each Mac (32 random bytes), stored only as a Worker secret and in the Keychain |
| A lost or old Mac | Remove the device: its secret is deleted, and its token stops working at once |
| Webhook replay | `delivery_id` is unique in the DO, and Cat Eye also drops duplicates |
| Payload leaks | Rows keep only IDs and status. No body logging. Observability off. |
| Secrets in process lists | All secrets go on stdin to `wrangler` and `gh` |
| Webhook secret compromise | Rotate from the panel |

## 7. Testing

**Worker (vitest pool workers):** signature valid, invalid and missing; ping; event filter; duplicate delivery; every `/v1/*` route rejects a missing or wrong token; one device's events filtered by its repos; `truncated` after retention; the alarm deletes old rows; retention update; poke reaches a socket; no body in logs.

**Cat Eye (`--selftest`):** partial-refresh merge; `detectTransitions` keeps the other repos; dedupe buffer; backoff; parsers for wrangler output (captured fixtures); secret masking in the log view; free-quota estimate.

**End to end:**
1. Set up from zero on Mac A: install, login, deploy, join, hooks. Run it again: nothing changes.
2. Mac B joins the same relay, without a new deploy or a pairing code.
3. Push: both Macs update in less than 3 s.
4. Quit Mac B, push 3 times, start Mac B: all 3 runs show, and Insights has them.
5. Mac B offline for longer than the retention period → `truncated` → full refresh, no error.
6. Change retention to 2 h: old rows are deleted at the next alarm.
7. Remove Mac B from Mac A: Mac B shows "relay error" and polls.
8. Rotate the webhook secret: deliveries still return 2xx.
9. Remove the relay: the hooks, the Worker and the Keychain items are gone.

## 8. Phases and estimate

| # | Phase | Days |
|---|---|---|
| 0 | Spike: deploy by hand, `wrangler login` from a subprocess, `whoami` parsing, find the URL of an existing relay, `repo` scope for hooks, `deployments list` behavior | 0.5 |
| 1 | Worker + DO log + tests | 1.5 |
| 2 | `RelayClient`, targeted refresh, `detectTransitions`, cadence, backfill | 1.5 |
| 3 | `Toolchain` (Node/brew/wrangler install, runner, log streaming) | 1 |
| 4 | `RelayDeployer` (deploy, join, retention, devices, rotate, remove) + `SecretStore` | 1 |
| 5 | `HookManager` (hooks, delivery checks, shared hook list) | 1 |
| 6 | Settings tabs + Live updates panel | 1.5 |
| 7 | End-to-end checklist on two Macs, README, CONTRIBUTING | 1 |
| | **Total** | **≈ 9** |

Milestone after phase 2 (about 3.5 days): the live path works on both Macs with a relay that was deployed by hand.

## 9. Open questions

1. Retention maximum: is 30 days enough?
2. Several Cloudflare accounts on one Mac: support only one account in v1?
3. Org webhooks (`admin:org_hook`) instead of one hook for each repo: v2?

## 10. Implementation notes

Changes from the plan, found during the implementation:

- **Relay URL on a second Mac.** The second Mac runs `wrangler deploy` of the same bundled version. The deploy output gives the `workers.dev` URL. Secrets and the DO data stay. No Cloudflare API token is necessary.
- **Repo names.** The Worker stores repo names in lowercase. Cat Eye maps them back to the configured names.
- **`/v1/events`** also returns `next` (the cursor to continue from) and `more`. `truncated` is true when `after` is older than the highest deleted `seq`.
- **`GET /`** also returns the Worker version, so Cat Eye can find an old relay before it joins.
- **Writes today** in `/v1/health` is an estimate: 6 rows for each event (the insert and the later delete, each with two indexes). The panel projects it to a full day.
- **Hook delivery time** comes from the newest event of each repo, so a webhook does not write a second row.
- **Compatibility date** is `2026-08-01`, because the local test runtime does not support later dates yet.
- **Node.js lookup** checks Homebrew, volta, asdf and nvm folders, then the user's login shell.
- **wrangler install** uses `npm install --omit=dev`. The test tools are dev dependencies in `worker/package.json`, and `build.sh` removes them from the copy in the app bundle.
- **Popover behavior.** The Live updates panel uses `.semitransient`, so the browser login does not close it.

Tests: `worker/test/index.test.js` (26 tests, `npm test`), and the relay checks in `cat-eye --selftest`. A local end-to-end run with `wrangler dev` passed: connect, webhook, poke, sync, targeted refresh request and ack. The end-to-end checklist in section 7 still needs a real deploy on two Macs.
