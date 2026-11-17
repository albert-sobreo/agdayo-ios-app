import { describe, expect, it } from "vitest";
import { FsDouble, FsTimestamp } from "../src/firestore";
import {
  activityFields,
  addActivitiesWrites,
  budgetCategoryFields,
  categoryChange,
  createTripWrites,
  dayNoteFields,
  joinCode,
  requireZonedTime,
  splitZonedTime,
  stayFields,
  stayWrite,
  transportFields,
  tripAllowance,
  tripUpdateFields,
} from "../src/trips";

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

describe("editing", () => {
  it("splits a local time into the app's day and HH:mm", () => {
    expect(splitZonedTime("2026-11-11T08:30:00+08:00", "departure")).toEqual({
      day: new FsTimestamp("2026-11-10T16:00:00.000Z"),
      time: "08:30",
    });
    expect(() => splitZonedTime("2026-11-11T08:30", "departure")).toThrow(/UTC offset/);
  });

  it("changes only the trip fields passed", () => {
    expect(tripUpdateFields({ name: "Baguio again", budget: 5000 })).toEqual({ name: "Baguio again", overallBudget: new FsDouble(5000) });
    expect(() => tripUpdateFields({ theme: "neon" })).toThrow(/theme/);
  });

  it("updates part of a stay and still checks the dates", () => {
    expect(stayFields({ checkOutTime: "12:00" }, true)).toEqual({ checkOutTime: "12:00" });
    expect(() =>
      stayFields({ checkIn: "2026-11-18T15:00:00+08:00", checkOut: "2026-11-16T11:00:00+08:00" }, true),
    ).toThrow(/after checkIn/);
  });

  it("writes transport the way the app stores it", () => {
    const fields = transportFields(
      {
        mode: "flight",
        from: "Manila (MNL)",
        to: "Singapore (SIN)",
        departure: "2026-11-11T08:30:00+08:00",
        arrival: "2026-11-11T12:20:00+08:00",
        bookingRef: "ABC123",
        seat: "14A",
      },
      false,
      "SGD",
    );
    expect(fields).toMatchObject({
      mode: "flight",
      departureLocation: "Manila (MNL)",
      arrivalLocation: "Singapore (SIN)",
      departureTime: "08:30",
      arrivalTime: "12:20",
      bookingRef: "ABC123",
      seatNumber: "14A",
      cost: new FsDouble(0),
      currency: "SGD",
    });
    expect(() => transportFields({ mode: "spaceship", from: "a", to: "b", departure: "2026-11-11T08:30:00+08:00" }, false, "PHP")).toThrow(/mode/);
    expect(() =>
      transportFields({ departure: "2026-11-11T08:30:00+08:00", arrival: "2026-11-11T07:00:00+08:00" }, true, "PHP"),
    ).toThrow(/before departure/);
    expect(transportFields({ seat: "2C" }, true, "")).toEqual({ seatNumber: "2C" });
    expect(transportFields({ toLatitude: 1.3644, toLongitude: 103.9915 }, true, "")).toEqual({
      arrivalLatitude: new FsDouble(1.3644),
      arrivalLongitude: new FsDouble(103.9915),
    });
    expect(() => transportFields({ fromLatitude: 14.5 }, true, "")).toThrow(/latitude and longitude/);
  });

  it("stores a day note on local midnight", () => {
    expect(dayNoteFields({ day: "2026-11-16T21:00:00+08:00", title: "Night market", content: "Bring cash" })).toEqual({
      day: new FsTimestamp("2026-11-15T16:00:00.000Z"),
      title: "Night market",
      content: "Bring cash",
    });
  });

  it("keeps the Google place ID on activities", () => {
  });
});

describe("trip updates", () => {
  it("rejects an end date before the start date", () => {
    expect(() => tripUpdateFields({ startDate: "2026-11-18T00:00:00+08:00", endDate: "2026-11-16T00:00:00+08:00" })).toThrow(
      /before startDate/,
    );
  });
});

describe("tripAllowance", () => {
  const trip = (ownerUID: string, ownerUnlocked?: boolean) => ({ id: "T", name: "", data: { ownerUID, ...(ownerUnlocked === undefined ? {} : { ownerUnlocked }) } });

  it("counts only owned trips, and a trip without the flag means unlocked", () => {
    expect(tripAllowance("me", [trip("me", false), trip("other", true), trip("me", false)])).toEqual({ owned: 2, unlocked: false });
    expect(tripAllowance("me", [trip("me", false), trip("me")])).toEqual({ owned: 2, unlocked: true });
    expect(tripAllowance("me", [])).toEqual({ owned: 0, unlocked: false });
  });

  it("writes ownerUnlocked from the allowance", () => {
    const input = { name: "X", location: "X", startDate: "2026-12-10T00:00:00+08:00", endDate: "2026-12-11T00:00:00+08:00", currency: "PHP" };
    const [locked] = createTripWrites("me", input, "TRIP", "ABC234");
    const [unlocked] = createTripWrites("me", input, "TRIP", "ABC234", true);
    expect((locked as { fields: Record<string, unknown> }).fields.ownerUnlocked).toBe(false);
    expect((unlocked as { fields: Record<string, unknown> }).fields.ownerUnlocked).toBe(true);
  });
});

describe("budget categories", () => {
  const categoryId = "6F1C2A3B-4D5E-4F60-8A7B-9C0D1E2F3A4B";

  it("puts a cost under a category and out of any person's budget", () => {
    expect(categoryChange(categoryId)).toEqual({ fields: { budgetCategoryID: categoryId }, remove: ["budgetMemberUID"] });
  });

  it("takes a cost out of its category with an empty string, and leaves it alone when not passed", () => {
    expect(categoryChange("")).toEqual({ fields: {}, remove: ["budgetCategoryID"] });
    expect(categoryChange(undefined)).toBeUndefined();
    expect(() => categoryChange("Food")).toThrow(/categoryId from get_trip/);
  });

  it("sets the category on activities added in one go", () => {
    const { writes } = addActivitiesWrites("TRIP", [
      { title: "Lunch", location: "Maxwell", time: "2026-12-10T12:00:00+08:00", cost: 10, budgetCategoryId: categoryId },
    ]);
    expect(writes[0]).toMatchObject({ kind: "set", fields: { budgetCategoryID: categoryId } });
  });

  it("stores the planned amount as a double", () => {
    expect(budgetCategoryFields({ name: " Food ", amount: 200 })).toEqual({ name: "Food", amount: new FsDouble(200) });
    expect(budgetCategoryFields({ amount: 50 }, true)).toEqual({ amount: new FsDouble(50) });
  });
});
