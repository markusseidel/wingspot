#!/usr/bin/env python3
"""Makes a new snapshot from a published one by adding the airports in a CSV that it doesn't have yet.

Airports that have closed are left out of the OurAirports import, so people could not pick them for a flight from
the past. They are listed by hand in seed/closed_airports.csv, with IDs from 9,000,000 up. The airports in the
snapshot stay exactly as published, so no airport id changes. Writes refdata.sqlite and manifest.json to --out.
Standard library only.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import shutil
import sqlite3
import sys
from pathlib import Path

COLUMNS = {
    "id", "icao_code", "iata_code", "name", "municipality", "iso_country", "continent", "type",
    "latitude_deg", "longitude_deg", "elevation_ft", "closed_on", "keywords",
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--snapshot", type=Path, required=True, help="the published refdata.sqlite")
    parser.add_argument("--airports", type=Path, default=Path(__file__).parent / "seed" / "closed_airports.csv",
                        help="CSV with the airports to have")
    parser.add_argument("--out", type=Path, required=True, help="output directory")
    parser.add_argument("--data-version", required=True)
    args = parser.parse_args()

    args.out.mkdir(parents=True, exist_ok=True)
    database = args.out / "refdata.sqlite"
    shutil.copyfile(args.snapshot, database)
    db = sqlite3.connect(database)
    have = {row[0] for row in db.execute("SELECT id FROM airports")}
    added = []
    with args.airports.open(newline="", encoding="utf-8") as file:
        reader = csv.DictReader(file)
        if set(reader.fieldnames or []) != COLUMNS:
            print(f"error: {args.airports}: expected the columns {sorted(COLUMNS)}", file=sys.stderr)
            return 1
        for row in reader:
            airport_id = int(row["id"])
            if airport_id in have:
                continue
            db.execute(
                "INSERT INTO airports (id, icao, iata, name, city, country_code, continent, type, latitude, longitude,"
                " elevation_ft, default_search, keywords) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?)",
                (
                    airport_id, row["icao_code"] or None, row["iata_code"] or None, row["name"], row["municipality"] or None,
                    row["iso_country"].upper(), row["continent"].upper(), row["type"], float(row["latitude_deg"]),
                    float(row["longitude_deg"]), int(row["elevation_ft"]) if row["elevation_ft"] else None,
                    row["keywords"] or None,
                ),
            )
            added.append(airport_id)
    db.execute("INSERT INTO airports_fts (airports_fts) VALUES ('rebuild')")
    db.execute("INSERT INTO airports_fts (airports_fts) VALUES ('optimize')")
    db.execute("UPDATE meta SET value = ? WHERE key = 'data_version'", (args.data_version,))
    db.commit()
    schema_version = int(db.execute("SELECT value FROM meta WHERE key = 'refdata_schema_version'").fetchone()[0])
    counts = {
        "airports": db.execute("SELECT COUNT(*) FROM airports").fetchone()[0],
        "aircraft_types": db.execute("SELECT COUNT(*) FROM aircraft_types").fetchone()[0],
    }
    db.execute("VACUUM")
    db.close()
    data = database.read_bytes()
    manifest = {
        "schema_version": schema_version, "data_version": args.data_version, "sha256": hashlib.sha256(data).hexdigest(),
        "size_bytes": len(data), "counts": counts, "added_airports": added,
    }
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"added airports {added}; {counts['airports']} airports, {counts['aircraft_types']} types")
    return 0


if __name__ == "__main__":
    sys.exit(main())
