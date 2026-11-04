-- Destination guides ("Know before you go"), one per country.
CREATE TABLE IF NOT EXISTS guides (
  country_code TEXT PRIMARY KEY,      -- ISO 3166-1 alpha-2, upper case, e.g. 'SG'
  title        TEXT NOT NULL,         -- e.g. 'Singapore'
  sections     TEXT NOT NULL,         -- JSON array of { id, title, items: [{ text, source? }] }
  sources      TEXT NOT NULL,         -- JSON array of { title, url }
  checked_at   TEXT NOT NULL,         -- when the facts were last checked (ISO 8601)
  updated_at   TEXT NOT NULL          -- when this row was last written (ISO 8601)
);
