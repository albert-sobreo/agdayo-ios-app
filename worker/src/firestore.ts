import { importPKCS8, SignJWT } from "jose";
import { HttpError } from "./http";

/**
 * A small Firestore REST client that signs in as a service account, so the
 * connector can read and write the same documents the app syncs. Service
 * accounts skip security rules, so every caller checks trip membership first.
 */

/** Wraps a number that must be stored as a double, even when it's whole (e.g. a cost of 20). */
export class FsDouble {
  constructor(readonly value: number) {}
}

/** Marks a value to be written as a Firestore timestamp. */
export class FsTimestamp {
  constructor(readonly iso: string) {}
}

export type FsInput =
  | null
  | boolean
  | number
  | string
  | FsDouble
  | FsTimestamp
  | FsInput[]
  | { [key: string]: FsInput | undefined };

export type FsValue =
  | { nullValue: null }
  | { booleanValue: boolean }
  | { integerValue: string }
  | { doubleValue: number }
  | { stringValue: string }
  | { timestampValue: string }
  | { arrayValue: { values?: FsValue[] } }
  | { mapValue: { fields?: Record<string, FsValue> } }
  | { referenceValue: string }
  | { geoPointValue: { latitude: number; longitude: number } }
  | { bytesValue: string };

export function encodeValue(value: FsInput): FsValue {
  if (value === null) return { nullValue: null };
  if (value instanceof FsDouble) return { doubleValue: value.value };
  if (value instanceof FsTimestamp) return { timestampValue: value.iso };
  if (typeof value === "boolean") return { booleanValue: value };
  if (typeof value === "number") {
    return Number.isInteger(value) ? { integerValue: String(value) } : { doubleValue: value };
  }
  if (typeof value === "string") return { stringValue: value };
  if (Array.isArray(value)) return { arrayValue: { values: value.map(encodeValue) } };
  return { mapValue: { fields: encodeFields(value) } };
}

/** Encodes an object's fields, leaving out undefined ones. */
export function encodeFields(object: Record<string, FsInput | undefined>): Record<string, FsValue> {
  const fields: Record<string, FsValue> = {};
  for (const [key, value] of Object.entries(object)) {
    if (value !== undefined) fields[key] = encodeValue(value);
  }
  return fields;
}

/** Turns a Firestore value into plain JSON. Timestamps become ISO 8601 strings. */
export function decodeValue(value: FsValue): unknown {
  if ("nullValue" in value) return null;
  if ("booleanValue" in value) return value.booleanValue;
  if ("integerValue" in value) return Number(value.integerValue);
  if ("doubleValue" in value) return value.doubleValue;
  if ("stringValue" in value) return value.stringValue;
  if ("timestampValue" in value) return new Date(value.timestampValue).toISOString();
  if ("arrayValue" in value) return (value.arrayValue.values ?? []).map(decodeValue);
  if ("mapValue" in value) return decodeFields(value.mapValue.fields ?? {});
  if ("referenceValue" in value) return value.referenceValue;
  if ("geoPointValue" in value) return value.geoPointValue;
  return null;
}

export function decodeFields(fields: Record<string, FsValue>): Record<string, unknown> {
  const result: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(fields)) result[key] = decodeValue(value);
  return result;
}

export interface FsDocument {
  /** The last path segment, e.g. the activity's UUID. */
  id: string;
  data: Record<string, unknown>;
}

interface RawDocument {
  name: string;
  fields?: Record<string, FsValue>;
}

function toDocument(raw: RawDocument): FsDocument {
  return { id: raw.name.slice(raw.name.lastIndexOf("/") + 1), data: decodeFields(raw.fields ?? {}) };
}

/** One write in an atomic commit. Paths are relative, like "trips/ABC/activities/DEF". */
export type FsWrite =
  | {
      kind: "set";
      path: string;
      fields: Record<string, FsInput | undefined>;
      /** Fields to set to the server's time, like FieldValue.serverTimestamp(). */
      serverTimestamps?: string[];
      /** Fail if the document already exists. */
      mustNotExist?: boolean;
    }
  | {
      kind: "update";
      path: string;
      fields: Record<string, FsInput | undefined>;
      /** Fields to remove. */
      remove?: string[];
      serverTimestamps?: string[];
    }
  | { kind: "arrayUnion"; path: string; field: string; values: string[] }
  | { kind: "delete"; path: string };

export interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

export function parseServiceAccount(json: string | undefined): ServiceAccount {
  if (!json) throw new HttpError(500, "FIREBASE_SERVICE_ACCOUNT isn't set on the server.");
  let parsed: Partial<ServiceAccount>;
  try {
    parsed = JSON.parse(json) as Partial<ServiceAccount>;
  } catch {
    throw new HttpError(500, "FIREBASE_SERVICE_ACCOUNT isn't valid JSON.");
  }
  if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
    throw new HttpError(500, "FIREBASE_SERVICE_ACCOUNT is missing project_id, client_email or private_key.");
  }
  return parsed as ServiceAccount;
}

const tokenCache = new Map<string, { token: string; expiresAt: number }>();

/**
 * A self-signed JWT for the service account. Google APIs accept these
 * directly as bearer tokens, so there's no token exchange round trip.
 */
async function accessToken(account: ServiceAccount, audience: string): Promise<string> {
  const key = `${account.client_email}|${audience}`;
  const hit = tokenCache.get(key);
  const now = Math.floor(Date.now() / 1000);
  if (hit && hit.expiresAt - 300 > now) return hit.token;
  const privateKey = await importPKCS8(account.private_key, "RS256");
  const token = await new SignJWT({})
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(account.client_email)
    .setSubject(account.client_email)
    .setAudience(audience)
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(privateKey);
  tokenCache.set(key, { token, expiresAt: now + 3600 });
  return token;
}

export class Firestore {
  private readonly root: string;
  private readonly documentsUrl: string;

  constructor(
    private readonly account: ServiceAccount,
    private readonly fetcher: typeof fetch = fetch,
  ) {
    this.root = `projects/${account.project_id}/databases/(default)/documents`;
    this.documentsUrl = `https://firestore.googleapis.com/v1/${this.root}`;
  }

  /** The full resource name for a relative path. */
  name(path: string): string {
    return `${this.root}/${path}`;
  }

  private async request(url: string, init: RequestInit = {}): Promise<Response> {
    const token = await accessToken(this.account, "https://firestore.googleapis.com/");
    const response = await this.fetcher(url, {
      ...init,
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json", ...init.headers },
    });
    if (!response.ok && response.status !== 404) {
      const text = await response.text();
      console.error("Firestore error", response.status, text);
      if (response.status === 409 || text.includes("ALREADY_EXISTS")) {
        throw new HttpError(409, "That record already exists.");
      }
      if (text.includes("NOT_FOUND")) throw new HttpError(404, "That record doesn't exist.");
      throw new HttpError(502, `Firestore answered ${response.status}.`);
    }
    return response;
  }

  async get(path: string): Promise<FsDocument | null> {
    const response = await this.request(`${this.documentsUrl}/${path}`);
    if (response.status === 404) return null;
    return toDocument((await response.json()) as RawDocument);
  }

  /** Fetches several documents by path; missing ones are left out. */
  async getAll(paths: string[]): Promise<FsDocument[]> {
    if (paths.length === 0) return [];
    const response = await this.request(`${this.documentsUrl}:batchGet`, {
      method: "POST",
      body: JSON.stringify({ documents: paths.map((path) => this.name(path)) }),
    });
    const results = (await response.json()) as { found?: RawDocument }[];
    return results.flatMap((result) => (result.found ? [toDocument(result.found)] : []));
  }

  /** Every document in a collection, following pages. */
  async list(collectionPath: string): Promise<FsDocument[]> {
    const documents: FsDocument[] = [];
    let pageToken: string | undefined;
    do {
      const url = new URL(`${this.documentsUrl}/${collectionPath}`);
      url.searchParams.set("pageSize", "300");
      if (pageToken) url.searchParams.set("pageToken", pageToken);
      const response = await this.request(url.toString());
      if (response.status === 404) return documents;
      const page = (await response.json()) as { documents?: RawDocument[]; nextPageToken?: string };
      documents.push(...(page.documents ?? []).map(toDocument));
      pageToken = page.nextPageToken;
    } while (pageToken);
    return documents;
  }

  /** Applies writes atomically: all of them land, or none do. */
  async commit(writes: FsWrite[]): Promise<void> {
    if (writes.length === 0) return;
    if (writes.length > 500) throw new HttpError(400, "Too many changes at once (500 max).");
    await this.request(`${this.documentsUrl}:commit`, {
      method: "POST",
      body: JSON.stringify({ writes: writes.map((write) => this.encodeWrite(write)) }),
    });
  }

  encodeWrite(write: FsWrite): Record<string, unknown> {
    const name = this.name(write.path);
    const timestamps = (fields: string[] | undefined) =>
      fields?.length ? { updateTransforms: fields.map((fieldPath) => ({ fieldPath, setToServerValue: "REQUEST_TIME" })) } : {};
    switch (write.kind) {
      case "set":
        return {
          update: { name, fields: encodeFields(write.fields) },
          ...timestamps(write.serverTimestamps),
          ...(write.mustNotExist ? { currentDocument: { exists: false } } : {}),
        };
      case "update": {
        const fieldPaths = [
          ...Object.keys(write.fields).filter((key) => write.fields[key] !== undefined),
          ...(write.remove ?? []),
        ];
        return {
          update: { name, fields: encodeFields(write.fields) },
          updateMask: { fieldPaths },
          ...timestamps(write.serverTimestamps),
          currentDocument: { exists: true },
        };
      }
      case "arrayUnion":
        // Empty mask: creates the document if needed and touches only this array.
        return {
          update: { name, fields: {} },
          updateMask: { fieldPaths: [] },
          updateTransforms: [
            { fieldPath: write.field, appendMissingElements: { values: write.values.map(encodeValue) } },
          ],
        };
      case "delete":
        return { delete: name };
    }
  }
}
