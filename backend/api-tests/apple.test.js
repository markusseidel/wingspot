// Sign in with Apple, server side: the code exchange and the revoke, with a fake Apple.
import assert from "node:assert/strict";
import { generateKeyPairSync, verify } from "node:crypto";
import { describe, test } from "node:test";
import { clientSecret, configFromEnv, exchangeCode, revokeToken } from "../supabase/functions/me/apple.ts";

const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
const config = {
  key: privateKey.export({ type: "pkcs8", format: "pem" }), keyId: "SIWAKEY123", teamId: "TEAM123456",
  clientId: "site.wingspot.ios", host: "https://apple.test",
};

const fake = (status, body = {}) => {
  const calls = [];
  const impl = async (url, init) => {
    calls.push({ url, fields: Object.fromEntries(init.body) });
    return new Response(JSON.stringify(body), { status });
  };
  return { calls, impl };
};

describe("the client secret", () => {
  test("is a short-lived token signed with the key", async () => {
    const secret = await clientSecret(config, 1_000_000);
    const [header, claims, signature] = secret.split(".");
    assert.deepEqual(JSON.parse(Buffer.from(header, "base64url")), { alg: "ES256", kid: "SIWAKEY123" });
    assert.deepEqual(JSON.parse(Buffer.from(claims, "base64url")), {
      iss: "TEAM123456", iat: 1_000_000, exp: 1_000_300, aud: "https://appleid.apple.com", sub: "site.wingspot.ios",
    });
    assert.ok(verify("sha256", Buffer.from(`${header}.${claims}`), { key: publicKey, dsaEncoding: "ieee-p1363" },
      Buffer.from(signature, "base64url")));
  });
});

describe("settings", () => {
  test("need the key, its ID and the team", () => {
    const env = { APPLE_SIWA_KEY: "k", APPLE_SIWA_KEY_ID: "i", APNS_TEAM_ID: "t" };
    assert.deepEqual(configFromEnv((n) => env[n]), { key: "k", keyId: "i", teamId: "t", clientId: "site.wingspot.ios" });
    assert.equal(configFromEnv((n) => ({ ...env, APPLE_SIWA_KEY: undefined })[n]), null);
    assert.equal(configFromEnv(() => undefined), null);
  });
});

describe("the exchange and the revoke", () => {
  test("a code becomes a refresh token", async () => {
    const apple = fake(200, { refresh_token: "r1", access_token: "a" });
    assert.equal(await exchangeCode(config, "code1", apple.impl), "r1");
    assert.equal(apple.calls[0].url, "https://apple.test/auth/token");
    assert.equal(apple.calls[0].fields.code, "code1");
    assert.equal(apple.calls[0].fields.grant_type, "authorization_code");
    assert.equal(apple.calls[0].fields.client_id, "site.wingspot.ios");
    assert.ok(apple.calls[0].fields.client_secret.split(".").length === 3);
  });

  test("a refused code gives nothing", async () => {
    assert.equal(await exchangeCode(config, "bad", fake(400, { error: "invalid_grant" }).impl), null);
    assert.equal(await exchangeCode(config, "odd", fake(200, {}).impl), null);
  });

  test("revoking sends the refresh token", async () => {
    const apple = fake(200);
    assert.equal(await revokeToken(config, "r1", apple.impl), true);
    assert.equal(apple.calls[0].url, "https://apple.test/auth/revoke");
    assert.equal(apple.calls[0].fields.token, "r1");
    assert.equal(apple.calls[0].fields.token_type_hint, "refresh_token");
    assert.equal(await revokeToken(config, "r1", fake(400).impl), false);
  });
});
