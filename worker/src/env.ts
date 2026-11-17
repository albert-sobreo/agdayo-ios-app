import type { OAuthHelpers } from "@cloudflare/workers-oauth-provider";

export interface Env {
  DB: D1Database;
  /** Firebase project whose ID tokens are accepted, e.g. "agdayo-app". */
  FIREBASE_PROJECT_ID: string;
  /**
   * Who may use the server (app and Claude): "*" for every signed-in Agdayo
   * account, or comma-separated Firebase UIDs. Empty allows nobody.
   */
  ALLOWED_UIDS: string;
  /** Comma-separated Firebase UIDs that are always refused, e.g. for abuse. Optional. */
  BLOCKED_UIDS?: string;

  // Claude connector (see oauth.ts and mcp.ts)
  /** Stores connector tokens, sign-ins in progress and connect codes. */
  OAUTH_KV: KVNamespace;
  /** Added by the OAuth provider library at runtime. */
  OAUTH_PROVIDER: OAuthHelpers;
  /** Google OAuth "Web application" client used to sign in to the connector. */
  GOOGLE_OAUTH_CLIENT_ID: string;
  /** Secret. */
  GOOGLE_OAUTH_CLIENT_SECRET: string;
  /** Hosts allowed to receive connector tokens. Defaults to claude.ai and claude.com. */
  ALLOWED_REDIRECT_HOSTS?: string;
  /** Firebase service account key JSON, for trips and finding a Google user's Agdayo account. Secret. */
  FIREBASE_SERVICE_ACCOUNT?: string;

  // MapKit JS, for the web app's map (see mapkit.ts). Secrets.
  MAPKIT_TEAM_ID?: string;
  MAPKIT_KEY_ID?: string;
  MAPKIT_PRIVATE_KEY?: string;
}
