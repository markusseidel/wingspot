import { configFromEnv, exchangeCode, revokeToken } from "./apple.ts";
import { authenticate, error, json, methodNotAllowed, notFound, serverError, serviceClient, subpath } from "../_shared/http.ts";

async function entitlements(request: Request): Promise<Response> {
  const auth = await authenticate(request);
  if (auth instanceof Response) return auth;

  // The database only returns the user's own rows.
  const { data, error } = await auth.db
    .from("entitlements")
    .select("entitlement, store, product_id, status, expires_at, auto_renew");
  if (error) return serverError(error);

  return json({ entitlements: data });
}

async function progress(request: Request): Promise<Response> {
  const auth = await authenticate(request);
  if (auth instanceof Response) return auth;

  // Also catches up on badges for check-ins that were uploaded before badges existed.
  const { data, error } = await auth.db.rpc("get_my_progress");
  if (error) return serverError(error);
  return json(data);
}

const PHOTO_BUCKET = "photos";

/** Every file path under a folder of the photo bucket, however deep. */
async function filesUnder(db: ReturnType<typeof serviceClient>, folder: string): Promise<string[]> {
  const found: string[] = [];
  for (let offset = 0;; offset += 100) {
    const { data, error } = await db.storage.from(PHOTO_BUCKET).list(folder, { limit: 100, offset });
    if (error) throw error;
    for (const entry of data) {
      // Folders have no id.
      if (entry.id) found.push(`${folder}/${entry.name}`);
      else found.push(...await filesUnder(db, `${folder}/${entry.name}`));
    }
    if (data.length < 100) return found;
  }
}

function appleConfig() {
  return configFromEnv((name) => Deno.env.get(name));
}

/** Revokes the Sign in with Apple token of this person, if the server has one. */
async function revokeApple(db: ReturnType<typeof serviceClient>, userId: string): Promise<void> {
  const config = appleConfig();
  const { data } = await db.from("apple_tokens").select("refresh_token").eq("user_id", userId).maybeSingle();
  if (!data) return;
  if (!config) {
    console.error("Apple token not revoked: the Sign in with Apple key is not set up");
    return;
  }
  try {
    if (!await revokeToken(config, data.refresh_token)) console.error("Apple refused to revoke the token");
  } catch {
    console.error("Revoking the Apple token failed");
  }
}

/** The phone sends the one-time code from Sign in with Apple. It is traded for a token that is kept for later. */
async function registerApple(request: Request): Promise<Response> {
  const auth = await authenticate(request);
  if (auth instanceof Response) return auth;
  let code: unknown;
  try {
    code = (await request.json()).code;
  } catch {
    return error(400, "invalid_request", "A code is required.");
  }
  if (typeof code !== "string" || code.length === 0 || code.length > 2000) return error(400, "invalid_request", "A code is required.");

  const config = appleConfig();
  // Without the key there is nothing to do. Signing in works either way.
  if (!config) return new Response(null, { status: 204 });
  try {
    const token = await exchangeCode(config, code);
    if (token) {
      const { error } = await serviceClient().from("apple_tokens")
        .upsert({ user_id: auth.user.id, refresh_token: token });
      if (error) throw error;
    }
  } catch (cause) {
    return serverError(cause);
  }
  return new Response(null, { status: 204 });
}

/**
 * Deletes the signed-in person's account for good: their photo files first, then the auth user, which the
 * database follows by removing the profile and everything that belongs to it. Safe to retry if it fails halfway.
 */
async function deleteAccount(request: Request): Promise<Response> {
  const auth = await authenticate(request);
  if (auth instanceof Response) return auth;

  const admin = serviceClient();
  try {
    // Apple wants the link to the Apple ID ended. A failure here is logged and doesn't keep the account alive.
    await revokeApple(admin, auth.user.id);
    // Lists the whole folder instead of trusting the database rows, so files that were never registered go too.
    const files = await filesUnder(admin, auth.user.id);
    for (let i = 0; i < files.length; i += 100) {
      const { error } = await admin.storage.from(PHOTO_BUCKET).remove(files.slice(i, i + 100));
      if (error) throw error;
    }
    const { error } = await admin.auth.admin.deleteUser(auth.user.id);
    if (error) throw error;
  } catch (cause) {
    return serverError(cause);
  }
  return new Response(null, { status: 204 });
}

Deno.serve((request) => {
  const path = subpath(request);
  if (path.length === 0) return request.method === "DELETE" ? deleteAccount(request) : methodNotAllowed();
  if (path.length === 1 && path[0] === "apple") return request.method === "POST" ? registerApple(request) : methodNotAllowed();
  if (path.length !== 1) return notFound();
  const handler = path[0] === "entitlements" ? entitlements : path[0] === "progress" ? progress : null;
  if (!handler) return notFound();
  if (request.method !== "GET") return methodNotAllowed();
  return handler(request);
});
