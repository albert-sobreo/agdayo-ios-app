import { describe, expect, it } from "vitest";
import { isAllowedUid, uidList } from "../src/auth";

describe("uidList", () => {
  it("splits and trims", () => {
    expect([...uidList(" a , b,,")]).toEqual(["a", "b"]);
    expect(uidList("").size).toBe(0);
    expect(uidList(undefined).size).toBe(0);
  });
});

describe("isAllowedUid", () => {
  it("lets everyone in with *, except blocked accounts", () => {
    expect(isAllowedUid({ ALLOWED_UIDS: "*" }, "anyone")).toBe(true);
    expect(isAllowedUid({ ALLOWED_UIDS: "*", BLOCKED_UIDS: "bad" }, "bad")).toBe(false);
    expect(isAllowedUid({ ALLOWED_UIDS: "*" }, "")).toBe(false);
  });

  it("otherwise only listed accounts, and empty allows nobody", () => {
    expect(isAllowedUid({ ALLOWED_UIDS: "a,b" }, "b")).toBe(true);
    expect(isAllowedUid({ ALLOWED_UIDS: "a,b" }, "c")).toBe(false);
    expect(isAllowedUid({ ALLOWED_UIDS: "" }, "a")).toBe(false);
  });
});
