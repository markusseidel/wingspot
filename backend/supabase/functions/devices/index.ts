import { authenticate, error, json, methodNotAllowed, notFound, serverError, subpath } from "../_shared/http.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_TEXT_LENGTH = 4096;

const invalid = (message: string) => error(400, "invalid_request", message);

function isOptionalText(value: unknown): value is string | null | undefined {
  return value === undefined || value === null ||
    (typeof value === "string" && value.length > 0 && value.length <= MAX_TEXT_LENGTH);
}

/** Returns a description of the first problem, or null if the registration is valid. */
function validate(body: Record<string, unknown>): string | null {
  if (typeof body.id !== "string" || !UUID.test(body.id)) return "id must be a UUID.";
  if (body.platform !== "ios" && body.platform !== "android") return "platform must be ios or android.";
  if (typeof body.app_version !== "string" || !body.app_version || body.app_version.length > 100) {
    return "app_version is required.";
  }
  for (const field of ["push_token", "os_version", "locale"]) {
    if (!isOptionalText(body[field])) return `${field} must be a non-empty string or null.`;
  }
  const pushEnv = body.push_env ?? null;
  if (pushEnv !== null && pushEnv !== "sandbox" && pushEnv !== "production") {
    return "push_env must be sandbox, production or null.";
  }
  if (body.platform === "android" && pushEnv !== null) return "push_env must be null on Android.";
  return null;
}

async function register(request: Request): Promise<Response> {
  const auth = await authenticate(request);
  if (auth instanceof Response) return auth;

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return invalid("The request body must be JSON.");
  }
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return invalid("The request body must be an object.");
  }
  const device = body as Record<string, unknown>;
  const problem = validate(device);
  if (problem) return invalid(problem);

  const { data, error: failure } = await auth.db.rpc("register_device", {
    device_id: device.id,
    device_platform: device.platform,
    device_app_version: device.app_version,
    device_push_token: device.push_token ?? null,
    device_push_env: device.push_env ?? null,
    device_os_version: device.os_version ?? null,
    device_locale: device.locale ?? null,
  });
  if (failure) return serverError(failure);

  return json({
    id: data.id,
    platform: data.platform,
    push_token: data.push_token,
    push_env: data.push_env,
    app_version: data.app_version,
    os_version: data.os_version,
    locale: data.locale,
    last_seen_at: data.last_seen_at,
  });
}

async function unregister(request: Request, id: string): Promise<Response> {
  const auth = await authenticate(request);
  if (auth instanceof Response) return auth;
  if (!UUID.test(id)) return invalid("id must be a UUID.");

  // The database only lets users delete their own devices.
  const { error: failure } = await auth.db.from("devices").delete().eq("id", id);
  if (failure) return serverError(failure);
  return new Response(null, { status: 204 });
}

Deno.serve((request) => {
  const path = subpath(request);
  if (path.length === 0) {
    return request.method === "POST" ? register(request) : methodNotAllowed();
  }
  if (path.length === 1) {
    return request.method === "DELETE" ? unregister(request, path[0]) : methodNotAllowed();
  }
  return notFound();
});
