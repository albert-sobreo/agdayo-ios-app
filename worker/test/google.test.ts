import { describe, expect, it } from "vitest";
import { normalizeMatrix, normalizePlace, normalizeRoute, parseDuration, parseMode } from "../src/google";

const now = new Date("2026-05-12T01:00:00Z");

describe("parseDuration", () => {
  it("reads Google's seconds strings", () => {
    expect(parseDuration("1080s")).toBe(1080);
    expect(parseDuration("12.6s")).toBe(13);
    expect(parseDuration(undefined)).toBe(0);
  });
});

describe("parseMode", () => {
  it("defaults to transit and rejects unknown modes", () => {
    expect(parseMode(undefined)).toBe("transit");
    expect(parseMode("walk")).toBe("walk");
    expect(() => parseMode("jeepney")).toThrow(/mode must be/);
  });
});

describe("normalizeRoute", () => {
  const route = {
    duration: "1080s",
    distanceMeters: 2600,
    travelAdvisory: { transitFare: { currencyCode: "SGD", units: "1", nanos: 590000000 } },
    localizedValues: { transitFare: { text: "S$1.59" } },
    legs: [
      {
        steps: [
          { travelMode: "WALK", staticDuration: "120s", distanceMeters: 150 },
          { travelMode: "WALK", staticDuration: "120s", distanceMeters: 150 },
          {
            travelMode: "TRANSIT",
            staticDuration: "240s",
            distanceMeters: 1900,
            transitDetails: {
              headsign: "Expo",
              stopCount: 2,
              stopDetails: {
                departureStop: { name: "Bugis" },
                arrivalStop: { name: "Bayfront" },
                departureTime: "2026-05-12T01:17:00Z",
                arrivalTime: "2026-05-12T01:21:00Z",
              },
              transitLine: {
                name: "Downtown Line",
                nameShort: "DT",
                color: "#005ec4",
                vehicle: { name: { text: "Subway" }, type: "SUBWAY" },
              },
            },
          },
          { travelMode: "WALK", staticDuration: "480s", distanceMeters: 400 },
        ],
      },
    ],
  };

  it("merges walking steps and keeps transit details", () => {
    const result = normalizeRoute(route, "transit", false, now);
    expect(result.durationSeconds).toBe(1080);
    expect(result.steps.map((step) => step.kind)).toEqual(["walk", "transit", "walk"]);
    expect(result.steps[0]).toMatchObject({ durationSeconds: 240, distanceMeters: 300 });
    expect(result.steps[1]?.transit).toMatchObject({
      lineName: "Downtown Line",
      lineShortName: "DT",
      vehicle: "Subway",
      departureStop: "Bugis",
      arrivalStop: "Bayfront",
      stopCount: 2,
      headsign: "Expo",
    });
    expect(result.fare).toEqual({ currency: "SGD", amount: 1.59, text: "S$1.59" });
    expect(result.source).toBe("Google");
    expect(result.fetchedAt).toBe(now.toISOString());
  });

  it("marks routes computed for a different time", () => {
    expect(normalizeRoute(route, "transit", true, now).timeAdjusted).toBe(true);
  });

  it("handles an empty route", () => {
    const result = normalizeRoute({}, "walk", false, now);
    expect(result).toMatchObject({ durationSeconds: 0, distanceMeters: 0, steps: [] });
    expect(result.fare).toBeUndefined();
  });
});

describe("normalizeMatrix", () => {
  it("fills cells, treating missing indexes as 0 and skipping cells without a route", () => {
    const matrix = normalizeMatrix(
      [
        { destinationIndex: 1, duration: "600s", distanceMeters: 1000, condition: "ROUTE_EXISTS" },
        { originIndex: 1, duration: "650s", distanceMeters: 1100, condition: "ROUTE_EXISTS" },
        { condition: "ROUTE_EXISTS", duration: "0s", distanceMeters: 0 },
        { originIndex: 1, destinationIndex: 1, condition: "ROUTE_NOT_FOUND" },
      ],
      2,
      "walk",
      now,
    );
    expect(matrix.durationSeconds).toEqual([
      [0, 600],
      [650, null],
    ]);
    expect(matrix.distanceMeters).toEqual([
      [0, 1000],
      [1100, null],
    ]);
  });
});

describe("normalizePlace", () => {
  it("keeps the useful fields", () => {
    expect(
      normalizePlace({
        id: "abc",
        displayName: { text: "Lau Pa Sat" },
        formattedAddress: "18 Raffles Quay",
        location: { latitude: 1.2807, longitude: 103.8504 },
        rating: 4.2,
        userRatingCount: 30000,
        priceLevel: "PRICE_LEVEL_INEXPENSIVE",
        primaryTypeDisplayName: { text: "Food court" },
        regularOpeningHours: { weekdayDescriptions: ["Monday: Open 24 hours"] },
        googleMapsUri: "https://maps.google.com/?cid=1",
      }),
    ).toEqual({
      id: "abc",
      name: "Lau Pa Sat",
      address: "18 Raffles Quay",
      location: { latitude: 1.2807, longitude: 103.8504 },
      rating: 4.2,
      ratingCount: 30000,
      priceLevel: "inexpensive",
      type: "Food court",
      openingHours: ["Monday: Open 24 hours"],
      mapsUrl: "https://maps.google.com/?cid=1",
    });
  });

  it("keeps opening periods for checking a time", () => {
    const place = normalizePlace({
      id: "bencab",
      displayName: { text: "BenCab Museum" },
      regularOpeningHours: {
        periods: [
          { open: { day: 2, hour: 9 }, close: { day: 2, hour: 17, minute: 30 } },
          { open: { day: 0, hour: 0, minute: 0 } },
          { close: { day: 3, hour: 1 } },
        ],
      },
      utcOffsetMinutes: 480,
    });
    expect(place.openingPeriods).toEqual([
      { open: { day: 2, hour: 9, minute: 0 }, close: { day: 2, hour: 17, minute: 30 } },
      { open: { day: 0, hour: 0, minute: 0 } },
    ]);
    expect(place.utcOffsetMinutes).toBe(480);
  });
});
