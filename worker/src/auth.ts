import { createRemoteJWKSet, jwtVerify } from "jose";
import type { Env } from "./env";
import { HttpError } from "./http";

/** Google's public keys for Firebase Auth ID tokens. Cached per isolate by jose. */
const firebaseKeys = createRemoteJWKSet(
  new URL("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"),
);

/** The UIDs in `ALLOWED_UIDS`, trimmed. An empty list allows nobody. */
export function allowedUids(env: Pick<Env, "ALLOWED_UIDS">): Set<string> {
  return new Set(
    env.ALLOWED_UIDS.split(",")
      .map((uid) => uid.trim())
      .filter(Boolean),
  );
}

/**
 * Checks the `Authorization: Bearer <Firebase ID token>` header the app sends
 * and returns the signed-in user's UID. Only UIDs listed in `ALLOWED_UIDS`
 * get through, since this server spends your Google quota.
 */
export async function requireUser(request: Request, env: Env): Promise<string> {
  const header = request.headers.get("authorization") ?? "";
  const match = /^Bearer\s+(.+)$/i.exec(header);
  if (!match?.[1]) throw new HttpError(401, "Sign in to use this server.");

  let uid: string | undefined;
  try {
    const { payload } = await jwtVerify(match[1], firebaseKeys, {
      issuer: `https://securetoken.google.com/${env.FIREBASE_PROJECT_ID}`,
      audience: env.FIREBASE_PROJECT_ID,
    });
    uid = payload.sub;
  } catch {
    throw new HttpError(401, "Your sign-in has expired or is invalid. Sign in again.");
  }
  if (!uid || !allowedUids(env).has(uid)) {
    throw new HttpError(403, "This account isn't allowed to use this server.");
  }
  return uid;
}
