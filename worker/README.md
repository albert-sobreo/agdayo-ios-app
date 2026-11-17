# Agdayo Worker

Agdayo's own server on Cloudflare Workers. It holds the API keys and gives the
app and Claude transit routes, travel times, places and destination guides,
and lets Claude write trips straight into Agdayo.

- The app calls `/v1` with a Firebase sign-in token.
- Claude calls `/mcp` as a **custom connector**. Anyone with an Agdayo account
  can connect their own Claude (custom connectors work on Claude's free plan),
  and it then acts as their account only: it sees and changes just the trips
  they own or have joined.

Who may use the server is `ALLOWED_UIDS`: `"*"` lets every signed-in Agdayo
account in, and `BLOCKED_UIDS` shuts out an abuser. Every call that reaches
Google counts against a daily allowance per account (`GOOGLE_DAILY_LIMIT`,
default 300; a 10-place `travel_times` counts 100, cached answers are free).
`UNLIMITED_UIDS` skips the allowance.

| Endpoint | What it returns |
| --- | --- |
| `GET /health` | `{ ok: true }`, no sign-in needed |
| `GET /open/trip/:id?day=YYYY-MM-DD` | A page that opens the trip (and that day's itinerary) in the app via `agdayo://trip/...`. No sign-in; it only forwards the ID |
| `POST /v1/route` | One route with steps (lines, stops, walking parts) and fare when Google has it. `{ route: null }` when there's no route, e.g. no transit data in that city |
| `POST /v1/matrix` | Travel times and distances between 2–10 places |
| `POST /v1/places/search` | Places matching a text query near a point, with opening hours |
| `GET /v1/places/:id` | One place by Google place ID |
| `GET /v1/guides`, `GET /v1/guides/:countryCode` | Destination guides, stored in D1. The guide is switched off in the app and connector for now; saved guides stay |
| `POST /v1/connect-code` | A one-time code (`ABCD-2345`, 10 minutes) the app shows for connecting Claude |
| `POST /mcp` | The Claude connector (MCP). Sign-in at `/authorize` (connect code or Google), tokens at `/token` |

### Connector tools

| Tool | What Claude can do |
| --- | --- |
| `list_trips`, `get_trip` | Read your trips: stays, transport, activities, day notes |
| `create_trip`, `update_trip` | Start a new trip (shows up when the trip list refreshes), or change its name, dates, budget and so on. Free accounts keep the app's limit of 2 owned trips |
| `add_stay`, `update_stay`, `delete_stay` | Hotels, with their map pins |
| `add_activities`, `update_activity`, `delete_activity` | Write the plan, up to 40 activities at a time. Each keeps its Google place ID so the app can check opening hours |
| `add_transport`, `update_transport`, `delete_transport` | Flights, buses, trains and ferries |
| `set_day_note`, `delete_day_note` | Notes on a day |
| `plan_route`, `travel_times` | Google transit/walk/drive routes and times |
| `search_places`, `place_details` | Google Places, with coordinates and opening hours |

Everything Claude writes is marked `createdBy: "claude"`. Claude is told to
show you the plan and get your OK before any change, and the Claude app also
asks before each write tool runs. Times are written with the destination's
UTC offset so they land on the right hour. Trip tools return an `appLink`
(the `/open/trip/...` page above), which Claude shares as an "Open in Agdayo"
link.

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
4. **Who can use it.** `ALLOWED_UIDS` is `"*"` (every signed-in account). To
   keep it to yourself instead, put your User UID there (Firebase console ›
   Authentication › Users). Put your own UID in `UNLIMITED_UIDS` so the daily
   Google allowance doesn't apply to you. Then create the usage table with
   `npm run db:migrate` (again, if you ran it before).
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
   a test user.) Put the **Client ID** in `GOOGLE_OAUTH_CLIENT_ID` in
   `wrangler.jsonc`, then:
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
   paste it into a chat. The server also uses it to find which Agdayo account
   a Google sign-in belongs to.
9. **Deploy** again (`npm run deploy`).
10. **Add the connector.** On claude.ai (web or desktop): Settings ›
    Connectors › Add custom connector, name it Agdayo, URL
    `https://agdayo.<you>.workers.dev/mcp`. Click Connect, then on the Agdayo
    page either enter a code from the app (Profile › Connect Claude) or choose
    Continue with Google. It then works on the Claude phone app too.

The connector acts as whichever Agdayo account signed in. A connect code ties
it to the account that made the code in the app, so it works for Apple, Google
and email accounts alike. Continue with Google only matches an Agdayo account
that signs in with that same Google account. Adding a UID to `BLOCKED_UIDS`
cuts off both the app and Claude for that account.

### Letting other people sign in with Google

While the Google consent screen (Google Cloud › APIs & Services › OAuth
consent screen) is in **Testing**, only its test users can use Continue with
Google. Everyone else can still connect with a code from the app. To open
Google sign-in to everyone, set the publishing status to **In production**.
The connector only asks for `openid email`, which don't need Google's
verification.

### Keeping the Google bill in check

The daily allowance caps each account. As a hard cap on the whole project, in
Google Cloud › APIs & Services, open the **Routes API** and **Places API
(New)**, then Quotas, and lower the requests-per-day limits to what you're
happy to pay for. Keep the budget alert from step 1.

To deploy automatically after this, connect the repo in the Cloudflare
dashboard (Workers › agdayo › Settings › Builds) with **root directory**
`worker`, so pushes to `main` that touch this folder redeploy it.

## Developing

```sh
npm test          # unit tests
npm run typecheck
npm run dev       # local server; put secrets in .dev.vars
```
