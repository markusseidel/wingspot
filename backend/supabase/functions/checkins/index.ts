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

const MAX_PHOTO_BYTES = 3 * 1024 * 1024;
const MAX_PHOTOS_PER_CHECKIN = 4;

/**
 * Looks through the JPEG's segments. Returns its size, or a reason to refuse it. The phone removes all
 * metadata before upload, so EXIF, XMP and other segments that can carry a location are refused. A colour profile is fine.
 */
function inspectJpeg(bytes: Uint8Array): { width: number; height: number } | string {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) return "not_jpeg";
  let i = 2;
  while (i + 4 <= bytes.length) {
    if (bytes[i] !== 0xff) return "not_jpeg";
    const marker = bytes[i + 1];
    if (marker === 0xff) { i++; continue; }
    // JFIF (E0), the colour profile (E2) and Adobe's colour flag (EE) carry no location. EXIF and XMP (E1),
    // IPTC and the rest of the application segments, and comments do, or could.
    if (marker >= 0xe1 && marker <= 0xef && marker !== 0xe2 && marker !== 0xee) return "has_metadata";
    if (marker === 0xfe) return "has_metadata";
    const length = (bytes[i + 2] << 8) | bytes[i + 3];
    if ((marker >= 0xc0 && marker <= 0xcf) && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc) {
      if (i + 9 > bytes.length) return "not_jpeg";
      return { height: (bytes[i + 5] << 8) | bytes[i + 6], width: (bytes[i + 7] << 8) | bytes[i + 8] };
    }
    if (marker === 0xda) return "not_jpeg";
    i += 2 + length;
  }
  return "not_jpeg";
}

/** PUT /v1/checkins/{checkin_id}/photos/{photo_id}: the body is the JPEG. Repeating it is harmless. */
async function putPhoto(request: Request, checkinId: string, photoId: string): Promise<Response> {
  if (!UUID.test(checkinId) || !UUID.test(photoId)) return invalid("The ids must be UUIDs.");
  const auth = await authenticate(request);
  if (auth instanceof Response) return auth;

  if (request.headers.get("Content-Type")?.split(";")[0].trim() !== "image/jpeg") {
    return error(415, "unsupported_media_type", "The photo must be a JPEG.");
  }
  const declared = Number(request.headers.get("Content-Length") ?? 0);
  if (declared > MAX_PHOTO_BYTES) return error(413, "photo_too_large", "The photo is larger than 3 MB.");
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.length === 0) return invalid("The request body must be the photo.");
  if (bytes.length > MAX_PHOTO_BYTES) return error(413, "photo_too_large", "The photo is larger than 3 MB.");

  const jpeg = inspectJpeg(bytes);
  if (jpeg === "not_jpeg") return error(415, "unsupported_media_type", "The photo must be a JPEG.");
  if (jpeg === "has_metadata") {
    return invalid("The photo must have its metadata removed before upload, including any location.");
  }

  // Check ownership and the limit before storing anything, so a refused photo leaves no file behind.
  const path = `${auth.user.id}/${checkinId.toLowerCase()}/${photoId.toLowerCase()}.jpg`;
  const { data: owned, error: ownedFailure } = await auth.db
    .from("checkins").select("id").eq("id", checkinId.toLowerCase()).maybeSingle();
  if (ownedFailure) return serverError(ownedFailure);
  if (!owned) return error(404, "unknown_checkin", "That check-in has not been uploaded yet.");
  const { data: existing, error: countFailure } = await auth.db
    .from("checkin_photos").select("id").eq("checkin_id", checkinId.toLowerCase());
  if (countFailure) return serverError(countFailure);
  const known = (existing ?? []).some((row: { id: string }) => row.id === photoId.toLowerCase());
  if (!known && (existing ?? []).length >= MAX_PHOTOS_PER_CHECKIN) {
    return error(409, "too_many_photos", `A check-in can have at most ${MAX_PHOTOS_PER_CHECKIN} photos.`);
  }

  const { error: storeFailure } = await auth.db.storage
    .from("photos").upload(path, bytes, { contentType: "image/jpeg", upsert: true });
  if (storeFailure) return serverError(storeFailure);

  const { data: status, error: registerFailure } = await auth.db.rpc("register_photo", {
    photo_id: photoId.toLowerCase(), checkin: checkinId.toLowerCase(),
    photo_width: jpeg.width, photo_height: jpeg.height,
  });
  if (registerFailure) return serverError(registerFailure);
  if (status === "stored") return json({ id: photoId.toLowerCase(), status: "stored" });
  if (status === "id_taken") return error(409, "id_taken", "That photo id belongs to another check-in.");
  if (status === "too_many_photos") {
    return error(409, "too_many_photos", `A check-in can have at most ${MAX_PHOTOS_PER_CHECKIN} photos.`);
  }
  if (status === "unknown_checkin") return error(404, "unknown_checkin", "That check-in has not been uploaded yet.");
  return serverError(`register_photo said ${status}`);
}

Deno.serve((request) => {
  const path = subpath(request);
  if (path.length === 0) return request.method === "POST" ? upload(request) : methodNotAllowed();
  if (path.length === 3 && path[1] === "photos") {
    return request.method === "PUT" ? putPhoto(request, path[0], path[2]) : methodNotAllowed();
  }
  return notFound();
});
