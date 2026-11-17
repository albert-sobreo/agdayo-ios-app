import { describe, expect, it } from "vitest";
import { chargeGoogle, dailyLimit, matrixUnits } from "../src/usage";

/** Just enough of D1 for the upsert in chargeGoogle. */
function memoryDb() {
  const rows = new Map<string, number>();
  const db = {
    prepare: () => ({
      bind: (uid: string, day: string, units: number) => ({
        first: async () => {
          const key = `${uid}|${day}`;
          const total = (rows.get(key) ?? 0) + units;
          rows.set(key, total);
          return { units: total };
        },
      }),
    }),
  } as unknown as D1Database;
  return { db, rows };
}

describe("daily Google limit", () => {
  it("defaults to 300 and reads GOOGLE_DAILY_LIMIT", () => {
    expect(dailyLimit({})).toBe(300);
    expect(dailyLimit({ GOOGLE_DAILY_LIMIT: "5" })).toBe(5);
    expect(dailyLimit({ GOOGLE_DAILY_LIMIT: "x" })).toBe(300);
    expect(matrixUnits(10)).toBe(100);
  });

  it("refuses once an account passes its limit, per day", async () => {
    const { db } = memoryDb();
    const env = { DB: db, GOOGLE_DAILY_LIMIT: "3" };
    const day1 = new Date("2026-11-17T10:00:00Z");
    await chargeGoogle(env, "u", 2, day1);
    await chargeGoogle(env, "u", 1, day1);
    await expect(chargeGoogle(env, "u", 1, day1)).rejects.toMatchObject({ status: 429 });
    await chargeGoogle(env, "other", 1, day1);
    await chargeGoogle(env, "u", 1, new Date("2026-11-18T00:00:01Z"));
  });

  it("skips UNLIMITED_UIDS", async () => {
    const { db, rows } = memoryDb();
    await chargeGoogle({ DB: db, GOOGLE_DAILY_LIMIT: "0", UNLIMITED_UIDS: "me" }, "me", 50);
    expect(rows.size).toBe(0);
  });
});
