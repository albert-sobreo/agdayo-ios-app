# Agdayo Worker

Agdayo's own server on Cloudflare Workers. It lets Claude write trips straight
into Agdayo, as a **custom connector** (custom connectors work on Claude's
free plan).

- Claude calls `/mcp`. Anyone with an Agdayo account can connect their own
  Claude, and it then acts as their account only: it sees and changes just the
  trips they own or have joined.
- The app calls `/v1` with a Firebase sign-in token, to get a connect code.

Who may use the server is `ALLOWED_UIDS`: `"*"` lets every signed-in Agdayo
account in, and `BLOCKED_UIDS` shuts an account out (app and Claude, including
tokens already handed out).

The server calls no paid map APIs. The app works out travel times itself with
Apple Maps.

| Endpoint | What it returns |
| --- | --- |
| `GET /health` | `{ ok: true }`, no sign-in needed |
| `GET /open/trip/:id?day=YYYY-MM-DD` | A page that opens the trip (and that day's itinerary) in the app via `agdayo://trip/...`. No sign-in; it only forwards the ID |
| `POST /v1/connect-code` | A one-time code (`ABCD-2345`, 10 minutes) the app shows for connecting Claude |
| `GET /v1/guides`, `GET /v1/guides/:countryCode` | Destination guides saved in D1. The guide is switched off in the app and connector for now; saved guides stay |
| `POST /mcp` | The Claude connector (MCP). Sign-in at `/authorize` (connect code or Google), tokens at `/token` |

### Connector tools

| Tool | What Claude can do |
| --- | --- |
| `list_trips`, `get_trip` | Read your trips: stays, transport, activities, day notes |
| `create_trip`, `update_trip` | Start a new trip (shows up when the trip list refreshes), or change its name, dates, budget and so on. Free accounts keep the app's limit of 2 owned trips |
| `add_stay`, `update_stay`, `delete_stay` | Hotels, with their map pins |
| `add_activities`, `update_activity`, `delete_activity` | Write the plan, up to 40 activities at a time |
| `add_transport`, `update_transport`, `delete_transport` | Flights, buses, trains and ferries |
| `set_day_note`, `delete_day_note` | Notes on a day |

Everything Claude writes is marked `createdBy: "claude"`. Claude is told to
show you the plan and get your OK before any change, and the Claude app also
asks before each write tool runs. Times are written with the destination's
UTC offset so they land on the right hour. Trip tools return an `appLink`
(the `/open/trip/...` page above), which Claude shares as an "Open in Agdayo"
link.

## One-time setup

You need a Cloudflare account.

1. **Install and sign in** (from this folder):
   ```sh
   npm install
   npx wrangler login
   ```
2. **Database and sign-in storage.**
   ```sh
   npx wrangler d1 create agdayo
   ```
   Copy the printed `database_id` into `wrangler.jsonc`, then:
   ```sh
   npm run db:migrate
   npx wrangler kv namespace create OAUTH_KV
   ```
   Copy the printed `id` into `kv_namespaces` in `wrangler.jsonc`. Wrangler
   refuses to deploy or set secrets until it exists.
3. **Who can use it.** `ALLOWED_UIDS` is `"*"` (every signed-in account). To
   keep it to yourself instead, put your User UID there (Firebase console ›
   Authentication › Users).
4. **Access to trips.** In the Firebase console › Project settings › Service
   accounts, click **Generate new private key**. Then store the whole file as
   a secret and delete the download:
   ```sh
   npx wrangler secret put FIREBASE_SERVICE_ACCOUNT < ~/Downloads/agdayo-app-*.json
   ```
   This key can read and write all of Agdayo's data, so never commit it or
   paste it into a chat. The server also uses it to find which Agdayo account
   a Google sign-in belongs to.
5. **Google sign-in client** (for "Continue with Google"; optional, codes work
   without it). In Google Cloud › APIs & Services › Credentials, create an
   **OAuth client ID** of type **Web application** with the authorized
   redirect URI `https://agdayo.<you>.workers.dev/callback`. Put the **Client
   ID** in `GOOGLE_OAUTH_CLIENT_ID` in `wrangler.jsonc`, then:
   ```sh
   npx wrangler secret put GOOGLE_OAUTH_CLIENT_SECRET
   ```
   While the OAuth consent screen is in **Testing**, only its test users can
   use Continue with Google. To open it to everyone, set the publishing status
   to **In production**. The connector only asks for `openid email`, which
   don't need Google's verification.
6. **Deploy.**
   ```sh
   npm run deploy
   ```
   Wrangler prints the address, like `https://agdayo.<you>.workers.dev`.
   Check `https://agdayo.<you>.workers.dev/health` returns `{"ok":true}`.
7. **Add the connector.** In the Claude app (phone, desktop or claude.ai),
   open the **Plugins** tab and add a custom connector named Agdayo with the
   URL `https://agdayo.<you>.workers.dev/mcp`. Tap Connect, then on the
   Agdayo page either enter a code from the app (Profile › Connect Claude) or
   choose Continue with Google. It then works everywhere you use Claude.

The connector acts as whichever Agdayo account signed in. A connect code ties
it to the account that made the code in the app, so it works for Apple, Google
and email accounts alike. Continue with Google only matches an Agdayo account
that signs in with that same Google account.

To deploy automatically after this, connect the repo in the Cloudflare
dashboard (Workers › agdayo › Settings › Builds) with **root directory**
`worker`, so pushes to `main` that touch this folder redeploy it.

## Developing

```sh
npm test          # unit tests
npm run typecheck
npm run dev       # local server; put secrets in .dev.vars
```
