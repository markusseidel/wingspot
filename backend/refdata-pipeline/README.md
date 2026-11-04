# Reference data pipeline

Builds the read-only SQLite database that both apps use on the device (`docs/CONCEPT.md` §10). The schema is part of the shared contract: [`contracts/refdata/schema.sql`](../../contracts/refdata/schema.sql).

Requires Python 3.9 or later, with no other dependencies.

## Build

Download the [OurAirports](https://ourairports.com/data/) airport list (public domain), then run the build:

```bash
curl -fLo /tmp/airports.csv https://davidmegginson.github.io/ourairports-data/airports.csv
python3 build_refdata.py --airports /tmp/airports.csv --out /tmp/refdata --data-version 2026-11-04
```

This writes `refdata.sqlite` and `manifest.json` to the output folder. Rows that can't be used are listed in the manifest under `skipped` and don't stop the build. Curated keywords for an airport that isn't in the data are listed under `unmatched_keywords`. A missing column does stop it, and any existing database is kept.

## Update aircraft types

Download [FAA Order JO 7360.1](https://www.faa.gov/regulations_policies/orders_notices/index.cfm/go/document.current/documentNumber/7360.1) and the [Aircraft Characteristics Database](https://www.faa.gov/airports/engineering/aircraft_char_database), then regenerate the list. Extracting the text needs macOS.

```bash
swift extract_pdf.swift order.pdf order.txt
python3 faa_aircraft_types.py --order-text order.txt --spreadsheet aircraft_data.xlsx --report report.json
```

Check `report.json` before committing. It lists rows it couldn't read, ambiguous values and conflicts between the two sources. Fix a wrong name in `aircraft_type_overrides.csv`, not in the generated file.

## Load into Postgres

Check-ins reference airports and aircraft types by the IDs in the snapshot, so load each snapshot into Postgres **before** publishing it. Otherwise an app could send an ID the server doesn't have. Run these from `backend/`, linked to the hosted project:

```bash
python3 refdata-pipeline/postgres_import.py --snapshot /tmp/refdata/refdata.sqlite --out /tmp/refdata/sql
for file in /tmp/refdata/sql/*.sql; do supabase db query --remote --file "$file" --yes > /dev/null || break; done
```

The batches only add or update rows, so they're safe to rerun. Airports that leave a later snapshot stay in Postgres, because check-ins may reference them.

## Publish

Run these from `backend/`, linked to the hosted project. Set `V` to the build's data version. Each snapshot gets its own path, because apps may still be using an older one.

```bash
V=2026-11-04
supabase storage cp /tmp/refdata/refdata.sqlite ss:///refdata/$V/refdata.sqlite --remote --experimental --content-type application/vnd.sqlite3
```

Download the file from `https://<project-ref>.supabase.co/storage/v1/object/public/refdata/$V/refdata.sqlite` and compare its SHA-256 with `manifest.json`. Then add a row to `refdata_snapshots` with the manifest's values, so the API never points at a missing file. `/v1/refdata/manifest` returns the newest row.

## Data sources

| Table | Source | Status |
|---|---|---|
| `airports` | OurAirports, excluding closed airports. Its `keywords` column is searchable, plus German names from [`seed/airport_keywords.csv`](seed/airport_keywords.csv), curated by hand | Imported |
| `aircraft_types` | [`seed/aircraft_types.csv`](seed/aircraft_types.csv), generated from FAA Order JO 7360.1, with [`seed/aircraft_type_overrides.csv`](seed/aircraft_type_overrides.csv) and [`seed/aircraft_families.csv`](seed/aircraft_families.csv) curated by hand | Generated. Reuse terms for commercial use still need confirming |
| `operators` | Not chosen | Empty, licensing is undecided |
| `aircraft` | Not chosen | Empty, licensing is undecided (concept §16, question 6) |

## Test

```bash
python3 tests/test_build_refdata.py
```
