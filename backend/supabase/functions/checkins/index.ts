import { authenticate, error, json, methodNotAllowed, notFound, serverError, subpath } from "../_shared/http.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_ITEMS = 50;

const invalid = (message: string) => error(400, "invalid_request", message);

/** Every item needs an id, because the response reports one result per id. The database checks the rest. */
function shapeProblem(items: unknown): string | null {
  if (!Array.isArray(items)) return "checkins must be an array.";
  if (items.length === 0) return "checkins must not be empty.";
  if (items.length > MAX_ITEMS) return `At most ${MAX_ITEMS} check-ins per request.`;
  const seen = new Set<string>();
  for (const item of items) {
    if (typeof item !== "object" || item === null || Array.isArray(item)) return "Each check-in must be an object.";
    const id = (item as Record<string, unknown>).id;
    if (typeof id !== "string" || !UUID.test(id)) return "Each check-in needs an id that is a UUID.";
    if (seen.has(id.toLowerCase())) return "Check-in ids must be unique within a request.";
    seen.add(id.toLowerCase());
  }
  return null;
}

async function upload(request: Request): Promise<Response> {
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
  const items = (body as Record<string, unknown>).checkins;
  const problem = shapeProblem(items);
  if (problem) return invalid(problem);

  // One call stores the whole batch. The database stores each item on its own and repeats are harmless.
  const { data, error: failure } = await auth.db.rpc("sync_checkins", { items });
  if (failure) return serverError(failure);
  return json(data);
}

Deno.serve((request) => {
  const path = subpath(request);
  if (path.length !== 0) return notFound();
  return request.method === "POST" ? upload(request) : methodNotAllowed();
});
