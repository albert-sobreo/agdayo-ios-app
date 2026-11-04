import { describe, expect, it } from "vitest";
import { connectorUid, isAllowedRedirect } from "../src/oauth";

describe("isAllowedRedirect", () => {
  it("only lets Claude receive tokens", () => {
    expect(isAllowedRedirect("https://claude.ai/api/mcp/auth_callback", {})).toBe(true);
    expect(isAllowedRedirect("https://claude.com/api/mcp/auth_callback", {})).toBe(true);
    expect(isAllowedRedirect("https://evil.example/cb", {})).toBe(false);
    expect(isAllowedRedirect("http://claude.ai/cb", {})).toBe(false);
    expect(isAllowedRedirect("https://claude.ai.evil.example/cb", {})).toBe(false);
    expect(isAllowedRedirect("https://other.example/cb", { ALLOWED_REDIRECT_HOSTS: "other.example" })).toBe(true);
  });
});

describe("connectorUid", () => {
  it("uses CONNECTOR_UID, or the only allowed UID", () => {
    expect(connectorUid({ ALLOWED_UIDS: "abc" })).toBe("abc");
    expect(connectorUid({ ALLOWED_UIDS: "abc,def", CONNECTOR_UID: "def" })).toBe("def");
    expect(() => connectorUid({ ALLOWED_UIDS: "abc,def" })).toThrow(/CONNECTOR_UID/);
    expect(() => connectorUid({ ALLOWED_UIDS: "abc", CONNECTOR_UID: "zzz" })).toThrow(/ALLOWED_UIDS/);
    expect(() => connectorUid({ ALLOWED_UIDS: "" })).toThrow();
  });
});
