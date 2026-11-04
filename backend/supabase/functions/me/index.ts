import { authenticate, json, methodNotAllowed, notFound, serverError, subpath } from "../_shared/http.ts";

Deno.serve(async (request) => {
  const path = subpath(request);
  if (path.length !== 1 || path[0] !== "entitlements") return notFound();
  if (request.method !== "GET") return methodNotAllowed();

  const auth = await authenticate(request);
  if (auth instanceof Response) return auth;

  // The database only returns the user's own rows.
  const { data, error } = await auth.db
    .from("entitlements")
    .select("entitlement, store, product_id, status, expires_at, auto_renew");
  if (error) return serverError(error);

  return json({ entitlements: data });
});
