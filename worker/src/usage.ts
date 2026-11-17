import { uidList } from "./auth";
import type { Env } from "./env";
import { cached, HttpError } from "./http";

/**
 * A daily allowance of Google calls per account, so opening the server to
 * everyone can't run up the Google bill. Only real Google calls count: cached
 * answers are free. A Google Cloud quota on the APIs is the hard backstop.
 */

export const defaultDailyLimit = 300;

export function dailyLimit(env: Pick<Env, "GOOGLE_DAILY_LIMIT">): number {
  const parsed = Number.parseInt(env.GOOGLE_DAILY_LIMIT ?? "", 10);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : defaultDailyLimit;
}

/** Adds `units` to today's count for this account, or throws 429 once it would pass the limit. */
export async function chargeGoogle(env: Pick<Env, "DB" | "GOOGLE_DAILY_LIMIT" | "UNLIMITED_UIDS">, uid: string, units = 1, now = new Date()): Promise<void> {
  if (uidList(env.UNLIMITED_UIDS).has(uid)) return;
  const limit = dailyLimit(env);
  const day = now.toISOString().slice(0, 10);
  const row = await env.DB.prepare(
    `INSERT INTO google_usage (uid, day, units) VALUES (?1, ?2, ?3)
     ON CONFLICT (uid, day) DO UPDATE SET units = units + ?3
     RETURNING units`,
  )
    .bind(uid, day, units)
    .first<{ units: number }>();
  if ((row?.units ?? units) > limit) {
    throw new HttpError(429, `You've reached today's limit of Google routes and place lookups (${limit}). It resets at midnight UTC.`);
  }
}

/**
 * `cached`, but a cache miss is charged to the account before Google is
 * called. Use for every call that reaches Google.
 */
export function googleCached<T>(
  env: Pick<Env, "DB" | "GOOGLE_DAILY_LIMIT" | "UNLIMITED_UIDS">,
  uid: string,
  units: number,
  namespace: string,
  key: unknown,
  ttlSeconds: number,
  load: () => Promise<T>,
): Promise<T> {
  return cached(namespace, key, ttlSeconds, async () => {
    await chargeGoogle(env, uid, units);
    return load();
  });
}

/** Google bills a route matrix per origin-destination pair. */
export function matrixUnits(points: number): number {
  return points * points;
}
