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

const runEvent = (repo, id = 1, action = "completed") => ({
  action,
  repository: { full_name: repo },
  workflow_run: { id, head_branch: "secret-branch", display_title: "secret title" },
});

const hub = () => env.HUB.get(env.HUB.idFromName("hub"));

beforeEach(() =>
  runInDurableObject(hub(), (obj) => {
    obj.sql.exec("DELETE FROM events; DELETE FROM devices; DELETE FROM hooks; DELETE FROM org_hooks; DELETE FROM config");
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

  it("accepts an org event without a repository", async () => {
    const r = await webhook("projects_v2_item", {
      action: "edited",
      organization: { login: "Acme" },
      projects_v2_item: { node_id: "PVTI_1", project_node_id: "PVT_9" },
    });
    expect(r.status).toBe(202);
    const body = await (await authed("/v1/events?after=0")).json();
    expect(body.events.at(-1)).toMatchObject({
      repo: "", org: "acme", kind: "projects_v2_item", projectId: "PVT_9", itemId: "PVTI_1", issueNumber: null,
    });
  });

  it("stores no text from a projects_v2_item payload", async () => {
    await webhook("projects_v2_item", {
      action: "edited",
      organization: { login: "Acme" },
      sender: { login: "hidden-user" },
      projects_v2_item: {
        node_id: "PVTI_1",
        project_node_id: "PVT_9",
        content_title: "hidden-title",
        content_body: "hidden-body",
      },
    }, { id: "proj-text" });
    const body = await (await authed("/v1/events?after=0")).json();
    const row = body.events.find((e) => e.deliveryId === "proj-text");
    const stored = await runInDurableObject(hub(), (obj) =>
      JSON.stringify(obj.sql.exec("SELECT * FROM events WHERE delivery_id = 'proj-text'").toArray()));
    expect(JSON.stringify(row)).not.toContain("hidden-title");
    expect(JSON.stringify(row)).not.toContain("hidden-body");
    expect(JSON.stringify(row)).not.toContain("hidden-user");
    expect(stored).not.toContain("hidden-title");
    expect(stored).not.toContain("hidden-body");
    expect(stored).not.toContain("hidden-user");
    expect((await (await authed("/v1/health")).json()).projectEventsToday).toBeGreaterThan(0);
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
    ["PUT", "/v1/org-hooks/acme"], ["GET", "/v1/connect"],
  ];
  for (const [method, path] of routes) {
    it(`${method} ${path} needs a token`, async () => {
      expect((await call(path, { method })).status).toBe(401);
      expect((await authed(path, "wrong", { method })).status).toBe(401);
    });
  }

  it("serves the discovery route without auth", async () => {
    expect(await (await call("/")).json()).toEqual({ app: "cat-eye-relay", version: "2" });
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

  it("filters org events by the orgs of the device", async () => {
    await putJSON("/v1/devices/self", { name: "A", repos: ["o/a"], orgs: ["Acme"] }, "token-a");
    await putJSON("/v1/devices/self", { name: "B", repos: ["o/b"], orgs: [] }, "token-b");
    await webhook("projects_v2_item", {
      action: "edited",
      organization: { login: "Acme" },
      projects_v2_item: { node_id: "PVTI_1", project_node_id: "PVT_9" },
    });
    await webhook("workflow_run", runEvent("o/b", 2));
    await webhook("issues", { action: "opened", organization: { login: "Acme" }, repository: { full_name: "Acme/App" }, issue: { number: 4, title: "hidden-title" } });
    const a = await (await authed("/v1/events?after=0", "token-a")).json();
    const b = await (await authed("/v1/events?after=0", "token-b")).json();
    expect(a.events.map((e) => e.kind)).toEqual(["projects_v2_item", "issues"]);
    expect(a.events[1]).toMatchObject({ repo: "acme/app", org: "acme", issueNumber: 4 });
    expect(JSON.stringify(a)).not.toContain("hidden-title");
    expect(b.events.map((e) => e.repo)).toEqual(["o/b"]);
    expect((await (await authed("/v1/health")).json()).devices.find((d) => d.id === "AAAA").orgs).toEqual(["acme"]);
  });

  it("records hooks", async () => {
    await putJSON("/v1/hooks/O/R", { hookId: 42 });
    const health = await (await authed("/v1/health")).json();
    expect(health.hooks).toContainEqual({ repo: "o/r", hookId: 42, lastDelivery: null });
    await authed("/v1/hooks/o/r", "token-a", { method: "DELETE" });
    expect((await (await authed("/v1/health")).json()).hooks).toEqual([]);
  });

  it("records org hooks", async () => {
    await putJSON("/v1/org-hooks/Acme", { hookId: 7 });
    const health = await (await authed("/v1/health")).json();
    expect(health.orgHooks).toContainEqual({ org: "acme", hookId: 7, lastDelivery: null });
    await authed("/v1/org-hooks/acme", "token-a", { method: "DELETE" });
    expect((await (await authed("/v1/health")).json()).orgHooks).toEqual([]);
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
      org: null, projectId: null, itemId: null, issueNumber: null,
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
