# The Wingspot backup file

A Wingspot backup (`Wingspotted-backup-2026-11-26.wingspotbackup`; files from before the rename are named `Wingspot-backup-…`) holds the whole logbook of the phone: every check-in and the routes of imported KML flights (schema 2; schema 1 files held only what the server did not have yet, #391). It is written so that **nobody needs Wingspot to read it back**. Plan and decisions: [BACKUP-PLAN.md](BACKUP-PLAN.md), issue #310.

## Reading it without the app

The file is ordinary gzip-compressed JSON (UTF-8).

1. Rename it to `backup.json.gz` and unzip it: double-click on a Mac, 7-Zip on Windows, or `gunzip backup.json.gz` in a terminal.
2. Open `backup.json` in any text editor.
3. For the routes on a map, copy the value of `"routes"` (an object starting with `"type": "FeatureCollection"`) into a file `routes.geojson`, and open that in [geojson.io](https://geojson.io), QGIS or Google Earth Pro.

Wingspot also restores an unzipped `.json` file.

## Top level

| Field | Type | Meaning |
|---|---|---|
| `format` | string | Always `"wingspot-backup"`. |
| `schema` | integer | The version of this layout, `2` today. An app refuses a schema newer than it knows and asks to be updated. Schema 1 files are still read. |
| `created_at` | string | When the backup was made, ISO 8601 in UTC. |
| `app` | string | The app and build that wrote it, for information. |
| `platform` | string | `"ios"` or `"android"`, for information. A backup restores on either. |
| `counts` | object | `routes` and `checkins`, for information. |
| `routes` | object | A GeoJSON `FeatureCollection` ([RFC 7946](https://www.rfc-editor.org/rfc/rfc7946)), one `Feature` per flight. |
| `checkins` | array | The check-ins of the logbook. |

Readers ignore fields they do not know, so later versions can add some without breaking older files.

## Routes

Each feature is a `LineString` of the positions of the flight, `[longitude, latitude]` in degrees (WGS 84), rounded to 5 decimals (about 1 m), in flight order. Its `properties`:

| Field | Meaning |
|---|---|
| `checkin_id` | The flight's check-in id (a UUID). This is what ties the route to the flight in the logbook. Always there. |
| `flight_number`, `origin`, `destination` | The flight number and the IATA codes of the airports, for people reading the file. Optional. |
| `day` | The day of the flight, `YYYY-MM-DD` (UTC). Optional. |

The route itself is never sent to the Wingspot server (Flightradar24 terms): it lives on the phone and in this file only.

## Check-ins

Every check-in on the phone, each saying whether the server has it (schema 1 files held only the ones it did not). Photos are not in the backup (they are on the server once a check-in is sent).

| Field | Type | Meaning |
|---|---|---|
| `id` | UUID | The check-in id, the same on every device. Required. |
| `kind` | string | `"spotted"`, `"airport"` or `"flown"`. Required. |
| `occurred_at` | string | When it happened, ISO 8601 in UTC, with or without fractional seconds. Required. |
| `time_known` | boolean | `false` when only the day is known (a backdated entry). Default `true`. |
| `saved_at` | string | When it was saved on the phone. |
| `registration`, `type_icao`, `type_name` | string | The aircraft. |
| `airport_id`, `airport_code` | integer, string | Spotted and airport check-ins: the airport. |
| `latitude`, `longitude` | number | Where the person was, in degrees. |
| `visit_context` | string | Airport check-ins: `"spotting"`, `"departing"`, `"arriving"`, `"transit"`, `"working"` or `"museum"`. |
| `spot_id`, `spot_name` | integer, string | The spotting location. |
| `visit_id` | UUID | Sightings of a session: the airport check-in that started it. |
| `origin_id`, `origin_code`, `destination_id`, `destination_code` | integer, string | Flights: the route. |
| `flight_number`, `cabin`, `seat` | string | Flights. `cabin` is `"economy"`, `"premium_economy"`, `"business"` or `"first"`. |
| `flight_id` | UUID | Airport visits a flight created: that flight. |
| `source_id` | UUID | A check-in taken over from a friend: the friend's check-in. |
| `on_server` | boolean | `true` when the server already has the check-in (schema 2). Default `false`. |
| `owner_id` | UUID | The account the check-in belongs to, when the phone knows it (schema 2, written by the iPhone app). |

Airport ids are the ids of the Wingspot reference data (from [OurAirports](https://ourairports.com/data/)); the codes are there so the file reads without it.

## Restoring

Restore adds, it never deletes. A route whose flight already has one on the phone is skipped unless the person chooses to replace routes; a check-in whose id is already on the phone is skipped. A route for a flight the phone does not have yet is kept and appears when the flight arrives, for example after signing in. A check-in with `on_server` comes back as already sent, so it is not uploaded again; on the iPhone it belongs to `owner_id`, or to the account that is signed in when the file has none. The other check-ins go to the account that is signed in, or the next one that signs in, and are sent like any new check-in.

## Example

[`contracts/test-vectors/backup/example-schema2.json`](../contracts/test-vectors/backup/example-schema2.json) (the same content gzip-compressed: `example-schema2.wingspotbackup`), and the schema 1 file [`example.json`](../contracts/test-vectors/backup/example.json) (`example.wingspotbackup`). Both apps are tested against these files.
