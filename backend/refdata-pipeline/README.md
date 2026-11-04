# Reference data pipeline

Builds the read-only SQLite database that both apps use on the device (`docs/CONCEPT.md` §10). The schema is part of the shared contract: [`contracts/refdata/schema.sql`](../../contracts/refdata/schema.sql).

Requires Python 3.9 or later, with no other dependencies.

## Build

Download the [OurAirports](https://ourairports.com/data/) airport list (public domain), then run the build:

```bash
curl -fLo /tmp/airports.csv https://davidmegginson.github.io/ourairports-data/airports.csv
python3 build_refdata.py --airports /tmp/airports.csv --out /tmp/refdata --data-version 2026-11-04
```

This writes `refdata.sqlite` and `manifest.json` to the output folder. Rows that can't be used are listed in the manifest under `skipped` and don't stop the build. A missing column does stop it, and any existing database is kept.

## Data sources

| Table | Source | Status |
|---|---|---|
| `airports` | OurAirports, excluding closed airports | Imported |
| `aircraft_types` | [`seed/aircraft_types.csv`](seed/aircraft_types.csv), curated by hand | 22 common types, about 2,500 planned |
| `operators` | Not chosen | Empty, licensing is undecided |
| `aircraft` | Not chosen | Empty, licensing is undecided (concept §16, question 6) |

## Test

```bash
python3 tests/test_build_refdata.py
```
