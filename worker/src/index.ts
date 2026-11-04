import { requireUser } from "./auth";
import type { Env } from "./env";
import {
  computeMatrix,
  computeRoute,
  maxMatrixPoints,
  parseMode,
  placeDetails,
  searchPlaces,
} from "./google";
import { getGuide, listGuides, parseCountryCode, parseGuide, putGuide } from "./guides";
import {
  cached,
  errorResponse,
  HttpError,
  json,
  optionalTime,
  readJson,
  requireLatLng,
  requireString,
} from "./http";

/**
 * Agdayo's server. Every /v1 route needs a Firebase ID token from an allowed
 * account (see auth.ts). Routes:
 *
 *   GET  /health                   no sign-in; for uptime checks
 *   POST /v1/route                 { origin, destination, mode?, departureTime?, arrivalTime? }
 *   POST /v1/matrix                { points: LatLng[] (2–10), mode? }
 *   POST /v1/places/search         { query, near?, radiusMeters?, limit? }
 *   GET  /v1/places/:id
 *   GET  /v1/guides
 *   GET  /v1/guides/:countryCode
 *   PUT  /v1/guides/:countryCode   Guide body (see guides.ts)
 */
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      return await route(request, env);
    } catch (error) {
      return errorResponse(error);
    }
  },
} satisfies ExportedHandler<Env>;

async function route(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const path = url.pathname.replace(/\/+$/, "") || "/";
  const method = request.method;

  if (path === "/health" && method === "GET") return json({ ok: true });
  if (!path.startsWith("/v1/")) throw new HttpError(404, "Not found.");

  await requireUser(request, env);

  if (path === "/v1/route" && method === "POST") {
    const body = await readJson(request);
    const routeRequest = {
      origin: requireLatLng(body.origin, "origin"),
      destination: requireLatLng(body.destination, "destination"),
      mode: parseMode(body.mode),
      departureTime: optionalTime(body.departureTime, "departureTime"),
      arrivalTime: optionalTime(body.arrivalTime, "arrivalTime"),
    };
    const result = await cached("route", routeRequest, 300, () => computeRoute(env, routeRequest));
    // No route is a normal answer (e.g. no transit data in that city), not an error.
    return json({ route: result });
  }

  if (path === "/v1/matrix" && method === "POST") {
    const body = await readJson(request);
    if (!Array.isArray(body.points) || body.points.length < 2 || body.points.length > maxMatrixPoints) {
      throw new HttpError(400, `points must list 2 to ${maxMatrixPoints} places.`);
    }
    const points = body.points.map((point, index) => requireLatLng(point, `points[${index}]`));
    const mode = parseMode(body.mode);
    return json(await cached("matrix", { points, mode }, 300, () => computeMatrix(env, points, mode)));
  }

  if (path === "/v1/places/search" && method === "POST") {
    const body = await readJson(request);
    const search = {
      query: requireString(body.query, "query"),
      near: body.near === undefined ? undefined : requireLatLng(body.near, "near"),
      radiusMeters: typeof body.radiusMeters === "number" ? body.radiusMeters : undefined,
      limit: typeof body.limit === "number" ? body.limit : undefined,
    };
    return json({ places: await cached("places", search, 3600, () => searchPlaces(env, search)) });
  }

  const placeMatch = /^\/v1\/places\/([^/]+)$/.exec(path);
  if (placeMatch?.[1] && method === "GET") {
    const id = decodeURIComponent(placeMatch[1]);
    return json({ place: await cached("place", id, 3600, () => placeDetails(env, id)) });
  }

  if (path === "/v1/guides" && method === "GET") {
    return json({ guides: await listGuides(env.DB) });
  }

  const guideMatch = /^\/v1\/guides\/([^/]+)$/.exec(path);
  if (guideMatch?.[1]) {
    const countryCode = parseCountryCode(guideMatch[1]);
    if (method === "GET") {
      const guide = await getGuide(env.DB, countryCode);
      if (!guide) throw new HttpError(404, `No guide for ${countryCode} yet.`);
      return json({ guide });
    }
    if (method === "PUT") {
      const guide = parseGuide(countryCode, await readJson(request));
      await putGuide(env.DB, guide);
      return json({ guide });
    }
  }

  throw new HttpError(404, "Not found.");
}
