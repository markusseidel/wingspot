#!/usr/bin/env python3
"""Writes SQL batches that load a reference snapshot into Postgres.

Check-ins reference airports and aircraft types by the IDs apps read from the snapshot, so the
server tables are loaded from that same file. Batches only add or update rows and can be rerun.
Columns that aren't in the snapshot, such as geofence, are left alone.
"""
from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

SUPPORTED_SCHEMA_VERSION = 2
DEFAULT_BATCH_SIZE = 2000

TYPE_COLUMNS = ("icao_code", "manufacturer", "model", "family", "engine_type", "engine_count", "wtc")
AIRPORT_COLUMNS = ("id", "icao", "iata", "name", "city", "country_code", "continent", "elevation_ft", "location")


class InputError(Exception):
    """The snapshot can't be used."""


def _literal(value: object) -> str:
    if value is None:
        return "null"
    if isinstance(value, (int, float)):
        return repr(value)
    return "'" + str(value).replace("'", "''") + "'"


def _upsert(table: str, columns: tuple[str, ...], key: str, rows: list[list[str]]) -> str:
    values = ",\n".join(f"({', '.join(row)})" for row in rows)
    updates = ", ".join(f"{column} = excluded.{column}" for column in columns if column != key)
    return (
        f"insert into public.{table} ({', '.join(columns)}) values\n{values}\n"
        f"on conflict ({key}) do update set {updates};\n"
    )


def _airport_row(row: tuple) -> list[str]:
    *fields, latitude, longitude = row
    location = f"{_literal(f'SRID=4326;POINT({longitude!r} {latitude!r})')}::extensions.geography"
    return [_literal(field) for field in fields] + [location]


def write_batches(snapshot: Path, out_dir: Path, batch_size: int = DEFAULT_BATCH_SIZE) -> dict:
    """Writes numbered .sql files to out_dir, types first, and returns the row counts."""
    if batch_size < 1:
        raise InputError("batch size must be at least 1")
    if not snapshot.is_file():
        raise InputError(f"{snapshot}: not found")

    db = sqlite3.connect(f"file:{snapshot}?mode=ro", uri=True)
    try:
        version = db.execute("PRAGMA user_version").fetchone()[0]
        if version != SUPPORTED_SCHEMA_VERSION:
            raise InputError(f"{snapshot}: schema version {version}, expected {SUPPORTED_SCHEMA_VERSION}")
        types = db.execute(f"SELECT {', '.join(TYPE_COLUMNS)} FROM aircraft_types ORDER BY icao_code").fetchall()
        airports = db.execute(
            "SELECT id, icao, iata, name, city, country_code, continent, elevation_ft, latitude, longitude"
            " FROM airports ORDER BY id"
        ).fetchall()
    except sqlite3.DatabaseError as error:
        raise InputError(f"{snapshot}: {error}") from error
    finally:
        db.close()

    out_dir.mkdir(parents=True, exist_ok=True)
    for old in out_dir.glob("*.sql"):
        old.unlink()

    statements = [_upsert("aircraft_types", TYPE_COLUMNS, "icao_code", [[_literal(v) for v in row] for row in types])]
    for start in range(0, len(airports), batch_size):
        rows = [_airport_row(row) for row in airports[start:start + batch_size]]
        statements.append(_upsert("airports", AIRPORT_COLUMNS, "id", rows))
    for number, statement in enumerate(statements):
        (out_dir / f"{number:04}.sql").write_text(statement, encoding="utf-8")
    return {"aircraft_types": len(types), "airports": len(airports), "batches": len(statements)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--snapshot", type=Path, required=True, help="published refdata.sqlite")
    parser.add_argument("--out", type=Path, required=True, help="output directory, its .sql files are replaced")
    parser.add_argument("--batch-size", type=int, default=DEFAULT_BATCH_SIZE, help="airports per file")
    args = parser.parse_args()

    try:
        counts = write_batches(args.snapshot, args.out, args.batch_size)
    except (InputError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(f"{counts['aircraft_types']} aircraft types, {counts['airports']} airports, {counts['batches']} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
