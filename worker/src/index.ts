import { OAuthProvider } from "@cloudflare/workers-oauth-provider";
import { isAllowedUid, requireUser } from "./auth";
import { connectCodeTtlSeconds, createConnectCode, formatConnectCode } from "./connect";
import type { Env } from "./env";
import {
  computeMatrix,
  computeRoute,
  maxMatrixPoints,
  parseMode,
  placeDetails,
  searchPlaces,
} from "./google";
import { getGuide, listGuides, parseCountryCode } from "./guides";
import {
  errorResponse,
  HttpError,
  json,
  optionalTime,
  readJson,
  requireLatLng,
  requireString,
} from "./http";
import { handleMcp } from "./mcp";
import { authorize, authorizeWithCode, authorizeWithGoogle, callback, type ConnectorProps } from "./oauth";
import { openPage } from "./open";
import { googleCached, matrixUnits } from "./usage";

/**
 * Agdayo's server. Two front doors:
 *
 * - The app calls /v1 with a Firebase ID token (auth.ts).
 * - Claude calls /mcp as a custom connector, with a token from signing in at
 *   /authorize (oauth.ts) as the person's own Agdayo account.
 *
 * Who may use either is ALLOWED_UIDS ("*" for everyone signed in). Google
 * calls count against a daily limit per account (usage.ts). The OAuth provider library serves /token, /register
 *   and the .well-known metadata.
 *
 *   GET  /health                   no sign-in; for uptime checks
 *   GET  /open/trip/:id?day=       no sign-in; opens the trip in the app (open.ts)
 *   POST /v1/route                 { origin, destination, mode?, departureTime?, arrivalTime? }
 *   POST /v1/matrix                { points: LatLng[] (2–10), mode? }
 *   POST /v1/places/search         { query, near?, radiusMeters?, limit? }
 *   GET  /v1/places/:id
 *   GET  /v1/guides
 *   GET  /v1/guides/:countryCode
 *   POST /v1/connect-code          a one-time code for connecting Claude (connect.ts)
 *   POST /mcp                      MCP JSON-RPC (see mcp.ts)
 */
export default {
  fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    return providerFor(new URL(request.url).origin).fetch(request, env, ctx);
  },
} satisfies ExportedHandler<Env>;

/**
 * The OAuth provider wants the connector's public address up front. It's
 * whatever address Claude was given (workers.dev or a custom domain), so build
 * one provider per origin rather than hard-coding it.
 */
const providers = new Map<string, OAuthProvider<Env>>();

function providerFor(origin: string): OAuthProvider<Env> {
  let provider = providers.get(origin);
  if (!provider) {
    provider = createProvider(origin);
    providers.set(origin, provider);
  }
  return provider;
}

function createProvider(origin: string): OAuthProvider<Env> {
  return new OAuthProvider<Env>({
    resourceMetadata: { resource: `${origin}/mcp`, resource_name: "Agdayo" },
    apiRoute: "/mcp",
    apiHandler: {
      async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
        const { uid } = (ctx as ExecutionContext & { props: ConnectorProps }).props;
        // Blocking a UID (or narrowing ALLOWED_UIDS) cuts Claude off too, without revoking tokens.
        if (!isAllowedUid(env, uid)) return json({ error: "This account isn't allowed to use this server." }, 403);
        try {
          return await handleMcp(request, env, uid);
        } catch (error) {
          return errorResponse(error);
        }
      },
    },
    defaultHandler: {
      async fetch(request: Request, env: Env): Promise<Response> {
        try {
          return await route(request, env);
        } catch (error) {
          return errorResponse(error);
        }
      },
    },
    authorizeEndpoint: "/authorize",
    tokenEndpoint: "/token",
    clientRegistrationEndpoint: "/register",
    scopesSupported: ["trips"],
  });
}

async function route(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const path = url.pathname.replace(/\/+$/, "") || "/";
  const method = request.method;

  if (path === "/health" && method === "GET") return json({ ok: true });
  if (path === "/authorize" && method === "GET") return authorize(request, env);
  if (path === "/authorize/code" && method === "POST") return authorizeWithCode(request, env);
  if (path === "/authorize/google" && method === "GET") return authorizeWithGoogle(request, env);
  if (path === "/callback" && method === "GET") return callback(request, env);
  if (path.startsWith("/open/trip/") && method === "GET") return openPage(url);
  if (!path.startsWith("/v1/")) throw new HttpError(404, "Not found.");

  const uid = await requireUser(request, env);

  if (path === "/v1/connect-code" && method === "POST") {
    const code = await createConnectCode(env, uid);
    return json({ code: formatConnectCode(code), expiresInSeconds: connectCodeTtlSeconds });
  }

  if (path === "/v1/route" && method === "POST") {
    const body = await readJson(request);
    const routeRequest = {
      origin: requireLatLng(body.origin, "origin"),
      destination: requireLatLng(body.destination, "destination"),
      mode: parseMode(body.mode),
      departureTime: optionalTime(body.departureTime, "departureTime"),
      arrivalTime: optionalTime(body.arrivalTime, "arrivalTime"),
    };
    const result = await googleCached(env, uid, 1, "route", routeRequest, 300, () => computeRoute(env, routeRequest));
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
    return json(await googleCached(env, uid, matrixUnits(points.length), "matrix", { points, mode }, 300, () => computeMatrix(env, points, mode)));
  }

  if (path === "/v1/places/search" && method === "POST") {
    const body = await readJson(request);
    const search = {
      query: requireString(body.query, "query"),
      near: body.near === undefined ? undefined : requireLatLng(body.near, "near"),
      radiusMeters: typeof body.radiusMeters === "number" ? body.radiusMeters : undefined,
      limit: typeof body.limit === "number" ? body.limit : undefined,
    };
    return json({ places: await googleCached(env, uid, 1, "places", search, 3600, () => searchPlaces(env, search)) });
  }

  const placeMatch = /^\/v1\/places\/([^/]+)$/.exec(path);
  if (placeMatch?.[1] && method === "GET") {
    const id = decodeURIComponent(placeMatch[1]);
    return json({ place: await googleCached(env, uid, 1, "place", id, 3600, () => placeDetails(env, id)) });
  }

  if (path === "/v1/guides" && method === "GET") {
    return json({ guides: await listGuides(env.DB) });
  }

  const guideMatch = /^\/v1\/guides\/([^/]+)$/.exec(path);
  if (guideMatch?.[1]) {
    const countryCode = parseCountryCode(guideMatch[1]);
    // Read-only while the guide is switched off; saved guides stay in D1.
    if (method === "GET") {
      const guide = await getGuide(env.DB, countryCode);
      if (!guide) throw new HttpError(404, `No guide for ${countryCode} yet.`);
      return json({ guide });
    }
  }

  throw new HttpError(404, "Not found.");
}
