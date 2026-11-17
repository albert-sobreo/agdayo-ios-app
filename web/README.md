# Agdayo web (beta)

Vue 3 + Vite + Tailwind v4 web app for Agdayo. It signs in with the same Firebase
accounts and reads and writes the same Firestore trips as the iPhone app, live.

## Run

```bash
npm install
npm run dev        # http://localhost:5173
npm run test:unit  # unit tests
npm run build      # type-check + production build into dist/
npm run deploy     # build, then upload to the agdayo-web Worker (Cloudflare)
```

## Setup (once)

1. Firebase console › Project settings › Your apps › Add app › Web. Put its
   `apiKey` and `appId` in `src/config.ts` (the config isn't secret).
2. Firebase console › Authentication › Settings › Authorized domains: add
   `localhost` (usually there already) and the deployed domain.
3. Apple sign-in on the web needs a Services ID in the Apple Developer account,
   with the web domain and `https://agdayo-app.firebaseapp.com/__/auth/handler`
   as a return URL, then the Services ID in Firebase › Authentication › Apple.
4. Set `appStoreUrl` in `src/config.ts` to the app's App Store link.

## Rules for this code

- **Free tier only, no payments.** Paid features stay in the iPhone app, and
  unlocking only happens there. The web reads whether someone has paid
  (`users/{uid}.unlocked`, or the per-trip `ownerUnlocked` flag) and never sells anything.
- **Keep the app's Firestore shapes.** The iPhone app decodes these documents into
  SwiftData. Every write is in `src/lib/writes.ts`, with the same field names and
  types as `Agdayo/Services/Sync/*Sync.swift` and `worker/src/trips.ts`. Edits only
  update the fields the web form owns, so cost splits and other app-only fields are kept.
- **Design tokens** in `src/assets/main.css` are copied from `Agdayo/Shared/Theme`.
  Put `data-theme="<trip theme>"` on a wrapper to get `bg-trip-50`, `text-trip-500`, etc.
- **No secrets** in this folder: the repo is public.
