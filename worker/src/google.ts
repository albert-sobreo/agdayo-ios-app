import type { Env } from "./env";
import { HttpError, type LatLng } from "./http";

// ---------------------------------------------------------------------------
// Shapes Agdayo and Claude see. Google's responses are reduced to these so the
// app and the MCP tools share one format that doesn't change with Google's.
// ---------------------------------------------------------------------------

export type TravelMode = "transit" | "walk" | "drive" | "bicycle";

export interface TransitLeg {
  lineName: string;
  lineShortName?: string;
  /** e.g. "Subway", "Bus", "Tram". */
  vehicle: string;
  /** Line colour as "#RRGGBB", when the operator publishes one. */
  color?: string;
  textColor?: string;
  headsign?: string;
  departureStop: string;
  arrivalStop: string;
  departureTime?: string;
  arrivalTime?: string;
  stopCount?: number;
}

export interface RouteStep {
  kind: TravelMode;
  durationSeconds: number;
  distanceMeters: number;
  instruction?: string;
  transit?: TransitLeg;
}

export interface RouteResult {
  mode: TravelMode;
  durationSeconds: number;
  distanceMeters: number;
  fare?: { currency: string; amount: number; text?: string };
  steps: RouteStep[];
  /**
   * True when Google had no schedule for the requested time (often a trip far
   * in the future) and the route was computed for leaving now instead.
   */
  timeAdjusted: boolean;
  source: "Google";
  fetchedAt: string;
}

export interface Place {
  id: string;
  name: string;
  address?: string;
  location?: LatLng;
  rating?: number;
  ratingCount?: number;
  priceLevel?: string;
  type?: string;
  /** Google's human-readable weekly hours, e.g. "Monday: 9:00 AM – 9:00 PM". */
  openingHours?: string[];
  mapsUrl?: string;
}

export interface TravelMatrix {
  mode: TravelMode;
  /** durationSeconds[from][to]; null when there's no route. */
  durationSeconds: (number | null)[][];
  distanceMeters: (number | null)[][];
  source: "Google";
  fetchedAt: string;
}

// ---------------------------------------------------------------------------
// Google request helpers
// ---------------------------------------------------------------------------

const googleModes: Record<TravelMode, string> = {
  transit: "TRANSIT",
  walk: "WALK",
  drive: "DRIVE",
  bicycle: "BICYCLE",
};

export function parseMode(value: unknown): TravelMode {
  if (value === undefined) return "transit";
  if (typeof value === "string" && value in googleModes) return value as TravelMode;
  throw new HttpError(400, `mode must be one of ${Object.keys(googleModes).join(", ")}.`);
}

/** Google sends durations as "123s". */
export function parseDuration(value: unknown): number {
  if (typeof value !== "string") return 0;
  const seconds = Number.parseFloat(value.replace(/s$/, ""));
  return Number.isFinite(seconds) ? Math.round(seconds) : 0;
}

function waypoint(point: LatLng) {
  return { location: { latLng: { latitude: point.latitude, longitude: point.longitude } } };
}

async function google(env: Env, url: string, fieldMask: string, body?: unknown): Promise<unknown> {
  if (!env.GOOGLE_MAPS_API_KEY) throw new HttpError(503, "GOOGLE_MAPS_API_KEY isn't set on the server.");
  const response = await fetch(url, {
    method: body === undefined ? "GET" : "POST",
    headers: {
      "content-type": "application/json",
      "x-goog-api-key": env.GOOGLE_MAPS_API_KEY,
      "x-goog-fieldmask": fieldMask,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!response.ok) {
    const detail = await response.text();
    console.error(`Google ${response.status} for ${url}: ${detail.slice(0, 500)}`);
    if (response.status === 404) throw new HttpError(404, "Google has no result for that.");
    throw new HttpError(502, "Google couldn't answer right now.");
  }
  return response.json();
}

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------

const routeFieldMask = [
  "routes.duration",
  "routes.distanceMeters",
  "routes.travelAdvisory.transitFare",
  "routes.localizedValues.transitFare",
  "routes.legs.steps.travelMode",
  "routes.legs.steps.staticDuration",
  "routes.legs.steps.distanceMeters",
  "routes.legs.steps.navigationInstruction.instructions",
  "routes.legs.steps.transitDetails",
].join(",");

export interface RouteRequest {
  origin: LatLng;
  destination: LatLng;
  mode: TravelMode;
  /** ISO 8601. Transit only; other modes route for now. */
  departureTime?: string;
  /** ISO 8601. Transit only; wins over departureTime. */
  arrivalTime?: string;
}

export async function computeRoute(env: Env, request: RouteRequest): Promise<RouteResult | null> {
  const timed = request.mode === "transit" && (request.arrivalTime || request.departureTime);
  const first = await fetchRoute(env, request, Boolean(timed));
  if (first) return normalizeRoute(first, request.mode, false);
  if (!timed) return null;
  // No schedule for that time (usually too far ahead): fall back to now.
  const now = await fetchRoute(env, request, false);
  return now ? normalizeRoute(now, request.mode, true) : null;
}

async function fetchRoute(env: Env, request: RouteRequest, useTime: boolean): Promise<GoogleRoute | null> {
  const body: Record<string, unknown> = {
    origin: waypoint(request.origin),
    destination: waypoint(request.destination),
    travelMode: googleModes[request.mode],
    languageCode: "en",
    units: "METRIC",
  };
  if (useTime) {
    if (request.arrivalTime) body.arrivalTime = request.arrivalTime;
    else if (request.departureTime) body.departureTime = request.departureTime;
  }
  const result = (await google(env, "https://routes.googleapis.com/directions/v2:computeRoutes", routeFieldMask, body)) as {
    routes?: GoogleRoute[];
  };
  return result.routes?.[0] ?? null;
}

// The parts of Google's route response that are read. Everything is optional
// because Google omits empty fields.
export interface GoogleRoute {
  duration?: string;
  distanceMeters?: number;
  travelAdvisory?: { transitFare?: { currencyCode?: string; units?: string; nanos?: number } };
  localizedValues?: { transitFare?: { text?: string } };
  legs?: { steps?: GoogleStep[] }[];
}

interface GoogleStep {
  travelMode?: string;
  staticDuration?: string;
  distanceMeters?: number;
  navigationInstruction?: { instructions?: string };
  transitDetails?: {
    headsign?: string;
    stopCount?: number;
    stopDetails?: {
      departureStop?: { name?: string };
      arrivalStop?: { name?: string };
      departureTime?: string;
      arrivalTime?: string;
    };
    transitLine?: {
      name?: string;
      nameShort?: string;
      color?: string;
      textColor?: string;
      vehicle?: { name?: { text?: string }; type?: string };
    };
  };
}

function stepKind(travelMode: string | undefined): TravelMode {
  switch (travelMode) {
    case "TRANSIT":
      return "transit";
    case "DRIVE":
      return "drive";
    case "BICYCLE":
      return "bicycle";
    default:
      return "walk";
  }
}

/**
 * Reduces a Google route to Agdayo's shape. Google splits walking into many
 * turn-by-turn steps; consecutive walking steps are merged into one, so a
 * transit trip reads "Walk 4 min, Downtown Line 2 stops, Walk 8 min".
 */
export function normalizeRoute(route: GoogleRoute, mode: TravelMode, timeAdjusted: boolean, now = new Date()): RouteResult {
  const steps: RouteStep[] = [];
  for (const step of route.legs?.flatMap((leg) => leg.steps ?? []) ?? []) {
    const kind = stepKind(step.travelMode);
    const durationSeconds = parseDuration(step.staticDuration);
    const distanceMeters = step.distanceMeters ?? 0;
    const previous = steps[steps.length - 1];
    if (kind !== "transit" && previous && previous.kind === kind && !previous.transit) {
      previous.durationSeconds += durationSeconds;
      previous.distanceMeters += distanceMeters;
      continue;
    }
    const normalized: RouteStep = { kind, durationSeconds, distanceMeters };
    const details = step.transitDetails;
    if (kind === "transit" && details) {
      const line = details.transitLine ?? {};
      normalized.transit = {
        lineName: line.name ?? line.nameShort ?? "Transit",
        lineShortName: line.nameShort,
        vehicle: line.vehicle?.name?.text ?? line.vehicle?.type ?? "Transit",
        color: line.color,
        textColor: line.textColor,
        headsign: details.headsign,
        departureStop: details.stopDetails?.departureStop?.name ?? "",
        arrivalStop: details.stopDetails?.arrivalStop?.name ?? "",
        departureTime: details.stopDetails?.departureTime,
        arrivalTime: details.stopDetails?.arrivalTime,
        stopCount: details.stopCount,
      };
    } else if (kind !== "walk" && step.navigationInstruction?.instructions) {
      normalized.instruction = step.navigationInstruction.instructions;
    }
    steps.push(normalized);
  }

  const result: RouteResult = {
    mode,
    durationSeconds: parseDuration(route.duration),
    distanceMeters: route.distanceMeters ?? 0,
    steps,
    timeAdjusted,
    source: "Google",
    fetchedAt: now.toISOString(),
  };
  const fare = route.travelAdvisory?.transitFare;
  if (fare?.currencyCode) {
    result.fare = {
      currency: fare.currencyCode,
      amount: Math.round((Number(fare.units ?? 0) + (fare.nanos ?? 0) / 1e9) * 1e6) / 1e6,
      text: route.localizedValues?.transitFare?.text,
    };
  }
  return result;
}

// ---------------------------------------------------------------------------
// Travel time matrix
// ---------------------------------------------------------------------------

/** Transit matrices are capped at 100 elements by Google; 10 × 10 fits. */
export const maxMatrixPoints = 10;

interface GoogleMatrixElement {
  originIndex?: number;
  destinationIndex?: number;
  duration?: string;
  distanceMeters?: number;
  condition?: string;
}

export async function computeMatrix(env: Env, points: LatLng[], mode: TravelMode): Promise<TravelMatrix> {
  const waypoints = points.map((point) => ({ waypoint: waypoint(point) }));
  const elements = (await google(
    env,
    "https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix",
    "originIndex,destinationIndex,duration,distanceMeters,condition",
    { origins: waypoints, destinations: waypoints, travelMode: googleModes[mode] },
  )) as GoogleMatrixElement[];
  return normalizeMatrix(elements, points.length, mode);
}

export function normalizeMatrix(elements: GoogleMatrixElement[], size: number, mode: TravelMode, now = new Date()): TravelMatrix {
  const empty = () => Array.from({ length: size }, () => Array<number | null>(size).fill(null));
  const durationSeconds = empty();
  const distanceMeters = empty();
  for (const element of elements) {
    // Google leaves out index 0, since it's the protobuf default.
    const from = element.originIndex ?? 0;
    const to = element.destinationIndex ?? 0;
    if (element.condition !== "ROUTE_EXISTS") continue;
    const durationRow = durationSeconds[from];
    const distanceRow = distanceMeters[from];
    if (!durationRow || !distanceRow || to >= size) continue;
    durationRow[to] = parseDuration(element.duration);
    distanceRow[to] = element.distanceMeters ?? 0;
  }
  return { mode, durationSeconds, distanceMeters, source: "Google", fetchedAt: now.toISOString() };
}

// ---------------------------------------------------------------------------
// Places
// ---------------------------------------------------------------------------

const placeFields = [
  "id",
  "displayName",
  "formattedAddress",
  "location",
  "rating",
  "userRatingCount",
  "priceLevel",
  "primaryTypeDisplayName",
  "regularOpeningHours.weekdayDescriptions",
  "googleMapsUri",
];

export interface GooglePlace {
  id?: string;
  displayName?: { text?: string };
  formattedAddress?: string;
  location?: { latitude?: number; longitude?: number };
  rating?: number;
  userRatingCount?: number;
  priceLevel?: string;
  primaryTypeDisplayName?: { text?: string };
  regularOpeningHours?: { weekdayDescriptions?: string[] };
  googleMapsUri?: string;
}

export function normalizePlace(place: GooglePlace): Place {
  const result: Place = { id: place.id ?? "", name: place.displayName?.text ?? "" };
  if (place.formattedAddress) result.address = place.formattedAddress;
  if (typeof place.location?.latitude === "number" && typeof place.location.longitude === "number") {
    result.location = { latitude: place.location.latitude, longitude: place.location.longitude };
  }
  if (place.rating !== undefined) result.rating = place.rating;
  if (place.userRatingCount !== undefined) result.ratingCount = place.userRatingCount;
  if (place.priceLevel) result.priceLevel = place.priceLevel.replace(/^PRICE_LEVEL_/, "").toLowerCase();
  if (place.primaryTypeDisplayName?.text) result.type = place.primaryTypeDisplayName.text;
  if (place.regularOpeningHours?.weekdayDescriptions?.length) {
    result.openingHours = place.regularOpeningHours.weekdayDescriptions;
  }
  if (place.googleMapsUri) result.mapsUrl = place.googleMapsUri;
  return result;
}

export interface PlaceSearch {
  query: string;
  near?: LatLng;
  radiusMeters?: number;
  limit?: number;
}

export async function searchPlaces(env: Env, search: PlaceSearch): Promise<Place[]> {
  const body: Record<string, unknown> = {
    textQuery: search.query,
    maxResultCount: Math.min(Math.max(search.limit ?? 8, 1), 20),
    languageCode: "en",
  };
  if (search.near) {
    body.locationBias = {
      circle: { center: search.near, radius: Math.min(Math.max(search.radiusMeters ?? 5_000, 100), 50_000) },
    };
  }
  const result = (await google(
    env,
    "https://places.googleapis.com/v1/places:searchText",
    placeFields.map((field) => `places.${field}`).join(","),
    body,
  )) as { places?: GooglePlace[] };
  return (result.places ?? []).map(normalizePlace);
}

export async function placeDetails(env: Env, id: string): Promise<Place> {
  if (!/^[A-Za-z0-9_-]{1,300}$/.test(id)) throw new HttpError(400, "That isn't a Google place ID.");
  const place = (await google(
    env,
    `https://places.googleapis.com/v1/places/${id}?languageCode=en`,
    placeFields.join(","),
  )) as GooglePlace;
  return normalizePlace(place);
}
