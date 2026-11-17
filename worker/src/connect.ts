import type { Env } from "./env";

/**
 * Connect codes: a signed-in Agdayo app asks for a short code (POST
 * /v1/connect-code), and the person types it on the connector's sign-in page.
 * Works for every kind of Agdayo account (Apple, Google, email), with nothing
 * to set up on Apple's or Google's side.
 */

export const connectCodeTtlSeconds = 600;
/** Wrong codes allowed per sign-in attempt before it has to start again. */
export const maxCodeAttempts = 5;
const alphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
const codeLength = 8;

/** Eight characters from an alphabet without look-alikes (no 0/O, 1/I/L). */
export function newConnectCode(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(codeLength));
  return [...bytes].map((byte) => alphabet[byte % alphabet.length]).join("");
}

/** Upper-cases and drops spaces and dashes, so "abcd-2345" matches "ABCD2345". */
export function normalizeConnectCode(input: string): string {
  return input.toUpperCase().replace(/[\s-]/g, "");
}

export function formatConnectCode(code: string): string {
  return `${code.slice(0, 4)}-${code.slice(4)}`;
}

export async function createConnectCode(env: Pick<Env, "OAUTH_KV">, uid: string): Promise<string> {
  const code = newConnectCode();
  await env.OAUTH_KV.put(`connect:${code}`, uid, { expirationTtl: connectCodeTtlSeconds });
  return code;
}

/** The UID the code was made for, once; the code is used up either way. */
export async function redeemConnectCode(env: Pick<Env, "OAUTH_KV">, input: string): Promise<string | undefined> {
  const code = normalizeConnectCode(input);
  if (code.length !== codeLength || [...code].some((char) => !alphabet.includes(char))) return undefined;
  const key = `connect:${code}`;
  const uid = await env.OAUTH_KV.get(key);
  if (uid) await env.OAUTH_KV.delete(key);
  return uid ?? undefined;
}
