import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TESTS_DIR.parent))

import build_refdata  # noqa: E402
import faa_aircraft_types  # noqa: E402
import postgres_import  # noqa: E402

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
        self.assertEqual(ids, [1, 2, 3, 4, 5, 8])
        self.assertEqual(self.manifest["counts"]["airports"], 6)

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
        self.assertEqual(flags, {1: 1, 2: 1, 3: 1, 4: 0, 5: 1, 8: 1})

    def test_airport_search(self):
        self.assertEqual(self.search_airports("fra"), ["FRA"])
        self.assertEqual(self.search_airports("frank*"), ["FRA"])
        self.assertEqual(self.search_airports("eddl"), ["DUS"])
        self.assertEqual(self.search_airports("new york"), ["JFK"])

    def test_airport_search_ignores_diacritics(self):
        self.assertEqual(self.search_airports("dusseldorf"), ["DUS"])
        self.assertEqual(self.search_airports("düsseldorf"), ["DUS"])

    def test_airport_search_finds_keywords(self):
        self.assertEqual(self.search_airports("munich"), ["MUC"])
        self.assertEqual(self.search_airports("münchen"), ["MUC"])
        self.assertEqual(self.search_airports("munchen"), ["MUC"])
        self.assertEqual(self.search_airports("strauss"), ["MUC"])

    def test_blank_keywords_become_null(self):
        self.assertIsNone(self.one("SELECT keywords FROM airports WHERE id = 1")[0])

    def test_aircraft_type_search(self):
        rows = self.db.execute(
            "SELECT icao_code FROM aircraft_types_fts WHERE aircraft_types_fts MATCH 'a388'"
        ).fetchall()
        self.assertEqual(rows, [("A388",)])
        rows = self.db.execute(
            "SELECT count(*) FROM aircraft_types_fts WHERE aircraft_types_fts MATCH 'family:737'"
        ).fetchone()
        self.assertGreaterEqual(rows[0], 2)  # at least B38M, B738

    def test_registration_tables_exist_but_are_empty(self):
        self.assertEqual(self.one("SELECT count(*) FROM aircraft")[0], 0)
        self.assertEqual(self.one("SELECT count(*) FROM operators")[0], 0)

    def test_records_versions(self):
        meta = dict(self.db.execute("SELECT key, value FROM meta"))
        self.assertEqual(meta, {"refdata_schema_version": "2", "data_version": "test-1"})
        self.assertEqual(self.one("PRAGMA user_version")[0], 2)

    def test_manifest_describes_the_file(self):
        written = json.loads((self.tmp / "out" / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(written, self.manifest)
        data = (self.tmp / "out" / "refdata.sqlite").read_bytes()
        self.assertEqual(written["size_bytes"], len(data))
        self.assertEqual(written["schema_version"], 2)
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
            self.assertIn(wtc, {"L", "M", "H", "J", None})
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

    def keywords_file(self, text):
        path = self.tmp / "keywords.csv"
        path.write_text(text, encoding="utf-8")
        return path

    def test_curated_keywords_are_added_and_searchable(self):
        path = self.keywords_file("icao_code,keywords\nEDDM,Bayern-Flughafen\neddf,lowercase code\nXXXX,Nowhere\n")
        out = self.tmp / "out"
        manifest = build_refdata.build(AIRPORTS, build_refdata.DEFAULT_TYPES_PATH, out, "test", path)

        db = sqlite3.connect(out / "refdata.sqlite")
        self.addCleanup(db.close)
        keywords = db.execute("SELECT keywords FROM airports WHERE icao = 'EDDM'").fetchone()[0]
        self.assertEqual(keywords, "Franz Josef Strauss Airport, Flughafen München Franz Josef Strauß, Bayern-Flughafen")
        found = db.execute("SELECT rowid FROM airports_fts WHERE airports_fts MATCH 'bayern'").fetchall()
        self.assertEqual(found, [(8,)])
        self.assertEqual(manifest["unmatched_keywords"], ["XXXX", "eddf"])

    def test_duplicate_curated_keywords_fail(self):
        path = self.keywords_file("icao_code,keywords\nEDDM,One\nEDDM,Two\n")
        with self.assertRaisesRegex(build_refdata.InputError, "duplicate airport: EDDM"):
            build_refdata.build(AIRPORTS, build_refdata.DEFAULT_TYPES_PATH, self.tmp / "out", "test", path)

    def test_curated_keywords_seed_is_well_formed(self):
        rows = build_refdata._rows(build_refdata.DEFAULT_KEYWORDS_PATH, build_refdata.KEYWORD_COLUMNS)
        codes = [row["icao_code"] for row in rows]
        self.assertEqual(codes, sorted(set(codes)))
        for row in rows:
            self.assertRegex(row["icao_code"], "^[A-Z0-9]{4}$")
            self.assertTrue(row["keywords"])

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


ORDER_TEXT = """
=== PAGE 1 ===
Appendix A. Decode - contents only
A333 Fixed-wing 9J/H Heavy B III 8 NOT, Read From Contents
=== PAGE 2 ===
06/12/2025 JO 7360.1K
Appendix A
A-3
Type
Designator Class
WTC CWT SRS LAHSO MANUFACTURER, Model
A333 Fixed-wing 2J/H Heavy B III 8 AIRBUS, A-330-300
A10* Fixed-wing 2J/L Medium G III FAIRCHILD (1), A-10 Thunderbolt 2
FAIRCHILD (1), OA-10 Thunderbolt 2
A359 Fixed-wing 2J/H Heavy B III 9
AIRBUS, A-350-900 XWB
AIRBUS. ACJ-350-900
C172 Fixed-wing 1P/S Light I I 1
AVIONES COLOMBIA, 172
CESSNA, 172
CESSNA, 172 Skyhawk
A25 @Fixed-wing 1P/S Light I I AEROPRACT, A-25 Breeze
AG60 @Fixed-wing 4T/ Medium III CAIGA, AG-600 Kunlong
MDNT Powered-lift 12E/S I III ARCHER, Midnight
B350 Fixed-wing 2T/S+ Light/Medium H II BEECH, B300
EC35 Helicopter 2T/S Light I I AIRBUS HELICOPTERS, EC-135
NONE Fixed-wing 1P/S Light I I
GANT Fixed-wing CT/S+ Medium H III FAIREY, Gannet
ODD1 Fixed-wing strange row
ZZZZ (any manufacturer), Aircraft type not (yet) assigned a designator
stray text
"""


class FaaAircraftTypesTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.tmp = Path(directory.name)
        self.overrides = self.tmp / "overrides.csv"
        self.overrides.write_text(
            "icao_code,manufacturer,model,family,engine_type,engine_count,wtc\n"
            "A333,Airbus,A330-300,,,,\n"
            "GANT,Fairey,Gannet,,turboprop,2,\n",
            encoding="utf-8",
        )
        self.families = self.tmp / "families.csv"
        self.families.write_text("icao_code,family\nA333,A330\nGONE,Nothing\n", encoding="utf-8")

    def generate(self, spreadsheet=None):
        rows, report = faa_aircraft_types.generate(ORDER_TEXT, self.overrides, self.families, spreadsheet or {})
        return {row["icao_code"]: row for row in rows}, report

    def test_reads_rows_with_the_model_on_later_lines(self):
        rows, _ = self.generate()
        self.assertEqual(rows["A359"]["model"], "A-350-900 XWB")
        self.assertEqual(rows["A359"]["engine_count"], "2")
        self.assertEqual(rows["A359"]["wtc"], "H")

    def test_prefers_the_most_listed_maker(self):
        rows, _ = self.generate()
        self.assertEqual((rows["C172"]["manufacturer"], rows["C172"]["model"]), ("Cessna", "172"))

    def test_removes_the_manufacturer_marker(self):
        rows, _ = self.generate()
        self.assertEqual(rows["A10"]["manufacturer"], "Fairchild")

    def test_reads_amphibians_missing_columns_and_many_engines(self):
        rows, _ = self.generate()
        self.assertIn("A25", rows)
        self.assertEqual(rows["AG60"]["wtc"], "M")
        self.assertEqual(rows["MDNT"]["engine_count"], "12")
        self.assertEqual(rows["MDNT"]["engine_type"], "electric")

    def test_helicopters_use_the_helicopter_engine_type(self):
        rows, _ = self.generate()
        self.assertEqual(rows["EC35"]["engine_type"], "helicopter")

    def test_reports_ambiguous_values_instead_of_guessing(self):
        rows, report = self.generate()
        self.assertEqual(rows["B350"]["wtc"], "")
        self.assertIn("B350", report["undecided"]["wtc"])

    def test_overrides_and_families_win_and_only_where_filled(self):
        rows, _ = self.generate()
        self.assertEqual(rows["A333"]["model"], "A330-300")
        self.assertEqual(rows["A333"]["engine_type"], "jet")
        self.assertEqual(rows["A333"]["family"], "A330")
        self.assertEqual(rows["GANT"]["engine_count"], "2")

    def test_reports_what_it_could_not_use(self):
        rows, report = self.generate()
        self.assertNotIn("NONE", rows)
        self.assertEqual(report["dropped_no_name"], ["NONE"])
        self.assertEqual(report["unparsed_rows"], ["ODD1 Fixed-wing strange row"])
        self.assertEqual(report["unattached_lines"], ["stray text"])
        self.assertEqual(report["special"], ["ZZZZ"])
        self.assertEqual(report["families_not_in_output"], ["GONE"])

    def test_skips_contents_pages(self):
        rows, _ = self.generate()
        self.assertEqual(rows["A333"]["engine_count"], "2")

    def test_uses_the_spreadsheet_model_and_reports_conflicts(self):
        sheet = {"C172": {"Manufacturer": "CESSNA", "Model_FAA": "Cessna Skyhawk 172", "Num_Engines": "2",
                          "Physical_Class_Engine": "Jet", "ICAO_WTC": "Heavy"},
                 "XTRA": {"Manufacturer": "X", "Model_FAA": "X 1"}}
        rows, report = self.generate(sheet)
        self.assertEqual(rows["C172"]["model"], "Skyhawk 172")
        conflicts = report["conflicts_with_spreadsheet"]
        self.assertEqual(len(conflicts["engine_count"]), 1)
        self.assertEqual(len(conflicts["engine_type"]), 1)
        self.assertEqual(len(conflicts["wtc"]), 1)
        self.assertEqual(report["spreadsheet_not_in_order"], ["XTRA"])

    def test_writes_a_type_the_order_lacks_when_its_override_is_complete(self):
        with self.overrides.open("a", encoding="utf-8") as file:
            file.write("CONC,Aérospatiale-BAC,Concorde,,jet,4,H\nHALF,Some,Partial,,,,\n")
        rows, _ = self.generate()
        self.assertEqual((rows["CONC"]["model"], rows["CONC"]["engine_count"], rows["CONC"]["wtc"]), ("Concorde", "4", "H"))
        self.assertNotIn("HALF", rows)

    def test_needs_appendix_a(self):
        with self.assertRaisesRegex(faa_aircraft_types.InputError, "Appendix A not found"):
            faa_aircraft_types.generate("nothing", self.overrides, self.families, {})

    def test_duplicate_override_fails(self):
        self.overrides.write_text(
            "icao_code,manufacturer,model,family,engine_type,engine_count,wtc\nA333,A,B,,,,\nA333,A,B,,,,\n",
            encoding="utf-8",
        )
        with self.assertRaisesRegex(faa_aircraft_types.InputError, "duplicate type: A333"):
            self.generate()


class PostgresImportTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.tmp = Path(directory.name)
        build_refdata.build(AIRPORTS, build_refdata.DEFAULT_TYPES_PATH, self.tmp / "snapshot", "test")
        self.snapshot = self.tmp / "snapshot" / "refdata.sqlite"
        self.out = self.tmp / "sql"

    def files(self):
        return sorted(self.out.glob("*.sql"))

    def test_splits_airports_into_batches_after_the_types(self):
        counts = postgres_import.write_batches(self.snapshot, self.out, batch_size=4)
        self.assertEqual(counts["airports"], 6)
        self.assertEqual(counts["batches"], 3)
        self.assertEqual([path.name for path in self.files()], ["0000.sql", "0001.sql", "0002.sql"])
        self.assertIn("insert into public.aircraft_types", self.files()[0].read_text(encoding="utf-8"))
        self.assertIn("insert into public.airports", self.files()[1].read_text(encoding="utf-8"))

    def test_writes_location_as_longitude_then_latitude(self):
        postgres_import.write_batches(self.snapshot, self.out)
        sql = self.files()[1].read_text(encoding="utf-8")
        self.assertIn("'SRID=4326;POINT(8.570556 50.033333)'::extensions.geography", sql)

    def test_updates_existing_rows_but_not_other_columns(self):
        postgres_import.write_batches(self.snapshot, self.out)
        sql = self.files()[1].read_text(encoding="utf-8")
        self.assertIn("on conflict (id) do update set icao = excluded.icao", sql)
        self.assertNotIn("geofence", sql)
        self.assertNotIn("is_island", sql)

    def test_escapes_text_and_keeps_nulls(self):
        self.assertEqual(postgres_import._literal("O'Hare"), "'O''Hare'")
        self.assertEqual(postgres_import._literal(None), "null")
        self.assertEqual(postgres_import._literal(13), "13")

    def test_replaces_old_batches(self):
        postgres_import.write_batches(self.snapshot, self.out, batch_size=1)
        postgres_import.write_batches(self.snapshot, self.out)
        self.assertEqual(len(self.files()), 2)

    def test_rejects_another_schema_version(self):
        other = self.tmp / "other.sqlite"
        db = sqlite3.connect(other)
        db.execute("PRAGMA user_version = 1")
        db.close()
        with self.assertRaisesRegex(postgres_import.InputError, "schema version 1"):
            postgres_import.write_batches(other, self.out)

    def test_rejects_missing_snapshot(self):
        with self.assertRaisesRegex(postgres_import.InputError, "not found"):
            postgres_import.write_batches(self.tmp / "missing.sqlite", self.out)


if __name__ == "__main__":
    unittest.main()
