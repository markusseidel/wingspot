#!/usr/bin/env python3
"""Makes a new snapshot from a published one by adding the aircraft types in a CSV that it doesn't have yet.

The airports stay exactly as published, so no airport id changes. Use it to publish a few more types without
rebuilding the airport data. Writes refdata.sqlite and manifest.json to --out. Standard library only.
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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--snapshot", type=Path, required=True, help="the published refdata.sqlite")
    parser.add_argument("--types", type=Path, required=True, help="CSV with the types to have, as in seed/aircraft_types.csv")
    parser.add_argument("--out", type=Path, required=True, help="output directory")
    parser.add_argument("--data-version", required=True)
    args = parser.parse_args()

    args.out.mkdir(parents=True, exist_ok=True)
    database = args.out / "refdata.sqlite"
    shutil.copyfile(args.snapshot, database)
    db = sqlite3.connect(database)
    have = {row[0] for row in db.execute("SELECT icao_code FROM aircraft_types")}
    added = []
    with args.types.open(newline="", encoding="utf-8") as file:
        for row in csv.DictReader(file):
            if row["icao_code"] in have:
                continue
            values = (
                row["icao_code"], row["manufacturer"], row["model"], row["family"] or None, row["engine_type"] or None,
                int(row["engine_count"]) if row["engine_count"] else None, row["wtc"] or None,
            )
            db.execute("INSERT INTO aircraft_types VALUES (?, ?, ?, ?, ?, ?, ?)", values)
            db.execute("INSERT INTO aircraft_types_fts (icao_code, manufacturer, model, family) VALUES (?, ?, ?, ?)", values[:4])
            added.append(row["icao_code"])
    db.execute("UPDATE meta SET value = ? WHERE key = 'data_version'", (args.data_version,))
    db.execute("INSERT INTO aircraft_types_fts (aircraft_types_fts) VALUES ('optimize')")
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
        "size_bytes": len(data), "counts": counts, "added_types": added,
    }
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"added {added}; {counts['aircraft_types']} types, {counts['airports']} airports")
    return 0


if __name__ == "__main__":
    sys.exit(main())
