// Cat Eye relay: verifies GitHub and Plane webhooks, keeps a short event log in one
// Durable Object, and pokes connected Macs over WebSocket.
// Logs never contain headers or bodies.
import { DurableObject } from "cloudflare:workers";

const KINDS = new Set([
  "workflow_run", "workflow_job", "pull_request", "pull_request_review",
]);
const HOUR_MS = 3600_000;
const enc = new TextEncoder();

const json = (data, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const hub = env.HUB.get(env.HUB.idFromName("hub"));

    if (url.pathname === "/" && request.method === "GET") {
      return json({ app: "cat-eye-relay", version: env.RELAY_VERSION });
    }
    if (url.pathname === "/webhook" && request.method === "POST") {
      return handleWebhook(request, env, hub);
    }
    const plane = /^\/plane\/([a-z0-9_-]{1,64})$/i.exec(url.pathname);
    if (plane && request.method === "POST") {
      // The Hub has the secret of each workspace, so it checks the signature.
      return hub.fetch(`https://hub/internal/plane/${plane[1].toLowerCase()}`, {
        method: "POST", body: await request.arrayBuffer(),
        headers: {
          "x-plane-signature": request.headers.get("x-plane-signature") || "",
          "x-plane-event": request.headers.get("x-plane-event") || "",
          "x-plane-delivery": request.headers.get("x-plane-delivery") || "",
        },
      });
    }
    if (url.pathname.startsWith("/v1/")) {
      const deviceId = await authenticate(request, env);
      if (!deviceId) return json({ error: "unauthorized" }, 401);
      const headers = new Headers(request.headers);
      headers.set("x-device-id", deviceId);
      if (url.pathname === "/v1/webhook-secret") {
        return env.WEBHOOK_SECRET ? json({ secret: env.WEBHOOK_SECRET }) : json({ error: "not set" }, 404);
      }
      return hub.fetch(new Request(request, { headers }));
    }
    return json({ error: "not found" }, 404);
  },
};

async function handleWebhook(request, env, hub) {
  if (!env.WEBHOOK_SECRET) return json({ error: "relay not configured" }, 503);
  const body = await request.arrayBuffer();
  if (!(await verifySignature(env.WEBHOOK_SECRET, body, request.headers.get("x-hub-signature-256")))) {
    console.log("webhook 401");
    return json({ error: "bad signature" }, 401);
  }
  const kind = request.headers.get("x-github-event") || "";
  if (kind === "ping") return json({ ok: true });
  if (!KINDS.has(kind)) return new Response(null, { status: 204 });

  let p;
  try { p = JSON.parse(new TextDecoder().decode(body)); } catch { return json({ error: "bad json" }, 400); }
  const repo = p.repository?.full_name;
  const deliveryId = request.headers.get("x-github-delivery");
  if (!repo || !deliveryId) return json({ error: "missing fields" }, 400);

  // Keep only IDs and status. Titles, branches, users and bodies stay out.
  const event = {
    deliveryId,
    repo: repo.toLowerCase(),
    kind,
    action: p.action ?? null,
    runId: p.workflow_run?.id ?? p.workflow_job?.run_id ?? null,
    jobId: p.workflow_job?.id ?? null,
    prNumber: p.pull_request?.number ?? null,
  };
  console.log(`webhook ${kind}`);
  return hub.fetch("https://hub/internal/event", { method: "POST", body: JSON.stringify(event) });
}

export async function verifySignature(secret, body, header) {
  if (!header || !header.startsWith("sha256=")) return false;
  return verifyHex(secret, body, header.slice(7));
}

// Plane sends the hex digest, sometimes with a "sha256=" prefix.
export async function verifyPlaneSignature(secret, body, header) {
  if (!header) return false;
  return verifyHex(secret, body, header.startsWith("sha256=") ? header.slice(7) : header);
}

async function verifyHex(secret, body, hex) {
  if (!/^[0-9a-f]{64}$/i.test(hex)) return false;
  const sig = new Uint8Array(hex.match(/../g).map((b) => parseInt(b, 16)));
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["verify"]);
  return crypto.subtle.verify("HMAC", key, sig, body);
}

// Plane may send `data` as a JSON string.
function planeObject(v) {
  if (typeof v === "string") { try { return JSON.parse(v); } catch { return null; } }
  return v && typeof v === "object" ? v : null;
}

// Keep only IDs and the event name. Names, bodies and users stay out.
export function planeEvent(workspace, p, headers) {
  const id = (v) => (typeof v === "string" && v.length <= 64 ? v : null);
  const data = planeObject(p.data) || planeObject(p.previous_attributes) || {};
  const header = headers.get("x-plane-event") || "";
  const event = /^[a-z_.]+$/.test(header) ? header : (typeof p.event === "string" && /^[a-z_.]+$/.test(p.event) ? p.event : "");
  const type = String(p.entity_type || "");
  const deliveryId = id(p.event_id) || id(headers.get("x-plane-delivery")) || id(p.delivery_id);
  if (!deliveryId) return null;
  return {
    deliveryId: `plane:${deliveryId}`,
    repo: "",
    org: `plane:${workspace}`,
    kind: "plane",
    action: (event || type).slice(0, 64) || null,
    projectId: type === "project" ? id(p.entity_id) : id(data.project_id) || id(data.project),
    itemId: type === "issue" || type === "workitem" ? id(p.entity_id) : id(data.issue_id) || id(data.issue),
  };
}

// Returns the device ID of the DEVICE_<id> secret that matches the bearer token.
async function authenticate(request, env) {
  const m = /^Bearer (\S+)$/.exec(request.headers.get("authorization") || "");
  if (!m) return null;
  const given = await sha256(m[1]);
  let found = null;
  for (const [name, value] of Object.entries(env)) {
    if (!name.startsWith("DEVICE_") || typeof value !== "string") continue;
    // Compare every candidate so timing does not show which one matched.
    if (crypto.subtle.timingSafeEqual(given, await sha256(value))) found = name.slice(7);
  }
  return found;
}

async function sha256(s) {
  return crypto.subtle.digest("SHA-256", enc.encode(s));
}

const EVENTS_TABLE = `
  CREATE TABLE IF NOT EXISTS events (
    seq INTEGER PRIMARY KEY AUTOINCREMENT,
    delivery_id TEXT NOT NULL UNIQUE,
    repo TEXT NOT NULL,
    kind TEXT NOT NULL,
    action TEXT,
    run_id INTEGER, job_id INTEGER, pr_number INTEGER,
    received_at INTEGER NOT NULL,
    org TEXT, project_id TEXT, item_id TEXT
  )`;
const PLANE_TABLE = "CREATE TABLE IF NOT EXISTS plane_hooks (workspace TEXT PRIMARY KEY, hook_id TEXT, secret TEXT NOT NULL)";

export class Hub extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    this.sql.exec(`
      ${EVENTS_TABLE};
      CREATE INDEX IF NOT EXISTS events_received ON events(received_at);
      CREATE TABLE IF NOT EXISTS devices (id TEXT PRIMARY KEY, name TEXT, cursor INTEGER NOT NULL DEFAULT 0,
        repos TEXT NOT NULL DEFAULT '[]', orgs TEXT NOT NULL DEFAULT '[]', last_seen INTEGER);
      CREATE TABLE IF NOT EXISTS hooks (repo TEXT PRIMARY KEY, hook_id INTEGER);
      ${PLANE_TABLE};
      CREATE TABLE IF NOT EXISTS config (key TEXT PRIMARY KEY, value TEXT);
    `);
    this.migrate();
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
    ctx.blockConcurrencyWhile(async () => {
      if ((await ctx.storage.getAlarm()) === null) await ctx.storage.setAlarm(Date.now() + HOUR_MS);
    });
  }

  // Adds columns an already-deployed Hub is missing. Safe to run more than once.
  migrate() {
    const exists = this.sql.exec("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'events'").toArray()[0];
    if (!exists) this.sql.exec(EVENTS_TABLE);
    const eventCols = new Set(this.sql.exec("SELECT name FROM pragma_table_info('events')").toArray().map((r) => r.name));
    for (const [col, type] of [["org", "TEXT"], ["project_id", "TEXT"], ["item_id", "TEXT"]]) {
      if (!eventCols.has(col)) this.sql.exec(`ALTER TABLE events ADD COLUMN ${col} ${type}`);
    }
    this.sql.exec("CREATE INDEX IF NOT EXISTS events_org ON events(org)");
    // GitHub org hooks were for GitHub Projects. Plane replaces them.
    this.sql.exec("DROP TABLE IF EXISTS org_hooks");
    this.sql.exec(PLANE_TABLE);
    const deviceCols = new Set(this.sql.exec("SELECT name FROM pragma_table_info('devices')").toArray().map((r) => r.name));
    if (deviceCols.size && !deviceCols.has("orgs")) {
      this.sql.exec("ALTER TABLE devices ADD COLUMN orgs TEXT NOT NULL DEFAULT '[]'");
    }
  }

  config(key, fallback) {
    const row = this.sql.exec("SELECT value FROM config WHERE key = ?", key).toArray()[0];
    return row ? row.value : fallback;
  }

  setConfig(key, value) {
    this.sql.exec("INSERT INTO config (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", key, String(value));
  }

  retentionHours() {
    return Number(this.config("retention_hours", 24));
  }

  head() {
    return this.sql.exec("SELECT COALESCE(MAX(seq), 0) AS head FROM events").one().head;
  }

  async alarm() {
    this.prune(Date.now());
    await this.ctx.storage.setAlarm(Date.now() + HOUR_MS);
  }

  // Deletes events older than the retention period. Records the highest deleted
  // seq, so a device behind it knows it missed events.
  prune(now) {
    const cutoff = now - this.retentionHours() * HOUR_MS;
    const max = this.sql.exec("SELECT MAX(seq) AS m FROM events WHERE received_at < ?", cutoff).one().m;
    if (max === null) return;
    this.sql.exec("DELETE FROM events WHERE received_at < ?", cutoff);
    this.setConfig("pruned_through", Math.max(max, Number(this.config("pruned_through", 0))));
  }

  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;
    const device = request.headers.get("x-device-id");

    if (path === "/internal/event" && method === "POST") return this.addEvent(await request.json());
    const inPlane = /^\/internal\/plane\/([a-z0-9_-]+)$/.exec(path);
    if (inPlane && method === "POST") return this.planeWebhook(inPlane[1], request);
    if (!device) return json({ error: "unauthorized" }, 401);

    if (path === "/v1/connect") {
      if (request.headers.get("upgrade") !== "websocket") return json({ error: "expected websocket" }, 426);
      const pair = new WebSocketPair();
      this.ctx.acceptWebSocket(pair[1], [device]);
      return new Response(null, { status: 101, webSocket: pair[0] });
    }
    if (path === "/v1/events" && method === "GET") {
      const after = Math.max(0, Number(url.searchParams.get("after") || 0));
      const limit = Math.min(Math.max(1, Number(url.searchParams.get("limit") || 500)), 500);
      return json(this.events(device, after, limit));
    }
    if (path === "/v1/ack" && method === "POST") {
      const { seq } = await request.json();
      if (!Number.isInteger(seq) || seq < 0) return json({ error: "bad seq" }, 400);
      this.touch(device);
      this.sql.exec("UPDATE devices SET cursor = MAX(cursor, ?) WHERE id = ?", Math.min(seq, this.head()), device);
      return json({ ok: true });
    }
    if (path === "/v1/devices/self" && method === "PUT") {
      const { name, repos, orgs } = await request.json();
      if (!Array.isArray(repos) || repos.some((r) => typeof r !== "string")) return json({ error: "bad repos" }, 400);
      if (orgs !== undefined && (!Array.isArray(orgs) || orgs.some((o) => typeof o !== "string"))) {
        return json({ error: "bad orgs" }, 400);
      }
      const list = JSON.stringify(repos.map((r) => r.toLowerCase()));
      const orgJSON = Array.isArray(orgs) ? JSON.stringify(orgs.map((o) => o.toLowerCase())) : null;
      this.sql.exec(
        `INSERT INTO devices (id, name, cursor, repos, orgs, last_seen) VALUES (?, ?, ?, ?, COALESCE(?, '[]'), ?)
         ON CONFLICT(id) DO UPDATE SET name = excluded.name, repos = excluded.repos,
           orgs = COALESCE(?, devices.orgs), last_seen = excluded.last_seen`,
        device, String(name || device).slice(0, 80), this.head(), list, orgJSON, Date.now(), orgJSON);
      return json({ ok: true });
    }
    const dev = /^\/v1\/devices\/([A-Za-z0-9]+)$/.exec(path);
    if (dev && method === "DELETE") {
      this.sql.exec("DELETE FROM devices WHERE id = ?", dev[1]);
      for (const ws of this.ctx.getWebSockets(dev[1])) ws.close(4001, "device removed");
      return json({ ok: true });
    }
    if (path === "/v1/health" && method === "GET") {
      this.touch(device);
      return json(this.health());
    }
    if (path === "/v1/config" && method === "PUT") {
      const { retentionHours } = await request.json();
      if (!Number.isInteger(retentionHours) || retentionHours < 1 || retentionHours > 720) {
        return json({ error: "retentionHours must be 1-720" }, 400);
      }
      this.setConfig("retention_hours", retentionHours);
      this.prune(Date.now());
      return json({ retentionHours });
    }
    const hook = /^\/v1\/hooks\/([^/]+\/[^/]+)$/.exec(path);
    if (hook) {
      const repo = decodeURIComponent(hook[1]).toLowerCase();
      if (method === "PUT") {
        const { hookId } = await request.json();
        if (!Number.isInteger(hookId)) return json({ error: "bad hookId" }, 400);
        this.sql.exec(
          "INSERT INTO hooks (repo, hook_id) VALUES (?, ?) ON CONFLICT(repo) DO UPDATE SET hook_id = excluded.hook_id",
          repo, hookId);
        return json({ ok: true });
      }
      if (method === "DELETE") {
        this.sql.exec("DELETE FROM hooks WHERE repo = ?", repo);
        return json({ ok: true });
      }
    }
    const planeHook = /^\/v1\/plane-hooks\/([a-z0-9_-]{1,64})$/i.exec(path);
    if (planeHook) {
      const workspace = planeHook[1].toLowerCase();
      if (method === "PUT") {
        const { hookId, secret } = await request.json();
        if (typeof hookId !== "string" || !hookId) return json({ error: "bad hookId" }, 400);
        if (typeof secret !== "string" || secret.length < 16) return json({ error: "bad secret" }, 400);
        this.sql.exec(
          `INSERT INTO plane_hooks (workspace, hook_id, secret) VALUES (?, ?, ?)
           ON CONFLICT(workspace) DO UPDATE SET hook_id = excluded.hook_id, secret = excluded.secret`,
          workspace, hookId, secret);
        return json({ ok: true });
      }
      if (method === "DELETE") {
        this.sql.exec("DELETE FROM plane_hooks WHERE workspace = ?", workspace);
        return json({ ok: true });
      }
    }
    return json({ error: "not found" }, 404);
  }

  // Plane disables a webhook after 5 failed deliveries. Only a bad signature fails.
  async planeWebhook(workspace, request) {
    const row = this.sql.exec("SELECT secret FROM plane_hooks WHERE workspace = ?", workspace).toArray()[0];
    if (!row) return json({ error: "unknown workspace" }, 404);
    const body = await request.arrayBuffer();
    if (!(await verifyPlaneSignature(row.secret, body, request.headers.get("x-plane-signature")))) {
      console.log("plane webhook 401");
      return json({ error: "bad signature" }, 401);
    }
    let p;
    try { p = JSON.parse(new TextDecoder().decode(body)); } catch { return json({ ok: true, ignored: "bad json" }); }
    const event = planeEvent(workspace, p, request.headers);
    if (!event) return json({ ok: true, ignored: "no event id" });
    console.log(`plane webhook ${event.action}`);
    const res = this.addEvent(event);
    return new Response(res.body, { status: 200, headers: res.headers });
  }

  addEvent(e) {
    const now = Date.now();
    const inserted = this.sql.exec(
      `INSERT INTO events (delivery_id, repo, kind, action, run_id, job_id, pr_number, received_at, org, project_id, item_id)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(delivery_id) DO NOTHING RETURNING seq`,
      e.deliveryId, e.repo || "", e.kind, e.action ?? null, e.runId ?? null, e.jobId ?? null, e.prNumber ?? null, now,
      e.org ?? null, e.projectId ?? null, e.itemId ?? null).toArray();
    if (inserted.length === 0) return json({ duplicate: true }, 202);
    const msg = JSON.stringify({ type: "poke", head: inserted[0].seq });
    for (const ws of this.ctx.getWebSockets()) {
      try { ws.send(msg); } catch {}
    }
    return json({ ok: true }, 202);
  }

  events(device, after, limit) {
    const row = this.sql.exec("SELECT repos, orgs FROM devices WHERE id = ?", device).toArray()[0];
    const repos = row ? JSON.parse(row.repos) : [];
    const orgs = row?.orgs ? JSON.parse(row.orgs) : [];
    const head = this.head();
    const prunedThrough = Number(this.config("pruned_through", 0));
    const oldest = this.sql.exec("SELECT MIN(seq) AS m FROM events").one().m;
    // A device that registered no repos and no orgs gets all events.
    const rows = repos.length || orgs.length
      ? this.sql.exec(
          `SELECT * FROM events WHERE seq > ? AND (
             repo IN (SELECT value FROM json_each(?))
             OR org IN (SELECT value FROM json_each(?))
           ) ORDER BY seq LIMIT ?`,
          after, JSON.stringify(repos), JSON.stringify(orgs), limit).toArray()
      : this.sql.exec("SELECT * FROM events WHERE seq > ? ORDER BY seq LIMIT ?", after, limit).toArray();
    const more = rows.length === limit;
    return {
      events: rows.map((r) => ({
        seq: r.seq, deliveryId: r.delivery_id, repo: r.repo ?? "", kind: r.kind, action: r.action,
        runId: r.run_id, jobId: r.job_id, prNumber: r.pr_number, receivedAt: r.received_at,
        org: r.org ?? null, projectId: r.project_id ?? null, itemId: r.item_id ?? null,
      })),
      head,
      next: more ? rows[rows.length - 1].seq : head,
      more,
      oldest,
      truncated: after < prunedThrough,
    };
  }

  touch(device) {
    this.sql.exec("UPDATE devices SET last_seen = ? WHERE id = ?", Date.now(), device);
  }

  health() {
    const now = Date.now();
    const head = this.head();
    const dayStart = now - (now % (24 * HOUR_MS));
    const stats = this.sql.exec(
      "SELECT COUNT(*) AS n, MIN(received_at) AS oldest, SUM(received_at >= ?) AS today FROM events", dayStart).one();
    const projectToday = this.sql.exec(
      "SELECT COUNT(*) AS n FROM events WHERE received_at >= ? AND kind = 'plane'", dayStart).one().n;
    const connected = new Set(this.ctx.getWebSockets().flatMap((ws) => this.ctx.getTags(ws)));
    const last = new Map(this.sql.exec("SELECT repo, MAX(received_at) AS at FROM events GROUP BY repo").toArray()
      .map((r) => [r.repo, r.at]));
    const lastOrg = new Map(this.sql.exec(
      "SELECT org, MAX(received_at) AS at FROM events WHERE org IS NOT NULL GROUP BY org").toArray()
      .map((r) => [r.org, r.at]));
    return {
      version: this.env.RELAY_VERSION,
      retentionHours: this.retentionHours(),
      head,
      events: stats.n,
      oldestAt: stats.oldest,
      lastWebhookAt: last.size ? Math.max(...last.values()) : null,
      eventsToday: stats.today ?? 0,
      projectEventsToday: projectToday ?? 0,
      // Estimate: the insert and the later delete each write the row and two indexes.
      rowsWrittenToday: (stats.today ?? 0) * 6,
      devices: this.sql.exec("SELECT id, name, cursor, repos, orgs, last_seen FROM devices ORDER BY name").toArray().map((d) => ({
        id: d.id, name: d.name, lastSeen: d.last_seen, lag: Math.max(0, head - d.cursor),
        repos: JSON.parse(d.repos), orgs: JSON.parse(d.orgs || "[]"), connected: connected.has(d.id),
      })),
      hooks: this.sql.exec("SELECT repo, hook_id FROM hooks ORDER BY repo").toArray().map((h) => ({
        repo: h.repo, hookId: h.hook_id, lastDelivery: last.get(h.repo) ?? null,
      })),
      planeHooks: this.sql.exec("SELECT workspace, hook_id FROM plane_hooks ORDER BY workspace").toArray().map((h) => ({
        workspace: h.workspace, hookId: h.hook_id, lastDelivery: lastOrg.get(`plane:${h.workspace}`) ?? null,
      })),
    };
  }

  webSocketMessage() {}

  webSocketClose(ws, code) {
    try { ws.close(code, "closed"); } catch {}
  }
}
