import { HttpError } from "./http";

/** A "Know before you go" guide for one country. */
export interface Guide {
  countryCode: string;
  title: string;
  sections: GuideSection[];
  sources: { title: string; url: string }[];
  /** When the facts were last checked, ISO 8601. */
  checkedAt: string;
  updatedAt: string;
}

export interface GuideSection {
  /** Stable key such as "getting-around", "money", "plugs". */
  id: string;
  title: string;
  items: { text: string; source?: string }[];
}

export function parseCountryCode(value: string): string {
  const code = value.trim().toUpperCase();
  if (!/^[A-Z]{2}$/.test(code)) throw new HttpError(400, "Use a two-letter country code, like SG.");
  return code;
}

function isString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

/** Validates a guide written by the app or by Claude. Throws a 400 explaining what's wrong. */
export function parseGuide(countryCode: string, body: Record<string, unknown>, now = new Date()): Guide {
  if (!isString(body.title)) throw new HttpError(400, "title is required.");
  if (!Array.isArray(body.sections) || body.sections.length === 0) {
    throw new HttpError(400, "sections must be a non-empty list.");
  }
  const sections = body.sections.map((raw, index): GuideSection => {
    const section = (raw ?? {}) as Record<string, unknown>;
    if (!isString(section.id) || !isString(section.title) || !Array.isArray(section.items)) {
      throw new HttpError(400, `sections[${index}] needs id, title and items.`);
    }
    const items = section.items.map((rawItem, itemIndex) => {
      const item = (rawItem ?? {}) as Record<string, unknown>;
      if (!isString(item.text)) throw new HttpError(400, `sections[${index}].items[${itemIndex}].text is required.`);
      return isString(item.source) ? { text: item.text, source: item.source } : { text: item.text };
    });
    return { id: section.id, title: section.title, items };
  });
  const sources = Array.isArray(body.sources)
    ? body.sources.map((raw, index) => {
        const source = (raw ?? {}) as Record<string, unknown>;
        if (!isString(source.title) || !isString(source.url) || !/^https?:\/\//.test(source.url)) {
          throw new HttpError(400, `sources[${index}] needs a title and an http(s) url.`);
        }
        return { title: source.title, url: source.url };
      })
    : [];
  const checkedAt =
    typeof body.checkedAt === "string" && !Number.isNaN(Date.parse(body.checkedAt))
      ? new Date(body.checkedAt).toISOString()
      : now.toISOString();
  return { countryCode, title: body.title.trim(), sections, sources, checkedAt, updatedAt: now.toISOString() };
}

interface GuideRow {
  country_code: string;
  title: string;
  sections: string;
  sources: string;
  checked_at: string;
  updated_at: string;
}

export async function getGuide(db: D1Database, countryCode: string): Promise<Guide | null> {
  const row = await db.prepare("SELECT * FROM guides WHERE country_code = ?").bind(countryCode).first<GuideRow>();
  if (!row) return null;
  return {
    countryCode: row.country_code,
    title: row.title,
    sections: JSON.parse(row.sections) as GuideSection[],
    sources: JSON.parse(row.sources) as Guide["sources"],
    checkedAt: row.checked_at,
    updatedAt: row.updated_at,
  };
}

export async function listGuides(db: D1Database): Promise<{ countryCode: string; title: string; checkedAt: string }[]> {
  const { results } = await db
    .prepare("SELECT country_code, title, checked_at FROM guides ORDER BY title")
    .all<Pick<GuideRow, "country_code" | "title" | "checked_at">>();
  return results.map((row) => ({ countryCode: row.country_code, title: row.title, checkedAt: row.checked_at }));
}

export async function putGuide(db: D1Database, guide: Guide): Promise<void> {
  await db
    .prepare(
      `INSERT INTO guides (country_code, title, sections, sources, checked_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(country_code) DO UPDATE SET
         title = excluded.title, sections = excluded.sections, sources = excluded.sources,
         checked_at = excluded.checked_at, updated_at = excluded.updated_at`,
    )
    .bind(
      guide.countryCode,
      guide.title,
      JSON.stringify(guide.sections),
      JSON.stringify(guide.sources),
      guide.checkedAt,
      guide.updatedAt,
    )
    .run();
}
