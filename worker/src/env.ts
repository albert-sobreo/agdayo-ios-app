import type { OAuthHelpers } from "@cloudflare/workers-oauth-provider";

export interface Env {
  DB: D1Database;
  /** Google Cloud key with the Routes API and Places API (New) enabled. Secret. */
  GOOGLE_MAPS_API_KEY: string;
  /** Firebase project whose ID tokens are accepted, e.g. "agdayo-app". */
  FIREBASE_PROJECT_ID: string;
  /** Comma-separated Firebase UIDs allowed to call the server. Empty allows nobody. */
  ALLOWED_UIDS: string;

  // Claude connector (see oauth.ts and mcp.ts)
  /** Stores connector tokens and sign-ins in progress. */
  OAUTH_KV: KVNamespace;
  /** Added by the OAuth provider library at runtime. */
  OAUTH_PROVIDER: OAuthHelpers;
  /** Google OAuth "Web application" client used to sign in to the connector. */
  GOOGLE_OAUTH_CLIENT_ID: string;
  /** Secret. */
  GOOGLE_OAUTH_CLIENT_SECRET: string;
  /** Comma-separated Google accounts allowed to connect Claude. Empty allows nobody. */
  ALLOWED_EMAILS: string;
  /** Firebase UID the connector acts as. Optional when ALLOWED_UIDS has exactly one UID. */
  CONNECTOR_UID?: string;
  /** Hosts allowed to receive connector tokens. Defaults to claude.ai and claude.com. */
  ALLOWED_REDIRECT_HOSTS?: string;
  /** Firebase service account key JSON, for reading and writing trips. Secret. */
  FIREBASE_SERVICE_ACCOUNT?: string;
}
