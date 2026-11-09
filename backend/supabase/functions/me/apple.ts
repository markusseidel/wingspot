// Sign in with Apple, server side: when someone signs in with Apple, the one-time code from the phone is traded for a
// refresh token that is kept privately. When the account is deleted, that token is revoked at Apple, which Apple
// requires. Plain TypeScript with no Deno-only imports, so the API tests can load it with Node.
import { base64url, signingKey, textBytes } from "../send-push/apns.ts";

export interface AppleConfig {
  /** The contents of the `.p8` key file made for Sign in with Apple. */
  key: string;
  keyId: string;
  teamId: string;
  /** The app's bundle ID, which is the client ID for sign-in from the app. */
  clientId: string;
  /** Tests point this at a fake server. */
  host?: string;
}

const HOST = "https://appleid.apple.com";

/** The settings from the function's secrets, or null while the key hasn't been set up. */
export function configFromEnv(get: (name: string) => string | undefined): AppleConfig | null {
  const key = get("APPLE_SIWA_KEY");
  const keyId = get("APPLE_SIWA_KEY_ID");
  const teamId = get("APPLE_TEAM_ID") ?? get("APNS_TEAM_ID");
  if (!key || !keyId || !teamId) return null;
  return { key, keyId, teamId, clientId: get("APPLE_CLIENT_ID") ?? "site.wingspot.ios" };
}

/** The "password" for Apple's token endpoints: a short-lived token signed with the key. */
export async function clientSecret(config: AppleConfig, nowSeconds: number): Promise<string> {
  const header = base64url(textBytes(JSON.stringify({ alg: "ES256", kid: config.keyId })));
  const claims = base64url(textBytes(JSON.stringify({
    iss: config.teamId, iat: nowSeconds, exp: nowSeconds + 300, aud: HOST, sub: config.clientId,
  })));
  const input = `${header}.${claims}`;
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, await signingKey(config.key), textBytes(input),
  );
  return `${input}.${base64url(signature)}`;
}

async function post(
  config: AppleConfig, path: string, fields: Record<string, string>, fetchImpl: typeof fetch,
): Promise<Response> {
  const body = new URLSearchParams({
    client_id: config.clientId, client_secret: await clientSecret(config, Math.floor(Date.now() / 1000)), ...fields,
  });
  return await fetchImpl(`${config.host ?? HOST}${path}`, {
    method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body,
  });
}

/** Trades the one-time code for a refresh token. Null if Apple refuses. The code and token are never logged. */
export async function exchangeCode(config: AppleConfig, code: string, fetchImpl: typeof fetch = fetch): Promise<string | null> {
  const response = await post(config, "/auth/token", { code, grant_type: "authorization_code" }, fetchImpl);
  if (!response.ok) return null;
  try {
    const token = (await response.json()).refresh_token;
    return typeof token === "string" && token ? token : null;
  } catch {
    return null;
  }
}

/** Ends the link between the person's Apple ID and the app. True if Apple accepted it. */
export async function revokeToken(config: AppleConfig, refreshToken: string, fetchImpl: typeof fetch = fetch): Promise<boolean> {
  const response = await post(config, "/auth/revoke", { token: refreshToken, token_type_hint: "refresh_token" }, fetchImpl);
  return response.ok;
}
