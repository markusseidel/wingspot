-- Schema of the read-only on-device reference database, shared by iOS and Android
-- (docs/CONCEPT.md §10). Bump user_version on any change that clients must know about.
PRAGMA user_version = 2;

CREATE TABLE meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE airports (
  id             INTEGER PRIMARY KEY,  -- OurAirports ID, stable across snapshots
  icao           TEXT,
  iata           TEXT,
  name           TEXT NOT NULL,
  city           TEXT,
  country_code   TEXT NOT NULL,
  continent      TEXT NOT NULL,
  type           TEXT NOT NULL,        -- large_airport, small_airport, heliport, ...
  latitude       REAL NOT NULL,
  longitude      REAL NOT NULL,
  elevation_ft   INTEGER,
  default_search INTEGER NOT NULL,     -- 1 if it has an IATA code or scheduled service
  keywords       TEXT                  -- other names, e.g. Flughafen München
);
CREATE INDEX airports_icao ON airports (icao);
CREATE INDEX airports_iata ON airports (iata);

CREATE TABLE aircraft_types (
  icao_code    TEXT PRIMARY KEY,       -- A388
  manufacturer TEXT NOT NULL,          -- Airbus
  model        TEXT NOT NULL,          -- A380-800
  family       TEXT,                   -- A380
  engine_type  TEXT,                   -- jet, turboprop, piston, helicopter, electric, rocket
  engine_count INTEGER,
  wtc          TEXT                    -- ICAO wake turbulence category: L, M, H, J
) WITHOUT ROWID;

CREATE TABLE operators (
  id           INTEGER PRIMARY KEY,
  icao         TEXT,
  iata         TEXT,
  name         TEXT NOT NULL,
  country_code TEXT,
  alliance     TEXT,
  category     TEXT
);
CREATE INDEX operators_icao ON operators (icao);
CREATE INDEX operators_iata ON operators (iata);

-- The primary key also serves registration prefix search, so no FTS table is needed:
-- the FTS tokenizer would split D-AIMA into two tokens.
CREATE TABLE aircraft (
  registration TEXT PRIMARY KEY,       -- canonical form, see contracts/test-vectors/registrations.json
  icao24       TEXT,
  type_icao    TEXT REFERENCES aircraft_types (icao_code),
  operator_id  INTEGER REFERENCES operators (id)
) WITHOUT ROWID;

CREATE VIRTUAL TABLE airports_fts USING fts5 (
  name, city, icao, iata, keywords,
  content = 'airports', content_rowid = 'id',
  tokenize = 'unicode61 remove_diacritics 2', prefix = '2 3'
);

-- aircraft_types has no rowid, so this index holds its own copy of the text.
CREATE VIRTUAL TABLE aircraft_types_fts USING fts5 (
  icao_code, manufacturer, model, family,
  tokenize = 'unicode61 remove_diacritics 2', prefix = '2 3'
);

CREATE VIRTUAL TABLE operators_fts USING fts5 (
  name, icao, iata,
  content = 'operators', content_rowid = 'id',
  tokenize = 'unicode61 remove_diacritics 2', prefix = '2 3'
);
