import type { AuthRequest } from "@cloudflare/workers-oauth-provider";
import { createRemoteJWKSet, jwtVerify } from "jose";
import { allowedUids } from "./auth";
import type { Env } from "./env";
import { HttpError } from "./http";

/**
 * Sign-in for the Claude connector. When the user adds Agdayo in Claude,
 * Claude opens /authorize; we send them to Google, check the Google account is
 * on ALLOWED_EMAILS, then hand Claude a token tied to the Firebase UID the
 * connector acts as. The OAuth provider library does the token side.
 */

/** What every connector token carries. Read back in the /mcp handler. */
export interface ConnectorProps {
  uid: string;
  email: string;
}

const googleKeys = createRemoteJWKSet(new URL("https://www.googleapis.com/oauth2/v3/certs"));
const pendingTtlSeconds = 600;

function list(value: string | undefined): string[] {
  return (value ?? "")
    .split(",")
    .map((item) => item.trim().toLowerCase())
    .filter(Boolean);
}

/**
 * Only Claude may receive tokens. Without this, anyone could register a client
 * with their own redirect address and trick the user into approving it.
 */
export function isAllowedRedirect(redirectUri: string, env: Pick<Env, "ALLOWED_REDIRECT_HOSTS">): boolean {
  let url: URL;
  try {
    url = new URL(redirectUri);
  } catch {
    return false;
  }
  const hosts = list(env.ALLOWED_REDIRECT_HOSTS || "claude.ai,claude.com");
  return url.protocol === "https:" && hosts.includes(url.hostname.toLowerCase());
}

/** The Firebase UID the connector reads and writes as: CONNECTOR_UID, or the only UID in ALLOWED_UIDS. */
export function connectorUid(env: Pick<Env, "CONNECTOR_UID" | "ALLOWED_UIDS">): string {
  const configured = env.CONNECTOR_UID?.trim();
  const allowed = allowedUids(env);
  if (configured) {
    if (!allowed.has(configured)) throw new HttpError(500, "CONNECTOR_UID must also be listed in ALLOWED_UIDS.");
    return configured;
  }
  if (allowed.size === 1) return [...allowed][0] as string;
  throw new HttpError(500, "Set CONNECTOR_UID, or list exactly one UID in ALLOWED_UIDS.");
}

function page(title: string, message: string, status: number): Response {
  const escape = (text: string) => text.replace(/[&<>"']/g, (char) => `&#${char.charCodeAt(0)};`);
  return new Response(
    `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>${escape(title)}</title>` +
      `<body style="font:16px system-ui;max-width:32rem;margin:4rem auto;padding:0 1rem"><h1 style="font-size:1.4rem">${escape(title)}</h1><p>${escape(message)}</p></body>`,
    { status, headers: { "content-type": "text/html; charset=utf-8" } },
  );
}

function callbackUrl(request: Request): string {
  return new URL("/callback", request.url).toString();
}

/** GET /authorize: checks Claude's request, then sends the user to Google. */
export async function authorize(request: Request, env: Env): Promise<Response> {
  let authRequest: AuthRequest;
  try {
    authRequest = await env.OAUTH_PROVIDER.parseAuthRequest(request);
  } catch {
    return page("Can't connect", "This sign-in link is invalid. Start again from Claude.", 400);
  }
  if (!isAllowedRedirect(authRequest.redirectUri, env)) {
    return page("Can't connect", "Only Claude can connect to Agdayo.", 400);
  }
  if (!env.GOOGLE_OAUTH_CLIENT_ID) return page("Not set up", "GOOGLE_OAUTH_CLIENT_ID isn't set on the server.", 500);

  const state = crypto.randomUUID();
  await env.OAUTH_KV.put(`pending:${state}`, JSON.stringify(authRequest), { expirationTtl: pendingTtlSeconds });
  const google = new URL("https://accounts.google.com/o/oauth2/v2/auth");
  google.searchParams.set("client_id", env.GOOGLE_OAUTH_CLIENT_ID);
  google.searchParams.set("redirect_uri", callbackUrl(request));
  google.searchParams.set("response_type", "code");
  google.searchParams.set("scope", "openid email");
  google.searchParams.set("state", state);
  google.searchParams.set("prompt", "select_account");
  return Response.redirect(google.toString(), 302);
}

/** GET /callback: Google sends the user back here. Checks the account and returns them to Claude. */
export async function callback(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const state = url.searchParams.get("state");
  const code = url.searchParams.get("code");
  if (!state || !code) return page("Sign-in cancelled", "Start again from Claude if you want to connect.", 400);

  const pending = await env.OAUTH_KV.get(`pending:${state}`);
  if (!pending) return page("Sign-in expired", "That took too long. Start again from Claude.", 400);
  await env.OAUTH_KV.delete(`pending:${state}`);
  const authRequest = JSON.parse(pending) as AuthRequest;

  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code,
      client_id: env.GOOGLE_OAUTH_CLIENT_ID,
      client_secret: env.GOOGLE_OAUTH_CLIENT_SECRET,
      redirect_uri: callbackUrl(request),
      grant_type: "authorization_code",
    }),
  });
  if (!tokenResponse.ok) {
    console.error("Google token error", tokenResponse.status, await tokenResponse.text());
    return page("Couldn't sign in", "Google didn't accept the sign-in. Try again.", 502);
  }
  const { id_token: idToken } = (await tokenResponse.json()) as { id_token?: string };
  if (!idToken) return page("Couldn't sign in", "Google didn't return an account.", 502);

  let email: string;
  try {
    const { payload } = await jwtVerify(idToken, googleKeys, {
      issuer: ["https://accounts.google.com", "accounts.google.com"],
      audience: env.GOOGLE_OAUTH_CLIENT_ID,
    });
    if (payload.email_verified !== true || typeof payload.email !== "string") throw new Error("unverified email");
    email = payload.email.toLowerCase();
  } catch {
    return page("Couldn't sign in", "Google's answer couldn't be verified. Try again.", 401);
  }
  if (!list(env.ALLOWED_EMAILS).includes(email)) {
    return page("Not allowed", `${email} isn't allowed to use this Agdayo server.`, 403);
  }

  let uid: string;
  try {
    uid = connectorUid(env);
  } catch (error) {
    return page("Not set up", error instanceof Error ? error.message : "Server isn't set up.", 500);
  }
  const props: ConnectorProps = { uid, email };
  const { redirectTo } = await env.OAUTH_PROVIDER.completeAuthorization({
    request: authRequest,
    userId: uid,
    metadata: { email },
    scope: authRequest.scope,
    props,
  });
  return Response.redirect(redirectTo, 302);
}
