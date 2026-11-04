import { error, json, methodNotAllowed, notFound, publicClient, serverError, subpath } from "../_shared/http.ts";

Deno.serve(async (request) => {
  const path = subpath(request);
  if (path.length !== 1 || path[0] !== "manifest") return notFound();
  if (request.method !== "GET") return methodNotAllowed();

  const { data, error: failure } = await publicClient()
    .from("refdata_snapshots")
    .select("schema_version, data_version, url, sha256, size_bytes")
    .order("id", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (failure) return serverError(failure);
  if (!data) return error(404, "no_snapshot", "No snapshot has been published yet.");

  return json(data);
});
