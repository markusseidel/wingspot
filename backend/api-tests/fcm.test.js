// Android push: the Firebase Cloud Messaging sender, with a fake Google.
import assert from "node:assert/strict";
import { generateKeyPairSync, verify } from "node:crypto";
import { describe, test } from "node:test";
import { deliver } from "../supabase/functions/send-push/apns.ts";
import { accessToken, fcmConfigFrom, fcmMessage, sendFcm } from "../supabase/functions/send-push/fcm.ts";

const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const pem = privateKey.export({ type: "pkcs8", format: "pem" });
const config = {
  clientEmail: "push@wingspot-test.iam.gserviceaccount.com", privateKey: pem, projectId: "wingspot-test",
  tokenUrl: "https://google.test/token", sendUrl: (id) => `https://fcm.test/v1/projects/${id}/messages:send`,
};
const row = (overrides = {}) => ({
  id: "r1", kind: "salute", actor_id: "a1", actor_username: "anna", actor_name: null, checkin_id: "c1", subject: "D-AIPC", snippet: null,
  devices: [{ id: "d1", token: "ftok1", env: "production", locale: "de", platform: "android" }],
  ...overrides,
});

/** A fake Google: hands out a token, then answers sends per device token. */
function fakeGoogle(answers = {}) {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, init });
    if (url === config.tokenUrl) return new Response(JSON.stringify({ access_token: "ya29.test", expires_in: 3600 }), { status: 200 });
    const token = JSON.parse(init.body).message.token;
    const answer = answers[token] ?? { status: 200 };
    if (answer.throws) throw new Error("offline");
    return new Response(answer.error ? JSON.stringify({ error: answer.error }) : "{}", { status: answer.status });
  };
  return { calls, fetchImpl };
}

describe("FCM", () => {
  test("the service account secret is read, and a broken one is ignored", () => {
    const secret = JSON.stringify({ client_email: "a@b.c", private_key: pem, project_id: "p" });
    assert.deepEqual(fcmConfigFrom(secret), { clientEmail: "a@b.c", privateKey: pem, projectId: "p" });
    assert.equal(fcmConfigFrom("not json"), null);
    assert.equal(fcmConfigFrom(JSON.stringify({ client_email: "a@b.c" })), null);
    assert.equal(fcmConfigFrom(undefined), null);
  });

  test("the access token request is a valid RS256 token for the Firebase scope", async () => {
    const google = fakeGoogle();
    assert.equal(await accessToken(config, 1_800_000_000, google.fetchImpl), "ya29.test");
    const body = new URLSearchParams(google.calls[0].init.body.toString());
    assert.equal(body.get("grant_type"), "urn:ietf:params:oauth:grant-type:jwt-bearer");
    const [header, claims, signature] = body.get("assertion").split(".");
    assert.equal(JSON.parse(Buffer.from(header, "base64url")).alg, "RS256");
    const decoded = JSON.parse(Buffer.from(claims, "base64url"));
    assert.equal(decoded.iss, config.clientEmail);
    assert.equal(decoded.scope, "https://www.googleapis.com/auth/firebase.messaging");
    assert.equal(verify("sha256", Buffer.from(`${header}.${claims}`), publicKey, Buffer.from(signature, "base64url")), true);
    assert.equal(await accessToken(config, 1, async () => new Response("no", { status: 401 })), null);
  });

  test("the message has the text in the phone's language and what is needed to open the right screen", () => {
    const { message } = fcmMessage(row(), row().devices[0]);
    assert.equal(message.token, "ftok1");
    assert.equal(message.notification.body, "hat deinen Check-in salutiert (D-AIPC).");
    assert.deepEqual(message.data, { type: "salute", checkin: "c1", actor: "a1" });
    assert.equal(message.android.notification.channel_id, "wingspot_activity");
    assert.equal(message.android.collapse_key, "salute-c1");
  });

  test("a dead token is reported, an odd failure is retried, and a bad payload is not a dead token", async () => {
    const google = fakeGoogle({
      gone: { status: 404, error: { status: "NOT_FOUND" } },
      busy: { status: 503, error: { status: "UNAVAILABLE" } },
      bad: { status: 400, error: { status: "INVALID_ARGUMENT", message: "Invalid JSON payload" } },
      badtoken: { status: 400, error: { status: "INVALID_ARGUMENT", message: "The registration token is not a valid FCM registration token" } },
    });
    const dev = (token) => ({ id: token, token, env: "production", locale: "en", platform: "android" });
    const result = (token) => sendFcm(config, "ya29", dev(token), row(), google.fetchImpl);
    assert.deepEqual(await result("fine"), { ok: true });
    assert.equal((await result("gone")).dead, true);
    assert.equal((await result("busy")).dead, false);
    assert.equal((await result("bad")).dead, false);
    assert.equal((await result("badtoken")).dead, true);
  });
});

describe("delivering to both kinds of phone", () => {
  const apple = { key: "unused", keyId: "K", teamId: "T", topic: "t" };
  const android = (google) => ({
    token: (now, f) => accessToken(config, now, f),
    send: (token, device, r, f) => sendFcm(config, token, device, r, f),
  });

  test("an Android device is sent through FCM and an unknown platform counts as iOS", async () => {
    const google = fakeGoogle();
    const rows = [row()];
    const [outcome] = await deliver(rows, null, 1_800_000_000, google.fetchImpl, android(google));
    assert.deepEqual(outcome, { id: "r1", delivered: true, dead: [] });
    assert.equal(google.calls[1].url, "https://fcm.test/v1/projects/wingspot-test/messages:send");
    assert.equal(google.calls[1].init.headers.authorization, "Bearer ya29.test");
  });

  test("without Firebase set up an Android device is skipped, and a failed token request puts the row back", async () => {
    const google = fakeGoogle();
    assert.deepEqual((await deliver([row()], null, 1, google.fetchImpl, null))[0], { id: "r1", delivered: true, dead: [] });
    assert.equal(google.calls.length, 0);
    const refused = async () => new Response("no", { status: 401 });
    assert.equal((await deliver([row()], null, 1, refused, android()))[0].delivered, false);
  });

  test("dead Android tokens are reported", async () => {
    const google = fakeGoogle({ ftok1: { status: 404, error: { status: "NOT_FOUND" } } });
    assert.deepEqual((await deliver([row()], null, 1, google.fetchImpl, android(google)))[0], { id: "r1", delivered: true, dead: ["d1"] });
  });
});
