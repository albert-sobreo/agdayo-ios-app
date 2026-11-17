-- Google calls per account per day (UTC), for the daily limit in usage.ts.
CREATE TABLE IF NOT EXISTS google_usage (
  uid TEXT NOT NULL,
  day TEXT NOT NULL,
  units INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (uid, day)
);
