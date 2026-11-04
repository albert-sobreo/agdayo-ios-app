import { describe, expect, it } from "vitest";
import { FsDouble, FsTimestamp } from "../src/firestore";
import { activityFields, addActivitiesWrites, createTripWrites, joinCode, requireZonedTime, stayWrite } from "../src/trips";

describe("requireZonedTime", () => {
  it("needs a UTC offset so times land on the right hour", () => {
    expect(requireZonedTime("2026-12-10T09:00:00+08:00", "time")).toEqual(new FsTimestamp("2026-12-10T01:00:00.000Z"));
    expect(requireZonedTime("2026-12-10T09:00Z", "time").iso).toBe("2026-12-10T09:00:00.000Z");
    expect(() => requireZonedTime("2026-12-10T09:00:00", "time")).toThrow(/UTC offset/);
    expect(() => requireZonedTime("tomorrow", "time")).toThrow();
  });
});

describe("joinCode", () => {
  it("uses the app's alphabet and length", () => {
    expect(joinCode()).toMatch(/^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{6}$/);
  });
});

describe("createTripWrites", () => {
  it("writes the trip, join code, owner membership and the user's trip list together", () => {
    const writes = createTripWrites(
      "uid1",
      { name: "Singapore", location: "Singapore", startDate: "2026-12-10T00:00:00+08:00", endDate: "2026-12-14T00:00:00+08:00", currency: "sgd" },
      "TRIP",
      "ABC234",
    );
    expect(writes.map((write) => [write.kind, write.path])).toEqual([
      ["set", "trips/TRIP"],
      ["set", "tripJoinCodes/ABC234"],
      ["set", "trips/TRIP/members/uid1"],
      ["arrayUnion", "users/uid1"],
    ]);
    const trip = writes[0];
    expect(trip?.kind === "set" && trip.fields).toMatchObject({
      ownerUID: "uid1",
      currency: "SGD",
      theme: "teal",
      overallBudget: new FsDouble(0),
      tripDescription: "",
      joinCode: "ABC234",
      createdBy: "claude",
    });
  });

  it("rejects an end before the start and unknown themes", () => {
    const base = { name: "x", location: "x", startDate: "2026-12-10T00:00:00+08:00", endDate: "2026-12-14T00:00:00+08:00", currency: "SGD" };
    expect(() => createTripWrites("u", { ...base, endDate: "2026-12-01T00:00:00+08:00" })).toThrow(/before/);
    expect(() => createTripWrites("u", { ...base, theme: "neon" })).toThrow(/theme/);
  });
});

describe("activities", () => {
  it("fills the fields the app requires and marks Claude's items", () => {
    const { writes, ids } = addActivitiesWrites("TRIP", [
      { title: "Gardens by the Bay", location: "18 Marina Gardens Dr", latitude: 1.2816, longitude: 103.8636, time: "2026-12-10T18:00:00+08:00", cost: 20, costCurrency: "sgd" },
    ]);
    expect(ids).toHaveLength(1);
    const write = writes[0];
    expect(write?.path).toBe(`trips/TRIP/activities/${ids[0]}`);
    expect(write?.kind === "set" && write.fields).toEqual({
      title: "Gardens by the Bay",
      location: "18 Marina Gardens Dr",
      date: new FsTimestamp("2026-12-10T10:00:00.000Z"),
      activityDescription: "",
      iconName: "mappin.and.ellipse",
      latitude: new FsDouble(1.2816),
      longitude: new FsDouble(103.8636),
      cost: new FsDouble(20),
      costCurrency: "SGD",
      createdBy: "claude",
    });
  });

  it("says which activity is wrong", () => {
    expect(() => addActivitiesWrites("T", [{ title: "ok", location: "x", time: "2026-12-10T09:00:00+08:00" }, { title: "no time", location: "x" }])).toThrow(
      /activities\[1\]: time/,
    );
  });

  it("updates only what was passed", () => {
    expect(activityFields({ time: "2026-12-10T10:00:00+08:00" }, true)).toEqual({ date: new FsTimestamp("2026-12-10T02:00:00.000Z") });
  });
});

describe("stayWrite", () => {
  it("writes an AccommodationDTO with defaults", () => {
    const write = stayWrite(
      "TRIP",
      { name: "Hotel", location: "1 Road", latitude: 1.3, longitude: 103.8, checkIn: "2026-12-10T15:00:00+08:00", checkOut: "2026-12-14T11:00:00+08:00" },
      "STAY",
    );
    expect(write.path).toBe("trips/TRIP/accommodations/STAY");
    expect(write.kind === "set" && write.fields).toMatchObject({ type: "hotel", numberOfRooms: 1, totalCost: new FsDouble(0), checkInTime: "15:00", checkOutTime: "11:00" });
  });
});
