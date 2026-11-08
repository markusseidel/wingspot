// Milestone 10b: writing and sending push notifications, with a fake Apple.
import assert from "node:assert/strict";
import { generateKeyPairSync, verify } from "node:crypto";
import { execFileSync } from "node:child_process";
import { describe, test } from "node:test";
import { deliver, payload, providerToken, render } from "../supabase/functions/send-push/apns.ts";

const row = (overrides = {}) => ({
  id: "r1", kind: "salute", actor_id: "a1", actor_username: "anna", actor_name: null, checkin_id: "c1",
  subject: "D-AIPC", snippet: null,
  devices: [{ id: "d1", token: "tok1", env: "production", locale: "en_US" }],
  ...overrides,
});

const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
const config = {
  key: privateKey.export({ type: "pkcs8", format: "pem" }), keyId: "KEY1234567", teamId: "TEAM123456",
  topic: "site.wingspot.ios", host: (env) => `https://${env}.apns.test`,
};

describe("push texts", () => {
  test("English and German for each kind", () => {
    assert.deepEqual(render(row({ kind: "follow", subject: null }), "en_US"), { title: "anna", body: "started following you." });
    assert.equal(render(row({ kind: "follow", subject: null }), "de_DE").body, "folgt dir jetzt.");
    assert.equal(render(row(), "en").body, "saluted your check-in (D-AIPC).");
    assert.equal(render(row(), "de").body, "hat deinen Check-in gesalutiert (D-AIPC).");
    assert.equal(render(row({ subject: null }), "en").body, "saluted your check-in.");
    assert.equal(render(row({ kind: "comment", snippet: "Nice  one\n!" }), "en").body, "commented: “Nice one !”");
    assert.equal(render(row({ kind: "comment", snippet: "Toll" }), "de").body, "hat kommentiert: „Toll“");
  });

  test("the display name wins over the username, and no locale means English", () => {
    assert.equal(render(row({ actor_name: "Anna B." }), null).title, "Anna B.");
    assert.equal(render(row(), null).body, "saluted your check-in (D-AIPC).");
  });

  test("the payload carries what the app needs to open the right screen", () => {
    const body = payload(row(), "en");
    assert.equal(body.type, "salute");
    assert.equal(body.checkin, "c1");
    assert.equal(body.aps.alert.title, "anna");
    assert.equal(body.aps.category, "WINGSPOT_ACTIVITY", "the app shows a neutral text for this category while previews are hidden");
    assert.equal(body.aps["thread-id"], "salute-c1");
    assert.equal(payload(row({ kind: "follow", checkin_id: null }), "en").aps["thread-id"], "follow");
  });
});

describe("the provider token", () => {
  test("is a valid ES256 token with the key and team, and stays the same for 20 minutes", async () => {
    const now = 1_800_000_000;
    const token = await providerToken(config, now);
    const [header, claims, signature] = token.split(".");
    assert.deepEqual(JSON.parse(Buffer.from(header, "base64url")), { alg: "ES256", kid: "KEY1234567" });
    const parsed = JSON.parse(Buffer.from(claims, "base64url"));
    assert.equal(parsed.iss, "TEAM123456");
    assert.equal(parsed.iat, Math.floor(now / 1200) * 1200);
    const ok = verify("sha256", Buffer.from(`${header}.${claims}`), { key: publicKey, dsaEncoding: "ieee-p1363" },
      Buffer.from(signature, "base64url"));
    assert.ok(ok, "the signature checks out with the public key");
    const later = JSON.parse(Buffer.from((await providerToken(config, now + 60)).split(".")[1], "base64url"));
    assert.equal(later.iat, parsed.iat);
  });

  test("accepts the key with escaped line breaks, as it can come out of an environment variable", async () => {
    const escaped = { ...config, key: config.key.trim().replace(/\n/g, "\\n") };
    assert.equal((await providerToken(escaped, 1_800_000_000)).split(".").length, 3);
  });
});

/** A fake Apple: answers per token and remembers what it was asked. */
function fakeApple(answers) {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, init });
    const token = url.split("/").pop();
    const answer = answers[token] ?? { status: 200 };
    if (answer.throws) throw new Error("offline");
    return new Response(answer.reason ? JSON.stringify({ reason: answer.reason }) : null, { status: answer.status });
  };
  return { calls, fetchImpl };
}

describe("sending", () => {
  test("posts to the right host with the right headers and body", async () => {
    const apple = fakeApple({});
    const rows = [row({ devices: [
      { id: "d1", token: "tok1", env: "production", locale: "de_DE" },
      { id: "d2", token: "tok2", env: "sandbox", locale: "en_US" },
    ] })];
    const [outcome] = await deliver(rows, config, 1_800_000_000, apple.fetchImpl);
    assert.deepEqual(outcome, { id: "r1", delivered: true, dead: [] });
    assert.equal(apple.calls[0].url, "https://production.apns.test/3/device/tok1");
    assert.equal(apple.calls[1].url, "https://sandbox.apns.test/3/device/tok2");
    const headers = apple.calls[0].init.headers;
    assert.match(headers.authorization, /^bearer [\w-]+\.[\w-]+\.[\w-]+$/);
    assert.equal(headers["apns-topic"], "site.wingspot.ios");
    assert.equal(headers["apns-push-type"], "alert");
    assert.equal(headers["apns-collapse-id"], "salute-c1");
    assert.equal(JSON.parse(apple.calls[0].init.body).aps.alert.body, "hat deinen Check-in gesalutiert (D-AIPC).");
    assert.equal(JSON.parse(apple.calls[1].init.body).aps.alert.body, "saluted your check-in (D-AIPC).");
  });

  test("a dead token is reported and the row still counts as done", async () => {
    const apple = fakeApple({ tok1: { status: 410, reason: "Unregistered" }, tok2: { status: 400, reason: "BadDeviceToken" } });
    const rows = [row({ devices: [
      { id: "d1", token: "tok1", env: "production", locale: null }, { id: "d2", token: "tok2", env: "production", locale: null },
    ] })];
    assert.deepEqual((await deliver(rows, config, 1, apple.fetchImpl))[0], { id: "r1", delivered: true, dead: ["d1", "d2"] });
  });

  test("a failure that may pass puts the row back, but one good device is enough", async () => {
    const down = fakeApple({ tok1: { status: 503, reason: "ServiceUnavailable" } });
    assert.equal((await deliver([row()], config, 1, down.fetchImpl))[0].delivered, false);
    const offline = fakeApple({ tok1: { throws: true } });
    assert.equal((await deliver([row()], config, 1, offline.fetchImpl))[0].delivered, false);
    const rejected = fakeApple({ tok1: { status: 403, reason: "ExpiredProviderToken" } });
    const outcome = (await deliver([row()], config, 1, rejected.fetchImpl))[0];
    assert.equal(outcome.delivered, false);
    assert.deepEqual(outcome.dead, [], "a problem with our own token never removes a device");
    const mixed = fakeApple({ tok1: { status: 503 } });
    const rows = [row({ devices: [
      { id: "d1", token: "tok1", env: "production", locale: null }, { id: "d2", token: "tok2", env: "production", locale: null },
    ] })];
    assert.equal((await deliver(rows, config, 1, mixed.fetchImpl))[0].delivered, true);
  });

  test("a row without devices is done and calls nobody", async () => {
    const apple = fakeApple({});
    assert.deepEqual((await deliver([row({ devices: [] })], config, 1, apple.fetchImpl))[0], { id: "r1", delivered: true, dead: [] });
    assert.equal(apple.calls.length, 0);
  });

  test("follows and comments don't replace each other on the phone", async () => {
    const apple = fakeApple({});
    await deliver([row({ kind: "comment", snippet: "hi" }), row({ id: "r2", kind: "follow", checkin_id: null })], config, 1, apple.fetchImpl);
    assert.equal(apple.calls[0].init.headers["apns-collapse-id"], undefined);
    assert.equal(apple.calls[1].init.headers["apns-collapse-id"], undefined);
  });
});

describe("the send-push endpoint", () => {
  const root = new URL("../", import.meta.url).pathname;
  const status = JSON.parse(execFileSync("supabase", ["status", "--workdir", root, "-o", "json"], { encoding: "utf8" }));
  const url = `${status.API_URL}/functions/v1/send-push`;

  test("refuses a call without the secret, and a GET", async () => {
    const post = await fetch(url, { method: "POST", headers: { apikey: status.ANON_KEY } });
    assert.equal(post.status, 401);
    const wrong = await fetch(url, { method: "POST", headers: { apikey: status.ANON_KEY, "x-push-secret": "nope" } });
    assert.equal(wrong.status, 401);
    assert.equal((await fetch(url, { headers: { apikey: status.ANON_KEY } })).status, 405);
  });
});
