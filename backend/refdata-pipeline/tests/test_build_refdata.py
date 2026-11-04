import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TESTS_DIR.parent))

import build_refdata  # noqa: E402

AIRPORTS = TESTS_DIR / "fixtures" / "airports.csv"


class BuildRefdataTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.tmp = Path(directory.name)
        self.manifest = build_refdata.build(
            AIRPORTS, build_refdata.DEFAULT_TYPES_PATH, self.tmp / "out", "test-1"
        )
        self.db = sqlite3.connect(self.tmp / "out" / "refdata.sqlite")
        self.addCleanup(self.db.close)

    def one(self, sql, *args):
        return self.db.execute(sql, args).fetchone()

    def search_airports(self, query):
        rows = self.db.execute(
            "SELECT airports.iata FROM airports_fts JOIN airports ON airports.id = airports_fts.rowid"
            " WHERE airports_fts MATCH ? ORDER BY airports.id",
            (query,),
        )
        return [row[0] for row in rows]

    def test_imports_only_usable_airports(self):
        ids = [row[0] for row in self.db.execute("SELECT id FROM airports ORDER BY id")]
        self.assertEqual(ids, [1, 2, 3, 4, 5])
        self.assertEqual(self.manifest["counts"]["airports"], 5)

    def test_reports_bad_rows_but_not_closed_airports(self):
        skipped = " ".join(self.manifest["skipped"])
        self.assertEqual(len(self.manifest["skipped"]), 2)
        self.assertIn("airport 7: coordinates out of range", skipped)
        self.assertIn("airport 1: duplicate id", skipped)

    def test_duplicate_id_keeps_first_row(self):
        self.assertEqual(self.one("SELECT name FROM airports WHERE id = 1")[0], "Frankfurt Airport")

    def test_maps_columns(self):
        self.assertEqual(
            self.one("SELECT icao, iata, city, country_code, continent, elevation_ft FROM airports WHERE id = 2"),
            ("KJFK", "JFK", "New York", "US", "NA", 13),
        )

    def test_blank_values_become_null(self):
        self.assertEqual(
            self.one("SELECT icao, iata, city, elevation_ft FROM airports WHERE id = 4"),
            (None, None, None, None),
        )

    def test_default_search_needs_iata_or_scheduled_service(self):
        flags = dict(self.db.execute("SELECT id, default_search FROM airports"))
        self.assertEqual(flags, {1: 1, 2: 1, 3: 1, 4: 0, 5: 1})

    def test_airport_search(self):
        self.assertEqual(self.search_airports("fra"), ["FRA"])
        self.assertEqual(self.search_airports("frank*"), ["FRA"])
        self.assertEqual(self.search_airports("eddl"), ["DUS"])
        self.assertEqual(self.search_airports("new york"), ["JFK"])

    def test_airport_search_ignores_diacritics(self):
        self.assertEqual(self.search_airports("dusseldorf"), ["DUS"])
        self.assertEqual(self.search_airports("düsseldorf"), ["DUS"])

    def test_aircraft_type_search(self):
        rows = self.db.execute(
            "SELECT icao_code FROM aircraft_types_fts WHERE aircraft_types_fts MATCH 'a388'"
        ).fetchall()
        self.assertEqual(rows, [("A388",)])
        rows = self.db.execute(
            "SELECT count(*) FROM aircraft_types_fts WHERE aircraft_types_fts MATCH 'family:737'"
        ).fetchone()
        self.assertEqual(rows[0], 2)  # B38M, B738

    def test_registration_tables_exist_but_are_empty(self):
        self.assertEqual(self.one("SELECT count(*) FROM aircraft")[0], 0)
        self.assertEqual(self.one("SELECT count(*) FROM operators")[0], 0)

    def test_records_versions(self):
        meta = dict(self.db.execute("SELECT key, value FROM meta"))
        self.assertEqual(meta, {"refdata_schema_version": "1", "data_version": "test-1"})
        self.assertEqual(self.one("PRAGMA user_version")[0], 1)

    def test_manifest_describes_the_file(self):
        written = json.loads((self.tmp / "out" / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(written, self.manifest)
        data = (self.tmp / "out" / "refdata.sqlite").read_bytes()
        self.assertEqual(written["size_bytes"], len(data))
        self.assertEqual(written["schema_version"], 1)
        self.assertRegex(written["sha256"], "^[0-9a-f]{64}$")

    def test_build_is_deterministic(self):
        again = build_refdata.build(AIRPORTS, build_refdata.DEFAULT_TYPES_PATH, self.tmp / "again", "test-1")
        self.assertEqual(again["sha256"], self.manifest["sha256"])

    def test_data_version_changes_the_file(self):
        other = build_refdata.build(AIRPORTS, build_refdata.DEFAULT_TYPES_PATH, self.tmp / "other", "test-2")
        self.assertNotEqual(other["sha256"], self.manifest["sha256"])

    def test_leaves_no_temporary_file(self):
        self.assertFalse((self.tmp / "out" / "refdata.sqlite.tmp").exists())

    def test_foreign_keys_and_integrity_hold(self):
        self.assertEqual(self.one("PRAGMA integrity_check")[0], "ok")
        self.assertEqual(self.db.execute("PRAGMA foreign_key_check").fetchall(), [])

    def test_seed_types_are_unique_and_well_formed(self):
        rows = self.db.execute("SELECT icao_code, wtc, engine_count FROM aircraft_types").fetchall()
        self.assertGreater(len(rows), 0)
        for code, wtc, engines in rows:
            self.assertRegex(code, "^[A-Z0-9]{2,4}$")
            self.assertIn(wtc, {"L", "M", "H", "J"})
            self.assertGreater(engines, 0)


class InvalidInputTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.tmp = Path(directory.name)

    def test_missing_column_fails_and_keeps_previous_database(self):
        out = self.tmp / "out"
        build_refdata.build(AIRPORTS, build_refdata.DEFAULT_TYPES_PATH, out, "good")
        before = (out / "refdata.sqlite").read_bytes()

        bad = self.tmp / "bad.csv"
        bad.write_text("id,name\n1,Nowhere\n", encoding="utf-8")
        with self.assertRaisesRegex(build_refdata.InputError, "missing columns.*icao_code"):
            build_refdata.build(bad, build_refdata.DEFAULT_TYPES_PATH, out, "bad")

        self.assertEqual((out / "refdata.sqlite").read_bytes(), before)
        self.assertFalse((out / "refdata.sqlite.tmp").exists())

    def test_duplicate_aircraft_type_fails(self):
        types = self.tmp / "types.csv"
        types.write_text(
            "icao_code,manufacturer,model,family,engine_type,engine_count,wtc\n"
            "A388,Airbus,A380-800,A380,jet,4,J\n"
            "A388,Airbus,A380-800,A380,jet,4,J\n",
            encoding="utf-8",
        )
        with self.assertRaises(build_refdata.InputError):
            build_refdata.build(AIRPORTS, types, self.tmp / "out", "test")

    def test_empty_data_version_fails(self):
        with self.assertRaises(build_refdata.InputError):
            build_refdata.build(AIRPORTS, build_refdata.DEFAULT_TYPES_PATH, self.tmp / "out", "")


if __name__ == "__main__":
    unittest.main()
