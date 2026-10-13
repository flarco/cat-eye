import { env, runInDurableObject, runDurableObjectAlarm } from "cloudflare:test";
import { exports } from "cloudflare:workers";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const BASE = "https://relay.test";
const enc = new TextEncoder();
let delivery = 0;

const call = (path, init = {}) => exports.default.fetch(new Request(BASE + path, init));
const authed = (path, token = "token-a", init = {}) =>
  call(path, { ...init, headers: { ...(init.headers || {}), authorization: `Bearer ${token}` } });
const putJSON = (path, body, token) =>
  authed(path, token, { method: "PUT", body: JSON.stringify(body) });

async function sign(secret, body) {
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode(body)));
  return "sha256=" + [...mac].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function webhook(kind, payload, { secret = "test-secret", id } = {}) {
  const body = JSON.stringify(payload);
  return call("/webhook", {
    method: "POST",
    body,
    headers: {
      "x-github-event": kind,
      "x-github-delivery": id ?? `d-${++delivery}`,
      "x-hub-signature-256": await sign(secret, body),
    },
  });
}

const PLANE_SECRET = "plane_wh_test_secret_0123456789";

async function planeHook(workspace, payload, { secret = PLANE_SECRET, event = "workitem.updated", prefix = "" } = {}) {
  const body = JSON.stringify(payload);
  return call(`/plane/${workspace}`, {
    method: "POST",
    body,
    headers: {
      "x-plane-event": event,
      "x-plane-delivery": `pd-${++delivery}`,
      "x-plane-signature": prefix + (await sign(secret, body)).slice(7),
    },
  });
}

const planeItem = (eventId, extra = {}) => ({
  version: "v2", event_id: eventId, entity_type: "issue", entity_id: "11111111-1111-1111-1111-111111111111",
  event: "WebhookScope.ScopeChoices.WORKITEM_UPDATED",
  data: { project_id: "22222222-2222-2222-2222-222222222222", name: "hidden-title", description_html: "<p>hidden-body</p>" },
  previous_attributes: { priority: "none" },
  ...extra,
});

const runEvent = (repo, id = 1, action = "completed") => ({
  action,
  repository: { full_name: repo },
  workflow_run: { id, head_branch: "secret-branch", display_title: "secret title" },
});

const hub = () => env.HUB.get(env.HUB.idFromName("hub"));

beforeEach(() =>
  runInDurableObject(hub(), (obj) => {
    obj.sql.exec("DELETE FROM events; DELETE FROM devices; DELETE FROM hooks; DELETE FROM plane_hooks; DELETE FROM config");
  }));
afterEach(() => vi.restoreAllMocks());

describe("webhook", () => {
  it("accepts a valid signature", async () => {
    const r = await webhook("workflow_run", runEvent("O/Repo"));
    expect(r.status).toBe(202);
  });

  it("rejects an invalid signature", async () => {
    const r = await webhook("workflow_run", runEvent("o/repo"), { secret: "wrong" });
    expect(r.status).toBe(401);
  });

  it("rejects a missing signature", async () => {
    const r = await call("/webhook", { method: "POST", body: "{}", headers: { "x-github-event": "workflow_run" } });
    expect(r.status).toBe(401);
  });

  it("answers a ping", async () => {
    const r = await webhook("ping", { zen: "hi" });
    expect(r.status).toBe(200);
  });

  it("ignores other events", async () => {
    const r = await webhook("push", { repository: { full_name: "o/repo" } });
    expect(r.status).toBe(204);
  });

  it("stores IDs only and drops duplicates", async () => {
    await webhook("workflow_job", { action: "queued", repository: { full_name: "o/r" }, workflow_job: { id: 9, run_id: 7 } }, { id: "same" });
    const dup = await webhook("workflow_job", { action: "queued", repository: { full_name: "o/r" }, workflow_job: { id: 9, run_id: 7 } }, { id: "same" });
    expect(await dup.json()).toEqual({ duplicate: true });
    const body = await (await authed("/v1/events?after=0")).json();
    const rows = body.events.filter((e) => e.deliveryId === "same");
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ repo: "o/r", kind: "workflow_job", action: "queued", runId: 7, jobId: 9 });
    expect(JSON.stringify(body)).not.toContain("secret");
  });

  it("ignores GitHub project events", async () => {
    const r = await webhook("projects_v2_item", {
      action: "edited",
      organization: { login: "Acme" },
      projects_v2_item: { node_id: "PVTI_1", project_node_id: "PVT_9" },
    });
    expect(r.status).toBe(204);
  });

  it("never logs the body", async () => {
    const spies = ["log", "info", "warn", "error", "debug"].map((m) => vi.spyOn(console, m));
    await webhook("workflow_run", runEvent("o/logged"));
    await webhook("workflow_run", runEvent("o/logged"), { secret: "wrong" });
    const out = spies.flatMap((s) => s.mock.calls.flat()).join(" ");
    expect(out).not.toContain("secret-branch");
    expect(out).not.toContain("o/logged");
  });
});

describe("auth", () => {
  const routes = [
    ["GET", "/v1/events"], ["POST", "/v1/ack"], ["PUT", "/v1/devices/self"], ["DELETE", "/v1/devices/AAAA"],
    ["GET", "/v1/health"], ["PUT", "/v1/config"], ["GET", "/v1/webhook-secret"], ["PUT", "/v1/hooks/o/r"],
    ["PUT", "/v1/plane-hooks/acme"], ["GET", "/v1/connect"],
  ];
  for (const [method, path] of routes) {
    it(`${method} ${path} needs a token`, async () => {
      expect((await call(path, { method })).status).toBe(401);
      expect((await authed(path, "wrong", { method })).status).toBe(401);
    });
  }

  it("serves the discovery route without auth", async () => {
    expect(await (await call("/")).json()).toEqual({ app: "cat-eye-relay", version: "3" });
  });

  it("returns the webhook secret to a device", async () => {
    expect(await (await authed("/v1/webhook-secret")).json()).toEqual({ secret: "test-secret" });
  });
});

describe("devices and events", () => {
  it("filters events by the repos of the device", async () => {
    await putJSON("/v1/devices/self", { name: "A", repos: ["o/a"] }, "token-a");
    await putJSON("/v1/devices/self", { name: "B", repos: ["o/b"] }, "token-b");
    await webhook("workflow_run", runEvent("o/a", 1));
    await webhook("workflow_run", runEvent("O/B", 2));
    const a = await (await authed("/v1/events?after=0", "token-a")).json();
    const b = await (await authed("/v1/events?after=0", "token-b")).json();
    expect(a.events.map((e) => e.repo)).toEqual(["o/a"]);
    expect(b.events.map((e) => e.repo)).toEqual(["o/b"]);
    expect(a.next).toBe(a.head);
  });

  it("pages with next and more", async () => {
    for (let i = 0; i < 3; i++) await webhook("workflow_run", runEvent("o/p", i));
    const r = await (await authed("/v1/events?after=0&limit=2")).json();
    expect(r.more).toBe(true);
    expect(r.next).toBe(r.events[1].seq);
  });

  it("acks move the cursor forward only", async () => {
    await putJSON("/v1/devices/self", { name: "A", repos: [] }, "token-a");
    await webhook("workflow_run", runEvent("o/c"));
    const head = (await (await authed("/v1/events?after=0")).json()).head;
    await authed("/v1/ack", "token-a", { method: "POST", body: JSON.stringify({ seq: head }) });
    await authed("/v1/ack", "token-a", { method: "POST", body: JSON.stringify({ seq: 0 }) });
    const health = await (await authed("/v1/health")).json();
    expect(health.devices.find((d) => d.id === "AAAA").lag).toBe(0);
  });

  it("removes a device", async () => {
    await putJSON("/v1/devices/self", { name: "B", repos: [] }, "token-b");
    await authed("/v1/devices/BBBB", "token-a", { method: "DELETE" });
    const health = await (await authed("/v1/health")).json();
    expect(health.devices.some((d) => d.id === "BBBB")).toBe(false);
  });

  it("filters Plane events by the workspaces of the device", async () => {
    await putJSON("/v1/plane-hooks/acme", { hookId: "h-1", secret: PLANE_SECRET });
    await putJSON("/v1/devices/self", { name: "A", repos: ["o/a"], orgs: ["plane:Acme"] }, "token-a");
    await putJSON("/v1/devices/self", { name: "B", repos: ["o/b"], orgs: [] }, "token-b");
    await planeHook("acme", planeItem("e-filter"));
    await webhook("workflow_run", runEvent("o/b", 2));
    const a = await (await authed("/v1/events?after=0", "token-a")).json();
    const b = await (await authed("/v1/events?after=0", "token-b")).json();
    expect(a.events.map((e) => e.kind)).toEqual(["plane"]);
    expect(b.events.map((e) => e.repo)).toEqual(["o/b"]);
    expect((await (await authed("/v1/health")).json()).devices.find((d) => d.id === "AAAA").orgs).toEqual(["plane:acme"]);
  });

  it("records hooks", async () => {
    await putJSON("/v1/hooks/O/R", { hookId: 42 });
    const health = await (await authed("/v1/health")).json();
    expect(health.hooks).toContainEqual({ repo: "o/r", hookId: 42, lastDelivery: null });
    await authed("/v1/hooks/o/r", "token-a", { method: "DELETE" });
    expect((await (await authed("/v1/health")).json()).hooks).toEqual([]);
  });

  it("records Plane hooks without the secret in health", async () => {
    expect((await putJSON("/v1/plane-hooks/Acme", { hookId: 7, secret: PLANE_SECRET })).status).toBe(400);
    expect((await putJSON("/v1/plane-hooks/Acme", { hookId: "h-7", secret: "short" })).status).toBe(400);
    await putJSON("/v1/plane-hooks/Acme", { hookId: "h-7", secret: PLANE_SECRET });
    const health = await (await authed("/v1/health")).json();
    expect(health.planeHooks).toEqual([{ workspace: "acme", hookId: "h-7", lastDelivery: null }]);
    expect(JSON.stringify(health)).not.toContain(PLANE_SECRET);
    await authed("/v1/plane-hooks/acme", "token-a", { method: "DELETE" });
    expect((await (await authed("/v1/health")).json()).planeHooks).toEqual([]);
  });

  it("migrates an old events table twice and still reads its rows", async () => {
    await runInDurableObject(hub(), (obj) => {
      obj.sql.exec("DROP TABLE events");
      obj.sql.exec(`CREATE TABLE events (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        delivery_id TEXT NOT NULL UNIQUE,
        repo TEXT NOT NULL,
        kind TEXT NOT NULL,
        action TEXT,
        run_id INTEGER, job_id INTEGER, pr_number INTEGER,
        received_at INTEGER NOT NULL
      )`);
      obj.sql.exec(
        "INSERT INTO events (delivery_id, repo, kind, action, received_at) VALUES ('legacy', 'o/legacy', 'workflow_run', 'completed', ?)",
        Date.now());
      obj.migrate();
      obj.migrate();
    });
    const body = await (await authed("/v1/events?after=0")).json();
    const row = body.events.find((e) => e.deliveryId === "legacy");
    expect(row).toMatchObject({
      repo: "o/legacy", kind: "workflow_run", action: "completed",
      org: null, projectId: null, itemId: null,
    });
  });
});

describe("retention", () => {
  it("validates the range", async () => {
    expect((await putJSON("/v1/config", { retentionHours: 0 })).status).toBe(400);
    expect((await putJSON("/v1/config", { retentionHours: 721 })).status).toBe(400);
    expect(await (await putJSON("/v1/config", { retentionHours: 48 })).json()).toEqual({ retentionHours: 48 });
    expect((await (await authed("/v1/health")).json()).retentionHours).toBe(48);
  });

  it("the alarm deletes old rows and marks the gap", async () => {
    await webhook("workflow_run", runEvent("o/old"));
    await runInDurableObject(hub(), (obj) => {
      obj.sql.exec("UPDATE events SET received_at = received_at - ?", 25 * 3600_000);
    });
    await webhook("workflow_run", runEvent("o/new"));
    expect(await runDurableObjectAlarm(hub())).toBe(true);
    const r = await (await authed("/v1/events?after=0")).json();
    expect(r.events.map((e) => e.repo)).toEqual(["o/new"]);
    expect(r.truncated).toBe(true);
    const fresh = await (await authed(`/v1/events?after=${r.head}`)).json();
    expect(fresh.truncated).toBe(false);
  });
});

describe("websocket", () => {
  it("pokes a connected socket and answers ping", async () => {
    const res = await authed("/v1/connect", "token-a", { headers: { upgrade: "websocket" } });
    expect(res.status).toBe(101);
    const ws = res.webSocket;
    ws.accept();
    const got = [];
    const next = () => new Promise((resolve) => ws.addEventListener("message", (e) => resolve(e.data), { once: true }));
    let msg = next();
    ws.send("ping");
    got.push(await msg);
    msg = next();
    await webhook("workflow_run", runEvent("o/ws"));
    got.push(JSON.parse(await msg));
    expect(got[0]).toBe("pong");
    expect(got[1].type).toBe("poke");
    ws.close();
  });
});

describe("plane webhook", () => {
  beforeEach(() => putJSON("/v1/plane-hooks/acme", { hookId: "h-1", secret: PLANE_SECRET }));

  it("stores IDs only and answers 200", async () => {
    const r = await planeHook("acme", planeItem("e-1"));
    expect(r.status).toBe(200);
    const body = await (await authed("/v1/events?after=0")).json();
    expect(body.events.at(-1)).toMatchObject({
      deliveryId: "plane:e-1", repo: "", org: "plane:acme", kind: "plane", action: "workitem.updated",
      projectId: "22222222-2222-2222-2222-222222222222", itemId: "11111111-1111-1111-1111-111111111111",
    });
    const stored = await runInDurableObject(hub(), (obj) => JSON.stringify(obj.sql.exec("SELECT * FROM events").toArray()));
    expect(stored).not.toContain("hidden-title");
    expect(stored).not.toContain("hidden-body");
    const health = await (await authed("/v1/health")).json();
    expect(health.projectEventsToday).toBe(1);
    expect(health.planeHooks[0].lastDelivery).toBeGreaterThan(0);
  });

  it("accepts a sha256= prefix and data as a JSON string", async () => {
    const payload = planeItem("e-2", { data: JSON.stringify({ project_id: "p-str" }) });
    expect((await planeHook("acme", payload, { prefix: "sha256=", event: "workitem.comment.created" })).status).toBe(200);
    const body = await (await authed("/v1/events?after=0")).json();
    expect(body.events.at(-1)).toMatchObject({ projectId: "p-str", action: "workitem.comment.created" });
  });

  it("uses the entity id of a project event as the project", async () => {
    await planeHook("acme", { event_id: "e-3", entity_type: "project", entity_id: "p-9", data: {} }, { event: "project.updated" });
    const body = await (await authed("/v1/events?after=0")).json();
    expect(body.events.at(-1)).toMatchObject({ projectId: "p-9", itemId: null });
  });

  it("drops a repeated event id", async () => {
    await planeHook("acme", planeItem("e-4"));
    expect((await planeHook("acme", planeItem("e-4"))).status).toBe(200);
    const body = await (await authed("/v1/events?after=0")).json();
    expect(body.events.filter((e) => e.deliveryId === "plane:e-4")).toHaveLength(1);
  });

  it("rejects a bad signature and an unknown workspace", async () => {
    expect((await planeHook("acme", planeItem("e-5"), { secret: "wrong-secret-0123456789" })).status).toBe(401);
    expect((await call("/plane/acme", { method: "POST", body: "{}" })).status).toBe(401);
    expect((await planeHook("other", planeItem("e-6"))).status).toBe(404);
    const body = await (await authed("/v1/events?after=0")).json();
    expect(body.events).toHaveLength(0);
  });

  it("never logs the body", async () => {
    const spies = ["log", "info", "warn", "error", "debug"].map((m) => vi.spyOn(console, m));
    await planeHook("acme", planeItem("e-7"));
    const out = spies.flatMap((s) => s.mock.calls.flat()).join(" ");
    expect(out).not.toContain("hidden-title");
  });
});
