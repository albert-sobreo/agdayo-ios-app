import { describe, expect, it } from "vitest";
import { createConnectCode, formatConnectCode, newConnectCode, normalizeConnectCode, redeemConnectCode } from "../src/connect";

function memoryKv() {
  const store = new Map<string, string>();
  return {
    store,
    kv: {
      get: async (key: string) => store.get(key) ?? null,
      put: async (key: string, value: string) => void store.set(key, value),
      delete: async (key: string) => void store.delete(key),
    } as unknown as KVNamespace,
  };
}

describe("connect codes", () => {
  it("are eight characters without look-alikes", () => {
    for (let i = 0; i < 50; i++) expect(newConnectCode()).toMatch(/^[2-9A-HJ-NP-Z]{8}$/);
    expect(formatConnectCode("ABCD2345")).toBe("ABCD-2345");
    expect(normalizeConnectCode(" abcd-2345 ")).toBe("ABCD2345");
  });

  it("work once, for the account that made them", async () => {
    const { kv, store } = memoryKv();
    const code = await createConnectCode({ OAUTH_KV: kv }, "uid1");
    expect(await redeemConnectCode({ OAUTH_KV: kv }, "nope")).toBeUndefined();
    expect(await redeemConnectCode({ OAUTH_KV: kv }, formatConnectCode(code).toLowerCase())).toBe("uid1");
    expect(await redeemConnectCode({ OAUTH_KV: kv }, code)).toBeUndefined();
    expect(store.size).toBe(0);
  });
});
