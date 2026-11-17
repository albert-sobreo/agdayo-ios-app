import { importPKCS8, SignJWT } from "jose";
import type { Env } from "./env";
import { HttpError } from "./http";

/**
 * Short-lived MapKit JS tokens for the web app's map. Signed with the MapKit JS
 * key from the Apple Developer account (secrets MAPKIT_TEAM_ID, MAPKIT_KEY_ID,
 * MAPKIT_PRIVATE_KEY). Locked to the page's origin, so a token can't be reused
 * on another site.
 */
export const mapkitTokenTtlSeconds = 30 * 60;

let cachedKey: { pem: string; key: CryptoKey } | null = null;

async function signingKey(pem: string): Promise<CryptoKey> {
  if (cachedKey?.pem === pem) return cachedKey.key;
  // Secrets pasted by hand sometimes lose their line breaks; jose needs the PEM shape.
  const body = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  const normalized = `-----BEGIN PRIVATE KEY-----\n${body.match(/.{1,64}/g)?.join("\n") ?? ""}\n-----END PRIVATE KEY-----`;
  const key = await importPKCS8(normalized, "ES256");
  cachedKey = { pem, key };
  return key;
}

export async function createMapkitToken(env: Env, origin: string | null): Promise<string> {
  if (!env.MAPKIT_TEAM_ID || !env.MAPKIT_KEY_ID || !env.MAPKIT_PRIVATE_KEY) {
    throw new HttpError(503, "The map isn't set up on the server yet.");
  }
  const now = Math.floor(Date.now() / 1000);
  const jwt = new SignJWT(origin ? { origin } : {})
    .setProtectedHeader({ alg: "ES256", kid: env.MAPKIT_KEY_ID, typ: "JWT" })
    .setIssuer(env.MAPKIT_TEAM_ID)
    .setIssuedAt(now)
    .setExpirationTime(now + mapkitTokenTtlSeconds);
  return jwt.sign(await signingKey(env.MAPKIT_PRIVATE_KEY));
}
