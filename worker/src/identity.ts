import { importPKCS8, SignJWT } from "jose";
import type { ServiceAccount } from "./firestore";
import { HttpError } from "./http";

/**
 * Finds the Agdayo (Firebase) account a Google sign-in belongs to, so each
 * person's connector acts as their own account. Uses the Firebase Auth admin
 * API with the service account that also reads trips.
 */

interface LookupUser {
  localId: string;
  disabled?: boolean;
  providerUserInfo?: { providerId?: string; email?: string }[];
}

let cachedToken: { key: string; token: string; expiresAt: number } | undefined;

/** An OAuth access token for the service account (JWT bearer grant). */
async function adminToken(account: ServiceAccount, fetcher: typeof fetch): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.key === account.client_email && cachedToken.expiresAt - 300 > now) return cachedToken.token;
  const assertion = await new SignJWT({ scope: "https://www.googleapis.com/auth/identitytoolkit https://www.googleapis.com/auth/cloud-platform" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(account.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(await importPKCS8(account.private_key, "RS256"));
  const response = await fetcher("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!response.ok) {
    console.error("Service account token error", response.status, await response.text());
    throw new HttpError(502, "The server couldn't reach Firebase.");
  }
  const { access_token: token, expires_in: expiresIn } = (await response.json()) as { access_token: string; expires_in?: number };
  cachedToken = { key: account.client_email, token, expiresAt: now + (expiresIn ?? 3600) };
  return token;
}

/** The account in a lookup answer that signs in with this Google address, if any. */
export function pickGoogleAccount(users: LookupUser[] | undefined, email: string): string | undefined {
  const wanted = email.toLowerCase();
  const match = (users ?? []).find(
    (user) =>
      !user.disabled &&
      (user.providerUserInfo ?? []).some((info) => info.providerId === "google.com" && info.email?.toLowerCase() === wanted),
  );
  return match?.localId;
}

/**
 * The Firebase UID of the Agdayo account that signs in with this Google
 * address, or undefined when there's none (for example an Apple or
 * email-and-password account). Only Google-linked accounts match, so an
 * unverified email account can't claim someone's Google address.
 */
export async function firebaseUidForGoogleEmail(
  account: ServiceAccount,
  email: string,
  fetcher: typeof fetch = (input, init) => fetch(input, init),
): Promise<string | undefined> {
  const token = await adminToken(account, fetcher);
  const response = await fetcher(`https://identitytoolkit.googleapis.com/v1/projects/${account.project_id}/accounts:lookup`, {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify({ email: [email] }),
  });
  if (!response.ok) {
    console.error("Firebase account lookup error", response.status, await response.text());
    throw new HttpError(502, "The server couldn't look up your Agdayo account.");
  }
  const { users } = (await response.json()) as { users?: LookupUser[] };
  return pickGoogleAccount(users, email);
}
