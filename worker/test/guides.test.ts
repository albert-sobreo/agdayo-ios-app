import { describe, expect, it } from "vitest";
import { parseCountryCode, parseGuide } from "../src/guides";

const now = new Date("2026-11-04T00:00:00Z");

describe("parseCountryCode", () => {
  it("accepts two letters in any case", () => {
    expect(parseCountryCode("sg")).toBe("SG");
    expect(() => parseCountryCode("SGP")).toThrow(/two-letter/);
  });
});

describe("parseGuide", () => {
  const valid = {
    title: "Singapore",
    sections: [
      {
        id: "getting-around",
        title: "Getting around",
        items: [{ text: "Tap a contactless card on MRT and buses.", source: "https://www.transitlink.com.sg" }],
      },
    ],
    sources: [{ title: "Transitlink", url: "https://www.transitlink.com.sg" }],
    checkedAt: "2026-11-02T00:00:00Z",
  };

  it("accepts a well-formed guide", () => {
    const guide = parseGuide("SG", valid, now);
    expect(guide.title).toBe("Singapore");
    expect(guide.sections[0]?.items[0]?.source).toBe("https://www.transitlink.com.sg");
    expect(guide.checkedAt).toBe("2026-11-02T00:00:00.000Z");
    expect(guide.updatedAt).toBe(now.toISOString());
  });

  it("rejects guides without sections or with bad sources", () => {
    expect(() => parseGuide("SG", { ...valid, sections: [] }, now)).toThrow(/sections/);
    expect(() => parseGuide("SG", { ...valid, sources: [{ title: "x", url: "ftp://x" }] }, now)).toThrow(/sources\[0\]/);
  });

  it("defaults checkedAt to now", () => {
    const { checkedAt, ...rest } = valid;
    void checkedAt;
    expect(parseGuide("SG", rest, now).checkedAt).toBe(now.toISOString());
  });
});
