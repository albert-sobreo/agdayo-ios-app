# Agdayo Worker

Agdayo's own server on Cloudflare Workers. It holds the API keys and gives the
app (and, from Phase 3, Claude through the MCP connector) transit routes,
travel times, places and destination guides. Every `/v1` request needs a
Firebase sign-in token from an allowed account.

| Endpoint | What it returns |
| --- | --- |
| `GET /health` | `{ ok: true }`, no sign-in needed |
| `POST /v1/route` | One route with steps (lines, stops, walking parts) and fare when Google has it. `{ route: null }` when there's no route, e.g. no transit data in that city |
| `POST /v1/matrix` | Travel times and distances between 2–10 places |
| `POST /v1/places/search` | Places matching a text query near a point, with opening hours |
| `GET /v1/places/:id` | One place by Google place ID |
| `GET /v1/guides`, `GET/PUT /v1/guides/:countryCode` | Destination guides, stored in D1 |

Transit comes only from Google, everywhere. Where Google has no transit data
the route is `null`, and the app shows walking and driving instead.

## One-time setup

You need a Cloudflare account, and a Google Cloud project with billing on.

1. **Google key.** In Google Cloud, enable the **Routes API** and the
   **Places API (New)**, then create an API key restricted to those two APIs.
   Set a budget alert on the project.
2. **Install and sign in** (from this folder):
   ```sh
   npm install
   npx wrangler login
   ```
3. **Database.**
   ```sh
   npx wrangler d1 create agdayo
   ```
   Copy the printed `database_id` into `wrangler.jsonc`, then:
   ```sh
   npm run db:migrate
   ```
4. **Your user ID.** In the Firebase console, open Authentication › Users and
   copy your User UID into `ALLOWED_UIDS` in `wrangler.jsonc`.
5. **Secret.**
   ```sh
   npx wrangler secret put GOOGLE_MAPS_API_KEY
   ```
6. **Deploy.**
   ```sh
   npm run deploy
   ```
   Wrangler prints the address, like `https://agdayo.<you>.workers.dev`.
   Check `https://agdayo.<you>.workers.dev/health` returns `{"ok":true}`.

To deploy automatically after this, connect the repo in the Cloudflare
dashboard (Workers › agdayo › Settings › Builds) with **root directory**
`worker`, so pushes to `main` that touch this folder redeploy it.

## Developing

```sh
npm test          # unit tests
npm run typecheck
npm run dev       # local server; put secrets in .dev.vars
```
