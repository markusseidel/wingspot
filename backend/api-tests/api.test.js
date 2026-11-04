// Calls the Edge Functions on the local Supabase stack and checks real responses against
// contracts/openapi.yaml. Run from this folder after `supabase start`: npm test
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { after, before, describe, test } from "node:test";
import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";
import { parse } from "yaml";

const root = new URL("../", import.meta.url).pathname;
const status = JSON.parse(execFileSync("supabase", ["status", "--workdir", root, "-o", "json"], { encoding: "utf8" }));
const API = status.API_URL;
const SERVICE_KEY = status.SERVICE_ROLE_KEY;
const ANON_KEY = status.ANON_KEY;

// These tests write data, so never let them near a hosted project.
assert.match(API, /^http:\/\/127\.0\.0\.1:/, "API tests must only run against the local stack");

const spec = parse(readFileSync(new URL("../../contracts/openapi.yaml", import.meta.url), "utf8"));
const ajv = new Ajv2020({ strict: false, allErrors: true });
addFormats(ajv);
ajv.addSchema(spec, "openapi");

function assertMatches(schemaName, body) {
  const validate = ajv.compile({ $ref: `openapi#/components/schemas/${schemaName}` });
  assert.ok(validate(body), `${schemaName}: ${ajv.errorsText(validate.errors)}\n${JSON.stringify(body)}`);
}

async function call(path, { method = "GET", token, body, rawBody } = {}) {
  const response = await fetch(`${API}/functions${path}`, {
    method,
    headers: {
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(body !== undefined || rawBody !== undefined ? { "Content-Type": "application/json" } : {}),
    },
    body: rawBody ?? (body === undefined ? undefined : JSON.stringify(body)),
  });
  const text = await response.text();
  return { status: response.status, body: text ? JSON.parse(text) : null };
}

/** Reads or writes directly as the service role, to set up and verify what the API did. */
async function service(path, { method = "GET", body } = {}) {
  const response = await fetch(`${API}/rest/v1/${path}`, {
    method,
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      "Content-Type": "application/json",
      Prefer: "return=representation",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  assert.ok(response.ok, `service ${method} ${path}: ${response.status} ${text}`);
  return text ? JSON.parse(text) : null;
}

async function signUp() {
  const response = await fetch(`${API}/auth/v1/signup`, {
    method: "POST",
    headers: { apikey: ANON_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ email: `${randomUUID()}@example.test`, password: randomUUID() }),
  });
  const session = await response.json();
  assert.equal(response.status, 200, JSON.stringify(session));
  return { token: session.access_token, id: session.user.id };
}

function assertError(response, status) {
  assert.equal(response.status, status, JSON.stringify(response.body));
  assertMatches("Error", response.body);
}

const device = (overrides = {}) => ({
  id: randomUUID(),
  platform: "ios",
  push_token: randomUUID(),
  push_env: "sandbox",
  app_version: "0.1.0",
  os_version: "18.0",
  locale: "de-DE",
  ...overrides,
});

describe("GET /v1/config", () => {
  test("is public and matches the contract", async () => {
    const response = await call("/v1/config");
    assert.equal(response.status, 200);
    assertMatches("Config", response.body);
    assert.equal(response.body.min_version.ios, "0.1.0");
  });

  test("rejects other methods", async () => {
    assertError(await call("/v1/config", { method: "POST", body: {} }), 405);
  });
});

describe("GET /v1/refdata/manifest", () => {
  const snapshots = "refdata_snapshots?id=gt.0";
  before(() => service(snapshots, { method: "DELETE" }));
  after(() => service(snapshots, { method: "DELETE" }));

  test("returns 404 until a snapshot is published", async () => {
    assertError(await call("/v1/refdata/manifest"), 404);
  });

  test("returns the newest snapshot", async () => {
    const snapshot = (dataVersion, sha) => ({
      schema_version: 1, data_version: dataVersion, url: `https://example.test/${dataVersion}.sqlite`,
      sha256: sha.repeat(64), size_bytes: 1024,
    });
    await service("refdata_snapshots", { method: "POST", body: snapshot("old", "a") });
    await service("refdata_snapshots", { method: "POST", body: snapshot("new", "b") });

    const response = await call("/v1/refdata/manifest");
    assert.equal(response.status, 200);
    assertMatches("RefdataManifest", response.body);
    assert.equal(response.body.data_version, "new");
  });
});

describe("authentication", () => {
  const protectedCalls = [
    ["POST /v1/devices", "/v1/devices", { method: "POST", body: device() }],
    ["DELETE /v1/devices/{id}", `/v1/devices/${randomUUID()}`, { method: "DELETE" }],
    ["GET /v1/me/entitlements", "/v1/me/entitlements", {}],
  ];
  for (const [name, path, options] of protectedCalls) {
    test(`${name} needs a token`, async () => {
      assertError(await call(path, options), 401);
    });
    test(`${name} rejects an invalid token`, async () => {
      assertError(await call(path, { ...options, token: "not-a-token" }), 401);
    });
    test(`${name} rejects the anon key as a user`, async () => {
      assertError(await call(path, { ...options, token: ANON_KEY }), 401);
    });
  }
});

describe("devices", () => {
  let alice, bob;
  before(async () => {
    alice = await signUp();
    bob = await signUp();
  });

  test("registers a device and matches the contract", async () => {
    const body = device();
    const response = await call("/v1/devices", { method: "POST", token: alice.token, body });
    assert.equal(response.status, 200, JSON.stringify(response.body));
    assertMatches("Device", response.body);
    assert.equal(response.body.id, body.id);
    assert.equal(response.body.user_id, undefined, "must not expose user_id");

    const [row] = await service(`devices?id=eq.${body.id}`);
    assert.equal(row.user_id, alice.id);
  });

  test("minimal Android registration is valid", async () => {
    const body = { id: randomUUID(), platform: "android", app_version: "0.1.0" };
    const response = await call("/v1/devices", { method: "POST", token: alice.token, body });
    assert.equal(response.status, 200, JSON.stringify(response.body));
    assertMatches("Device", response.body);
    assert.equal(response.body.push_token, null);
  });

  test("registering again updates the same device", async () => {
    const body = device();
    await call("/v1/devices", { method: "POST", token: alice.token, body });
    const response = await call("/v1/devices", {
      method: "POST", token: alice.token, body: { ...body, app_version: "0.2.0" },
    });
    assert.equal(response.status, 200);
    assert.equal(response.body.app_version, "0.2.0");
    assert.equal((await service(`devices?id=eq.${body.id}`)).length, 1);
  });

  test("a push token moves to the latest account", async () => {
    const pushToken = randomUUID();
    const first = device({ push_token: pushToken });
    const second = device({ push_token: pushToken });
    await call("/v1/devices", { method: "POST", token: alice.token, body: first });
    const response = await call("/v1/devices", { method: "POST", token: bob.token, body: second });
    assert.equal(response.status, 200, JSON.stringify(response.body));

    const rows = await service(`devices?push_token=eq.${pushToken}`);
    assert.deepEqual(rows.map((row) => [row.id, row.user_id]), [[second.id, bob.id]]);
  });

  const invalidBodies = {
    "an invalid id": device({ id: "nope" }),
    "an unknown platform": device({ platform: "web" }),
    "no app version": { id: randomUUID(), platform: "ios" },
    "an unknown push environment": device({ push_env: "staging" }),
    "a push environment on Android": device({ platform: "android", push_env: "production" }),
    "an empty push token": device({ push_token: "" }),
    "a non-string locale": device({ locale: 42 }),
    "an oversized push token": device({ push_token: "x".repeat(5000) }),
    "an array": [],
  };
  for (const [name, body] of Object.entries(invalidBodies)) {
    test(`rejects ${name}`, async () => {
      assertError(await call("/v1/devices", { method: "POST", token: alice.token, body }), 400);
    });
  }

  test("rejects a body that isn't JSON", async () => {
    assertError(await call("/v1/devices", { method: "POST", token: alice.token, rawBody: "{oops" }), 400);
  });

  test("rejects an invalid id on delete", async () => {
    assertError(await call("/v1/devices/nope", { method: "DELETE", token: alice.token }), 400);
  });

  test("deletes your own device, repeatedly", async () => {
    const body = device();
    await call("/v1/devices", { method: "POST", token: alice.token, body });
    assert.equal((await call(`/v1/devices/${body.id}`, { method: "DELETE", token: alice.token })).status, 204);
    assert.deepEqual(await service(`devices?id=eq.${body.id}`), []);
    assert.equal((await call(`/v1/devices/${body.id}`, { method: "DELETE", token: alice.token })).status, 204);
  });

  test("cannot delete another user's device", async () => {
    const body = device();
    await call("/v1/devices", { method: "POST", token: alice.token, body });
    assert.equal((await call(`/v1/devices/${body.id}`, { method: "DELETE", token: bob.token })).status, 204);
    assert.equal((await service(`devices?id=eq.${body.id}`)).length, 1, "the device must still exist");
  });

  test("rejects other methods", async () => {
    assertError(await call("/v1/devices", { token: alice.token }), 405);
  });
});

describe("GET /v1/me/entitlements", () => {
  let alice, bob;
  before(async () => {
    alice = await signUp();
    bob = await signUp();
  });

  test("is empty for a new user", async () => {
    const response = await call("/v1/me/entitlements", { token: alice.token });
    assert.equal(response.status, 200);
    assertMatches("EntitlementList", response.body);
    assert.deepEqual(response.body.entitlements, []);
  });

  test("returns only the user's own entitlements, without store secrets", async () => {
    await service("entitlements", {
      method: "POST",
      body: {
        user_id: alice.id, entitlement: "pro", store: "app_store", product_id: "pro_yearly",
        original_transaction_id: "secret", status: "active", expires_at: "2030-01-01T00:00:00Z", auto_renew: true,
      },
    });

    const response = await call("/v1/me/entitlements", { token: alice.token });
    assert.equal(response.status, 200);
    assertMatches("EntitlementList", response.body);
    assert.equal(response.body.entitlements.length, 1);
    assert.equal(response.body.entitlements[0].status, "active");
    assert.ok(!JSON.stringify(response.body).includes("secret"), "must not expose the transaction ID");

    const other = await call("/v1/me/entitlements", { token: bob.token });
    assert.deepEqual(other.body.entitlements, []);
  });

  test("unknown paths return 404", async () => {
    assertError(await call("/v1/me/other", { token: alice.token }), 404);
  });
});
