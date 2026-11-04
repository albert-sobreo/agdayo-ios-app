import { HttpError } from "./http";

/**
 * "Open in Agdayo" links. Claude's chat can't link straight to the app's
 * agdayo:// scheme, so the connector hands out an https link to this server,
 * and this page sends the phone on to the app.
 *
 *   GET /open/trip/:tripId?day=YYYY-MM-DD  →  agdayo://trip/:tripId?day=YYYY-MM-DD
 *
 * The page needs no sign-in: it only forwards an ID, and the app shows the
 * trip only if the signed-in person already has it.
 */

const uuidPattern = /^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/i;
const dayPattern = /^\d{4}-\d{2}-\d{2}$/;

/** The local date at the start of a time with offset, e.g. "2026-11-16T09:00:00+08:00" → "2026-11-16". */
export function localDay(time: unknown): string | undefined {
  if (typeof time !== "string") return undefined;
  const day = time.slice(0, 10);
  return dayPattern.test(day) ? day : undefined;
}

/** The https link Claude shares. `day` is a local date like "2026-11-16". */
export function appLink(origin: string, tripId: string, day?: string): string {
  const url = new URL(`/open/trip/${encodeURIComponent(tripId)}`, origin);
  if (day && dayPattern.test(day)) url.searchParams.set("day", day);
  return url.toString();
}

/** The agdayo:// address the page forwards to, or an error for a bad link. */
export function schemeUrl(url: URL): string {
  const match = /^\/open\/trip\/([^/]+)$/.exec(url.pathname.replace(/\/+$/, ""));
  const tripId = match?.[1] ? decodeURIComponent(match[1]) : "";
  if (!uuidPattern.test(tripId)) throw new HttpError(404, "That isn't an Agdayo trip link.");
  const day = url.searchParams.get("day");
  const target = `agdayo://trip/${tripId.toUpperCase()}`;
  return day && dayPattern.test(day) ? `${target}?day=${day}` : target;
}

/** A tiny page that opens the app, with a button in case the browser wants a tap first. */
export function openPage(url: URL): Response {
  const target = schemeUrl(url);
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Open in Agdayo</title>
<style>
  :root { color-scheme: light dark; }
  body { margin: 0; min-height: 100vh; display: grid; place-items: center; font: 17px -apple-system, system-ui, sans-serif; background: Canvas; color: CanvasText; }
  main { text-align: center; padding: 24px; }
  a { display: inline-block; margin-top: 16px; padding: 14px 28px; border-radius: 999px; background: #1f7a5c; color: #fff; text-decoration: none; font-weight: 600; }
  p { opacity: 0.7; }
</style>
</head>
<body>
<main>
  <h1>Agdayo</h1>
  <a href="${target}">Open in Agdayo</a>
  <p>Opens the trip on a phone with Agdayo installed.</p>
</main>
<script>location.href = ${JSON.stringify(target)};</script>
</body>
</html>`;
  return new Response(html, {
    headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store", "referrer-policy": "no-referrer" },
  });
}
