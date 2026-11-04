# Agdayo Worker

Agdayo's own server on Cloudflare Workers. It holds the API keys and gives the
app and Claude transit routes, travel times, places and destination guides,
and lets Claude write trips straight into Agdayo.

- The app calls `/v1` with a Firebase sign-in token from an allowed account.
- Claude calls `/mcp` as a **custom connector** after you sign in with Google.

| Endpoint | What it returns |
| --- | --- |
| `GET /health` | `{ ok: true }`, no sign-in needed |
| `POST /v1/route` | One route with steps (lines, stops, walking parts) and fare when Google has it. `{ route: null }` when there's no route, e.g. no transit data in that city |
| `POST /v1/matrix` | Travel times and distances between 2–10 places |
| `POST /v1/places/search` | Places matching a text query near a point, with opening hours |
| `GET /v1/places/:id` | One place by Google place ID |
| `GET /v1/guides`, `GET/PUT /v1/guides/:countryCode` | Destination guides, stored in D1 |
| `POST /mcp` | The Claude connector (MCP). Sign-in at `/authorize`, tokens at `/token` |

### Connector tools

| Tool | What Claude can do |
| --- | --- |
| `list_trips`, `get_trip` | Read your trips: stays, transport, activities, day notes |
| `create_trip` | Start a new trip (shows up when the trip list refreshes) |
| `add_stay` | Add a hotel with its map pin |
| `add_activities`, `update_activity`, `delete_activity` | Write the plan, up to 40 activities at a time |
| `plan_route`, `travel_times` | Google transit/walk/drive routes and times |
| `search_places`, `place_details` | Google Places, with coordinates and opening hours |
| `get_guide`, `save_guide` | Read and save "Know before you go" guides |

Everything Claude writes is marked `createdBy: "claude"`. Claude is told to
show you the plan and get your OK before any change, and the Claude app also
asks before each write tool runs. Times are written with the destination's
UTC offset so they land on the right hour.

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
   Also create the storage for connector sign-ins. Wrangler refuses to
   deploy or set secrets until it exists:
   ```sh
   npx wrangler kv namespace create OAUTH_KV
   ```
   Copy the printed `id` into `kv_namespaces` in `wrangler.jsonc`.
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

### Connect Claude

7. **Google sign-in client.** In Google Cloud › APIs & Services › Credentials,
   create an **OAuth client ID** of type **Web application** with the
   authorized redirect URI `https://agdayo.<you>.workers.dev/callback`. (If
   asked, set up the consent screen as External, in Testing, with yourself as
   a test user.) Put the **Client ID** in `GOOGLE_OAUTH_CLIENT_ID` and your
   Google address in `ALLOWED_EMAILS` in `wrangler.jsonc`, then:
   ```sh
   npx wrangler secret put GOOGLE_OAUTH_CLIENT_SECRET
   ```
8. **Access to trips.** In the Firebase console › Project settings › Service
   accounts, click **Generate new private key**. Then store the whole file as
   a secret and delete the download:
   ```sh
   npx wrangler secret put FIREBASE_SERVICE_ACCOUNT < ~/Downloads/agdayo-app-*.json
   ```
   This key can read and write all of Agdayo's data, so never commit it or
   paste it into a chat.
9. **Deploy** again (`npm run deploy`).
10. **Add the connector.** On claude.ai (web or desktop): Settings ›
    Connectors › Add custom connector, name it Agdayo, URL
    `https://agdayo.<you>.workers.dev/mcp`. Click Connect and sign in with
    Google. It then works on the Claude phone app too.

The connector acts as your Firebase user: the UID in `ALLOWED_UIDS` (or
`CONNECTOR_UID` if you list more than one). Removing your UID from
`ALLOWED_UIDS` cuts off both the app and Claude.

To deploy automatically after this, connect the repo in the Cloudflare
dashboard (Workers › agdayo › Settings › Builds) with **root directory**
`worker`, so pushes to `main` that touch this folder redeploy it.

## Developing

```sh
npm test          # unit tests
npm run typecheck
npm run dev       # local server; put secrets in .dev.vars
```
