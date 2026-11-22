# KML import, real flight track and real flown distance: plan for issues #236 to #239

Issues by vogtim (epic #236 with #237 import, #238 track on a map, #239 real distance). Status: plan only, no code changes with this document. Where the issue text is a proposal and the app already does something different, this plan says so and recommends one way.

## What the issues ask for

| Issue | Ask |
|---|---|
| #237 import | Upload a Flightradar24 (FR24) `.kml` file and get a pre-filled flight entry: flight number, airline, route, times, type, registration. Review before saving, duplicates warned, deleting the flight deletes everything derived. The raw track is stored unchanged. |
| #238 track | The raw track (thousands of points) is simplified, stored light and shown on a map on the flight page. A flight over the date line must be one continuous line. |
| #239 distance | Flown distance from the raw track, great-circle distance, and the detour between them. Stats: total flown, per year, longest, biggest detour. Flights without a track show the great-circle distance, marked as such. |

#238 and #239 both need only the raw track from #237, so they can be built in parallel.

## What already exists

- **A flown check-in** (`checkins`, kind `flown`) has `origin_id`, `destination_id`, `flight_number`, `cabin_class`, `seat`, `aircraft_id` / `type_icao`, and `distance_km` (integer). The server works `distance_km` out when the flight is saved (`sync_checkins`, `edit_checkins`): `round(st_distance(origin.location, destination.location) / 1000)`. `st_distance` on `geography` is measured on the WGS84 ellipsoid, not on a sphere.
- **`distance_km` is used everywhere:** the distance badges (`distance_flown_km`), the friends leaderboard, "compare with a friend", the feed and `get_checkin`, and on the device the stats card (`CheckInStats`, using `GreatCircle` haversine from airport coordinates, checked against `contracts/test-vectors/distances.json`).
- **Airports** carry `icao`, `iata`, `name`, `city`, `location`, so IATA and ICAO codes from a KML can be resolved without a separate table (the issue's prototype needs an `iata-icao.csv`).
- **Offline-first sync.** New check-ins go through an outbox with local ids. Photos have their own outbox that runs after the check-in (`PhotoOutbox` on iOS, the matching code on Android). A track fits the same pattern.
- **Deleting** a check-in deletes photos by foreign key (`on delete cascade`). The same works for a track table.
- **Registration** parsing and normalisation exists on both platforms.
- **Aircraft types.** The live type list is short (27 types) until the licensing question is answered, and a flight with an unknown type is rejected as `unknown_type`. An import must leave the type empty when it is not in the list, never fail the flight.
- **Maps.** iOS uses MapKit, Android uses Google Maps Compose (needs the maps key, the maps explain when it is not set).
- **FR24 today** is only two links ("Look up the flight on Flightradar24"). Nothing is read from FR24 and no file import exists. A file the user picks is new ground on both platforms.

## Recommendations (decisions are listed in "Decisions needed")

### 1. Where the file is read: on the device

Parse the KML on the phone, show the review screen, and send only the fields and the track. The KML never leaves the device. This matches how boarding-pass scanning (BCBP) works and needs no new server parser. It means two parser implementations (Swift, Kotlin) that must agree, which is the rule already used for BCBP, registrations and distances: shared fixtures in `contracts/test-vectors/` that both test suites read.

Alternative: upload the file and parse it in an edge function (one implementation, but a multi-megabyte upload and a parser on the server for an undocumented HTML format). Not recommended.

### 2. One distance method on the server

The issue proposes haversine on the track and a great-circle reference. The server already measures the airport-to-airport figure on the ellipsoid. If the track were summed with haversine (a sphere, up to about 0.5 percent off) and compared with an ellipsoidal reference, the "detour" would carry a systematic error of the same size as a small detour. So:

- The server computes **both** numbers with PostGIS on the ellipsoid: the existing `distance_km` stays the airport-to-airport figure, and `st_length(track::geography)` gives the flown figure.
- PostGIS `geography` handles the date line without an unwrap, so #239's point 3 holds by construction.
- The app shows what the server returns. The haversine in `GreatCircle` stays for the offline stats card and for flights with no track.

### 3. Storage

One new private table, one new column set on `checkins`. Names are suggestions.

```
flight_tracks
  checkin_id   uuid primary key references checkins on delete cascade
  raw          geometry(LineStringZ, 4326)   -- as in the file, lon, lat, altitude; never changed
  simplified   geography(Geometry, 4326)     -- what the map draws, MultiLineString cut at the antimeridian (RFC 7946)
  bbox         jsonb / four numbers          -- for "fit the map to the route"
  points_raw, points_simplified  integer
  crosses_antimeridian boolean
  flown_km     double precision              -- st_length(raw::geography) / 1000, not rounded
  epsilon_m    integer                       -- which tolerance made `simplified`, so it can be rebuilt

checkins (new columns)
  import_source text      -- 'fr24_kml', null for everything else
  import_ref    text      -- the FR24 flight id from the link in the file
  unique index (user_id, import_ref) where import_ref is not null
```

- **Raw track is owner-only.** Row-level security lets only the owner read `raw`. The simplified line follows the check-in's visibility (public, friends, private), because it is what the flight page shows. This keeps the per-point detail out of other people's reach.
- **Deleting** the check-in removes the track by foreign key. Account erasure already removes the user's check-ins, so the track goes with them. No separate cleanup. A pgTAP test proves it.
- **Size.** A long-haul flight has some tens of thousands of points. Send the raw track as a compact text (Google encoded-polyline style, about 5 bytes per point at 1e-5 degrees, roughly 1 m) instead of JSON pairs. The server decodes it. Altitude is optional and only needed if taxi positions are to be trimmed later.
- **The duplicate rule** has two keys, as the issue says: the same FR24 flight id (`import_ref`) is a hard match; the same flight number on the same date is a warning the user may override (two legs can share a flight number and date).

### 4. Simplification on the server, from the raw track

The raw track is kept, so the simplified line can be rebuilt later with a better tolerance. Doing it in SQL gives one implementation instead of two.

1. Unwrap longitudes first, so no step sees a 360 degree jump (a window function over the points: each longitude is the one of `lon`, `lon - 360`, `lon + 360` closest to the previous point).
2. Project to Web Mercator (EPSG:3857) and run `ST_Simplify` (Ramer-Douglas-Peucker) with a tolerance in **metres**. This fixes the prototype's lesson that 0.005 degrees is a different distance east-west than north-south. Start at about 100 m for the flight page, tune from the logged point counts. A second, coarser level (about 1 km) for an all-flights map is optional and can come later.
3. Cut the result at the antimeridian into a `MultiLineString` for storage; the apps unwrap again at render time if their map needs one continuous line.
4. Compute the bbox from the unwrapped line.

Notes and risks:

- Web Mercator is undefined near the poles (beyond about 85 degrees). Airliner routes stay below that; the function clamps and logs instead of failing.
- Visvalingam-Whyatt (`ST_SimplifyVW`) is an alternative that often looks smoother. Compare both on a few real tracks before fixing the choice. This is a tuning step, not a design change.
- **How MapKit and Google Maps draw a line that crosses the date line is not verified.** Test the Tokyo to Los Angeles fixture on both platforms in the first map PR, and unwrap at render time only if a map needs it.

### 5. The import flow

1. **Getting the file in.** iOS: a "Import from file" action (`fileImporter`) and opening a `.kml` from the Files app or the share sheet. Android: `OpenMultipleDocuments` and a `VIEW`/`SEND` intent filter for `.kml`. Several files are accepted from the start, because the picker allows it.
2. **Parse** (`KmlFlight` on both platforms, pure code, no UI):
   - Track: every `<coordinates>` block with at least two points; drop sparse straight lines (an origin to destination line); take the block with the most points; fall back to the `Point` placemarks sorted by `<when>`.
   - Metadata: unescape the HTML in `<description>`, try the newer template (airport links, `<h3>IATA</h3>`) and the older one (`From: <b>Name (IATA)</b>`, `Departure:`); flight number from the `/flight/<id>` link, registration from the `/reg/<reg>` link; fallbacks `XXX-YYY` for the route and the first timestamp for the date.
   - **Every field is optional.** A missing field leaves an empty input and never stops the import.
3. **Resolve** IATA and ICAO codes to airport ids from the reference snapshot already on the device. A code that is not found leaves the airport empty and the user picks it.
4. **Review screen = the existing flown form**, pre-filled. A banner shows what was found and what was not. Nothing is saved before the user taps save.
5. **Save** like any flight, then queue the track in a second outbox step after the check-in is accepted (like photos), so an import works offline. Until the server has answered, the app shows the great-circle figure marked as such.
6. **Batch import** (several files) shows one review list and saves the ticked ones. It is a nice-to-have, so it goes into the last step of #237.

### 6. Showing the track (#238)

- Flight page: a map with the simplified line, start and end markers, zoomed to the bbox (not the centre of all points). Own flights show it; other people's flights show it when the check-in is visible to the viewer.
- **Raw and simplified point counts** are stored and may be shown in a small "debug" line behind a long-press in beta builds only.
- The "all flights of a user on one map or globe" is optional in the issue. Keep it out of the first release; it reuses the coarser level above.
- Account-wide map views are not changed.

### 7. Showing the distance (#239)

- Flight page: **great-circle distance**, **flown distance**, **detour** as "+X km (+Y percent)". Flights without a track show only the great-circle distance with a "great-circle" label.
- Stats (the profile stats card and, later, the extended stats view, see [EXTENDED-STATS.md](EXTENDED-STATS.md)): total km flown (real), per year, longest flight, biggest detour. Units follow the existing km / mi / nm setting.
- **Large gaps** (over the ocean): a gap becomes a straight segment, slightly short. A flight whose track has a gap above a threshold (to be tuned, for example 200 km) is marked "estimated".
- **Start and end.** The first and last point are not always at the airport. Add the airport to the first point and the last point to the airport when the gap is more than a few km, so taxi and the missing bits are included. Decide the threshold from the fixtures.

**Which number counts for badges and the leaderboard** is the biggest side effect (see "Decisions needed"). `distance_km` feeds distance badges, the friends leaderboard and compare. The plan keeps all of those on the airport-to-airport figure until the owner decides, so nobody's badges or ranking change by importing a file.

### 5a. Add a route to an existing flight (request by farodin91 on #236)

People log a flight first and export the file later, and Tim's flight in the beta showed that a flight saved without a file can never get a route. So the page of **your own flight** gets one more action, on both apps, device-only like the rest:

- **Where:** the flown flight page, under the flight details. "Add a route from a KML file" when the flight has no route, "Replace the route from a file" when it has one. Only for your own flights and only while the server switch `kml_import` is on.
- **Flow:** pick a file, read and parse it on the device (same parser as the import), then a confirmation that says what was found (positions, flown distance, and the detour as on the import form). Nothing is saved before the person confirms.
- **Never overwrites anything but the route.** Airports, date, flight number, registration and type of the flight stay as they are. The file's other fields are ignored.
- **Warnings, not blocks:** the file's airports differ from the flight's (compared by IATA code), or the file's day is more than 36 hours from the flight. The text says so and the person can still save, because airport codes in old files can differ and a wrong day is the person's call.
- **Replace:** when the flight already has a route, the confirmation says it will be replaced.
- **A file without a route** (no track, or only a straight line) says so and saves nothing.
- **Storage:** the same one file per check-in on the device (`FlightTrackFiles`), so the page, the stats and the map pick it up at once. Nothing goes to the server.
- **Not in this step:** attaching a route from the form of an already saved flight in the edit view, and a share-sheet entry. The batch import stays in step 6.

## Steps and size

| PR | Content | Size | Depends on |
|---|---|---|---|
| 0 | **Synthetic** KML fixtures written by hand from the documented structure: both description templates, a flight with a missing field, a placemark-only file, and a made-up Tokyo to Los Angeles track across the date line. Real FR24 files are used only locally for checking and are never committed (see "Test files") | small | none |
| 1 | Backend: migration (`flight_tracks`, new `checkins` columns), `save_flight_track` function (decode, unwrap, simplify, bbox, flown km), RLS, `get_checkin` and the feed reads return `flown_km` and the simplified line, pgTAP tests (RLS, delete cascade, date line, duplicate key), api-test, `access_test` function list, contract test vectors for track distance | medium | none |
| 2 | Parsers `KmlFlight` (Swift package and Kotlin core) with the shared synthetic fixtures, unit tests | medium | PR 0 |
| 3 | Import UI on iOS and Android: file picker, review on the flown form, duplicate warning, track outbox step, strings (German and English), both platforms clicked through | large | PR 1, 2 |
| 4 | Track on the flight page, both platforms (#238) | medium | PR 1, 3 |
| 5 | Distance on the flight page and the stats (#239) | medium | PR 1, 3 (independent of PR 4) |
| 6 | Batch import, "estimated" flag, optional all-flights map | later | PR 3 |

Production steps (migration push, function deploy, store builds) happen only on the owner's explicit word, as usual. Every user-facing change lands on iOS and Android together.

## Tests

- **Parser:** every field missing in turn, both templates, a file with no usable track, a file with only placemarks, HTML-escaped and unescaped text, an antimeridian fixture.
- **Server:** track distance against known values on the ellipsoid, the date line, a track of 2 points, a track of 50 000 points (time and size), duplicate key, RLS (owner reads raw, a friend reads only the simplified line of a friends-visible flight, a stranger nothing), cascade on delete and on account erasure.
- **Contract:** a shared JSON file of track distances so server, Swift and Kotlin agree on the rounded values shown.
- **App:** import from a real file on a device on both platforms, offline import then back online, the detour for a flight around closed airspace is clearly above the great-circle distance (the acceptance criterion in #239).

## Acceptance criteria, mapped

| Criterion | Where it is met |
|---|---|
| KMLs of both templates create a pre-filled entry (#237) | PR 2, 3 |
| Missing fields do not break the import (#237) | PR 2 tests, PR 3 |
| Same flight twice shows a duplicate warning (#237) | PR 1 (key), PR 3 (warning) |
| The raw track is stored, 2 or more points (#237) | PR 1 |
| Deleting a flight removes all derived data (#237) | PR 1 (cascade) |
| Looks like the raw track at normal zoom (#238) | PR 4, tolerance tuned in PR 1 |
| Tokyo to Los Angeles is one line (#238) | PR 1 (storage), PR 4 (render, test on both platforms) |
| Raw track unchanged, counts stored (#238) | PR 1 |
| Flown distance from the raw track, not the simplified one (#239) | PR 1 (computed from `raw`) |
| Detour around closed airspace is clearly higher (#239) | PR 5 |
| No jump across the date line (#239) | PR 1 (geography) |
| No track: great-circle marked as such (#239) | PR 5 |

## Decisions needed (owner)

1. **Which distance counts for badges, the leaderboard and the stats card?** (a) keep the airport-to-airport figure for those and show the real figure next to it (recommended, nothing changes retroactively); (b) switch to the real figure where a track exists (more honest, but badge levels and rankings move, and importing a file becomes a way to gain km); (c) a setting.
2. **Is KML import a Pro feature?** It fits the extended-stats idea of a Pro depth ([EXTENDED-STATS.md](EXTENDED-STATS.md)). Recommendation: free for the flight and the map, Pro only for the "real distance" statistics, if billing exists by then.
3. **Is using FR24 files allowed?** Not settled, see "FR24 terms of service" below. Until FR24 answers, the feature stays in beta groups and the plan's step 3 builds only the private, on-device path first. This is the one item that could stop the project.
4. **Privacy text.** A stored track says exactly when and where an aircraft flew with the user aboard. The privacy draft needs a line, and raw tracks stay owner-only (above).

## FR24 terms of service (read 22 November 2026)

Source: the [Terms of Service](https://www.flightradar24.com/terms-of-service), last updated 23 June 2026 (Flightradar24 AB, Sweden, Swedish law). This is a reading of the text, not legal advice. The terms do not mention KML files or third-party apps, so only FR24 can answer the open points. The page about the KML export tools could not be read, so who may export (Premium tiers) is from a search result and still to be confirmed.

| Clause | What it says | What it means here |
|---|---|---|
| 2.1 | The right to use is non-transferable and for personal, non-commercial use | The user's own use of their own file is the safe core |
| 5.3.1 | Commercial use, and any "public display (commercial or non-commercial)", needs the Business subscription | Showing a track to others in a product with a planned Pro tier may count |
| 2.3, 10.3 | Only human-operated browser or app; no robots, no scraping | No problem: Wingspot never contacts FR24, the user downloads the file |
| 8.2 | Published material that uses the content must credit Flightradar24 | A credit line would be needed wherever a derived line or distance is shown |
| 8.3, 10.2 | Do not let others access or reproduce information for unpermitted uses; no transfer or sublicensing of content to third parties | Uploading the raw track to our server, and showing it to friends, are the unclear parts |
| 2.5 | If the right to use ends, downloaded information must be destroyed | Another reason to keep the raw track deletable with the flight |
| 6.3.1 | The API allows commercial use but forbids persistent local copies and redistribution of raw data | The API is not a way to store tracks, so it is no alternative |

### Three levels, from safest to riskiest

1. **Private, on the device only.** The file is read on the phone, the track and distance stay in the app on that phone, nothing is uploaded or shown to anyone. Closest to "personal use".
2. **Private, stored in the user's account.** The track is uploaded to our server so it follows the user to other devices, owner-only (as in this plan). A transfer to a third party (us) is involved, which 2.1 and 10.2 do not clearly allow.
3. **Shared with friends.** The simplified line or the real distance shows in the feed or on a friend's view. This is where "public display" in 5.3.1 and clause 8.3 are most likely to apply.

### Effect on the steps

- Build the parser and the on-device import (PR 2, and the on-device part of PR 3) first. They are level 1 and do not depend on FR24's answer.
- Design PR 1 (server storage) so that levels 2 and 3 are switches: the table exists, but the upload and the sharing are turned on only after FR24 has answered. For level 3 the track's visibility is forced to "private" until then, even if the flight is public.
- Nothing from FR24 is shown to other users in the first release. The flown distance of an imported flight is shown only to its owner. This also settles decision 1 (the badges and leaderboard stay on the airport-to-airport figure).
- Whatever is shown gets a credit to Flightradar24 (8.2).

### A switch to turn the import off without an app update

The test builds already contain the import, and a "no" from FR24 should not need a new app version to take effect. `/v1/config` already returns `feature_flags` (a JSON object in the `app_config` table, one row). Plan:

- Add a flag `kml_import`. It is **on** when the key is missing, so offline and old behaviour do not change.
- Both apps read it when they read the config, remember the last value on the device, and hide the "Import a KML file" button when it is off. If the config can't be read, the last known value is used.
- **A build that was made before the flag exists cannot be switched off**, because it never reads it. The first build with the flag is therefore the one to hand to testers; the two builds from 22 November are the exception and are replaced by the next upload.
- A second flag `kml_tracks_keep` decides whether saved routes stay on the phones. When it is off, the apps delete the route files they hold, at the next start. Flights themselves stay.
- Switching it is a one-row update in the hosted database. That is a production change, so it needs the owner's explicit word, as usual.
- Tim's remark (issue 236) that the original path is not needed also helps: if FR24 allows personal use only, the track can be reduced to the thinned-out line, or dropped, and only the facts the user confirms (flight number, date, airports, aircraft type) stay.

### What three real exports looked like (22 November 2026)

Checked on one machine, with files the author sent; the files are not in the repository. All three were the newer layout. The flight data is in the description of the document. The track is **not** one line: a folder `Route` holds one two-point segment per step (too short to count as a track), and a folder `Trail` holds one timestamped point per position report, with altitude, speed and heading in its description. So the track comes from the timestamped points, sorted by time (793, 389 and 1138 points, flown distances 2 920, 504 and 11 486 km). The Helsinki flight crosses the 180° meridian on its detour around Russia, and its flown distance is far above the direct way. Altitude and speed per point are there if taxi positions should be trimmed later.

### Test files

This repository is public under the MIT licence, so a committed file is republished to everyone. Real FR24 exports therefore never go into the repository, the issues or the docs, and the same goes for the contents of the real `<description>` HTML. The parser tests use **synthetic** files: invented flights, invented tracks, hand-written from the structure described in the issues. Real files, if the issue author sends them privately, are used on one machine to check that the parser reads them, and are not kept in the working tree that gets committed.

### If FR24 says no

Switch `kml_import` off (see above), publish a build without the button, and remove the saved routes from the phones. Server upload and sharing were never switched on, so nothing needs to be deleted on the server. Tell the testers in German and English.

### Next step

A question to FR24 has been drafted (not sent). It asks the three levels as separate questions, asks whether a licence is needed, and how to credit. FR24 publishes no email address for this on its own pages: the official routes are the help center at support.fr24.com and the business inquiry form on the data-for-business page. `business@fr24.com` appears only in a LinkedIn post by their sales staff and must be verified before use.

## Open questions (for vogtim)

- Please share the prototype script and 3 to 4 real KML files, with the two templates and one date-line flight (Tokyo to Los Angeles), **privately** (by email or a private message), not in a public issue or pull request. They are used only to check the parser on a local machine and are never committed. Without real files the synthetic fixtures could miss how the format really looks.
- ~~Are the ATD and ETA in the description UTC or local time?~~ **Answered by three real files (checked on one machine, not committed): UTC.** The file prints "Coordinated Universal Time" next to each time, and the parser reads that into `timesAreUtc`. The author can still confirm that it is always so.
- Does FR24 offer the KML download in the phone app, or only on the website? This decides whether the file arrives through the share sheet or has to be moved by hand.
- ~~Does the file contain the aircraft type?~~ **Yes, in three real files**: `Aircraft (A359)` with the name below it. The parser reads it. A type missing from the live list stays empty after the import.

## Risks

- **The HTML in `<description>` is undocumented and changes.** Mitigation: every field optional, fixtures per template, an "import found these fields" banner so a silent format change is noticed in the beta.
- **Time zones** of ATD and ETA: UTC in the three real files, flagged by `timesAreUtc`. If a file says nothing, the times stay unconverted.
- **Map rendering over the date line** on both platforms (see 4).
- **Android maps key.** The track map needs the Google Maps key like the other maps.
- **Large files and batches** can be slow on old phones. Parse off the main thread and show progress.
- **Short type list.** Imported flights with a type that is not in the live list import without a type (as today's manual entry would be rejected).
