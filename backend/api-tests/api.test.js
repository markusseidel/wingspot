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
    ["POST /v1/checkins", "/v1/checkins", { method: "POST", body: { checkins: [{ id: randomUUID() }] } }],
    ["GET /v1/me/progress", "/v1/me/progress", {}],
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

describe("POST /v1/checkins", () => {
  const TYPE = "ZT99";
  const AIRPORT = 900001;
  const AIRPORT_2 = 900002;
  const registrations = [];
  const ids = [];
  let alice;
  let bob;

  const registration = () => {
    const letters = Array.from({ length: 4 }, () => String.fromCharCode(65 + Math.floor(Math.random() * 26))).join("");
    registrations.push(`D-${letters}`);
    return registrations.at(-1);
  };
  const item = (overrides = {}) => {
    const id = randomUUID();
    ids.push(id);
    return { id, kind: "spotted", occurred_at: new Date(Date.now() - 3600_000).toISOString(), registration: registration(), ...overrides };
  };
  const upload = (user, checkins) => call("/v1/checkins", { method: "POST", token: user.token, body: { checkins } });
  const stored = (id) => service(`checkins?id=eq.${id}&select=*`);

  before(async () => {
    await service("aircraft_types", { method: "POST", body: { icao_code: TYPE, manufacturer: "Test", model: "Zero" } });
    await service("airports", {
      method: "POST",
      body: { id: AIRPORT, icao: "ZZZZ", name: "Test", country_code: "DE", continent: "EU", location: "POINT(8.5 50.0)" },
    });
    await service("airports", {
      method: "POST",
      body: { id: AIRPORT_2, icao: "ZZZY", name: "Test Two", country_code: "DE", continent: "EU", location: "POINT(8.5 51.0)" },
    });
    alice = await signUp();
    bob = await signUp();
  });
  after(async () => {
    for (const id of ids) await service(`checkins?id=eq.${id}`, { method: "DELETE" });
    for (const value of registrations) await service(`aircraft?registration=eq.${value}`, { method: "DELETE" });
    await service(`airports?id=eq.${AIRPORT}`, { method: "DELETE" });
    await service(`airports?id=eq.${AIRPORT_2}`, { method: "DELETE" });
    await service(`aircraft_types?icao_code=eq.${TYPE}`, { method: "DELETE" });
  });

  test("stores a batch and matches the contract", async () => {
    const first = item({ type_icao: TYPE, airport_id: AIRPORT, latitude: 50.03, longitude: 8.57 });
    const second = item();
    const response = await upload(alice, [first, second]);
    assert.equal(response.status, 200, JSON.stringify(response.body));
    assertMatches("CheckinUploadResult", response.body);
    assert.deepEqual(response.body.results, [
      { id: first.id, status: "stored" },
      { id: second.id, status: "stored" },
    ]);

    const [row] = await stored(first.id);
    assert.equal(row.user_id, alice.id);
    assert.equal(row.kind, "spotted");
    assert.equal(row.type_icao, TYPE);
    assert.equal(row.airport_id, AIRPORT);
    assert.equal(row.visibility, "private");
    assert.equal(row.verification, "none");
    assert.ok(row.location, "the location is stored");

    // The shared aircraft row holds only the registration.
    const [aircraft] = await service(`aircraft?registration=eq.${first.registration}&select=*`);
    assert.equal(aircraft.id, row.aircraft_id);
    assert.equal(aircraft.data_status, "user_submitted");
    assert.equal(aircraft.type_icao, null);
    assert.equal(aircraft.operator_id, null);
  });

  test("uploading the same batch again stores nothing twice", async () => {
    const batch = [item(), item({ visibility: "public" })];
    const one = await upload(alice, batch);
    const two = await upload(alice, batch);
    assert.deepEqual(one.body, two.body);
    assert.deepEqual(two.body.results.map((r) => r.status), ["stored", "stored"]);
    for (const { id } of batch) assert.equal((await stored(id)).length, 1);
    assert.equal((await stored(batch[1].id))[0].visibility, "public");
  });

  test("two users sharing a registration share one aircraft row", async () => {
    const shared = registration();
    await upload(alice, [item({ registration: shared })]);
    await upload(bob, [item({ registration: shared })]);
    assert.equal((await service(`aircraft?registration=eq.${shared}&select=id`)).length, 1);
  });

  test("a type-only check-in creates no aircraft", async () => {
    const typeOnly = item({ registration: undefined, type_icao: TYPE });
    const response = await upload(alice, [typeOnly]);
    assert.equal(response.body.results[0].status, "stored");
    assert.equal((await stored(typeOnly.id))[0].aircraft_id, null);
  });

  test("an airport visit stores the airport and why the user was there, and ignores aircraft fields", async () => {
    const visit = item({ kind: "airport", airport_id: AIRPORT, context: "departing", type_icao: TYPE });
    const response = await upload(alice, [visit]);
    assert.deepEqual(response.body.results, [{ id: visit.id, status: "stored" }]);
    const [row] = await stored(visit.id);
    assert.equal(row.kind, "airport");
    assert.equal(row.airport_id, AIRPORT);
    assert.equal(row.visit_context, "departing");
    assert.equal(row.aircraft_id, null);
    assert.equal(row.type_icao, null);
    assert.equal((await upload(alice, [visit])).body.results[0].status, "stored", "a repeat is stored again");
  });

  test("a flight stores its route, details and the distance the server works out", async () => {
    const flight = item({
      kind: "flown", origin_id: AIRPORT, destination_id: AIRPORT_2, flight_number: "lh 400",
      cabin: "economy", seat: "12a", registration: undefined, type_icao: TYPE,
    });
    const response = await upload(alice, [flight]);
    assert.deepEqual(response.body.results, [{ id: flight.id, status: "stored" }]);
    const [row] = await stored(flight.id);
    assert.equal(row.kind, "flown");
    assert.equal(row.origin_id, AIRPORT);
    assert.equal(row.destination_id, AIRPORT_2);
    assert.equal(row.flight_number, "LH400");
    assert.equal(row.cabin_class, "economy");
    assert.equal(row.seat, "12A");
    assert.ok(row.distance_km >= 105 && row.distance_km <= 118, `distance ${row.distance_km}`);
    assert.equal(row.type_icao, TYPE);
  });

  test("another user's id is rejected and the original stays untouched", async () => {
    const mine = item();
    await upload(alice, [mine]);
    const response = await upload(bob, [{ ...mine, registration: registration() }]);
    assert.deepEqual(response.body.results, [{ id: mine.id, status: "rejected", code: "id_taken" }]);
    assert.equal((await stored(mine.id))[0].user_id, alice.id);
  });

  test("a bad item is rejected and the rest of the batch is stored", async () => {
    const good = item();
    const cases = [
      ["unsupported_kind", item({ kind: "banana" })],
      ["missing_airport", item({ kind: "airport", registration: undefined })],
      ["missing_route", item({ kind: "flown" })],
      ["invalid_route", item({ kind: "flown", origin_id: AIRPORT, destination_id: AIRPORT })],
      ["invalid_context", item({ kind: "airport", airport_id: AIRPORT, context: "napping" })],
      ["missing_aircraft", item({ registration: undefined })],
      ["invalid_registration", item({ registration: "not a registration" })],
      ["invalid_time", item({ occurred_at: new Date(Date.now() + 3 * 86400_000).toISOString() })],
      ["invalid_request", item({ occurred_at: "banana" })],
      ["unknown_type", item({ type_icao: "NOPE" })],
      ["unknown_airport", item({ airport_id: 987654 })],
      ["invalid_request", item({ airport_id: "x" })],
      ["invalid_location", item({ latitude: 50 })],
      ["invalid_location", item({ latitude: 95, longitude: 8 })],
      ["invalid_visibility", item({ visibility: "everyone" })],
    ];
    const response = await upload(alice, [good, ...cases.map(([, bad]) => bad)]);
    assert.equal(response.status, 200, JSON.stringify(response.body));
    assertMatches("CheckinUploadResult", response.body);
    assert.deepEqual(response.body.results[0], { id: good.id, status: "stored" });
    cases.forEach(([code, bad], index) => {
      assert.deepEqual(response.body.results[index + 1], { id: bad.id, status: "rejected", code }, `case ${index}`);
    });
    for (const [, bad] of cases) assert.equal((await stored(bad.id)).length, 0, "rejected items are not stored");
    assert.equal((await stored(good.id)).length, 1);
  });

  test("rejects a request that is not valid", async () => {
    const tooMany = Array.from({ length: 51 }, () => item());
    const bad = [
      ["empty list", { checkins: [] }],
      ["not a list", { checkins: "x" }],
      ["missing list", {}],
      ["too many", { checkins: tooMany }],
      ["item without id", { checkins: [{ kind: "spotted" }] }],
      ["item that is not an object", { checkins: ["x"] }],
    ];
    for (const [name, body] of bad) assertError(await call("/v1/checkins", { method: "POST", token: alice.token, body }), 400, name);

    const same = item();
    assertError(await call("/v1/checkins", { method: "POST", token: alice.token, body: { checkins: [same, same] } }), 400);
    assertError(await call("/v1/checkins", { method: "POST", token: alice.token, rawBody: "not json" }), 400);
    assertError(await call("/v1/checkins", { method: "POST", token: alice.token, body: [] }), 400);
  });

  test("rejects other methods and paths", async () => {
    assertError(await call("/v1/checkins", { token: alice.token }), 405);
    assertError(await call("/v1/checkins/x", { method: "POST", token: alice.token, body: {} }), 404);
  });

  test("clients still cannot write check-ins or aircraft directly", async () => {
    const direct = async (table, body) => {
      const response = await fetch(`${API}/rest/v1/${table}`, {
        method: "POST",
        headers: { apikey: ANON_KEY, Authorization: `Bearer ${alice.token}`, "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      return response.status;
    };
    const attempt = item();
    assert.ok([401, 403].includes(await direct("checkins", { id: attempt.id, user_id: alice.id, kind: "spotted", occurred_at: attempt.occurred_at })));
    assert.ok([401, 403].includes(await direct("aircraft", { registration: registration() })));
  });
});

describe("badges and progress", () => {
  const registrations = [];
  const ids = [];

  after(async () => {
    for (const id of ids) await service(`checkins?id=eq.${id}`, { method: "DELETE" });
    for (const value of registrations) await service(`aircraft?registration=eq.${value}`, { method: "DELETE" });
  });

  const spot = () => {
    const letters = Array.from({ length: 4 }, () => String.fromCharCode(65 + Math.floor(Math.random() * 26))).join("");
    registrations.push(`D-${letters}`);
    const id = randomUUID();
    ids.push(id);
    return { id, kind: "spotted", occurred_at: new Date(Date.now() - 3600_000).toISOString(), registration: registrations.at(-1) };
  };
  const upload = (user, checkins) => call("/v1/checkins", { method: "POST", token: user.token, body: { checkins } });
  const progress = (user) => call("/v1/me/progress", { token: user.token });

  test("a new user starts at level 1 with no XP, and hidden badges stay hidden", async () => {
    const user = await signUp();
    const response = await progress(user);
    assert.equal(response.status, 200, JSON.stringify(response.body));
    assertMatches("Progress", response.body);
    assert.equal(response.body.xp, 0);
    assert.equal(response.body.level, 1);
    assert.equal(response.body.hidden_remaining, 3);
    assert.equal(response.body.badges.length, 31);
    assert.ok(response.body.badges.every((badge) => !badge.hidden && badge.level === 0));
    assert.ok(response.body.badges.every((badge) => typeof badge.name.en === "string" && typeof badge.name.de === "string"));
  });

  test("an upload reports the unlocked badge, XP and level, and the answer matches the contract", async () => {
    const user = await signUp();
    const first = spot();
    const response = await upload(user, [first]);
    assert.equal(response.status, 200, JSON.stringify(response.body));
    assertMatches("CheckinUploadResult", response.body);
    assert.deepEqual(response.body.results, [{ id: first.id, status: "stored" }]);
    assert.deepEqual(response.body.badges_unlocked.map((badge) => badge.id), ["wheels_up"]);
    assert.equal(response.body.badges_unlocked[0].name.de, "Abheben");
    assert.equal(response.body.xp, 75, "10 for the check-in, 15 for a new registration, 50 for the badge");
    assert.equal(response.body.level, 1);
  });

  test("a repeated upload unlocks nothing new, but progress still has the badge", async () => {
    const user = await signUp();
    const first = spot();
    await upload(user, [first]);
    const again = await upload(user, [first]);
    assert.deepEqual(again.body.badges_unlocked, []);

    const response = await progress(user);
    const wheelsUp = response.body.badges.find((badge) => badge.id === "wheels_up");
    assert.equal(wheelsUp.level, 1);
    assert.ok(wheelsUp.unlocked_at);
    assert.equal(response.body.xp, 75);
    assert.equal(response.body.badges.find((badge) => badge.id === "logbook").value, 1);
  });

  test("progress catches up on check-ins that were stored without the engine", async () => {
    const user = await signUp();
    const item = spot();
    // Stored directly, as the check-ins uploaded before badges existed were.
    const [aircraft] = await service("aircraft", { method: "POST", body: { registration: item.registration, data_status: "user_submitted" } });
    await service("checkins", { method: "POST", body: { id: item.id, user_id: user.id, kind: "spotted", occurred_at: item.occurred_at, aircraft_id: aircraft.id } });

    const response = await progress(user);
    assert.equal(response.body.badges.find((badge) => badge.id === "wheels_up").level, 1);
    assert.equal(response.body.xp, 75);
  });

  test("rejects other methods", async () => {
    const user = await signUp();
    assertError(await call("/v1/me/progress", { method: "POST", token: user.token, body: {} }), 405);
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
