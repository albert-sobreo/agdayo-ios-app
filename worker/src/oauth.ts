import type { AuthRequest } from "@cloudflare/workers-oauth-provider";
import { createRemoteJWKSet, jwtVerify } from "jose";
import { isAllowedUid } from "./auth";
import { maxCodeAttempts, redeemConnectCode } from "./connect";
import type { Env } from "./env";
import { parseServiceAccount } from "./firestore";
import { firebaseUidForGoogleEmail } from "./identity";

/**
 * Sign-in for the Claude connector. Anyone with an Agdayo account can connect
 * their own Claude, and the connector then acts as that account only. When the
 * person adds Agdayo in Claude, Claude opens /authorize, which offers two ways
 * to prove which Agdayo account is theirs:
 *
 * - A connect code from the Agdayo app (Profile › Connect Claude). Works for
 *   every account: Apple, Google, or email and password.
 * - Signing in with Google, for accounts that sign in to Agdayo with Google.
 *
 * Either way Claude gets a token tied to that Firebase UID. The OAuth provider
 * library does the token side.
 */

/** What every connector token carries. Read back in the /mcp handler. */
export interface ConnectorProps {
  uid: string;
  /** The Google address used to sign in, or "" for a connect code. */
  email: string;
}

interface Pending {
  authRequest: AuthRequest;
  attempts: number;
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

const escape = (text: string) => text.replace(/[&<>"']/g, (char) => `&#${char.charCodeAt(0)};`);

function html(title: string, body: string, status: number): Response {
  return new Response(
    `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>${escape(title)}</title>` +
      `<style>body{font:16px system-ui;max-width:32rem;margin:3rem auto;padding:0 1rem;color:#222}h1{font-size:1.4rem}` +
      `input{font:1.3rem ui-monospace,monospace;letter-spacing:.15em;text-transform:uppercase;padding:.5rem;width:12ch}` +
      `button,.button{font:inherit;padding:.6rem 1rem;border-radius:.5rem;border:1px solid #888;background:#fff;color:#222;text-decoration:none;display:inline-block;cursor:pointer}` +
      `.primary{background:#222;color:#fff;border-color:#222}.error{color:#b00020}hr{border:0;border-top:1px solid #ddd;margin:2rem 0}small{color:#666}</style>` +
      `<body><h1>${escape(title)}</h1>${body}</body>`,
    { status, headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" } },
  );
}

function page(title: string, message: string, status: number): Response {
  return html(title, `<p>${escape(message)}</p>`, status);
}

/** The sign-in choice: a connect code from the app, or Google. */
export function choicePage(state: string, error?: string): Response {
  const body =
    (error ? `<p class="error">${escape(error)}</p>` : "") +
    `<p>Connect Claude to your own Agdayo account. Claude will only see and change trips you own or have joined.</p>` +
    `<h2 style="font-size:1.1rem">Use a code from the app</h2>` +
    `<p>In Agdayo, open <b>Profile › Connect Claude</b> and tap <b>Get code</b>. Then enter it here.</p>` +
    `<form method="post" action="/authorize/code"><input type="hidden" name="state" value="${escape(state)}">` +
    `<input name="code" placeholder="ABCD-2345" autocomplete="one-time-code" autocapitalize="characters" required maxlength="12"> ` +
    `<button class="primary" type="submit">Connect</button></form>` +
    `<hr><p>Sign in to Agdayo with Google?</p>` +
    `<a class="button" href="/authorize/google?state=${encodeURIComponent(state)}">Continue with Google</a>` +
    `<p><small>This only works for accounts that sign in to Agdayo with Google. Apple and email accounts use a code.</small></p>`;
  return html("Connect Agdayo to Claude", body, error ? 400 : 200);
}

function callbackUrl(request: Request): string {
  return new URL("/callback", request.url).toString();
}

async function loadPending(env: Env, state: string | null): Promise<Pending | undefined> {
  if (!state) return undefined;
  const raw = await env.OAUTH_KV.get(`pending:${state}`);
  return raw ? (JSON.parse(raw) as Pending) : undefined;
}

async function savePending(env: Env, state: string, pending: Pending): Promise<void> {
  await env.OAUTH_KV.put(`pending:${state}`, JSON.stringify(pending), { expirationTtl: pendingTtlSeconds });
}

/** Hands Claude a token for this account, or explains why it can't. */
async function finish(env: Env, state: string, pending: Pending, uid: string, email: string): Promise<Response> {
  await env.OAUTH_KV.delete(`pending:${state}`);
  if (!isAllowedUid(env, uid)) return page("Not allowed", "This Agdayo account isn't allowed to use the connector.", 403);
  const props: ConnectorProps = { uid, email };
  const { redirectTo } = await env.OAUTH_PROVIDER.completeAuthorization({
    request: pending.authRequest,
    userId: uid,
    metadata: email ? { email } : {},
    scope: pending.authRequest.scope,
    props,
  });
  return Response.redirect(redirectTo, 302);
}

/** GET /authorize: checks Claude's request, then shows the sign-in choice. */
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
  const state = crypto.randomUUID();
  await savePending(env, state, { authRequest, attempts: 0 });
  return choicePage(state);
}

/** POST /authorize/code: a connect code from the app. */
export async function authorizeWithCode(request: Request, env: Env): Promise<Response> {
  let form: FormData;
  try {
    form = await request.formData();
  } catch {
    return page("Can't connect", "Start again from Claude.", 400);
  }
  const state = String(form.get("state") ?? "");
  const pending = await loadPending(env, state);
  if (!pending) return page("Sign-in expired", "That took too long. Start again from Claude.", 400);

  const uid = await redeemConnectCode(env, String(form.get("code") ?? ""));
  if (!uid) {
    pending.attempts += 1;
    if (pending.attempts >= maxCodeAttempts) {
      await env.OAUTH_KV.delete(`pending:${state}`);
      return page("Too many tries", "Start again from Claude, and get a new code in the app.", 400);
    }
    await savePending(env, state, pending);
    return choicePage(state, "That code didn't work. Codes last 10 minutes and work once. Get a new one in the app and try again.");
  }
  return finish(env, state, pending, uid, "");
}

/** GET /authorize/google: sends the person to Google. */
export async function authorizeWithGoogle(request: Request, env: Env): Promise<Response> {
  const state = new URL(request.url).searchParams.get("state");
  if (!state || !(await loadPending(env, state))) return page("Sign-in expired", "That took too long. Start again from Claude.", 400);
  if (!env.GOOGLE_OAUTH_CLIENT_ID) return page("Not set up", "Google sign-in isn't set up on this server. Use a code from the app.", 500);
  const google = new URL("https://accounts.google.com/o/oauth2/v2/auth");
  google.searchParams.set("client_id", env.GOOGLE_OAUTH_CLIENT_ID);
  google.searchParams.set("redirect_uri", callbackUrl(request));
  google.searchParams.set("response_type", "code");
  google.searchParams.set("scope", "openid email");
  google.searchParams.set("state", state);
  google.searchParams.set("prompt", "select_account");
  return Response.redirect(google.toString(), 302);
}

/** GET /callback: Google sends the person back here. Finds their Agdayo account and returns them to Claude. */
export async function callback(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const state = url.searchParams.get("state");
  const code = url.searchParams.get("code");
  if (!state || !code) return page("Sign-in cancelled", "Start again from Claude if you want to connect.", 400);
  const pending = await loadPending(env, state);
  if (!pending) return page("Sign-in expired", "That took too long. Start again from Claude.", 400);

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

  let uid: string | undefined;
  try {
    uid = await firebaseUidForGoogleEmail(parseServiceAccount(env.FIREBASE_SERVICE_ACCOUNT), email);
  } catch (error) {
    console.error(error);
    return page("Couldn't sign in", "The server couldn't look up your Agdayo account. Try again, or use a code from the app.", 502);
  }
  if (!uid) {
    return choicePage(state, `${email} doesn't sign in to Agdayo with Google. If you use Apple or email to sign in, get a code in the app instead.`);
  }
  return finish(env, state, pending, uid, email);
}
