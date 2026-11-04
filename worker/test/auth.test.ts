import { describe, expect, it } from "vitest";
import { allowedUids } from "../src/auth";

describe("allowedUids", () => {
  it("splits and trims, and an empty value allows nobody", () => {
    expect([...allowedUids({ ALLOWED_UIDS: " a , b,," })]).toEqual(["a", "b"]);
    expect(allowedUids({ ALLOWED_UIDS: "" }).size).toBe(0);
  });
});
