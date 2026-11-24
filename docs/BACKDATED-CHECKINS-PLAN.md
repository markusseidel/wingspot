# Set a date on sightings and airport check-ins: plan for issue #312

Issue by vogtim: a flight check-in can have a date in the past, a sighting ("Gesichtet") or an airport check-in cannot, so backfilled sightings land on the wrong day and "Zuletzt am" is wrong. Status: plan only, nothing built. Tim's answers are in at the end.

## What the issue asks for

- A date, optionally with a time, when creating a sighting or an airport check-in; the default stays "now"; no dates in the future.
- The chosen date is shown everywhere (detail, profile, collections) and is the one "Zuletzt am" uses; the creation date stays stored separately.
- The date can be changed later in the edit screen.
- The same picker as the flight check-in; a suggestion from the photo's capture date (earliest photo wins), read on the device before the metadata is removed.
- A date without a time is stored as a day, not as midnight UTC. A time is read as local time at the airport.
- Badges use the event date. Backfilling on a Saturday must not earn a weekend badge, and golden-hour badges must not depend on when it was typed in.
- The spotting location suggestion uses the event date. A backfilled sighting is shown with its real date in the feed; an optional "do not post" toggle.
- Both apps.

## What exists today

- **The two dates are already separate.** `checkins.occurred_at` is the event, `created_at` is the row's creation (server default). On the phone `LocalCheckIn.occurredAt` is the event and `savedAt` is when it was entered (added for the collections, #274). So no new date column is needed. 134 sightings and airport visits in production already have an `occurred_at` more than a day before their creation (flights create airport visits at the flight's date), so old event dates already work through the sync.
- **The apps always use "now" for a sighting and an airport check-in.** `saveSpotted` and `saveAirport` take `at date = Date()` on iOS and `now = Instant.now()` on Android, and the screens never pass anything else. The new check-in id is a UUID v7 built from that time, which is harmless for an older date (the id is only a tiebreak in the feed paging).
- **A flight has a date picker.** iOS: `DatePicker("Date", in: ...Date(), displayedComponents: .date)` in `FlownCheckInView` and `FlownEditView`; Android: `FlightDatePicker`. The chosen day becomes a moment with `FlightDay.moment`: today keeps the real time, any other day is midday, which stays on that day in any time zone. Android has the same.
- **The server already takes any past time.** `sync_checkins` rejects only `occurred_at` more than a day in the future (`invalid_time`); there is no lower limit.
- **Editing cannot move a sighting or a visit.** On a repeated upload the sync only takes a new `occurred_at` when the check-in is a flight (`case when checkins.kind = 'flown' ...`). The edit screens for a sighting and an airport check-in change the aircraft and the reason only. A flight's edit moves the flight and its two airport visits together (iOS `updateFlown`); the server tells a visit of a flight by the equal time (`private.is_flight_visit`), so a visit of a flight must never be moved on its own.
- **Badges already use the event date.** `private.checkin_facts` reads `occurred_at` and turns it into local time with the longitude of the airport (the position of the check-in when there is no airport; the home airport for flights). So the weekend, streak and golden-hour badges are right for a backfilled check-in. What the issue fears (a creation-time badge) does not exist. What does happen: the badges are worked out when the check-in arrives, so a backfilled Saturday sighting does earn the badge for that Saturday, correctly.
- **Feed, delay and notifications.** The feed has two sorts, chosen on the Feed tab: by when it was checked in (`created_at`, the default on both apps) and by the day of the event (`occurred_at`). A backdated sighting is therefore at the top of the feed by default, on the day it is typed in, and shows its event date on the card. Only a person who switched to the event-date sort sees it at its place among old entries. The post delay for strangers is worked out from `occurred_at` (`occurred + delay <= now`), so a past event is visible at once; that is right, a past sighting tells nobody where you are now. Nothing notifies friends of a new check-in.
- **The "seen before" line uses the newest earlier entry.** After a save the result screen says how often the aircraft was seen and when last. With a backdated check-in "last seen" would pick the newest check-in, which is later than the new one. That must be limited to entries before the chosen date.
- **Spotting sessions.** After an airport check-in a session starts (`sessions.start(... startedAt: Date())`) and each sighting in it carries the visit's id (`visitID`) and gets the place suggested. A backdated visit needs its sightings on the same day.
- **Photos.** A photo is cut down and re-encoded on the phone before the upload (`PhotoPreparer` on iOS, `PhotoPrep.kt` on Android), which removes the metadata. The capture date is in the original, before that step. Android has no extra library for it; the framework `android.media.ExifInterface` reads it from a stream (API 24 and up).
- **Time zones.** The reference data has no time zone per airport, only the position. Everything that shows a time (a live check-in, a flight) shows it in the time zone of the phone that looks at it.

## Decisions

1. **One field "When", the same on every check-in screen.** A row "When" with "Now" by default. Tapping it opens the date (no days in the future) and a switch "Set the time", off by default. Used on the sighting screen, the airport screen and, in the edit screens, on a sighting and an airport check-in. The flight screens keep their date picker; it does not get a time (a flight is a day).
2. **Moments.** Date only: the same rule as flights (`FlightDay.moment`: today is now, another day is midday), so a backfilled day stays on that day. Date and time: that clock time in the time zone of the phone. There is no airport time zone in the data, and a time shown in the person's own zone is what every other time in the app does; reading "local time at the airport" would show the owner a different time than they typed whenever the airport is in another zone. The limit (a phone in a very different zone than the airport can shift the day by one at the edges) is the same one flights have today and is written in the help text.
3. **A flag so a day-only entry does not show "12:00".** A new column `checkins.time_known boolean not null default true`, sent by the sync (`time_known`), `false` for a date-only entry. The check-in page shows the time only when it is known. Old rows and flights stay as they are (a flight can switch later). Without the flag a backfilled sighting would claim to have happened at 12:00.
4. **Edit moves the event.** The sync takes `occurred_at` and `time_known` for a sighting and an airport check-in too, except for an airport visit that belongs to a flight (the apps hide the field there, the server refuses it). Moving an airport visit moves the sightings of its spotting session (same `visit_id`, still on the visit's old time) by the same step, like a flight moves its visits. The server checks that all dates are not in the future and not before 1990 (a new `invalid_time` case; a camera with a reset clock says 1970 or 2000).
5. **Badges after a move.** Moving a check-in changes what the day-based badges see, so the badges of that person are worked out again and may go down, the same step used after a delete and after the home-airport change (`20261120300000_badges_after_delete.sql`, `20261122800000_flight_time_uses_home.sql`). The build step finds out how the flight edit already triggers this and reuses it.
6. **The feed keeps its two sorts; the default stays "by check-in time".** A backdated sighting shows at the top of the feed when it is typed in and carries its event date on the card (the same as a backdated flight today). The sort "by event date" places it at its day. Nothing changes in the feed query. This is Tim's choice (issue #312); the first draft of this plan assumed the feed sorts by event date by default, which is wrong. What the card must do: show the event date (and the time only when known), not the day it was added. The check-in page and the collections show the real date; the collections' sort by date of entry (#274) finds a backfilled entry.
7. **No "do not post" toggle.** The visibility picker already decides who sees a check-in; backfilling private or for friends needs nothing new. The help text next to "When" says so.
8. **The photo date is a suggestion, not an automatic change.** When the first or earliest of the chosen photos has a capture date more than a day before now and "When" is still "Now", a line appears under the field: "Photo taken 12 Aug 2019 [Use this date]". A tap sets the date and the time (the photo has one, so "Set the time" switches on; an offset in the photo is used, otherwise the phone's zone). It never changes the field by itself: a photo from the camera roll can be old for other reasons. The date is read from the original before the metadata is removed and is kept in the draft for the session only; it is never uploaded.
9. **Sessions follow the date.** A visit with a chosen date starts its spotting session on that date; the sightings added in the session take the visit's date and time by default (the row says "Same as the visit") and can still be changed. A session that started "now" works as before.
10. **"Seen before" counts only what came earlier.** The result screen after saving looks at entries with an event date before the new one. A backfilled first sighting says "first time" even if the aircraft was seen last week. Counts such as "seen 5 times" stay total.
11. **Online or offline.** The date is part of the local check-in, so it works offline like everything else; nothing is added to the sync apart from `time_known`.

## Backend (one migration, one PR)

- Migration: add `checkins.time_known boolean not null default true`.
- `sync_checkins`: read `time_known`; on a repeated upload take `occurred_at` and `time_known` for `spotted` and `airport` check-ins that are not visits of a flight (and for flights as today); reject `occurred_at` earlier than 1990-01-01 or later than now + 1 day (`invalid_time`); when `occurred_at` of an airport visit changes, move its sightings (same `visit_id`, equal old time) by the same amount; queue the badge evaluation for the person.
- `get_feed`, `get_checkin`, `get_my_checkins` and the other readers return `time_known`; check the contract (`contracts/openapi.yaml`: `time_known` on the check-in item and in the sync body).
- pgTAP: a sighting uploaded with an old date keeps it; the edit moves a sighting and a standalone visit; a visit of a flight is refused; a visit's sightings follow; 1989 and next week are refused; `time_known` defaults to true and a `false` is kept; a weekend badge is earned for the event date and not for the creation date; moving a Saturday sighting to a Friday takes the weekend badge away; the access test lists nothing new (no new function).
- API test: sync with `occurred_at` in 2019 and `time_known: false`, then read it back.
- Deploy: database first, then the function if it changed, then the app builds. Older apps send no `time_known`, which means `true`, so nothing breaks.

## iOS (one PR)

- `WhenSection` (new view, `Features/CheckIn`): the row, the date picker (`in: ...Date()`), the time switch and time picker, the photo suggestion line; a small `WhenChoice` value (now, or date plus optional time) with a `moment()` that uses `FlightDay.moment` for date only. Used in `SpottedCheckInView`, `AirportCheckInView` and `CheckInEditView` (for a sighting and a standalone visit; hidden for a visit of a flight).
- Persistence: `saveSpotted` and `saveAirport` take the moment and `timeKnown`; `LocalCheckIn` gets `timeKnown: Bool?` (optional, SwiftData migration without a version bump, nil means true); `updateSpotted` and `updateVisit` take `occurredAt` and `timeKnown` and move the visit's sightings; `history` for the result line counts earlier entries only; `UUID.v7(at:)` takes the event date (already so).
- `PhotoPreparer` returns the capture date from `kCGImagePropertyExifDictionary` (`DateTimeOriginal`, `OffsetTimeOriginal`, plus the TIFF date as a fallback); `PreparedPhoto.takenAt`.
- The sync body (`SupabaseCheckInBackend` or the equivalent) sends `time_known`; the feed and check-in models read it; `CheckInDetailView` shows the time only when known. The strings in German and English; `check-strings.sh` passes.
- Tests: `WhenChoice` (today keeps the time, another day is midday, future days refused, time wins over midday), the "seen before" count with a backdated entry, moving a visit moves its sightings, EXIF date and offset from a sample JPEG.

## Android (one PR, same changes)

- `WhenField` composable (date dialog like `FlightDatePicker`, `TimePicker`, the suggestion line), used in the sighting and airport screens and in `SimpleEditScreen`; hidden for a visit of a flight.
- `core`: `saveSpotted` and `saveAirport` take the moment and `timeKnown`; the `checkins` table gets `time_known` (a database version step with the usual migration list); `updateSpotted` and `updateVisit` take the date and move the sightings; the "seen before" count; the sync body; the feed models.
- `PhotoPrep.kt`: capture date from `android.media.ExifInterface` on the picked stream (`TAG_DATETIME_ORIGINAL`, `TAG_OFFSET_TIME_ORIGINAL`) before the re-encode.
- Strings in `values` and `values-de`; unit tests next to the other core tests, a Compose test for the field.

## Order of work

1. Backend PR: migration, sync changes, tests, contract. Merge and deploy.
2. iOS and Android PRs together (the parity rule), then both builds with the tester text, and the release note for each platform.
3. Click-through on both apps against the local stack: backdate a sighting with and without time, with a photo that has a date, a backfilled session of three sightings on one day, then edit the date (a sighting, a standalone visit, a flight's visit, which must have no field), and check the weekend badge on a Saturday.

## Not in the first version

- A date for a flight's time (flights stay day-only).
- Reading the airport's time zone (needs time zone data per airport, then every displayed time can follow it).
- A "posted later" hint on a feed card (the feed card would need `created_at`).
- Bulk backfill from the photo library (pick many photos and create one sighting per day).
- Moving several check-ins at once.

## Answers (Tim, issue #312)

1. **Time zone:** the phone's time zone is fine; the airport's zone stays a later step.
2. **Feed:** a backdated sighting shows the old date but is listed as the newest item. That is what the default sort does today (see decision 6); no feed change.
3. **Photo date:** tap to use.
4. **Oldest date:** 1990 is fine.
