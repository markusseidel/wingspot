// Writing and sending push notifications through Apple's push service (APNs).
// Plain TypeScript with no Deno-only imports, so the API tests can load it with Node.

export interface PushDevice {
  id: string;
  token: string;
  env: "sandbox" | "production";
  locale: string | null;
}

/** One row from `claim_notifications`. */
export interface PushRow {
  id: string;
  kind: "follow" | "salute" | "comment";
  actor_id: string;
  actor_username: string;
  actor_name: string | null;
  checkin_id: string | null;
  subject: string | null;
  snippet: string | null;
  devices: PushDevice[];
}

export interface ApnsConfig {
  /** The contents of the `.p8` key file. */
  key: string;
  keyId: string;
  teamId: string;
  /** The app's bundle ID. */
  topic: string;
  /** Where to send, per environment. Tests point this at a fake server. */
  host?: (env: "sandbox" | "production") => string;
}

export interface Rendered {
  title: string;
  body: string;
}

/** German for people whose phone is set to German, English for everyone else. */
export function render(row: PushRow, locale: string | null): Rendered {
  const german = (locale ?? "").toLowerCase().startsWith("de");
  const name = row.actor_name?.trim() || row.actor_username;
  switch (row.kind) {
    case "follow":
      return { title: name, body: german ? "folgt dir jetzt." : "started following you." };
    case "salute": {
      const about = row.subject ? ` (${row.subject})` : "";
      return { title: name, body: german ? `hat deinen Check-in salutiert${about}.` : `saluted your check-in${about}.` };
    }
    case "comment": {
      const text = (row.snippet ?? "").replace(/\s+/g, " ").trim();
      return { title: name, body: german ? `hat kommentiert: „${text}“` : `commented: “${text}”` };
    }
  }
}

/** The app registers a notification category with this name. It holds the text the phone shows instead of the real
 * one while previews are hidden (iPhone Settings > Notifications > Wingspot > Show Previews). */
export const CATEGORY = "WINGSPOT_ACTIVITY";

/** What the phone gets: the text and just enough to open the right screen. */
export function payload(row: PushRow, locale: string | null): Record<string, unknown> {
  const { title, body } = render(row, locale);
  return {
    aps: {
      alert: { title, body },
      sound: "default",
      category: CATEGORY,
      "thread-id": row.checkin_id ? `${row.kind}-${row.checkin_id}` : row.kind,
    },
    type: row.kind,
    checkin: row.checkin_id,
    actor: row.actor_id,
  };
}

const base64url = (bytes: ArrayBuffer | Uint8Array): string => {
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let text = "";
  for (const byte of view) text += String.fromCharCode(byte);
  return btoa(text).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

const textBytes = (text: string) => new TextEncoder().encode(text);

async function signingKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/\\n/g, "\n")
    .replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
}

/**
 * The token that says the server may send. Apple wants a new one no more often than every 20 minutes and refuses
 * one older than an hour, so the time is rounded down to 20 minutes: every call in that window asks for the same iat.
 */
export async function providerToken(config: ApnsConfig, nowSeconds: number): Promise<string> {
  const iat = Math.floor(nowSeconds / 1200) * 1200;
  const header = base64url(textBytes(JSON.stringify({ alg: "ES256", kid: config.keyId })));
  const claims = base64url(textBytes(JSON.stringify({ iss: config.teamId, iat })));
  const input = `${header}.${claims}`;
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, await signingKey(config.key), textBytes(input),
  );
  return `${input}.${base64url(signature)}`;
}

const HOSTS = { sandbox: "https://api.sandbox.push.apple.com", production: "https://api.push.apple.com" };
/** Apple's answers that mean this token will never work again. */
const DEAD_REASONS = new Set(["BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic"]);

export type SendResult = { ok: true } | { ok: false; dead: boolean; status: number; reason: string };

export async function sendToDevice(
  config: ApnsConfig, token: string, device: PushDevice, row: PushRow,
  fetchImpl: typeof fetch = fetch,
): Promise<SendResult> {
  const host = (config.host ?? ((env) => HOSTS[env]))(device.env);
  const headers: Record<string, string> = {
    authorization: `bearer ${token}`,
    "apns-topic": config.topic,
    "apns-push-type": "alert",
    "apns-priority": "10",
    "content-type": "application/json",
  };
  // Several salutes on one check-in replace each other on the phone instead of piling up.
  if (row.kind === "salute" && row.checkin_id) headers["apns-collapse-id"] = `salute-${row.checkin_id}`;
  try {
    const response = await fetchImpl(`${host}/3/device/${device.token}`, {
      method: "POST", headers, body: JSON.stringify(payload(row, device.locale)),
    });
    if (response.ok) return { ok: true };
    let reason = "";
    try {
      reason = String((await response.json()).reason ?? "");
    } catch { /* an empty or odd body */ }
    return { ok: false, dead: response.status === 410 || (response.status === 400 && DEAD_REASONS.has(reason)), status: response.status, reason };
  } catch (cause) {
    return { ok: false, dead: false, status: 0, reason: cause instanceof Error ? cause.name : "network" };
  }
}

export interface Outcome {
  id: string;
  /** False puts the row back for another try. */
  delivered: boolean;
  dead: string[];
}

/**
 * Sends every claimed row to each of its devices. A row counts as delivered if at least one device got it, or if
 * there is nothing left to send to (no devices, or only dead ones). It goes back only when every send failed for
 * a reason that may pass, such as Apple being unreachable.
 */
export async function deliver(
  rows: PushRow[], config: ApnsConfig, nowSeconds: number, fetchImpl: typeof fetch = fetch,
): Promise<Outcome[]> {
  const token = rows.some((row) => row.devices.length > 0) ? await providerToken(config, nowSeconds) : "";
  const outcomes: Outcome[] = [];
  for (const row of rows) {
    const dead: string[] = [];
    let sent = 0;
    let retryable = 0;
    for (const device of row.devices) {
      const result = await sendToDevice(config, token, device, row, fetchImpl);
      if (result.ok) sent++;
      else if (result.dead) dead.push(device.id);
      else {
        retryable++;
        // Only the status and Apple's reason, never the token or the text.
        console.error(`push not sent: status ${result.status} ${result.reason}`);
      }
    }
    outcomes.push({ id: row.id, delivered: sent > 0 || retryable === 0, dead });
  }
  return outcomes;
}
