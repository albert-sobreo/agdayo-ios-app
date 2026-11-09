import type { Env } from "./env";
import { Firestore, type FsInput, parseServiceAccount } from "./firestore";
import { computeMatrix, computeRoute, maxMatrixPoints, parseMode, placeDetails, searchPlaces } from "./google";
import { getGuide, listGuides, parseCountryCode, parseGuide, putGuide } from "./guides";
import { cached, HttpError, optionalTime, requireLatLng, requireString } from "./http";
import { appLink, localDay } from "./open";
import {
  activityFields,
  addActivitiesWrites,
  createTripWrites,
  dayNoteFields,
  getTrip,
  listTrips,
  maxActivitiesPerCall,
  newId,
  requireTripAccess,
  stayFields,
  stayTypes,
  stayWrite,
  transportFields,
  transportModes,
  tripThemes,
  tripUpdateFields,
} from "./trips";

/**
 * The Agdayo connector for Claude: a stateless MCP server over Streamable HTTP
 * that answers with plain JSON (no event stream). Claude reaches it at /mcp
 * after signing in (see oauth.ts), which gives us the Firebase UID to act as.
 */

export const serverInfo = { name: "agdayo", title: "Agdayo", version: "0.1.0" };
const supportedVersions = ["2025-11-25", "2025-06-18", "2025-03-26"];

const instructions = `Agdayo is the user's travel app. Use these tools to plan trips and write them into Agdayo; the user then follows the plan in the app.
- Always show the plan in chat and get the user's OK before calling a tool that changes their trips (create_trip, update_trip, add_activities, update_activity, delete_activity, add_stay, update_stay, delete_stay, add_transport, update_transport, delete_transport, set_day_note, delete_day_note, save_guide).
- Show plans right in your reply as a short day-by-day list (time, place, one line why). Don't put a plan in a file, document or artifact.
- To change an existing plan, call get_trip first, then use the update_, delete_ and add_ tools. Show what will change and get the user's OK first.
- When an activity's place came from search_places, pass its placeId so the app can warn when the place is closed at that time.
- When adding transport, pin both ends with search_places (fromLatitude/toLatitude and so on) so the app can show travel between the airport or station and the stay.
- Times you write must be local times at the destination with their UTC offset, e.g. 2026-12-10T09:00:00+08:00 for Singapore.
- Use search_places to get real coordinates before adding activities or stays, so travel times work in the app.
- Transit directions and times come only from plan_route and travel_times (Google). If they return no transit route, say there's no transit data there and suggest walking or a car; never guess lines or times.
- Mention that routes and places are from Google.
- Trip tools return an appLink. After writing to a trip, share it as a link (e.g. [Open in Agdayo](appLink)) so the user can jump to that trip and day in the app.`;

export interface McpContext {
  env: Env;
  uid: string;
  /** This server's public origin, for appLink. */
  origin: string;
  /** Firestore, created on first use so tools that don't need it work without the service account. */
  firestore: () => Firestore;
}

type Args = Record<string, unknown>;

interface Tool {
  name: string;
  title: string;
  description: string;
  inputSchema: Record<string, unknown>;
  annotations: { readOnlyHint?: boolean; destructiveHint?: boolean; idempotentHint?: boolean; openWorldHint?: boolean };
  run: (args: Args, ctx: McpContext) => Promise<unknown>;
}

const latLng = {
  type: "object",
  properties: { latitude: { type: "number" }, longitude: { type: "number" } },
  required: ["latitude", "longitude"],
};
const zonedTime = { type: "string", description: "Local time with UTC offset, e.g. 2026-12-10T09:00:00+08:00." };
const tripId = { type: "string", description: "Trip ID from list_trips." };
const travelMode = { type: "string", enum: ["transit", "walk", "drive", "bicycle"], description: "Defaults to transit." };
const read = { readOnlyHint: true, openWorldHint: true };
const write = { readOnlyHint: false, destructiveHint: false, openWorldHint: false };

const activityProperties = {
  title: { type: "string" },
  location: { type: "string", description: "Place name or address shown in the app." },
  latitude: { type: "number" },
  longitude: { type: "number" },
  time: zonedTime,
  description: { type: "string", description: "Short notes: what to do, tips, how to get there." },
  icon: { type: "string", description: "SF Symbol name, e.g. fork.knife, building.columns, leaf, bag, moon.stars, tram.fill. Defaults to mappin.and.ellipse." },
  cost: { type: "number" },
  costCurrency: { type: "string", description: "Three-letter code, e.g. SGD." },
  costNote: { type: "string" },
  placeId: { type: "string", description: "Google place ID from search_places, so the app can check opening hours." },
};

const tripProperties = {
  name: { type: "string" },
  location: { type: "string", description: "e.g. Singapore" },
  startDate: { ...zonedTime, description: "First day, local midnight with offset, e.g. 2026-12-10T00:00:00+08:00." },
  endDate: { ...zonedTime, description: "Last day, local midnight with offset." },
  currency: { type: "string", description: "Three-letter code for the trip budget, e.g. SGD." },
  budget: { type: "number" },
  description: { type: "string" },
  theme: { type: "string", enum: [...tripThemes] },
  latitude: { type: "number" },
  longitude: { type: "number" },
  country: { type: "string" },
  city: { type: "string" },
};

const stayProperties = {
  name: { type: "string" },
  location: { type: "string", description: "Address." },
  latitude: { type: "number" },
  longitude: { type: "number" },
  type: { type: "string", enum: [...stayTypes] },
  checkIn: { ...zonedTime, description: "Check-in date and time with offset." },
  checkOut: { ...zonedTime, description: "Check-out date and time with offset." },
  checkInTime: { type: "string", description: "HH:mm, default 15:00." },
  checkOutTime: { type: "string", description: "HH:mm, default 11:00." },
  totalCost: { type: "number" },
  rooms: { type: "number" },
};

const transportProperties = {
  mode: { type: "string", enum: [...transportModes], description: "rideshare means taxi or ride-hailing (e.g. Grab). van is a UV Express or shuttle van; motorcycle is a motorcycle taxi (Angkas, habal-habal); bangka is a small outrigger boat." },
  from: { type: "string", description: "Where it leaves from, e.g. Manila (MNL) Terminal 3." },
  to: { type: "string", description: "Where it arrives, e.g. Singapore Changi (SIN) Terminal 1." },
  departure: { ...zonedTime, description: "Departure, local time at the origin with offset." },
  arrival: { ...zonedTime, description: "Arrival, local time at the destination with offset." },
  fromLatitude: { type: "number", description: "Pin for the departure point (airport, station), from search_places." },
  fromLongitude: { type: "number" },
  toLatitude: { type: "number", description: "Pin for the arrival point. With a stay pinned too, the app shows travel between them." },
  toLongitude: { type: "number" },
  bookingRef: { type: "string" },
  seat: { type: "string" },
  cost: { type: "number" },
  currency: { type: "string", description: "Three-letter code. Defaults to the trip's currency." },
  notes: { type: "string", description: "e.g. flight number, terminal, baggage." },
};

const recordId = (name: string) => ({ type: "string", description: `${name} from get_trip.` });

/** Changes or deletes one record of a trip after checking the user can edit it. */
async function changeRecord(
  ctx: McpContext,
  args: Args,
  idField: string,
  collection: string,
  fields: Record<string, FsInput | undefined> | null,
): Promise<{ tripId: string; recordId: string }> {
  const id = requireString(args.tripId, "tripId");
  const recordId = requireString(args[idField], idField);
  if (!/^[0-9A-Fa-f-]{36}$/.test(recordId)) throw new HttpError(400, `${idField} must be an ID from get_trip.`);
  const db = ctx.firestore();
  await requireTripAccess(db, ctx.uid, id);
  const path = `trips/${id}/${collection}/${recordId}`;
  if (fields === null) {
    await db.commit([{ kind: "delete", path }]);
  } else {
    if (Object.keys(fields).length === 0) throw new HttpError(400, "Pass at least one field to change.");
    await db.commit([{ kind: "update", path, fields }]);
  }
  return { tripId: id, recordId };
}

export const tools: Tool[] = [
  {
    name: "list_trips",
    title: "List trips",
    description: "Lists the user's Agdayo trips, newest first.",
    inputSchema: { type: "object", properties: {} },
    annotations: { readOnlyHint: true, openWorldHint: false },
    run: async (_args, ctx) => ({ trips: await listTrips(ctx.firestore(), ctx.uid) }),
  },
  {
    name: "get_trip",
    title: "Get trip",
    description: "Gets one trip with its stays, transport, activities (sorted by time) and day notes.",
    inputSchema: { type: "object", properties: { tripId }, required: ["tripId"] },
    annotations: { readOnlyHint: true, openWorldHint: false },
    run: async (args, ctx) => {
      const id = requireString(args.tripId, "tripId");
      return { ...(await getTrip(ctx.firestore(), ctx.uid, id)), appLink: appLink(ctx.origin, id) };
    },
  },
  {
    name: "create_trip",
    title: "Create trip",
    description: "Creates a new trip owned by the user. It shows up in Agdayo the next time the trip list refreshes.",
    inputSchema: {
      type: "object",
      properties: tripProperties,
      required: ["name", "location", "startDate", "endDate", "currency"],
    },
    annotations: write,
    run: async (args, ctx) => {
      const id = newId();
      await ctx.firestore().commit(createTripWrites(ctx.uid, args, id));
      return { tripId: id, created: true, appLink: appLink(ctx.origin, id, localDay(args.startDate)) };
    },
  },
  {
    name: "add_stay",
    title: "Add stay",
    description: "Adds a hotel or other stay to a trip. Include coordinates so the app can show travel times from it.",
    inputSchema: {
      type: "object",
      properties: { tripId, ...stayProperties },
      required: ["tripId", "name", "location", "latitude", "longitude", "checkIn", "checkOut"],
    },
    annotations: write,
    run: async (args, ctx) => {
      const id = requireString(args.tripId, "tripId");
      const db = ctx.firestore();
      await requireTripAccess(db, ctx.uid, id);
      const stayId = newId();
      await db.commit([stayWrite(id, args, stayId)]);
      return { stayId, added: true, appLink: appLink(ctx.origin, id, localDay(args.checkIn)) };
    },
  },
  {
    name: "add_activities",
    title: "Add activities",
    description: `Adds up to ${maxActivitiesPerCall} activities to a trip in one go (all or nothing).`,
    inputSchema: {
      type: "object",
      properties: {
        tripId,
        activities: {
          type: "array",
          maxItems: maxActivitiesPerCall,
          items: { type: "object", properties: activityProperties, required: ["title", "location", "time"] },
        },
      },
      required: ["tripId", "activities"],
    },
    annotations: write,
    run: async (args, ctx) => {
      const id = requireString(args.tripId, "tripId");
      const db = ctx.firestore();
      await requireTripAccess(db, ctx.uid, id);
      const { writes, ids } = addActivitiesWrites(id, args.activities);
      await db.commit(writes);
      const first = Array.isArray(args.activities) ? (args.activities[0] as Args | undefined) : undefined;
      return { activityIds: ids, added: ids.length, appLink: appLink(ctx.origin, id, localDay(first?.time)) };
    },
  },
  {
    name: "update_activity",
    title: "Update activity",
    description: "Changes some fields of an activity. Only the fields you pass change.",
    inputSchema: {
      type: "object",
      properties: { tripId, activityId: { type: "string" }, ...activityProperties },
      required: ["tripId", "activityId"],
    },
    annotations: { ...write, idempotentHint: true },
    run: async (args, ctx) => {
      const id = requireString(args.tripId, "tripId");
      const activityId = requireString(args.activityId, "activityId");
      const db = ctx.firestore();
      await requireTripAccess(db, ctx.uid, id);
      const fields = activityFields(args, true);
      if (Object.keys(fields).length === 0) throw new HttpError(400, "Pass at least one field to change.");
      await db.commit([{ kind: "update", path: `trips/${id}/activities/${activityId}`, fields }]);
      return { activityId, updated: Object.keys(fields), appLink: appLink(ctx.origin, id, localDay(args.time)) };
    },
  },
  {
    name: "delete_activity",
    title: "Delete activity",
    description: "Deletes an activity from a trip. Ask the user first.",
    inputSchema: { type: "object", properties: { tripId, activityId: { type: "string" } }, required: ["tripId", "activityId"] },
    annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false },
    run: async (args, ctx) => {
      const id = requireString(args.tripId, "tripId");
      const activityId = requireString(args.activityId, "activityId");
      const db = ctx.firestore();
      await requireTripAccess(db, ctx.uid, id);
      await db.commit([{ kind: "delete", path: `trips/${id}/activities/${activityId}` }]);
      return { activityId, deleted: true };
    },
  },
  {
    name: "update_trip",
    title: "Update trip",
    description: "Changes a trip's details: name, dates, place, budget, currency, description or theme. Only the fields you pass change.",
    inputSchema: { type: "object", properties: { tripId, ...tripProperties }, required: ["tripId"] },
    annotations: { ...write, idempotentHint: true },
    run: async (args, ctx) => {
      const id = requireString(args.tripId, "tripId");
      const db = ctx.firestore();
      await requireTripAccess(db, ctx.uid, id);
      const fields = tripUpdateFields(args);
      if (Object.keys(fields).length === 0) throw new HttpError(400, "Pass at least one field to change.");
      await db.commit([{ kind: "update", path: `trips/${id}`, fields, serverTimestamps: ["updatedAt"] }]);
      return { tripId: id, updated: Object.keys(fields), appLink: appLink(ctx.origin, id, localDay(args.startDate)) };
    },
  },
  {
    name: "update_stay",
    title: "Update stay",
    description: "Changes some fields of a stay. Only the fields you pass change.",
    inputSchema: { type: "object", properties: { tripId, stayId: recordId("stayId"), ...stayProperties }, required: ["tripId", "stayId"] },
    annotations: { ...write, idempotentHint: true },
    run: async (args, ctx) => {
      const fields = stayFields(args, true);
      const { tripId: id, recordId: stayId } = await changeRecord(ctx, args, "stayId", "accommodations", fields);
      return { stayId, updated: Object.keys(fields), appLink: appLink(ctx.origin, id, localDay(args.checkIn)) };
    },
  },
  {
    name: "delete_stay",
    title: "Delete stay",
    description: "Deletes a stay from a trip. Ask the user first.",
    inputSchema: { type: "object", properties: { tripId, stayId: recordId("stayId") }, required: ["tripId", "stayId"] },
    annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false },
    run: async (args, ctx) => {
      const { tripId: id, recordId: stayId } = await changeRecord(ctx, args, "stayId", "accommodations", null);
      return { stayId, deleted: true, appLink: appLink(ctx.origin, id) };
    },
  },
  {
    name: "add_transport",
    title: "Add transport",
    description: "Adds a flight, bus, train, ferry or other booked trip between places.",
    inputSchema: {
      type: "object",
      properties: { tripId, ...transportProperties },
      required: ["tripId", "mode", "from", "to", "departure"],
    },
    annotations: write,
    run: async (args, ctx) => {
      const id = requireString(args.tripId, "tripId");
      const db = ctx.firestore();
      const trip = await requireTripAccess(db, ctx.uid, id);
      const fields = transportFields(args, false, String(trip.data.currency ?? "USD"));
      const transportId = newId();
      await db.commit([
        { kind: "set", path: `trips/${id}/transportSegments/${transportId}`, fields: { ...fields, createdBy: "claude" }, mustNotExist: true },
      ]);
      return { transportId, added: true, appLink: appLink(ctx.origin, id, localDay(args.departure)) };
    },
  },
  {
    name: "update_transport",
    title: "Update transport",
    description: "Changes some fields of a transport booking. Only the fields you pass change.",
    inputSchema: {
      type: "object",
      properties: { tripId, transportId: recordId("transportId"), ...transportProperties },
      required: ["tripId", "transportId"],
    },
    annotations: { ...write, idempotentHint: true },
    run: async (args, ctx) => {
      const fields = transportFields(args, true, "");
      const { tripId: id, recordId: transportId } = await changeRecord(ctx, args, "transportId", "transportSegments", fields);
      return { transportId, updated: Object.keys(fields), appLink: appLink(ctx.origin, id, localDay(args.departure)) };
    },
  },
  {
    name: "delete_transport",
    title: "Delete transport",
    description: "Deletes a transport booking from a trip. Ask the user first.",
    inputSchema: { type: "object", properties: { tripId, transportId: recordId("transportId") }, required: ["tripId", "transportId"] },
    annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false },
    run: async (args, ctx) => {
      const { tripId: id, recordId: transportId } = await changeRecord(ctx, args, "transportId", "transportSegments", null);
      return { transportId, deleted: true, appLink: appLink(ctx.origin, id) };
    },
  },
  {
    name: "set_day_note",
    title: "Set day note",
    description: "Adds a note to a day of the trip, or changes one when you pass its noteId.",
    inputSchema: {
      type: "object",
      properties: {
        tripId,
        noteId: { type: "string", description: "noteId from get_trip, to change an existing note. Leave out to add one." },
        day: { ...zonedTime, description: "Any local time on that day, with offset, e.g. 2026-12-10T00:00:00+08:00." },
        title: { type: "string" },
        content: { type: "string" },
      },
      required: ["tripId"],
    },
    annotations: write,
    run: async (args, ctx) => {
      if (args.noteId !== undefined) {
        const fields = dayNoteFields(args, true);
        const { tripId: id, recordId: noteId } = await changeRecord(ctx, args, "noteId", "dayNotes", fields);
        return { noteId, updated: Object.keys(fields), appLink: appLink(ctx.origin, id, localDay(args.day)) };
      }
      const id = requireString(args.tripId, "tripId");
      const db = ctx.firestore();
      await requireTripAccess(db, ctx.uid, id);
      const noteId = newId();
      await db.commit([{ kind: "set", path: `trips/${id}/dayNotes/${noteId}`, fields: dayNoteFields(args), mustNotExist: true }]);
      return { noteId, added: true, appLink: appLink(ctx.origin, id, localDay(args.day)) };
    },
  },
  {
    name: "delete_day_note",
    title: "Delete day note",
    description: "Deletes a day note. Ask the user first.",
    inputSchema: { type: "object", properties: { tripId, noteId: recordId("noteId") }, required: ["tripId", "noteId"] },
    annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false },
    run: async (args, ctx) => {
      const { tripId: id, recordId: noteId } = await changeRecord(ctx, args, "noteId", "dayNotes", null);
      return { noteId, deleted: true, appLink: appLink(ctx.origin, id) };
    },
  },
  {
    name: "plan_route",
    title: "Plan route",
    description:
      "Directions between two points from Google: duration, distance and, for transit, each line with stops and scheduled times. Returns route: null when there's no route (e.g. no transit data in that city).",
    inputSchema: {
      type: "object",
      properties: {
        origin: latLng,
        destination: latLng,
        mode: travelMode,
        departureTime: { type: "string", description: "ISO 8601 with offset. Leave out for now." },
        arrivalTime: { type: "string", description: "ISO 8601 with offset, transit only." },
      },
      required: ["origin", "destination"],
    },
    annotations: read,
    run: async (args, ctx) => {
      const request = {
        origin: requireLatLng(args.origin, "origin"),
        destination: requireLatLng(args.destination, "destination"),
        mode: parseMode(args.mode),
        departureTime: optionalTime(args.departureTime, "departureTime"),
        arrivalTime: optionalTime(args.arrivalTime, "arrivalTime"),
      };
      return { route: await cached("route", request, 300, () => computeRoute(ctx.env, request)) };
    },
  },
  {
    name: "travel_times",
    title: "Travel times",
    description: `Travel time and distance between every pair of up to ${maxMatrixPoints} points (Google). Good for ordering a day's stops.`,
    inputSchema: {
      type: "object",
      properties: { points: { type: "array", items: latLng, minItems: 2, maxItems: maxMatrixPoints }, mode: travelMode },
      required: ["points"],
    },
    annotations: read,
    run: async (args, ctx) => {
      if (!Array.isArray(args.points) || args.points.length < 2 || args.points.length > maxMatrixPoints) {
        throw new HttpError(400, `points must list 2 to ${maxMatrixPoints} places.`);
      }
      const points = args.points.map((point, index) => requireLatLng(point, `points[${index}]`));
      const mode = parseMode(args.mode);
      return cached("matrix", { points, mode }, 300, () => computeMatrix(ctx.env, points, mode));
    },
  },
  {
    name: "search_places",
    title: "Search places",
    description: "Finds places by text (Google Places): name, address, coordinates, rating, opening hours.",
    inputSchema: {
      type: "object",
      properties: {
        query: { type: "string", description: "e.g. 'hawker centre near Chinatown Singapore'" },
        near: latLng,
        radiusMeters: { type: "number" },
        limit: { type: "number", description: "1 to 20, default 10." },
      },
      required: ["query"],
    },
    annotations: read,
    run: async (args, ctx) => {
      const search = {
        query: requireString(args.query, "query"),
        near: args.near === undefined ? undefined : requireLatLng(args.near, "near"),
        radiusMeters: typeof args.radiusMeters === "number" ? args.radiusMeters : undefined,
        limit: typeof args.limit === "number" ? args.limit : undefined,
      };
      return { places: await cached("places", search, 3600, () => searchPlaces(ctx.env, search)) };
    },
  },
  {
    name: "place_details",
    title: "Place details",
    description: "Details for one place ID from search_places.",
    inputSchema: { type: "object", properties: { placeId: { type: "string" } }, required: ["placeId"] },
    annotations: read,
    run: async (args, ctx) => {
      const id = requireString(args.placeId, "placeId");
      return { place: await cached("place", id, 3600, () => placeDetails(ctx.env, id)) };
    },
  },
  {
    name: "get_guide",
    title: "Get country guide",
    description: "Gets the saved 'Know before you go' guide for a country. Leave countryCode out to list saved guides.",
    inputSchema: { type: "object", properties: { countryCode: { type: "string", description: "Two letters, e.g. SG." } } },
    annotations: { readOnlyHint: true, openWorldHint: false },
    run: async (args, ctx) => {
      if (args.countryCode === undefined) return { guides: await listGuides(ctx.env.DB) };
      const code = parseCountryCode(requireString(args.countryCode, "countryCode"));
      return { guide: await getGuide(ctx.env.DB, code) };
    },
  },
  {
    name: "save_guide",
    title: "Save country guide",
    description:
      "Saves (replaces) a country's 'Know before you go' guide shown in the app. Research with web search first, cite sources, and keep items short and practical (getting around, money, plugs, SIM, etiquette, safety, emergency numbers).",
    inputSchema: {
      type: "object",
      properties: {
        countryCode: { type: "string" },
        title: { type: "string", description: "e.g. Singapore" },
        sections: {
          type: "array",
          items: {
            type: "object",
            properties: {
              id: { type: "string", description: "Stable key, e.g. getting-around, money, plugs." },
              title: { type: "string" },
              items: {
                type: "array",
                items: {
                  type: "object",
                  properties: { text: { type: "string" }, source: { type: "string", description: "URL backing this item." } },
                  required: ["text"],
                },
              },
            },
            required: ["id", "title", "items"],
          },
        },
        sources: {
          type: "array",
          items: { type: "object", properties: { title: { type: "string" }, url: { type: "string" } }, required: ["title", "url"] },
        },
        checkedAt: { type: "string", description: "When the facts were checked, ISO 8601. Defaults to now." },
      },
      required: ["countryCode", "title", "sections"],
    },
    annotations: { ...write, idempotentHint: true },
    run: async (args, ctx) => {
      const guide = parseGuide(parseCountryCode(requireString(args.countryCode, "countryCode")), args);
      await putGuide(ctx.env.DB, guide);
      return { saved: true, countryCode: guide.countryCode, sections: guide.sections.length };
    },
  },
];

const toolsByName = new Map(tools.map((tool) => [tool.name, tool]));

interface JsonRpcRequest {
  jsonrpc: "2.0";
  id?: string | number | null;
  method: string;
  params?: Record<string, unknown>;
}

type JsonRpcResponse =
  | { jsonrpc: "2.0"; id: string | number | null; result: unknown }
  | { jsonrpc: "2.0"; id: string | number | null; error: { code: number; message: string } };

function rpcError(id: JsonRpcRequest["id"], code: number, message: string): JsonRpcResponse {
  return { jsonrpc: "2.0", id: id ?? null, error: { code, message } };
}

/** Handles one JSON-RPC message. Returns null for notifications, which get no answer. */
export async function handleRpc(message: unknown, ctx: McpContext): Promise<JsonRpcResponse | null> {
  if (typeof message !== "object" || message === null || (message as JsonRpcRequest).jsonrpc !== "2.0") {
    return rpcError(null, -32600, "Invalid request.");
  }
  const { id, method, params = {} } = message as JsonRpcRequest;
  const isNotification = id === undefined;
  if (typeof method !== "string") return rpcError(id, -32600, "Invalid request.");
  if (isNotification) return null;

  switch (method) {
    case "initialize": {
      const requested = typeof params.protocolVersion === "string" ? params.protocolVersion : "";
      return {
        jsonrpc: "2.0",
        id,
        result: {
          protocolVersion: supportedVersions.includes(requested) ? requested : supportedVersions[0],
          capabilities: { tools: { listChanged: false } },
          serverInfo,
          instructions,
        },
      };
    }
    case "ping":
      return { jsonrpc: "2.0", id, result: {} };
    case "tools/list":
      return {
        jsonrpc: "2.0",
        id,
        result: {
          tools: tools.map(({ name, title, description, inputSchema, annotations }) => ({
            name,
            title,
            description,
            inputSchema,
            annotations: { title, ...annotations },
          })),
        },
      };
    case "tools/call": {
      const tool = typeof params.name === "string" ? toolsByName.get(params.name) : undefined;
      if (!tool) return rpcError(id, -32602, `Unknown tool: ${String(params.name)}`);
      const args = (typeof params.arguments === "object" && params.arguments !== null ? params.arguments : {}) as Args;
      try {
        const result = await tool.run(args, ctx);
        return { jsonrpc: "2.0", id, result: { content: [{ type: "text", text: JSON.stringify(result) }] } };
      } catch (error) {
        // Tool errors go back to Claude as results so it can fix its input and retry.
        const text = error instanceof HttpError ? error.message : "Something went wrong on the server.";
        if (!(error instanceof HttpError)) console.error(error);
        return { jsonrpc: "2.0", id, result: { content: [{ type: "text", text }], isError: true } };
      }
    }
    default:
      return rpcError(id, -32601, `Method not found: ${method}`);
  }
}

/** The /mcp endpoint. POST carries JSON-RPC; there's no server-to-client stream, so GET is refused. */
export async function handleMcp(request: Request, env: Env, uid: string): Promise<Response> {
  if (request.method !== "POST") {
    return new Response(null, { status: 405, headers: { allow: "POST" } });
  }
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return Response.json(rpcError(null, -32700, "Body must be JSON."), { status: 400 });
  }
  let firestore: Firestore | undefined;
  const ctx: McpContext = {
    env,
    uid,
    origin: new URL(request.url).origin,
    firestore: () => (firestore ??= new Firestore(parseServiceAccount(env.FIREBASE_SERVICE_ACCOUNT))),
  };
  const messages = Array.isArray(body) ? body : [body];
  const responses = (await Promise.all(messages.map((message) => handleRpc(message, ctx)))).filter(
    (response): response is JsonRpcResponse => response !== null,
  );
  if (responses.length === 0) return new Response(null, { status: 202 });
  return Response.json(Array.isArray(body) ? responses : responses[0]);
}
