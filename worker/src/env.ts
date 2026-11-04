export interface Env {
  DB: D1Database;
  /** Google Cloud key with the Routes API and Places API (New) enabled. Secret. */
  GOOGLE_MAPS_API_KEY: string;
  /** Firebase project whose ID tokens are accepted, e.g. "agdayo-app". */
  FIREBASE_PROJECT_ID: string;
  /** Comma-separated Firebase UIDs allowed to call the server. Empty allows nobody. */
  ALLOWED_UIDS: string;
}
