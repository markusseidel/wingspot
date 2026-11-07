import { authenticate, json, methodNotAllowed, notFound, serverError, serviceClient, subpath } from "../_shared/http.ts";

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

/**
 * Deletes the signed-in person's account for good: their photo files first, then the auth user, which the
 * database follows by removing the profile and everything that belongs to it. Safe to retry if it fails halfway.
 */
async function deleteAccount(request: Request): Promise<Response> {
  const auth = await authenticate(request);
  if (auth instanceof Response) return auth;

  const admin = serviceClient();
  try {
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
  if (path.length !== 1) return notFound();
  const handler = path[0] === "entitlements" ? entitlements : path[0] === "progress" ? progress : null;
  if (!handler) return notFound();
  if (request.method !== "GET") return methodNotAllowed();
  return handler(request);
});
