import { createClient, type SupabaseClient, type User } from "npm:@supabase/supabase-js@2.49.4";

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/** Responds in the Error format from contracts/openapi.yaml. */
export function error(status: number, code: string, message: string): Response {
  return json({ code, message }, status);
}

export const methodNotAllowed = () => error(405, "method_not_allowed", "Method not allowed.");
export const notFound = () => error(404, "not_found", "Not found.");

/** Logs the cause and hides it from the client. */
export function serverError(cause: unknown): Response {
  console.error(cause);
  return error(500, "internal_error", "The request could not be processed.");
}

/** Path segments after the function name: `/devices/abc` gives `["abc"]`. */
export function subpath(request: Request): string[] {
  return new URL(request.url).pathname.split("/").filter(Boolean).slice(1);
}

/** Supabase lists publishable keys by name. The legacy anon key covers environments without them. */
function apiKey(): string {
  const keys = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
  return keys ? JSON.parse(keys).default : Deno.env.get("SUPABASE_ANON_KEY")!;
}

function client(authorization?: string): SupabaseClient {
  return createClient(Deno.env.get("SUPABASE_URL")!, apiKey(), {
    auth: { persistSession: false, autoRefreshToken: false },
    global: authorization ? { headers: { Authorization: authorization } } : undefined,
  });
}

/** A client without a user, limited to what the database allows anonymous visitors. */
export const publicClient = () => client();

/**
 * A client with full access, for the few things a user can't do as themselves, such as deleting their own
 * account. Only use it after `authenticate`, and only for the person that call returned.
 */
export const serviceClient = () =>
  createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

export interface Authenticated {
  /** Acts as the user, so the database's access rules apply. */
  db: SupabaseClient;
  user: User;
}

/** Validates the access token. Returns an error response if there is no valid user. */
export async function authenticate(request: Request): Promise<Authenticated | Response> {
  const authorization = request.headers.get("Authorization");
  const token = authorization?.match(/^Bearer (.+)$/)?.[1];
  const unauthorized = error(401, "unauthorized", "A valid access token is required.");
  if (!token) return unauthorized;

  const db = client(authorization!);
  const { data, error: failure } = await db.auth.getUser(token);
  if (failure || !data.user) return unauthorized;
  return { db, user: data.user };
}
