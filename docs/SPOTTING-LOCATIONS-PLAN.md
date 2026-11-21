# Spotting locations: plan for issue #218

Issue: "Spotting locations as first-class check-in places + spot-session linking and badges" (Jan Jansen). Status: PR 1 (backend) built, see "As built" at the end. Decisions 1 to 3 were taken as recommended. Hidden badges are not part of this plan.

## What already exists

- The first schema (concept §6.3) already has `spotting_locations` (airport, name, point, description, best time, legal notes, status pending/approved/rejected, created_by) and `sessions`. `checkins.spot_location_id` and `checkins.session_id` exist too.
- Nothing uses them yet: no API, no app screen, no badge counting.
- Today an airport check-in is a visit with a context such as "spotting", and a sighting is a separate check-in. Nothing links the two. The missing piece is "session → aircraft list".

## Decisions needed

1. **Must a spotting location belong to an airport?** Recommended: yes. The nearest airport is set automatically from the pin. It gives discovery (the airport's page) and country safety notes. A hill with no airport nearby simply gets the nearest one.
2. **Who approves new locations?** Recommended: the creator sees theirs at once, everyone else sees it once approved, using the existing report/alert flow. Alternative: publish at once and rely on reports (faster, riskier for places with legal issues).
3. **Session model.** Recommended: a session is a visit. It is an airport check-in with `spot_location_id`, and sightings carry the visit's id as `session_id`. Feed, delete, visibility, tags and edit keep working, and no new check-in kind is needed.
4. **Photo and coordinates.** One cover photo from the creator (reuses photo upload). The pin comes from a map, with an optional pasted Google Maps link that is only parsed for lat/lng. A visit's own GPS is never public; only the location's pin is.

## Backend (one migration, one PR)

- Extend `spotting_locations`: `photo_path`, `facing`, `tips`, `created_at`, `visits_count` (trigger-kept).
- RLS: approved rows readable by every signed-in user, own rows readable by the creator, insert only as yourself with status `pending`, approve and reject only through a security-definer function.
- Functions: `add_spotting_location(...)` (nearest airport, duplicate check within about 100 m with a similar name), `spotting_locations_near(airport | bbox)`, `get_spotting_location(id)` (details plus counts: sessions, aircraft, your own sessions).
- Check-in upload: an airport visit may carry `spot_location_id`, a sighting may carry `session_id` pointing at a visit of the same user. Both are validated. Older apps are unaffected.
- Reads: `get_checkin` returns the linked aircraft list, and a sighting returns "spotted at <location>". No second foreign-key path to `profiles` (PGRST201 rule).
- Stats (aircraft per session, sessions per location, locations visited) derive from the links, so no new tables.
- Badges (new category, definitions are data, no app update): First Spot Session, Deck Regular, Place Collector, Busy Day (10 or more aircraft in one session; concept §5 also lists "Session Pro", 50), Cartographer (an approved location of yours), Sunrise Hunter (local time from longitude, as in BADGES.md). Names and levels to be approved by the owner.
- Tests: pgTAP for RLS, duplicate detection, nearest airport, session linking and badge rules. An api-test, and the public function list in `access_test.sql` regenerated.

## iOS and Android (same changes on both)

1. Location page, from an airport's page and the map: cover photo, description and tips, "Open in Maps", counts, "Check in here".
2. Add a location: pin on a map, name, photo, tips, facing. Shows "pending review" until approved.
3. Spot session flow: check in at a location (starts a visit), new sightings link automatically with a "Session at X, 7 aircraft" bar, end session gives a summary. Linking afterwards: a picker for earlier sightings of the same day.
4. Detail pages: a visit lists its aircraft, a sighting shows "Spotted at ...".
5. Offline queue: the outbox must send the visit before its sightings, with local ids so linking works offline. Riskiest part: it touches the sync order in `CheckInStore` (iOS) and `CheckInViewModel` (Android).
6. Strings in German and English.

## Order and size

| PR | Content | Size |
| --- | --- | --- |
| 1 | Backend: migration, tests, contract | about 1 day |
| 2 | Both apps, read side: browse, location page, detail linking | about 1 day |
| 3 | Both apps, write side: add a location, sessions, outbox ordering | about 1.5 days |
| 4 | Badges, once the owner approves names and levels | small |

Deploy: database first, then the function, then a build.

## Risks

- Abuse and legal notes: pending approval, plus the country warning from concept §6.3.
- Duplicate or low-quality spots: the 100 m duplicate check.
- Outbox order and local ids: the likeliest source of bugs.
- Privacy: a spot's pin is public, a visit's own GPS never is.

## Not done

- No reply on the issue yet; waiting for decisions 1 to 3.

## As built: PR 1 (backend)

Migration `20261121900000_spotting_locations.sql`, tests in `spotting_locations_test.sql`. Not deployed yet.

- Decisions 1 to 3 as recommended: a place belongs to the nearest airport (within 150 km, else `no_airport_nearby`), new
  places wait for approval (you approve with a SQL update of `status`, there is no app function for it), and a session is
  an airport visit.
- The sightings of a session carry `visit_id`, the id of the visit. The old `sessions` table and `session_id` column from
  the first schema stay unused. `visit_id` has no foreign key (like `flight_id`): a trigger clears it when the visit is deleted.
- The upload (`sync_checkins`) takes `spot_location_id` on visits and `visit_id` on sightings. A link that does not hold
  (place at another airport, not approved and not yours, visit missing or not yours) is dropped and the check-in is
  stored anyway, so a bad link never blocks sync. Order matters: the app has to send the visit before its sightings
  in the same or an earlier call.
- New functions: `add_spotting_location` (name 3 to 80 characters, pin, optional description, best time, facing, tips,
  legal notes; answers pending, duplicate or a rejection code), `spotting_locations_at(airport)`,
  `get_spotting_location(id)` (public sessions, public aircraft, your own sessions) and `get_visit_sightings(visit)`
  (the aircraft of a session, as far as the viewer may see each one).
- At most 10 of your places can wait for approval at a time (a trigger, so it also holds for direct inserts).
- Counts use public check-ins only, plus your own, so a private visit never shows up in someone else's numbers.
- Not in this PR: the cover photo upload (the `photo_path` column exists), `visit_id` and the place in `get_checkin`
  and the feed (PR 2), and the badges (PR 4).

## As built: PR 2 (read side)

Migration `20261122100000_checkin_spot.sql`: `get_checkin_spot(check-in)` returns the place and the visit of a visit or a
sighting (and, for a visit, how many aircraft were linked), only for check-ins the caller may see. iOS and Android:
- The airport page lists the places of the airport (your own waiting ones are marked "Waiting for approval").
- A place page: map and "Open in Maps", the numbers (sessions, aircraft seen, your sessions), and the tips.
- A visit shows "At <place>" and the aircraft seen during it. A sighting shows "Spotted at <place>". Both open the place.
- On iPhone the places and the session are loaded by the screen that holds the list, because a view with nothing in it
  never runs its own task.
