# Aircraft check-in with a spotting location: plan for issue #286

Issue by vogtim: when you check in an aircraft, you cannot say at which spotting place you saw it. Status: built (PRs for issue #286; see "As built" at the end).

## What the issue asks for

1. An optional spotting location on an aircraft check-in, with the same picker as the airport check-in. It lists the places of the airport chosen for the sighting.
2. The aircraft check-in shows where it was seen ("Spotted at Besucherterrasse, FRA").
3. The page of a spotting location lists the aircraft spotted there.

## What already exists (and what it means)

- **A sighting can already show a place, but only through a session.** A visit at a place starts a session; sightings made in it carry the visit's id (`visit_id`), and `get_checkin_spot` answers "Spotted at <place>" from the visit's place. So point 2 already works inside a session. Tim's day is probably a day without a session: he logs sightings without first checking in at the place.
- **Everything on the phone is ready.** The local check-in has `spotID` / `spotName` on both apps, and the upload sends `spot_location_id` for any kind. The only block is on the server: `sync_checkins` keeps `spot_location_id` only for airport visits (`case when v_kind = 'airport' then private.valid_spot_location(...)`) and drops it for sightings.
- **The place page shows only counts.** `get_spotting_location` returns sessions and "aircraft seen" (aircraft counted through sessions), no list of aircraft.
- **Editing goes through the same upload.** `sync_checkins` is also the edit path, so a place set on a sighting later is validated the same way.

## Recommendations

1. **Tag the sighting directly, not through a made-up session.** A sighting gets its own `spot_location_id`, validated like for a visit: the place must be approved (or your own waiting one) and at the airport of the sighting; otherwise it is dropped and the check-in is stored anyway (a bad link never blocks sync). The alternative, creating a hidden visit for every tagged sighting, would put fake visits in the feed, the badge counts and the delete logic.
2. **The sighting's own place wins over the session's.** If both are set, the place on the sighting is shown. While a session runs at the same airport, the picker is not shown: the sighting already belongs to the session's place, and two ways to say the same thing would confuse.
3. **Only public numbers.** A place page and its list count public sightings (plus your own), like the existing counts. A private sighting never shows up in someone else's list.
4. **Badges are not changed.** The session badges count visits and the aircraft linked to them. A sighting tagged on its own is not a session, so it does not count there. If the owner wants "aircraft spotted at places" as a badge, that is a separate, later step.
5. **Older apps are unaffected.** They never send the field for sightings, and they keep showing the place through the session.

## Backend (one migration, one PR)

- `sync_checkins`: keep `spot_location_id` for sightings too, validated with `private.valid_spot_location(uid, id, airport)`. A sighting without an airport keeps no place.
- `get_checkin_spot`: for a sighting, the place is its own `spot_location_id` when set, otherwise the one of its visit. The `visit_id` part stays as it is.
- `get_spotting_location`: `aircraft` also counts public sightings tagged directly (no double counting of a sighting that is in a session at the same place).
- New `get_spot_sightings(place, limit, before)`: the aircraft spotted at a place, newest first, for the callers who may see each one: id, time, registration, type, who. It covers both ways (session and direct).
- Tests (pgTAP): a direct place is kept; a place at another airport is dropped; a pending place of someone else is dropped; the own place wins over the session's; private sightings are not listed for others; no double counting; edit sets and clears the place. `access_test.sql` function list, api-test.

## iOS and Android (same changes on both)

1. **Sighting form:** below the airport, a "Spotting location" picker with the places of the chosen airport (approved ones and your own waiting ones), "None" by default. Hidden when signed out, when there is no airport, and while a session runs at that airport. Same component as the airport check-in.
2. **Edit form of a sighting:** the same picker, so older sightings can get a place.
3. **Detail page:** already shows "Spotted at <place>" through `get_checkin_spot`; check that it also shows for a direct tag.
4. **Place page:** an "Aircraft spotted here" list (registration, type, date, name), each opening the check-in; first 20 with "Show more".
5. **Strings** in German and English, and a click-through on both apps against the local stack.

No outbox change: a direct place does not depend on another check-in, so the order of upload does not matter.

## Steps and size

| PR | Content | Size |
| --- | --- | --- |
| 1 | Backend: migration and tests | small |
| 2 | Both apps: picker on the sighting form and edit, place page list | medium |

Production: migration push, then app builds, on the owner's word as usual.

## Decisions needed (owner)

1. **Session at the same airport:** hide the picker (recommended) or show it with the session's place preselected?
2. **Badges:** keep them as they are (recommended), or count directly tagged sightings for place badges later?
3. **Old sightings:** allow setting a place in the edit form (recommended), or only for new sightings?

## Tim's answers (issue #286, 23 Nov)

1. A reminder is welcome when a sighting becomes part of a running session. The picker stays hidden during a session, and the sighting form already shows the session row ("Session at <place>") at the top, so that is the reminder.
2. Sightings with their own place do not count for the session badges. Agreed.
3. Older sightings can get a place afterwards in the edit screen. Agreed.
4. He logs single aircraft without a session, so the standalone picker is what he was missing.

## As built

- **Backend** (`20261124100000_sighting_spot_location.sql`): `sync_checkins` keeps `spot_location_id` for sightings too, validated like for a visit. A repeated upload (edit) takes the place the app sends: the field missing keeps the place (older apps), `null` clears it. `get_checkin_spot` answers with the sighting's own place first, then its session's. `get_spotting_location` counts each public sighting once (own place, or the place of a public session when it has none). New `get_spot_sightings(place, limit, before_time, before_id)`: public sightings plus your own, signed-in only. pgTAP: `sighting_spot_test.sql`; the contract describes the field.
- **iOS:** `SightingSpotRow` (picker, shared by the sighting form and the edit screen), `SpotChange` (`keep`, `set`, `clear`) on `updateSpotted`, the upload item always sends the place for a sighting, `SpotSighting` and the "Aircraft spotted here" list with "Show more" on the place page.
- **Android:** `SightingSpotField` (chips, same two places), `SpotChange`, the outbox sends `spot_location_id` or `null` for a sighting, `SocialApi.spotSightings` and the same list on the place page.
- **Edit safety:** the edit screen only changes the place when the places of the airport were read; an empty answer (no connection) keeps the place as it was. A sighting made in a session has no picker, in the form or the edit.
- **Not done:** a badge for aircraft spotted at places (a later step if wanted).
