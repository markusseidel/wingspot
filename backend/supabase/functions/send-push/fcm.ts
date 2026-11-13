// Sending push notifications to Android phones through Firebase Cloud Messaging (the HTTP v1 API).
// Plain TypeScript with no Deno-only imports, so the API tests can load it with Node.

import { base64url, textBytes } from "./apns.ts";
import type { PushDevice, PushRow, SendResult } from "./apns.ts";
import { render } from "./apns.ts";

export interface FcmConfig {
  /** The service account's e-mail (`client_email` in its JSON key). */
  clientEmail: string;
  /** Its private key in PEM form (`private_key`). */
  privateKey: string;
  /** The Firebase project (`project_id`). */
  projectId: string;
  /** Where to send. Tests point these at a fake server. */
  tokenUrl?: string;
  sendUrl?: (projectId: string) => string;
}

/** Reads the service account JSON that is kept in the FCM_SERVICE_ACCOUNT secret. Null when it is missing or broken. */
export function fcmConfigFrom(secret: string | undefined | null): FcmConfig | null {
  if (!secret) return null;
  try {
    const parsed = JSON.parse(secret);
    if (!parsed.client_email || !parsed.private_key || !parsed.project_id) return null;
    return { clientEmail: parsed.client_email, privateKey: parsed.private_key, projectId: parsed.project_id };
  } catch {
    return null;
  }
}

const TOKEN_URL = "https://oauth2.googleapis.com/token";
const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
/** The channel the app creates for these notifications. */
export const ANDROID_CHANNEL = "wingspot_activity";

async function rsaKey(pem: string): Promise<CryptoKey> {
  const body = pem.replace(/\\n/g, "\n").replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
}

/** Trades a signed request for an access token that is good for an hour. Null if Google refuses. */
export async function accessToken(config: FcmConfig, nowSeconds: number, fetchImpl: typeof fetch = fetch): Promise<string | null> {
  const header = base64url(textBytes(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claims = base64url(textBytes(JSON.stringify({
    iss: config.clientEmail, scope: SCOPE, aud: config.tokenUrl ?? TOKEN_URL, iat: nowSeconds, exp: nowSeconds + 3300,
  })));
  const input = `${header}.${claims}`;
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", await rsaKey(config.privateKey), textBytes(input));
  const response = await fetchImpl(config.tokenUrl ?? TOKEN_URL, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${input}.${base64url(signature)}` }),
  });
  if (!response.ok) return null;
  const answer = await response.json();
  return typeof answer.access_token === "string" ? answer.access_token : null;
}

/** What the phone gets: the text to show, and just enough to open the right screen. */
export function fcmMessage(row: PushRow, device: PushDevice): Record<string, unknown> {
  const { title, body } = render(row, device.locale);
  return {
    message: {
      token: device.token,
      notification: { title, body },
      data: { type: row.kind, checkin: row.checkin_id ?? "", actor: row.actor_id },
      android: {
        priority: "high",
        // Several salutes on one check-in replace each other on the phone instead of piling up.
        collapse_key: row.kind === "salute" && row.checkin_id ? `salute-${row.checkin_id}` : undefined,
        notification: { channel_id: ANDROID_CHANNEL, tag: row.checkin_id ? `${row.kind}-${row.checkin_id}` : row.kind },
      },
    },
  };
}

/** FCM's answers that mean this token will never work again. */
const DEAD_STATUSES = new Set(["UNREGISTERED", "NOT_FOUND", "INVALID_ARGUMENT"]);

export async function sendFcm(
  config: FcmConfig, token: string, device: PushDevice, row: PushRow, fetchImpl: typeof fetch = fetch,
): Promise<SendResult> {
  const url = (config.sendUrl ?? ((id) => `https://fcm.googleapis.com/v1/projects/${id}/messages:send`))(config.projectId);
  try {
    const response = await fetchImpl(url, {
      method: "POST",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify(fcmMessage(row, device)),
    });
    if (response.ok) return { ok: true };
    let reason = "";
    try {
      const failure = (await response.json()).error ?? {};
      reason = String(failure.status ?? "");
      // INVALID_ARGUMENT can also mean a bad payload, so only a token complaint counts as dead.
      const about = JSON.stringify(failure.details ?? failure.message ?? "");
      if (reason === "INVALID_ARGUMENT" && !/registration token|token/i.test(about)) reason = "INVALID_PAYLOAD";
    } catch { /* an empty or odd body */ }
    return { ok: false, dead: response.status === 404 || DEAD_STATUSES.has(reason), status: response.status, reason };
  } catch (cause) {
    return { ok: false, dead: false, status: 0, reason: cause instanceof Error ? cause.name : "network" };
  }
}
