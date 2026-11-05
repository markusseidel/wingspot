# Launch badges, draft for review

Draft for Milestone 4 (see [PHASE1.md](PHASE1.md) and concept §5). Nothing is built yet. Change anything here and I'll build the final list.

## How badges work

- A badge is data on the server: a rule, a name and description in German and English, and levels. New badges need no app update (concept §5.4).
- **Leveled** badges climb through levels, and each level counts as an unlock. **Single** badges unlock once. **Hidden** badges show as "???" until earned.
- At launch only **Spotted** check-ins exist, so every rule counts spotted check-ins. Flown and airport check-ins come with Milestone 5 and will count where it makes sense.
- Distinct counts ignore repeats: the same registration, type or airport counts once.
- "Local time" is estimated from the airport's longitude (UTC plus longitude divided by 15, rounded), because the airport data has no time zones.
- Level unlocks give bonus XP, 50 times the level (concept §5.3).
- Art for now: a symbol and a color per level. You can replace it with drawn art later without changing the rules.

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
| anniversary | Anniversary | Jahrestag | A check-in on the day you joined, in a later year | single, repeats yearly |

## Hidden (3)

These show as "???" until earned. Drop any you don't like.

| id | English | Deutsch | Rule |
|---|---|---|---|
| deja_vu | Déjà Vu | Déjà-vu | The same registration at the same airport on 3 different days |
| mirror_image | Mirror Image | Spiegelbild | A registration that reads the same backwards, such as D-ADAD with the dash ignored |
| new_year | New Year's Spot | Neujahrs-Spot | A check-in on 1 January |

## Later, when the data exists

- **Airlines:** distinct operators, alliances, flag carriers, low-cost carriers, cargo, special liveries. They need the operator import and an airline field on the check-in.
- **Rarity:** Unicorn, Last of Its Kind, Rare Bird. These need airframe counts and the full type list.
- **Flown:** Frequent Flyer, distance, long haul, red-eye. They come with Milestone 5.
- **Events and seasons:** airshow weekends, winter and summer badges, holidays. These are time-limited badges, set up on the server.
- **Social:** salutes on a check-in, spotting together with a friend. They come with Milestone 7.

## Open questions

1. Are 36 launch badges enough, or do you want more types before ICAO answers?
2. Keep the three hidden badges?
3. Any badge you want renamed or dropped?
