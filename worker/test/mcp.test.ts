import { describe, expect, it } from "vitest";
import type { Env } from "../src/env";
import { handleMcp, handleRpc, type McpContext, tools } from "../src/mcp";

const ctx: McpContext = {
  env: {} as Env,
  uid: "uid1",
  origin: "https://agdayo.example.com",
  firestore: () => {
    throw new Error("not used");
  },
};

describe("MCP", () => {
  it("negotiates the protocol version", async () => {
    const response = await handleRpc({ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-06-18" } }, ctx);
    expect(response).toMatchObject({ id: 1, result: { protocolVersion: "2025-06-18", serverInfo: { name: "agdayo" }, capabilities: { tools: {} } } });
    const unknown = await handleRpc({ jsonrpc: "2.0", id: 2, method: "initialize", params: { protocolVersion: "1999-01-01" } }, ctx);
    expect(unknown).toMatchObject({ result: { protocolVersion: "2025-11-25" } });
  });

  it("lists every tool with a schema, and marks write tools as not read-only", async () => {
    const response = await handleRpc({ jsonrpc: "2.0", id: 1, method: "tools/list" }, ctx);
    const listed = (response as { result: { tools: { name: string; inputSchema: { type: string }; annotations: { readOnlyHint?: boolean } }[] } }).result.tools;
    expect(listed.map((tool) => tool.name)).toEqual(tools.map((tool) => tool.name));
    for (const tool of listed) expect(tool.inputSchema.type).toBe("object");
    const writers = listed.filter((tool) => tool.annotations.readOnlyHint === false).map((tool) => tool.name);
    expect(writers.sort()).toEqual(["add_activities", "add_stay", "create_trip", "delete_activity", "save_guide", "update_activity"]);
  });

  it("returns tool input errors as results Claude can read", async () => {
    const response = await handleRpc({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "plan_route", arguments: { origin: {} } } }, ctx);
    expect(response).toMatchObject({ result: { isError: true, content: [{ type: "text", text: expect.stringContaining("origin") }] } });
  });

  it("answers unknown methods and tools with JSON-RPC errors", async () => {
    expect(await handleRpc({ jsonrpc: "2.0", id: 1, method: "resources/list" }, ctx)).toMatchObject({ error: { code: -32601 } });
    expect(await handleRpc({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "nope" } }, ctx)).toMatchObject({ error: { code: -32602 } });
  });

  it("accepts notifications with 202 and refuses GET", async () => {
    const env = {} as Env;
    const notification = new Request("https://x/mcp", { method: "POST", body: JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) });
    expect((await handleMcp(notification, env, "uid1")).status).toBe(202);
    expect((await handleMcp(new Request("https://x/mcp"), env, "uid1")).status).toBe(405);
    const ping = new Request("https://x/mcp", { method: "POST", body: JSON.stringify({ jsonrpc: "2.0", id: 7, method: "ping" }) });
    expect(await (await handleMcp(ping, env, "uid1")).json()).toEqual({ jsonrpc: "2.0", id: 7, result: {} });
  });
});
