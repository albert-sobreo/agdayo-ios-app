import type { FsDocument, FsInput, FsWrite, Firestore } from "./firestore";
import { FsDouble, FsTimestamp } from "./firestore";
import { HttpError } from "./http";

/**
 * Reads and writes Agdayo trips in Firestore, in the same shapes the app's
 * DTOs use (see Agdayo/Services/Sync/*Sync.swift). Anything the connector
 * writes carries `createdBy: "claude"` so the app can mark it later. The app
 * ignores fields it doesn't know.
 */

export const tripThemes = ["peach", "blue", "amber", "emerald", "violet", "teal", "rose", "slate"] as const;
export const stayTypes = ["hotel", "airbnb", "transient", "other"] as const;
/** TransportMode raw values in the app. */
export const transportModes = ["flight", "bus", "train", "car", "ferry", "rideshare", "other"] as const;
export const maxActivitiesPerCall = 40;

/** Matches TripMembershipService.generateRandomCode. */
export function joinCode(random: () => number = Math.random, length = 6): string {
  const chars = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
  return Array.from({ length }, () => chars[Math.floor(random() * chars.length)]).join("");
}

/** Swift's UUID().uuidString is upper case; the app's document IDs follow it. */
export function newId(): string {
  return crypto.randomUUID().toUpperCase();
}

/**
 * A time with an explicit UTC offset, like 2026-12-10T09:00:00+08:00. Without
 * the offset the server would read it as UTC and the activity would land at
 * the wrong hour on the phone.
 */
export function requireZonedTime(value: unknown, field: string): FsTimestamp {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:\d{2})$/.test(value.trim())) {
    throw new HttpError(400, `${field} must be a local time with its UTC offset, like 2026-12-10T09:00:00+08:00.`);
  }
  const time = Date.parse(value.trim());
  if (Number.isNaN(time)) throw new HttpError(400, `${field} isn't a real date.`);
  return new FsTimestamp(new Date(time).toISOString());
}

/**
 * Splits a local time with offset into the app's day + "HH:mm" pair, for
 * records that store them apart (transport, day notes). The day is local
 * midnight at the destination, which is how the app saves picked dates.
 */
export function splitZonedTime(value: unknown, field: string): { day: FsTimestamp; time: string } {
  requireZonedTime(value, field);
  const trimmed = String(value).trim();
  const offset = /(Z|[+-]\d{2}:\d{2})$/.exec(trimmed)?.[1] ?? "Z";
  return { day: requireZonedTime(`${trimmed.slice(0, 10)}T00:00:00${offset}`, field), time: trimmed.slice(11, 16) };
}

function text(value: unknown, field: string, fallback?: string): string {
  if (value === undefined || value === null || value === "") {
    if (fallback !== undefined) return fallback;
    throw new HttpError(400, `${field} is required.`);
  }
  if (typeof value !== "string") throw new HttpError(400, `${field} must be text.`);
  return value.trim();
}

function optionalText(value: unknown, field: string): string | undefined {
  if (value === undefined || value === null) return undefined;
  return text(value, field, "");
}

function optionalNumber(value: unknown, field: string, min = 0): number | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "number" || !Number.isFinite(value) || value < min) {
    throw new HttpError(400, `${field} must be a number of at least ${min}.`);
  }
  return value;
}

function optionalCoordinate(lat: unknown, lng: unknown, field: string): { latitude?: FsDouble; longitude?: FsDouble } {
  if (lat === undefined && lng === undefined) return {};
  if (typeof lat !== "number" || typeof lng !== "number" || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
    throw new HttpError(400, `${field} needs both latitude and longitude in degrees.`);
  }
  return { latitude: new FsDouble(lat), longitude: new FsDouble(lng) };
}

function hhmm(value: unknown, field: string, fallback: string): string {
  const result = text(value, field, fallback);
  if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(result)) throw new HttpError(400, `${field} must look like 15:00.`);
  return result;
}

function currency(value: unknown, field: string): string {
  const code = text(value, field).toUpperCase();
  if (!/^[A-Z]{3}$/.test(code)) throw new HttpError(400, `${field} must be a three-letter currency code, like SGD.`);
  return code;
}

/** Throws unless the user owns or has joined the trip. Returns the trip document. */
export async function requireTripAccess(db: Firestore, uid: string, tripId: string): Promise<FsDocument> {
  if (!/^[0-9A-Fa-f-]{36}$/.test(tripId)) throw new HttpError(400, "tripId must be a trip ID from list_trips.");
  const [trip, member] = await Promise.all([db.get(`trips/${tripId}`), db.get(`trips/${tripId}/members/${uid}`)]);
  if (!trip) throw new HttpError(404, "No trip with that ID.");
  if (trip.data.ownerUID !== uid && !member) throw new HttpError(403, "You aren't a member of that trip.");
  return trip;
}

export interface TripSummary {
  tripId: string;
  name: string;
  location: string;
  startDate: unknown;
  endDate: unknown;
  currency: unknown;
}

function summarize(doc: FsDocument): TripSummary {
  return {
    tripId: doc.id,
    name: String(doc.data.name ?? ""),
    location: String(doc.data.location ?? ""),
    startDate: doc.data.startDate,
    endDate: doc.data.endDate,
    currency: doc.data.currency,
  };
}

export async function listTrips(db: Firestore, uid: string): Promise<TripSummary[]> {
  const user = await db.get(`users/${uid}`);
  const ids = Array.isArray(user?.data.memberOfTripIDs) ? (user.data.memberOfTripIDs as string[]) : [];
  const trips = await db.getAll(ids.map((id) => `trips/${id}`));
  return trips.map(summarize).sort((a, b) => String(b.startDate).localeCompare(String(a.startDate)));
}

/** Leaves out money-splitting fields Claude doesn't need. */
function trim(data: Record<string, unknown>): Record<string, unknown> {
  const { budgetCategoryID, budgetMemberUID, paidByUID, splitUIDs, splitAmounts, exchangeRateToTripCurrency, ...rest } = data;
  void budgetCategoryID, budgetMemberUID, paidByUID, splitUIDs, splitAmounts, exchangeRateToTripCurrency;
  return rest;
}

export async function getTrip(db: Firestore, uid: string, tripId: string): Promise<Record<string, unknown>> {
  const trip = await requireTripAccess(db, uid, tripId);
  const [stays, transport, activities, dayNotes] = await Promise.all([
    db.list(`trips/${tripId}/accommodations`),
    db.list(`trips/${tripId}/transportSegments`),
    db.list(`trips/${tripId}/activities`),
    db.list(`trips/${tripId}/dayNotes`),
  ]);
  const byTime = (field: string) => (a: FsDocument, b: FsDocument) =>
    String(a.data[field] ?? "").localeCompare(String(b.data[field] ?? ""));
  return {
    trip: { ...summarize(trip), description: trip.data.tripDescription, latitude: trip.data.latitude, longitude: trip.data.longitude, budget: trip.data.overallBudget },
    stays: stays.sort(byTime("startDate")).map((doc) => ({ stayId: doc.id, ...trim(doc.data) })),
    transport: transport.sort(byTime("departureDate")).map((doc) => ({ transportId: doc.id, ...trim(doc.data) })),
    activities: activities.sort(byTime("date")).map((doc) => ({ activityId: doc.id, ...trim(doc.data) })),
    dayNotes: dayNotes.map((doc) => ({ noteId: doc.id, ...doc.data })),
  };
}

export function createTripWrites(uid: string, input: Record<string, unknown>, tripId = newId(), code = joinCode()): FsWrite[] {
  const theme = text(input.theme, "theme", "teal");
  if (!(tripThemes as readonly string[]).includes(theme)) {
    throw new HttpError(400, `theme must be one of ${tripThemes.join(", ")}.`);
  }
  const startDate = requireZonedTime(input.startDate, "startDate");
  const endDate = requireZonedTime(input.endDate, "endDate");
  if (endDate.iso < startDate.iso) throw new HttpError(400, "endDate is before startDate.");
  const fields: Record<string, FsInput | undefined> = {
    ownerUID: uid,
    name: text(input.name, "name"),
    location: text(input.location, "location"),
    theme,
    startDate,
    endDate,
    overallBudget: new FsDouble(optionalNumber(input.budget, "budget") ?? 0),
    currency: currency(input.currency, "currency"),
    tripDescription: text(input.description, "description", ""),
    memberBudgets: {},
    ownerUnlocked: true,
    joinCode: code,
    createdBy: "claude",
    ...optionalCoordinate(input.latitude, input.longitude, "the trip's location"),
    visitedCountry: optionalText(input.country, "country"),
    visitedCity: optionalText(input.city, "city"),
  };
  return [
    { kind: "set", path: `trips/${tripId}`, fields, serverTimestamps: ["createdAt", "updatedAt"], mustNotExist: true },
    { kind: "set", path: `tripJoinCodes/${code}`, fields: { tripID: tripId }, serverTimestamps: ["createdAt"], mustNotExist: true },
    { kind: "set", path: `trips/${tripId}/members/${uid}`, fields: { uid, role: "owner" }, serverTimestamps: ["joinedAt"] },
    { kind: "arrayUnion", path: `users/${uid}`, field: "memberOfTripIDs", values: [tripId] },
  ];
}

/** ActivityDTO fields from Claude's input. `partial` allows leaving required fields out (for updates). */
export function activityFields(input: Record<string, unknown>, partial = false): Record<string, FsInput | undefined> {
  const has = (key: string) => input[key] !== undefined;
  const fields: Record<string, FsInput | undefined> = {};
  if (!partial || has("title")) fields.title = text(input.title, "title");
  if (!partial || has("location")) fields.location = text(input.location, "location");
  if (!partial || has("time")) fields.date = requireZonedTime(input.time, "time");
  if (!partial || has("description")) fields.activityDescription = text(input.description, "description", "");
  if (!partial || has("icon")) fields.iconName = text(input.icon, "icon", "mappin.and.ellipse");
  if (has("latitude") || has("longitude")) Object.assign(fields, optionalCoordinate(input.latitude, input.longitude, "the activity's location"));
  if (has("cost")) {
    const cost = optionalNumber(input.cost, "cost");
    fields.cost = cost === undefined ? undefined : new FsDouble(cost);
  }
  if (has("costCurrency")) fields.costCurrency = currency(input.costCurrency, "costCurrency");
  if (has("costNote")) fields.costNote = text(input.costNote, "costNote", "");
  if (has("placeId")) fields.placeID = text(input.placeId, "placeId", "");
  return fields;
}

export function addActivitiesWrites(tripId: string, items: unknown): { writes: FsWrite[]; ids: string[] } {
  if (!Array.isArray(items) || items.length === 0) throw new HttpError(400, "activities must be a non-empty list.");
  if (items.length > maxActivitiesPerCall) throw new HttpError(400, `Add at most ${maxActivitiesPerCall} activities per call.`);
  const ids: string[] = [];
  const writes = items.map((raw, index): FsWrite => {
    if (typeof raw !== "object" || raw === null) throw new HttpError(400, `activities[${index}] must be an object.`);
    let fields: Record<string, FsInput | undefined>;
    try {
      fields = activityFields(raw as Record<string, unknown>);
    } catch (error) {
      if (error instanceof HttpError) throw new HttpError(400, `activities[${index}]: ${error.message}`);
      throw error;
    }
    const id = newId();
    ids.push(id);
    return { kind: "set", path: `trips/${tripId}/activities/${id}`, fields: { ...fields, createdBy: "claude" }, mustNotExist: true };
  });
  return { writes, ids };
}

/** AccommodationDTO fields from Claude's input. `partial` allows leaving required fields out (for updates). */
export function stayFields(input: Record<string, unknown>, partial = false): Record<string, FsInput | undefined> {
  const has = (key: string) => input[key] !== undefined;
  const fields: Record<string, FsInput | undefined> = {};
  if (!partial || has("name")) fields.name = text(input.name, "name");
  if (!partial || has("type")) {
    const type = text(input.type, "type", "hotel");
    if (!(stayTypes as readonly string[]).includes(type)) throw new HttpError(400, `type must be one of ${stayTypes.join(", ")}.`);
    fields.type = type;
  }
  if (!partial || has("location")) fields.location = text(input.location, "location");
  if (!partial || has("latitude") || has("longitude")) {
    Object.assign(fields, optionalCoordinate(input.latitude, input.longitude, "the stay's location"));
  }
  if (!partial || has("rooms")) fields.numberOfRooms = Math.round(optionalNumber(input.rooms, "rooms", 1) ?? 1);
  if (!partial || has("totalCost")) fields.totalCost = new FsDouble(optionalNumber(input.totalCost, "totalCost") ?? 0);
  if (!partial || has("checkInTime")) fields.checkInTime = hhmm(input.checkInTime, "checkInTime", "15:00");
  if (!partial || has("checkOutTime")) fields.checkOutTime = hhmm(input.checkOutTime, "checkOutTime", "11:00");
  if (!partial || has("checkIn")) fields.startDate = requireZonedTime(input.checkIn, "checkIn");
  if (!partial || has("checkOut")) fields.endDate = requireZonedTime(input.checkOut, "checkOut");
  const start = fields.startDate, end = fields.endDate;
  if (start instanceof FsTimestamp && end instanceof FsTimestamp && end.iso <= start.iso) {
    throw new HttpError(400, "checkOut must be after checkIn.");
  }
  return fields;
}

export function stayWrite(tripId: string, input: Record<string, unknown>, stayId = newId()): FsWrite {
  return {
    kind: "set",
    path: `trips/${tripId}/accommodations/${stayId}`,
    mustNotExist: true,
    fields: { ...stayFields(input), createdBy: "claude" },
  };
}

/** Trip document fields Claude may change. Only the fields passed change. */
export function tripUpdateFields(input: Record<string, unknown>): Record<string, FsInput | undefined> {
  const has = (key: string) => input[key] !== undefined;
  const fields: Record<string, FsInput | undefined> = {};
  if (has("name")) fields.name = text(input.name, "name");
  if (has("location")) fields.location = text(input.location, "location");
  if (has("startDate")) fields.startDate = requireZonedTime(input.startDate, "startDate");
  if (has("endDate")) fields.endDate = requireZonedTime(input.endDate, "endDate");
  if (has("budget")) fields.overallBudget = new FsDouble(optionalNumber(input.budget, "budget") ?? 0);
  if (has("currency")) fields.currency = currency(input.currency, "currency");
  if (has("description")) fields.tripDescription = text(input.description, "description", "");
  if (has("theme")) {
    const theme = text(input.theme, "theme");
    if (!(tripThemes as readonly string[]).includes(theme)) throw new HttpError(400, `theme must be one of ${tripThemes.join(", ")}.`);
    fields.theme = theme;
  }
  if (has("latitude") || has("longitude")) Object.assign(fields, optionalCoordinate(input.latitude, input.longitude, "the trip's location"));
  if (has("country")) fields.visitedCountry = text(input.country, "country", "");
  if (has("city")) fields.visitedCity = text(input.city, "city", "");
  return fields;
}

/**
 * TransportSegmentDTO fields from Claude's input. Departure and arrival come in
 * as local times with offset and are stored as the app does: a day plus "HH:mm".
 */
export function transportFields(
  input: Record<string, unknown>,
  partial: boolean,
  tripCurrency: string,
): Record<string, FsInput | undefined> {
  const has = (key: string) => input[key] !== undefined;
  const fields: Record<string, FsInput | undefined> = {};
  if (!partial || has("mode")) {
    const mode = text(input.mode, "mode");
    if (!(transportModes as readonly string[]).includes(mode)) throw new HttpError(400, `mode must be one of ${transportModes.join(", ")}.`);
    fields.mode = mode;
  }
  if (!partial || has("from")) fields.departureLocation = text(input.from, "from");
  if (!partial || has("to")) fields.arrivalLocation = text(input.to, "to");
  if (!partial || has("departure")) {
    const { day, time } = splitZonedTime(input.departure, "departure");
    fields.departureDate = day;
    fields.departureTime = time;
  }
  if (has("arrival")) {
    const { day, time } = splitZonedTime(input.arrival, "arrival");
    fields.arrivalDate = day;
    fields.arrivalTime = time;
  }
  if (has("departure") && has("arrival")) {
    if (requireZonedTime(input.arrival, "arrival").iso < requireZonedTime(input.departure, "departure").iso) {
      throw new HttpError(400, "arrival is before departure.");
    }
  }
  if (has("bookingRef")) fields.bookingRef = text(input.bookingRef, "bookingRef", "");
  if (has("seat")) fields.seatNumber = text(input.seat, "seat", "");
  if (has("notes")) fields.notes = text(input.notes, "notes", "");
  if (!partial || has("cost")) fields.cost = new FsDouble(optionalNumber(input.cost, "cost") ?? 0);
  if (!partial || has("currency")) fields.currency = has("currency") ? currency(input.currency, "currency") : tripCurrency;
  return fields;
}

/** DayNoteDTO fields. `day` is any local time that day, with offset; it's stored as local midnight. */
export function dayNoteFields(input: Record<string, unknown>, partial = false): Record<string, FsInput | undefined> {
  const has = (key: string) => input[key] !== undefined;
  const fields: Record<string, FsInput | undefined> = {};
  if (!partial || has("day")) fields.day = splitZonedTime(input.day, "day").day;
  if (!partial || has("title")) fields.title = text(input.title, "title", "");
  if (!partial || has("content")) fields.content = text(input.content, "content", "");
  return fields;
}
