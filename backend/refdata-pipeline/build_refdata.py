#!/usr/bin/env python3
"""Builds the on-device reference SQLite database and its manifest.

Uses only the standard library. The same inputs produce an identical file with the same
SQLite version, so the output deliberately contains no build timestamp.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import sqlite3
import sys
from pathlib import Path

PIPELINE_DIR = Path(__file__).resolve().parent
SCHEMA_PATH = PIPELINE_DIR.parents[1] / "contracts" / "refdata" / "schema.sql"
DEFAULT_TYPES_PATH = PIPELINE_DIR / "seed" / "aircraft_types.csv"
DEFAULT_KEYWORDS_PATH = PIPELINE_DIR / "seed" / "airport_keywords.csv"

AIRPORT_COLUMNS = {
    "id", "type", "name", "latitude_deg", "longitude_deg", "elevation_ft", "continent",
    "iso_country", "municipality", "scheduled_service", "icao_code", "iata_code", "keywords",
}
TYPE_COLUMNS = {"icao_code", "manufacturer", "model", "family", "engine_type", "engine_count", "wtc"}
KEYWORD_COLUMNS = {"icao_code", "keywords"}
EXCLUDED_AIRPORT_TYPES = {"closed"}


class InputError(Exception):
    """An input file can't be used at all, as opposed to a single bad row."""


def _rows(path: Path, required: set[str]) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as file:
        reader = csv.DictReader(file)
        missing = required - set(reader.fieldnames or [])
        if missing:
            raise InputError(f"{path}: missing columns: {', '.join(sorted(missing))}")
        return [{key: (value or "").strip() for key, value in row.items() if key} for row in reader]


def _airport(row: dict[str, str]) -> tuple:
    """Converts a CSV row. Raises ValueError if the row is unusable."""
    latitude = float(row["latitude_deg"])
    longitude = float(row["longitude_deg"])
    if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
        raise ValueError("coordinates out of range")
    if not row["name"]:
        raise ValueError("no name")
    if len(row["iso_country"]) != 2 or len(row["continent"]) != 2:
        raise ValueError("invalid country or continent")

    iata = row["iata_code"].upper() or None
    elevation = round(float(row["elevation_ft"])) if row["elevation_ft"] else None
    default_search = iata is not None or row["scheduled_service"] == "yes"
    return (
        int(row["id"]), row["icao_code"].upper() or None, iata, row["name"],
        row["municipality"] or None, row["iso_country"].upper(), row["continent"].upper(),
        row["type"], latitude, longitude, elevation, int(default_search), row["keywords"] or None,
    )


def _curated_keywords(path: Path) -> dict[str, str]:
    keywords: dict[str, str] = {}
    for row in _rows(path, KEYWORD_COLUMNS):
        if not (row["icao_code"] and row["keywords"]):
            raise InputError(f"{path}: incomplete row: {row}")
        if row["icao_code"] in keywords:
            raise InputError(f"{path}: duplicate airport: {row['icao_code']}")
        keywords[row["icao_code"]] = row["keywords"]
    return keywords


def _load_airports(
    db: sqlite3.Connection, path: Path, curated: dict[str, str]
) -> tuple[int, list[str], list[str]]:
    airports, skipped, matched = {}, [], set()
    for row in _rows(path, AIRPORT_COLUMNS):
        if row["type"] in EXCLUDED_AIRPORT_TYPES:
            continue
        extra = curated.get(row["icao_code"].upper())
        if extra:
            matched.add(row["icao_code"].upper())
            row["keywords"] = ", ".join(filter(None, [row["keywords"], extra]))
        try:
            airport = _airport(row)
        except ValueError as error:
            skipped.append(f"airport {row['id'] or '?'}: {error}")
            continue
        if airport[0] in airports:
            skipped.append(f"airport {airport[0]}: duplicate id")
            continue
        airports[airport[0]] = airport

    db.executemany(
        "INSERT INTO airports (id, icao, iata, name, city, country_code, continent, type,"
        " latitude, longitude, elevation_ft, default_search, keywords)"
        " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [airports[key] for key in sorted(airports)],
    )
    db.execute("INSERT INTO airports_fts (airports_fts) VALUES ('rebuild')")
    return len(airports), skipped, sorted(curated.keys() - matched)


def _load_types(db: sqlite3.Connection, path: Path) -> int:
    rows = sorted(_rows(path, TYPE_COLUMNS), key=lambda row: row["icao_code"])
    values = []
    for row in rows:
        if not (row["icao_code"] and row["manufacturer"] and row["model"]):
            raise InputError(f"{path}: incomplete row: {row}")
        count = int(row["engine_count"]) if row["engine_count"] else None
        values.append((
            row["icao_code"], row["manufacturer"], row["model"], row["family"] or None,
            row["engine_type"] or None, count, row["wtc"] or None,
        ))
    try:
        db.executemany("INSERT INTO aircraft_types VALUES (?, ?, ?, ?, ?, ?, ?)", values)
    except sqlite3.IntegrityError as error:
        raise InputError(f"{path}: {error}") from error
    db.executemany(
        "INSERT INTO aircraft_types_fts (icao_code, manufacturer, model, family) VALUES (?, ?, ?, ?)",
        [value[:4] for value in values],
    )
    return len(values)


def build(
    airports: Path, types: Path, out_dir: Path, data_version: str, keywords: Path = DEFAULT_KEYWORDS_PATH
) -> dict:
    """Writes refdata.sqlite and manifest.json to out_dir and returns the manifest."""
    if not data_version:
        raise InputError("data version must not be empty")
    out_dir.mkdir(parents=True, exist_ok=True)
    database = out_dir / "refdata.sqlite"
    temporary = out_dir / "refdata.sqlite.tmp"
    temporary.unlink(missing_ok=True)

    db = sqlite3.connect(temporary)
    try:
        db.executescript(SCHEMA_PATH.read_text(encoding="utf-8"))
        schema_version = db.execute("PRAGMA user_version").fetchone()[0]
        airport_count, skipped, unmatched = _load_airports(db, airports, _curated_keywords(keywords))
        type_count = _load_types(db, types)
        db.executemany(
            "INSERT INTO meta (key, value) VALUES (?, ?)",
            [("refdata_schema_version", str(schema_version)), ("data_version", data_version)],
        )
        db.execute("INSERT INTO airports_fts (airports_fts) VALUES ('optimize')")
        db.execute("INSERT INTO aircraft_types_fts (aircraft_types_fts) VALUES ('optimize')")
        db.commit()
        db.execute("VACUUM")
    except BaseException:
        db.close()
        temporary.unlink(missing_ok=True)
        raise
    db.close()
    temporary.replace(database)

    data = database.read_bytes()
    manifest = {
        "schema_version": schema_version,
        "data_version": data_version,
        "sha256": hashlib.sha256(data).hexdigest(),
        "size_bytes": len(data),
        "counts": {"airports": airport_count, "aircraft_types": type_count},
        "skipped": skipped,
        "unmatched_keywords": unmatched,
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--airports", type=Path, required=True, help="OurAirports airports.csv")
    parser.add_argument("--types", type=Path, default=DEFAULT_TYPES_PATH, help="aircraft types CSV")
    parser.add_argument("--keywords", type=Path, default=DEFAULT_KEYWORDS_PATH, help="curated airport keywords CSV")
    parser.add_argument("--out", type=Path, required=True, help="output directory")
    parser.add_argument("--data-version", required=True, help="identifies this data, e.g. 2026-11-04")
    args = parser.parse_args()

    try:
        manifest = build(args.airports, args.types, args.out, args.data_version, args.keywords)
    except (InputError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    counts = manifest["counts"]
    print(f"{counts['airports']} airports, {counts['aircraft_types']} aircraft types, "
          f"{manifest['size_bytes']} bytes, {len(manifest['skipped'])} rows skipped")
    for message in manifest["skipped"]:
        print(f"skipped {message}", file=sys.stderr)
    for icao in manifest["unmatched_keywords"]:
        print(f"curated keywords for unknown airport {icao}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
