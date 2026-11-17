import { describe, expect, it } from "vitest";
import { choicePage, isAllowedRedirect } from "../src/oauth";

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

describe("choicePage", () => {
  it("offers a code and Google, and escapes the state", async () => {
    const response = choicePage('x"><script>', "Wrong code");
    expect(response.status).toBe(400);
    const body = await response.text();
    expect(body).toContain('action="/authorize/code"');
    expect(body).toContain("/authorize/google?state=x%22%3E%3Cscript%3E");
    expect(body).not.toContain('x"><script>');
    expect(choicePage("s").status).toBe(200);
  });
});
