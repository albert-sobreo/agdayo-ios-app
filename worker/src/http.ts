/** An error with an HTTP status, turned into a JSON response by the router. */
export class HttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

export function json(body: unknown, status = 200, headers: HeadersInit = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...headers },
  });
}

export function errorResponse(error: unknown): Response {
  if (error instanceof HttpError) {
    return json({ error: error.message }, error.status);
  }
  console.error(error);
  return json({ error: "Something went wrong on the server." }, 500);
}

export async function readJson(request: Request): Promise<Record<string, unknown>> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    throw new HttpError(400, "Body must be JSON.");
  }
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    throw new HttpError(400, "Body must be a JSON object.");
  }
  return body as Record<string, unknown>;
}

export interface LatLng {
  latitude: number;
  longitude: number;
}

export function requireLatLng(value: unknown, field: string): LatLng {
  if (typeof value === "object" && value !== null) {
    const { latitude, longitude } = value as Record<string, unknown>;
    if (
      typeof latitude === "number" &&
      typeof longitude === "number" &&
      Math.abs(latitude) <= 90 &&
      Math.abs(longitude) <= 180
    ) {
      return { latitude, longitude };
    }
  }
  throw new HttpError(400, `${field} must be { latitude, longitude } in degrees.`);
}

export function optionalString(value: unknown, field: string): string | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "string") throw new HttpError(400, `${field} must be a string.`);
  return value;
}

export function requireString(value: unknown, field: string): string {
  const result = optionalString(value, field);
  if (!result || !result.trim()) throw new HttpError(400, `${field} is required.`);
  return result.trim();
}

/** An ISO 8601 timestamp, or undefined. Rejects anything Date can't parse. */
export function optionalTime(value: unknown, field: string): string | undefined {
  const text = optionalString(value, field);
  if (text === undefined) return undefined;
  const time = Date.parse(text);
  if (Number.isNaN(time)) throw new HttpError(400, `${field} must be an ISO 8601 time.`);
  return new Date(time).toISOString();
}

/**
 * Runs `load` once per `ttlSeconds` for the same key, using the Workers cache.
 * Keeps repeated lookups (the same route on every screen refresh) inside the
 * free allowances. Results that are null are not cached.
 */
export async function cached<T>(namespace: string, key: unknown, ttlSeconds: number, load: () => Promise<T>): Promise<T> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(JSON.stringify(key)));
  const hash = [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
  const cacheKey = new Request(`https://cache.agdayo.internal/${namespace}/${hash}`);
  const cache = caches.default;
  const hit = await cache.match(cacheKey);
  if (hit) return (await hit.json()) as T;
  const value = await load();
  if (value !== null && value !== undefined) {
    await cache.put(cacheKey, json(value, 200, { "cache-control": `max-age=${ttlSeconds}` }));
  }
  return value;
}
