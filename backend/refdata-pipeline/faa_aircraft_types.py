#!/usr/bin/env python3
"""Generates seed/aircraft_types.csv from FAA Order JO 7360.1, Appendix A.

The order lists several makers and models per designator, so this picks one name for each. Curated
files win over those choices, and rows or values it can't read are reported rather than guessed.
Uses only the standard library. The input is the order's text, from extract_pdf.swift.
"""
from __future__ import annotations

import argparse
import collections
import csv
import json
import re
import sys
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

PIPELINE_DIR = Path(__file__).resolve().parent
OVERRIDES_PATH = PIPELINE_DIR / "seed" / "aircraft_type_overrides.csv"
FAMILIES_PATH = PIPELINE_DIR / "seed" / "aircraft_families.csv"
OUTPUT_PATH = PIPELINE_DIR / "seed" / "aircraft_types.csv"
OUTPUT_COLUMNS = ["icao_code", "manufacturer", "model", "family", "engine_type", "engine_count", "wtc"]

ROW = re.compile(
    r"^(?P<code>[A-Z][A-Z0-9]{1,3})\*?\s+[@$]?(?P<cls>Fixed-wing|Helicopter|Gyroplane|Powered-lift)\s+"
    r"(?P<count>\d{0,2})(?P<engine>[A-Z]{1,2})/(?:[JHLS]\+?)?"
    r"(?:\s+(?P<wtc>Super|Heavy|Light/Medium|Medium|Light)(?=\s|$))?"
    r"(?:\s+[A-I](?=\s|$))?(?:\s+I{1,3}(?=\s|$))?(?:\s+\d{1,2}(?=\s|$))?(?:\s+(?P<first>.+))?$"
)
ROW_LIKE = re.compile(r"^[A-Z][A-Z0-9]{1,3}\*?\s+[@$]?(Fixed-wing|Helicopter|Gyroplane|Powered-lift)\b")
SPECIAL = re.compile(r"^[A-Z]{4}\s+\(any manufacturer\)")
# The order has a few typos with a full stop in place of the comma.
ENTRY = re.compile(r"^(?P<maker>[A-Z0-9][^a-z,.]*?(?:\s\(\d\))?)\s*[,.]\s*(?P<model>\S.*)$")
PAGE_FURNITURE = re.compile(
    r"^(\d\d/\d\d/\d{4}\b.*|Appendix A.*|A-\d+|Type|Designator|Designator Class|Class|Engine|Number-|Type/FAA|"
    r"Weight|ICAO|WTC CWT SRS LAHSO.*|\d+ ===.*)$"
)
WTC = {"Super": "J", "Heavy": "H", "Medium": "M", "Light": "L"}
ENGINES = {"E": "electric", "J": "jet", "P": "piston", "R": "rocket", "T": "turboprop"}
# Names that plain capitalization gets wrong. Three letters or fewer stay in capitals.
MAKER_NAMES = {
    "BAE": "BAE Systems", "BELL": "Bell", "BOEI": "Boeing", "CASA": "CASA", "CIRRUS": "Cirrus", "DAHER": "Daher",
    "DE HAVILLAND": "de Havilland", "PZL-MIELEC": "PZL-Mielec", "PZL-SWIDNIK": "PZL-Swidnik", "DE HAVILLAND CANADA": "De Havilland Canada", "DIAMOND": "Diamond",
    "MCDONNELL DOUGLAS": "McDonnell Douglas", "MCDONNELL": "McDonnell", "SAAB": "Saab", "PZL": "PZL",
}


class InputError(Exception):
    """An input can't be used at all, as opposed to a single row."""


def maker_name(raw: str) -> str:
    """Removes the order's (1) marker and turns FAIRCHILD into Fairchild."""
    name = re.sub(r"\s*\(\d\)$", "", raw).strip()
    if name in MAKER_NAMES:
        return MAKER_NAMES[name]
    return " ".join(word if len(word) <= 3 else "-".join(p.capitalize() for p in word.split("-")) for word in name.split())


def parse_order(text: str) -> tuple[dict[str, dict], dict[str, list]]:
    """Reads Appendix A into rows by designator, plus everything it couldn't read."""
    pages = [p for p in text.split("\n=== PAGE ") if re.search(r"^Appendix A\nA-\d+$", p, re.M)]
    if not pages:
        raise InputError("Appendix A not found")

    rows: dict[str, dict] = {}
    problems: dict[str, list] = {"unparsed_rows": [], "unattached_lines": [], "repeated_codes": [], "special": []}
    current = None
    for page in pages:
        for line in page.splitlines():
            line = line.strip()
            if not line or PAGE_FURNITURE.match(line):
                continue
            if SPECIAL.match(line):
                problems["special"].append(line.split()[0])
                current = None
                continue
            match = ROW.match(line)
            if match:
                code = match["code"]
                if code in rows:
                    problems["repeated_codes"].append(code)
                    current = None
                    continue
                current = rows[code] = {
                    "cls": match["cls"], "engine": match["engine"], "count": match["count"],
                    "wtc": match["wtc"], "entries": [],
                }
                line = match["first"] or ""
                if not line:
                    continue
            elif ROW_LIKE.match(line):
                problems["unparsed_rows"].append(line[:100])
                current = None
                continue
            entry = ENTRY.match(line)
            if entry and current is not None:
                current["entries"].append((entry["maker"].strip(), entry["model"].strip()))
            else:
                problems["unattached_lines"].append(line[:100])
    return rows, problems


def choose_name(entries: list[tuple[str, str]], preferred_maker: str | None) -> tuple[str, str]:
    """Picks the FAA spreadsheet's maker or else the most listed one, then that maker's first listed model."""
    counts = collections.Counter(maker for maker, _ in entries)
    maker = counts.most_common(1)[0][0]
    if preferred_maker:
        wanted = re.sub(r"[^A-Z]", "", preferred_maker.upper())
        for candidate in counts:
            if re.sub(r"[^A-Z]", "", re.sub(r"\(\d\)", "", candidate)) == wanted:
                maker = candidate
                break
    model = next(m for mk, m in entries if mk == maker)
    return maker, model


def _spreadsheet_model(sheet: dict | None, maker: str) -> str:
    """The spreadsheet names one model per type, without the order's military variants."""
    model = (sheet or {}).get("Model_FAA", "").strip()
    first, _, rest = model.partition(" ")
    if rest and first.lower() == maker.split()[0].split("-")[0].lower():
        return rest
    return model


def read_spreadsheet(path: Path) -> dict[str, dict]:
    """Reads the FAA Aircraft Characteristics Database by ICAO code."""
    ns = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
    with zipfile.ZipFile(path) as archive:
        strings = [
            "".join(t.text or "" for t in item.iter(f"{{{ns['m']}}}t"))
            for item in ET.fromstring(archive.read("xl/sharedStrings.xml")).findall("m:si", ns)
        ]
        sheet = ET.fromstring(archive.read("xl/worksheets/sheet1.xml")).find("m:sheetData", ns)
    table = []
    for row in sheet:
        cells = {}
        for cell in row:
            value = cell.find("m:v", ns)
            if value is None:
                continue
            column = 0
            for letter in re.match(r"[A-Z]+", cell.get("r")).group():
                column = column * 26 + ord(letter) - 64
            cells[column - 1] = strings[int(value.text)] if cell.get("t") == "s" else value.text
        table.append([cells.get(i, "") for i in range(max(cells, default=-1) + 1)])
    header = table[0]
    return {r[header.index("ICAO_Code")].strip(): dict(zip(header, r)) for r in table[1:] if r}


def _csv_rows(path: Path, required: set[str]) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as file:
        reader = csv.DictReader(file)
        missing = required - set(reader.fieldnames or [])
        if missing:
            raise InputError(f"{path}: missing columns: {', '.join(sorted(missing))}")
        return [{k: (v or "").strip() for k, v in row.items() if k} for row in reader]


def _keyed(path: Path, required: set[str]) -> dict[str, dict[str, str]]:
    result: dict[str, dict[str, str]] = {}
    for row in _csv_rows(path, required):
        if row["icao_code"] in result:
            raise InputError(f"{path}: duplicate type: {row['icao_code']}")
        result[row["icao_code"]] = row
    return result


def generate(text: str, overrides_path: Path, families_path: Path, spreadsheet: dict[str, dict]) -> tuple[list[dict], dict]:
    """Returns the output rows and a report for human review."""
    parsed, problems = parse_order(text)
    overrides = _keyed(overrides_path, set(OUTPUT_COLUMNS))
    families = _keyed(families_path, {"icao_code", "family"})

    output, no_name, undecided = [], [], collections.defaultdict(list)
    for code, row in sorted(parsed.items()):
        override = overrides.get(code, {})
        if row["entries"]:
            sheet = spreadsheet.get(code)
            raw_maker, model = choose_name(row["entries"], sheet["Manufacturer"] if sheet else None)
            maker = maker_name(raw_maker)
        else:
            maker, model = "", ""

        sheet_model = _spreadsheet_model(spreadsheet.get(code), maker)
        if sheet_model:
            model = sheet_model

        wtc = WTC.get(row["wtc"] or "", "")
        engine = "helicopter" if row["cls"] == "Helicopter" else ENGINES.get(row["engine"], "")
        if not wtc:
            undecided["wtc"].append(code)
        if not engine:
            undecided["engine_type"].append(f"{code}:{row['engine']}")

        result = {
            "icao_code": code, "manufacturer": maker, "model": model,
            "family": families.get(code, {}).get("family", ""), "engine_type": engine,
            "engine_count": row["count"], "wtc": wtc,
        }
        result.update({k: v for k, v in override.items() if k in OUTPUT_COLUMNS and v})
        if not (result["manufacturer"] and result["model"] and result["engine_count"]):
            no_name.append(code)
            continue
        output.append(result)

    report = _report(output, parsed, problems, overrides, families, spreadsheet, no_name, undecided)
    return output, report


def _report(output, parsed, problems, overrides, families, spreadsheet, no_name, undecided) -> dict:
    by_code = {row["icao_code"]: row for row in output}
    conflicts: dict[str, list] = {"engine_count": [], "engine_type": [], "wtc": []}
    sheet_engines = {"Jet": "jet", "Piston": "piston", "Turboprop": "turboprop", "Turboshaft": "helicopter"}
    sheet_wtc = {"Super": "J", "Heavy": "H", "Medium": "M", "Light": "L"}
    for code, sheet in spreadsheet.items():
        row = by_code.get(code)
        if not row:
            continue
        if sheet.get("Num_Engines") and sheet["Num_Engines"] != row["engine_count"]:
            conflicts["engine_count"].append(f"{code}: order {row['engine_count']}, spreadsheet {sheet['Num_Engines']}")
        kind = sheet_engines.get(sheet.get("Physical_Class_Engine"))
        if kind and row["engine_type"] and kind != row["engine_type"]:
            conflicts["engine_type"].append(f"{code}: order {row['engine_type']}, spreadsheet {kind}")
        wake = sheet_wtc.get(sheet.get("ICAO_WTC"))
        if wake and row["wtc"] and wake != row["wtc"]:
            conflicts["wtc"].append(f"{code}: order {row['wtc']}, spreadsheet {wake}")
    return {
        "counts": {
            "written": len(output),
            "parsed_from_order": len(parsed),
            "with_family": sum(1 for r in output if r["family"]),
            "without_wtc": sum(1 for r in output if not r["wtc"]),
            "by_engine_type": dict(collections.Counter(r["engine_type"] for r in output).most_common()),
            "by_wtc": dict(collections.Counter(r["wtc"] for r in output).most_common()),
        },
        "dropped_no_name": no_name,
        "undecided": dict(undecided),
        "overrides_not_in_order": sorted(set(overrides) - set(parsed)),
        "families_not_in_output": sorted(set(families) - set(by_code)),
        "spreadsheet_not_in_order": sorted(set(spreadsheet) - set(parsed)),
        "conflicts_with_spreadsheet": conflicts,
        **problems,
    }


def write_csv(rows: list[dict], path: Path) -> None:
    with path.open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, OUTPUT_COLUMNS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--order-text", type=Path, required=True, help="text of JO 7360.1, from extract_pdf.swift")
    parser.add_argument("--spreadsheet", type=Path, help="FAA Aircraft Characteristics Database .xlsx, as a cross-check")
    parser.add_argument("--overrides", type=Path, default=OVERRIDES_PATH)
    parser.add_argument("--families", type=Path, default=FAMILIES_PATH)
    parser.add_argument("--out", type=Path, default=OUTPUT_PATH)
    parser.add_argument("--report", type=Path, required=True, help="where to write the review report (JSON)")
    args = parser.parse_args()

    try:
        spreadsheet = read_spreadsheet(args.spreadsheet) if args.spreadsheet else {}
        rows, report = generate(args.order_text.read_text(encoding="utf-8"), args.overrides, args.families, spreadsheet)
    except (InputError, OSError, zipfile.BadZipFile, ET.ParseError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    write_csv(rows, args.out)
    args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"{len(rows)} aircraft types written, report in {args.report}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
