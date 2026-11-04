import { describe, expect, it } from "vitest";
import { HttpError } from "../src/http";
import { appLink, localDay, openPage, schemeUrl } from "../src/open";

const tripId = "55D69F87-4A05-41F5-AC8D-A7968371C17F";

describe("Open in Agdayo links", () => {
  it("builds the https link with an optional day", () => {
    expect(appLink("https://a.example", tripId)).toBe(`https://a.example/open/trip/${tripId}`);
    expect(appLink("https://a.example", tripId, "2026-11-16")).toBe(`https://a.example/open/trip/${tripId}?day=2026-11-16`);
    expect(appLink("https://a.example", tripId, "soon")).toBe(`https://a.example/open/trip/${tripId}`);
  });

  it("takes the local day from a time with offset", () => {
    expect(localDay("2026-11-16T21:00:00+08:00")).toBe("2026-11-16");
    expect(localDay(undefined)).toBeUndefined();
    expect(localDay("tomorrow")).toBeUndefined();
  });

  it("forwards to the app's scheme", () => {
    expect(schemeUrl(new URL(`https://a.example/open/trip/${tripId.toLowerCase()}?day=2026-11-17`))).toBe(
      `agdayo://trip/${tripId}?day=2026-11-17`,
    );
    expect(schemeUrl(new URL(`https://a.example/open/trip/${tripId}?day=<script>`))).toBe(`agdayo://trip/${tripId}`);
  });

  it("refuses anything that isn't a trip ID", () => {
    expect(() => schemeUrl(new URL("https://a.example/open/trip/javascript:alert(1)"))).toThrow(HttpError);
    expect(() => schemeUrl(new URL("https://a.example/open/trip/abc"))).toThrow(HttpError);
  });

  it("serves a page that opens the app", async () => {
    const response = openPage(new URL(`https://a.example/open/trip/${tripId}?day=2026-11-16`));
    expect(response.headers.get("content-type")).toContain("text/html");
    expect(await response.text()).toContain(`agdayo://trip/${tripId}?day=2026-11-16`);
  });
});
