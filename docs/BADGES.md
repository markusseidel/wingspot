# Launch badges

The 36 launch badges for Milestone 4 (see [PHASE1.md](PHASE1.md) and concept §5), as approved. The server seeds them in `20261105200000_badges.sql`.

## How badges work

- A badge is data on the server: a rule, a name and description in German and English, and levels. New badges need no app update (concept §5.4).
- **Leveled** badges climb through levels, and each level counts as an unlock. **Single** badges unlock once. **Hidden** badges show as "???" until earned.
- At launch only **Spotted** check-ins exist, so every rule counts spotted check-ins. Flown and airport check-ins come with Milestone 5 and will count where it makes sense.
- Distinct counts ignore repeats: the same registration, type or airport counts once.
- "Local time" is estimated from the airport's longitude (UTC plus longitude divided by 15, rounded), because the airport data has no time zones.
- **Time-of-day badges** (Night Owl, Early Bird, and any badge that uses the hour of the day) count only check-ins where the person was at the airport: spotting and standalone airport check-ins. A **flight and the two airport visits it creates do not count**, because a flight is logged at some moment (often now, or midday of an earlier day) and the estimated hour at a faraway airport would be made up (issue #277).
- **Day-based badges** (weekends, streaks, busy day, anniversary, same registration on different days, dates) give a **flight and its two airport visits the person's own time**, from the longitude of their home airport (UTC without one), so they fall on one day and a Friday flight is not a weekend in Asia. Spotting and standalone airport check-ins keep the time at the airport.
- Level unlocks give bonus XP, 50 times the level (concept §5.3).
- A level never goes down when badges are evaluated after an upload or when the badges page opens, even if a rule changes later. Deleting a check-in is the exception: it re-evaluates your badges, so levels, progress and XP follow the check-ins that are left. A badge that falls back to level 0 loses its unlock date, and earning it again is celebrated again.
- Art for now: a symbol and a color per level. You can replace it with drawn art later without changing the rules.

## Dormant until the data exists

`island_hopper` and `short_field` are in the database but switched off, because the airport data has no island flag and no runway lengths yet. They show up and can be earned once that data is imported and they are switched on. Their `valid_from` is `infinity` until then.

What each one needs:

- `short_field`: the longest runway length per airport. OurAirports publishes `runways.csv` with `length_ft` per runway, so the refdata pipeline can take the longest one and store it in metres. Decide what counts when an airport has no runway data (it should simply not qualify).
- `island_hopper`: an `is_island` flag per airport. No source in the current data has it. A way to get it is to test each airport's coordinates against island polygons (for example Natural Earth or OpenStreetMap), and decide a size limit so that Great Britain or Honshu don't count. Check the source's licence before importing.

After the data is in the snapshot, the app needs no change: switch the badges on by setting `valid_from` to null (see TODO).

## What the server needs that doesn't exist yet

- The country of a registration (from its prefix, such as D for Germany). The phone already has this table, and the server needs the same one, checked against the shared test file.
- Hosted has only 22 aircraft types until ICAO answers, so type badges only count those. The list can grow without changing a rule.
- Airline badges wait for the operator import and an airline field on the check-in.

## Milestones (7)

| id | English | Deutsch | Rule | Levels |
|---|---|---|---|---|
| wheels_up | Wheels Up | Abheben | Your first check-in | single |
| logbook | Logbook | Logbuch | Total check-ins | 10, 25, 50, 100, 250, 500, 1000 |
| fresh_metal | Fresh Metal | Frisches Metall | Distinct registrations | 5, 10, 25, 50, 100, 250, 500 |
| old_friend | Old Friend | Alter Bekannter | The same registration seen on different days | 2, 3, 5, 10 times |
| busy_day | Busy Day | Voller Tag | Check-ins in one day | 5, 10, 25 |
| wingman | Wingman | Wingman | Check-ins done together with friends, as the author or the tagged friend (see [FRIEND-TAGS.md](FRIEND-TAGS.md)) | 1, 5, 10, 25 |
| daily_spotter | Daily Spotter | Täglicher Spotter | Consecutive days with a check-in | 3, 7, 14, 30 |
| weekend_warrior | Weekend Warrior | Wochenend-Spotter | Consecutive weekends with a check-in | 2, 4, 8, 16 |

## Airports (9)

| id | English | Deutsch | Rule | Levels |
|---|---|---|---|---|
| gate_hopper | Gate Hopper | Flughafen-Hopper | Distinct airports | 3, 5, 10, 25, 50, 100 |
| home_base | Home Base | Heimatbasis | Check-ins at the same airport | 10, 25, 50, 100, 250 |
| home_turf | Home Turf | Heimspiel | A check-in at your home airport | single |
| continental | Continental | Kontinental | Airports on different continents | 2, 3, 4, 5, 6 |
| island_hopper | Island Hopper | Inselhüpfer | Distinct island airports | 1, 3, 5, 10 |
| short_field | Short Field | Kurze Piste | An airport with a runway under 1000 m | single |
| high_altitude | High Altitude | Dicke Luft | An airport above 2500 m | single |
| arctic_circle | Arctic Circle | Polarkreis | An airport north of the Arctic Circle | single |
| southern_cross | Southern Cross | Kreuz des Südens | An airport in the southern hemisphere | single |

## Countries (6)

| id | English | Deutsch | Rule | Levels |
|---|---|---|---|---|
| passport_stamps | Passport Stamps | Reisestempel | Countries of the airports you checked in at | 2, 3, 5, 10, 15, 25, 50 |
| register_collector | Register Collector | Register-Sammler | Distinct countries of registration | 3, 5, 10, 20, 30, 50 |
| far_from_home | Far From Home | Weit weg von zu Hause | Aircraft seen outside their own register's country | 5, 25, 100 |
| home_team | Home Team | Heimmannschaft | Distinct registrations from your home airport's country | 10, 50, 250 |
| neighbourhood_watch | Neighbourhood Watch | Nachbarschaftswache | Different registration countries at one airport | 3, 5, 10 |
| six_continents_registers | Global Fleet | Weltflotte | Registrations from different continents | 2, 3, 4, 5, 6 |

## Aircraft types (8)

Counts only the types in the database, 22 on hosted at first.

| id | English | Deutsch | Rule | Levels |
|---|---|---|---|---|
| type_rater | Type Rater | Typ-Berechtigung | Distinct aircraft types | 3, 5, 10, 25, 50, 100 |
| superjumbo | Superjumbo | Superjumbo | An Airbus A380 | single |
| queen_of_the_skies | Queen of the Skies | Königin der Lüfte | A Boeing 747, any variant | single |
| dreamliner | Dreamliner | Dreamliner | A Boeing 787, any variant | single |
| triple_seven | Triple Seven | Triple Seven | Distinct 777 types | 2, 4, 6 |
| airbus_fan | Airbus Fan | Airbus-Fan | Distinct Airbus types | 3, 6, 10, 20 |
| boeing_fan | Boeing Fan | Boeing-Fan | Distinct Boeing types | 3, 6, 10, 20 |
| prop_power | Prop Power | Propellerkraft | Distinct turboprop types | 1, 3, 5, 10 |

## Time of day (3)

| id | English | Deutsch | Rule | Levels |
|---|---|---|---|---|
| early_bird | Early Bird | Frühaufsteher | Check-ins between 04:00 and 06:00 local time | 1, 10, 25 |
| night_owl | Night Owl | Nachteule | Check-ins between 22:00 and 04:00 local time | 1, 10, 25 |
| anniversary | Anniversary | Jahrestag | Years in which you checked in on the day you joined, in a later year | 1, 2, 3, 5, 10 |

## Hidden badges

There are a few hidden badges. They show as "???" until earned. Their names, descriptions and rules are not in this repository, because it is public and a surprise should stay one. Their definitions are kept in `backend/private/hidden_badges.sql`, which is not committed (see `backend/private/README.md`). Production has them. The tests make their own hidden badges.

## Later, when the data exists

- **Airlines:** distinct operators, alliances, flag carriers, low-cost carriers, cargo, special liveries. They need the operator import and an airline field on the check-in.
- **Rarity:** Unicorn, Last of Its Kind, Rare Bird. These need airframe counts and the full type list.
- **Flown:** Frequent Flyer, distance, long haul, red-eye. They come with Milestone 5.
- **Events and seasons:** airshow weekends, winter and summer badges, holidays. These are time-limited badges, set up on the server.
- **Social:** salutes on a check-in, spotting together with a friend. They come with Milestone 7.

## Decisions

- 36 launch badges are enough, and the hidden badges stay.
- Hidden badges are secret in the app, and their definitions are not in the public repository. They can still be read from the `badges` table of the running service, which is acceptable for a surprise mechanic. Anyone who wants that closed too needs a change in the database rules (open question).

## Spotting (6)

Added with spotting locations (see [SPOTTING-LOCATIONS-PLAN.md](SPOTTING-LOCATIONS-PLAN.md)). A session is an airport visit at a
spotting location, and the aircraft spotted during it are linked to it. "Local time" is estimated from the airport's longitude, like the time badges.

| id | English | Deutsch | Rule | Levels |
|---|---|---|---|---|
| first_spot_session | First Session | Erste Session | Visits at a spotting location | single |
| deck_regular | Deck Regular | Stammgast | Most visits at one spotting location | 3, 5, 10, 25 |
| place_collector | Place Collector | Ortesammler | Different spotting locations visited | 3, 5, 10 |
| session_pro | Session Pro | Session-Profi | Most aircraft linked to one session | 10, 25, 50 |
| cartographer | Cartographer | Kartograf | Your own spotting locations that were approved | 1, 3, 10 |
| sunrise_hunter | Sunrise Hunter | Sonnenjäger | Sessions begun between 05:00 and 08:59 or between 17:00 and 20:59 local time | 1, 5, 15 |

The name "Busy Day" was already taken by the badge for many check-ins on one day, so the session badge is called Session Pro.
