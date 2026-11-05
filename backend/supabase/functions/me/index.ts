import { authenticate, json, methodNotAllowed, notFound, serverError, subpath } from "../_shared/http.ts";

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

Deno.serve((request) => {
  const path = subpath(request);
  if (path.length !== 1) return notFound();
  const handler = path[0] === "entitlements" ? entitlements : path[0] === "progress" ? progress : null;
  if (!handler) return notFound();
  if (request.method !== "GET") return methodNotAllowed();
  return handler(request);
});
