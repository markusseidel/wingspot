import { error, json, methodNotAllowed, serverError, serviceClient } from "../_shared/http.ts";
import { type ApnsConfig, type AndroidSender, deliver, type PushRow } from "./apns.ts";
import { accessToken, fcmConfigFrom, sendFcm } from "./fcm.ts";

/** Compares without stopping at the first difference. */
function sameSecret(a: string, b: string): boolean {
  const left = new TextEncoder().encode(a);
  const right = new TextEncoder().encode(b);
  let difference = left.length ^ right.length;
  for (let i = 0; i < Math.max(left.length, right.length); i++) difference |= (left[i] ?? 0) ^ (right[i] ?? 0);
  return difference === 0;
}

function config(): ApnsConfig | null {
  const key = Deno.env.get("APNS_KEY");
  const keyId = Deno.env.get("APNS_KEY_ID");
  const teamId = Deno.env.get("APNS_TEAM_ID");
  if (!key || !keyId || !teamId) return null;
  return { key, keyId, teamId, topic: Deno.env.get("APNS_TOPIC") ?? "site.wingspot.ios" };
}

/**
 * Called by the database when a notification is added (and every minute for leftovers), never by the app. It
 * knows the caller by a shared secret in the x-push-secret header. Without Apple's key and Firebase's service account it
 * does nothing and leaves the rows waiting.
 */
Deno.serve(async (request) => {
  if (request.method !== "POST") return methodNotAllowed();
  const expected = Deno.env.get("PUSH_SECRET");
  const given = request.headers.get("x-push-secret");
  if (!expected || !given || !sameSecret(given, expected)) {
    return error(401, "unauthorized", "A valid secret is required.");
  }
  const apns = config();
  const fcm = fcmConfigFrom(Deno.env.get("FCM_SERVICE_ACCOUNT"));
  if (!apns && !fcm) return json({ status: "not_configured" });
  const android: AndroidSender | null = fcm
    ? { token: (now, f) => accessToken(fcm, now, f), send: (token, device, row, f) => sendFcm(fcm, token, device, row, f) }
    : null;

  const db = serviceClient();
  const { data, error: failure } = await db.rpc("claim_notifications", { batch_size: 50 });
  if (failure) return serverError(failure);
  const rows = (data ?? []) as PushRow[];

  const outcomes = await deliver(rows, apns, Math.floor(Date.now() / 1000), fetch, android);
  for (const outcome of outcomes) {
    const { error: finishFailure } = await db.rpc("finish_notification", {
      notification: outcome.id, delivered: outcome.delivered, dead_devices: outcome.dead,
    });
    if (finishFailure) console.error("finish_notification failed", finishFailure.message);
  }
  return json({ status: "ok", claimed: rows.length, delivered: outcomes.filter((o) => o.delivered).length });
});
