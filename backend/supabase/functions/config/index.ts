import { json, methodNotAllowed, notFound, publicClient, serverError, subpath } from "../_shared/http.ts";

Deno.serve(async (request) => {
  if (subpath(request).length > 0) return notFound();
  if (request.method !== "GET") return methodNotAllowed();

  const { data, error } = await publicClient()
    .from("app_config")
    .select("min_version_ios, min_version_android, feature_flags")
    .single();
  if (error) return serverError(error);

  return json({
    min_version: { ios: data.min_version_ios, android: data.min_version_android },
    feature_flags: data.feature_flags,
  });
});
