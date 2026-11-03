# Wingspot — App Concept

> Log every aircraft you spot or fly on, every airport you visit — and earn badges for it.

Version 0.1 · November 2026 · Status: Draft for development kickoff

---

## 1. Vision

Wingspot is a social logbook for aviation enthusiasts. Users **check in** aircraft they have **seen** or **flown on**, and **airports** they visit. Every check-in feeds a personal collection, stats, a social feed and a **badge system** that rewards variety, rarity, travel and consistency.

**Core promise:** *"Never forget a plane. Turn every trip to the airport fence into progress."*

### Design principles
1. **Check-in in under 10 seconds.** At the fence, the plane is gone in 30 seconds. Speed beats completeness — details can be added later.
2. **Offline first.** Spotting spots and aircraft cabins have bad reception. Everything works offline and syncs later.
3. **Collection, not just a feed.** The value grows with the user's history: "my types", "my airlines", "my airports", "my registrations".
4. **Trustworthy progress.** Verified check-ins (GPS, ADS-B, boarding pass) make badges mean something.
5. **Respect safety and privacy.** Spotting is legally sensitive in some countries; location sharing is opt-in and coarse by default.

---

## 2. Target users

| Persona | Description | What they want |
|---|---|---|
| **The Spotter** (core) | Spends weekends at airport fences, shoots with a telephoto lens, knows registrations by heart. | Fast logging by registration, "first seen" vs. "seen again", rarity, photo uploads, leaderboards per airport. |
| **The Frequent Flyer** | Flies 20–100 times a year, cares about aircraft types and airlines. | Logging flights (ideally by scanning the boarding pass), miles, routes map, "flown on 30 types". |
| **The Casual Enthusiast** | Likes planes, goes to airshows, travels a few times a year. | Fun badges, nice visuals, easy "what plane is that?" help. |
| **The Avgeek Kid / Family** | Parents with kids watching planes. | Simple, playful check-ins, big badges. |

Primary target for MVP: **Spotter + Frequent Flyer**. They are the power users who create content and spread the app.

---

## 3. Core loop

```
   ┌────────────┐     ┌───────────────┐     ┌──────────────┐
   │  See / fly │ ──▶ │   Check in    │ ──▶ │  Reward      │
   │  a plane   │     │ (≤10 seconds) │     │ badge · stat │
   └────────────┘     └───────────────┘     │ "first seen" │
          ▲                                  └──────┬───────┘
          │          ┌───────────────┐              │
          └───────── │ Social & goals│ ◀────────────┘
                     │ feed · salute │
                     │ next badge %  │
                     └───────────────┘
```

Retention hooks: badge progress bars ("3 more Boeing 777 variants for *Triple Seven Collector*"), streaks (weekly spotting), seasonal events, friends' activity, airport leaderboards.

---

## 4. Check-in types

### 4.1 Spotted (seen) aircraft
The main check-in. Minimum required data: **aircraft** (by registration *or* by type).

| Field | Required | Notes |
|---|---|---|
| Registration (e.g. `D-AIMA`) | One of reg/type | Autocomplete from aircraft DB; fills type, operator, livery automatically. |
| Aircraft type (ICAO, e.g. `A388`) | One of reg/type | For when the reg wasn't readable. Counts for type badges, not reg badges. |
| Operator / airline | Auto | Overridable (wet lease, new owner). |
| Location | Auto | GPS → nearest airport or spotting location; can be "en route / overhead". |
| Date & time | Auto | From photo EXIF if a photo is attached. |
| Phase | Optional | Landing · Takeoff · Taxi · Parked · Overhead · Display (airshow) · Museum/static. |
| Tags | Optional | Special livery · Retro livery · First visit to airport · Go-around · Night · Military · Cargo · Bizjet · Rare. |
| Photo(s) | Optional | Up to 4 (Pro: 10). Original EXIF kept privately, stripped publicly. |
| Note | Optional | Free text, 500 chars. |
| Rating | Optional | 1–5 "spot quality" (light, angle, distance) — a personal score for the moment, not for the aircraft. |

**Result screen** shows: "🆕 First time seeing D-AIMA!" / "Seen for the 4th time — last time FRA, 12 Aug 2025", new badges, badge progress.

### 4.2 Flown (passenger flight)

| Field | Required | Notes |
|---|---|---|
| Flight number (e.g. `LH400`) + date | Recommended | Lookup via flight-data API → route, scheduled times, often registration and type. |
| Route (from → to) | Yes | Airports; distance computed as great-circle. |
| Aircraft registration / type | One of them | Prefilled from lookup or from the "seat-back"/safety card. |
| Cabin class | Optional | Economy · Premium Eco · Business · First. |
| Seat | Optional | e.g. 34K; window/aisle derived. |
| Role | Optional | Passenger · Crew · Pilot (pilot = separate badge track later). |
| Photo, note, rating | Optional | Rating here = flight experience 1–5. |

**Fast path: boarding pass scan.** The IATA *BCBP* barcode (PDF417/Aztec/QR) contains name, PNR, from, to, carrier, flight number, date (Julian), seat and class. Scan from camera or a screenshot (Vision framework, fully on-device) → prefilled check-in. The passenger name and PNR are **never stored or uploaded**.

### 4.3 Airport visit
Like a venue check-in.

- Auto-suggested by geofence when the user is inside an airport area (opt-in notification: "You're at Düsseldorf (DUS). Check in?").
- Context: Spotting · Departing · Arriving · Transit · Working · Museum/Airshow.
- Optional: which **spotting location** within the airport (see 6.3).
- Airport check-ins are **implicitly created** by spotted/flown check-ins at that airport (configurable), so users don't have to double log.

### 4.4 Quick check-ins (power features)
- **"What's overhead?"** — List of aircraft near the user from live ADS-B data, sorted by distance, with reg, type, airline, altitude. One tap = check-in, already **verified**. (Phase 2, see licensing notes in §10.)
- **Batch mode** — For a spotting session: rapid fire registration entries, one after another, saved as one "session" (shows as one feed post: "Spotted 37 aircraft at FRA").
- **Photo import** — Pick photos from the library; EXIF time + location prefill; ADS-B history can suggest which aircraft was at that place at that time.

---

## 5. Badges & gamification

### 5.1 Badge mechanics
- **Single badges** — unlocked once (e.g. *Superjumbo*: spot an A380).
- **Leveled badges** — same badge, rising levels (Lvl 1 → Lvl 10+). e.g. *Boeing Fan*: spot 5 / 10 / 25 / 50 … distinct Boeing types/regs.
- **Time-limited badges** — seasonal or event-based, only earnable in a window (e.g. *Winter Ops* in Dec–Feb, an airshow weekend badge).
- **Verified-only badges** — rare/high-value badges require verified check-ins to stop cheating.
- **Hidden badges** — surprise discoveries ("???" until unlocked).

### 5.2 Badge catalog for launch (~60 badges)

**Milestones**
| Badge | Rule |
|---|---|
| Wheels Up | First check-in of any kind |
| Logbook (Lvl) | Total check-ins: 10, 25, 50, 100, 250, 500, 1000, 2500, 5000 |
| Fresh Metal (Lvl) | Unique registrations: 10, 50, 100, 250, 500, 1000, 5000 |
| Type Rater (Lvl) | Unique aircraft types: 5, 10, 25, 50, 100, 150 |
| Fleet Watcher (Lvl) | Unique operators: 5, 10, 25, 50, 100, 250 |

**Aircraft types & manufacturers**
| Badge | Rule |
|---|---|
| Queen of the Skies | Spot a Boeing 747 (any variant) |
| Superjumbo | Spot an Airbus A380 |
| Triple Seven Collector (Lvl) | Spot distinct 777 variants (772, 77L, 77W, 77X, 778, 779, 77F) |
| Dreamliner | Fly on a 787 |
| Airbus Fan / Boeing Fan / Embraer Fan … (Lvl) | Distinct regs per manufacturer |
| Prop Power (Lvl) | Turboprop types |
| Rotor Head (Lvl) | Helicopters |
| Heavy Lifter | An-124, An-225 (historic), C-5, Beluga ST/XL, Dreamlifter |
| Whale Watcher | Spot any Beluga (A300-600ST or A330-743L) |
| Warbird | Spot a historic military aircraft (pre-1960 type) |
| Concorde Pilgrim | Check in at a museum displaying a Concorde |

**Airlines & alliances**
| Badge | Rule |
|---|---|
| Star Gazer / One World / Team Sky (Lvl) | Distinct member airlines of each alliance spotted or flown |
| Flag Carrier (Lvl) | Distinct national flag carriers |
| Low Cost, High Count (Lvl) | Distinct LCC operators |
| Cargo Hauler (Lvl) | Freighter check-ins |
| Painted Lady (Lvl) | Special-livery check-ins |
| Throwback (Lvl) | Retro-livery check-ins |

**Airports & geography**
| Badge | Rule |
|---|---|
| Gate Hopper (Lvl) | Unique airports visited: 5, 10, 25, 50, 100, 200 |
| Hub Hunter | Visit the 10 busiest airports in a region |
| Continental (Lvl) | Airports on 2 / 3 / 4 / 5 / 6 continents |
| Passport Stamps (Lvl) | Countries with an airport check-in |
| Home Base (Lvl) | Check-ins at the same airport: 10, 50, 100, 500 |
| Short Field | Visit an airport with a runway < 1000 m |
| High Altitude | Visit an airport > 2500 m elevation |
| Island Hopper | 5 island airports |

**Flown**
| Badge | Rule |
|---|---|
| Frequent Flyer (Lvl) | Flights: 10, 25, 50, 100, 250, 500 |
| Distance (Lvl) | Distance flown: 10k, 50k, 100k, 250k, 500k, 1M km |
| Around the World | Cumulative 40,075 km |
| Long Haul | Single flight > 8,000 km |
| Hop | Single flight < 100 km |
| Red-Eye | Departure between 22:00 and 04:00 local |
| Window Warrior | 25 window-seat flights |
| Front of the Plane | Fly in business or first |
| Equator Crosser | Route crossing the equator |
| Dateline | Route crossing the antimeridian |

**Time & behavior**
| Badge | Rule |
|---|---|
| Early Bird | Spot between 04:00 and 06:00 local |
| Night Owl (Lvl) | Spots after sunset (computed with solar position) |
| Weekend Warrior (Lvl) | Spot on N consecutive weekends |
| Session Pro | 50 aircraft in a single spotting session |
| Rainy Day | Check-in while weather is rain (optional weather API) |
| Go-Around | Tag a go-around |
| Anniversary | Check in on your Wingspot anniversary |

**Rarity**
| Badge | Rule |
|---|---|
| Unicorn | Spot an aircraft type with < 10 airframes in service |
| Last of Its Kind | Spot an aircraft type in its final year of passenger service (curated list) |
| First of Its Kind | Spot a type within 6 months of entry into service |
| Rare Bird | Spot a registration nobody else on Wingspot has logged at this airport |

**Community & events**
| Badge | Rule |
|---|---|
| Social Flyer | Get 10 salutes on a single check-in |
| Wingman | Check in together with a friend (same place, same hour) |
| Airshow Season (time-limited) | Check in at a curated airshow event |
| Seasonal badges | e.g. *Winter Ops*, *Summer Rush*, *Holiday Heavies* |

### 5.3 User level (XP)
Each check-in gives XP; badges give bonus XP. Levels show on the profile ("Lvl 23 · Captain").

| Action | XP |
|---|---|
| Spotted check-in | 10 |
| New registration (first seen by you) | +15 |
| New type | +30 |
| Flown check-in | 25 (+1 per 500 km) |
| New airport | +40 |
| Photo attached | +5 |
| Verified check-in | ×1.5 |
| Badge unlocked | 50 × level |

Rank titles: Cadet → Student Pilot → First Officer → Captain → Senior Captain → Chief Pilot → Ace → Legend.

### 5.4 Badge engine design
Badges are **data, not code**. Each badge is a JSON rule evaluated server-side after each check-in (and recomputed in batch when the reference data changes).

```json
{
  "id": "triple_seven_collector",
  "name": "Triple Seven Collector",
  "category": "types",
  "kind": "leveled",
  "requiresVerified": false,
  "metric": {
    "aggregate": "count_distinct",
    "field": "aircraft_type_icao",
    "filter": { "checkin_kind": ["spotted", "flown"], "type_family": "B777" }
  },
  "levels": [2, 4, 6, 7],
  "validFrom": null,
  "validUntil": null
}
```

Supported aggregates: `count`, `count_distinct`, `sum` (distance), `max` (single flight distance), `streak` (consecutive periods), `exists` (single), `custom` (escape hatch → named SQL function). This lets you add new badges (and seasonal events) without an app update.

---

## 6. Social features

### 6.1 Friends & feed
- Follow model (asymmetric) with optional "friends" (mutual) for private profiles.
- Feed: friends' check-ins, badge unlocks, session summaries, milestones.
- Reactions: **Salute** ✈️ (the "like") + comments.
- Global feed per airport ("Live at FRA") — only public check-ins, delay configurable.

### 6.2 Profiles
- Header: avatar, level, home airport, totals (check-ins · regs · types · airports · km flown).
- Tabs: Activity · Badges · Collection · Map · Photos.
- **Collection** views: by type, by operator, by airport, by registration (with "times seen"), "most seen aircraft".
- **Map:** airports visited (pins), routes flown (great-circle arcs), spotting locations.
- Year in Review ("Wingspot Wrapped") — shareable story image every December.

### 6.3 Airports & spotting locations
Airports are the "venues". Each airport page has:
- Info (IATA/ICAO, runways, elevation, country), map.
- **Spotting locations** (user-contributed, moderated): coordinates, best runway direction, best time of day (sun position), parking, legal notes, photos, rating.
- Leaderboards: most check-ins this month, most unique regs, "Top spotter".
- Recent activity and "rare today" (unusual types logged in the last 24h).

### 6.4 Lists & goals
- Personal wishlists: "Want to see: A340-600, An-124, B747-8i in LH retro".
- Notifications when a friend logs an aircraft on your wishlist at a nearby airport (opt-in).

---

## 7. Trust & verification

| Level | How | Badge eligibility |
|---|---|---|
| **Unverified** | Manual entry | All non-verified badges |
| **Location-verified** | GPS fix within airport geofence (airport polygon + 5 km buffer) at check-in time | + airport badges |
| **ADS-B verified** | Aircraft's ADS-B track within ~15 km of user location ±10 min | + verified/rare badges |
| **Boarding-pass verified** | BCBP scan matches flight + date | + verified flown badges |

Anti-cheat rules: rate limit (e.g. max 200 check-ins/hour), impossible-travel detection (two airport check-ins 2000 km apart in 1 h → flagged), backdated check-ins (> 7 days) never count as verified.

---

## 8. Safety, privacy & legal

- **Location:** stored precisely only privately. Public check-ins show the airport/spotting location, never raw GPS. Option to delay public posts by 1–24 h.
- **Home location** is never inferred or shown; profile shows "home airport" only if the user sets it.
- **Sensitive aircraft:** military, government and blocked (e.g. LADD/PIA, private) registrations: no public live display, optional hiding of registration on public posts.
- **Country safety notes:** some countries treat photography at airports/military sites as a crime. Show a warning on airports in flagged countries; spotting location pages carry legal notes.
- **User-generated content (App Store Guideline 1.2):** report & block users, report content, moderation queue, EULA with zero-tolerance policy, filtering of offensive text.
- **Sign in with Apple** required as soon as any third-party login exists (Guideline 4.8).
- **Photos:** EXIF GPS stripped from public versions; users keep copyright; license grant to display only.
- **GDPR:** data export (JSON/CSV), account deletion inside the app (Guideline 5.1.1(v)), minimal analytics.
- **Naming & branding:** "Wingspot" is your own brand; don't use names, logos or styling of existing apps/sites (e.g. beer check-in apps or Planespotters.net) in store listing or UI. Airline logos are trademarks — use airline names + ICAO codes and neutral colored tail markers instead of real logos unless licensed.

---

## 9. Information architecture & screens

### Tab bar (5 tabs)
1. **Feed** — friends + "near me".
2. **Explore** — search (reg, type, airline, airport, user), airports near me, trending rare aircraft, map.
3. **➕ Check in** — center action button → sheet with three options: *Spotted · Flown · Airport*. Long-press = last used mode.
4. **Badges** — earned, in progress (sorted by "closest to unlock"), catalog, events.
5. **Profile** — stats, collection, map, settings.

### Key screens

| Screen | Purpose / notes |
|---|---|
| Onboarding | 3 screens value prop → sign in (Apple / email) → choose home airport → permissions (location "when in use", notifications) asked **in context**, not upfront. |
| Check-in: Spotted | Big registration field with live autocomplete (local DB) · type fallback · location chip · tags · photo · "Check in" button. Keyboard optimized for regs (uppercase, dash auto-insert per country prefix: `DAIMA` → `D-AIMA`). |
| Check-in: Flown | Scan boarding pass (primary) · or flight number + date · or manual route. |
| Check-in: Airport | Nearest airports list, context picker, spotting location picker. |
| Check-in result | Celebration screen: new reg/type/airport chips, XP gain, badges unlocked (animated + haptic), progress to next badge, share card. |
| Aircraft detail (registration) | Photo gallery from community, type, operator history, first flight / age, "you've seen it N times", map of where it was spotted by everyone. |
| Aircraft type detail | Family, manufacturer, specs, your regs of this type, % of known fleet seen. |
| Airport detail | See §6.3. |
| Badge detail | Art, description, levels, your progress, rarity ("3.2% of users have this"), recent earners among friends. |
| Session | Live counter during a spotting session, list of entries, end session → summary post. |
| Stats | Charts: check-ins over time, top types/airlines/airports, km per year, heatmap calendar. |
| Settings | Privacy (default visibility, post delay), units (km/nm/mi), notifications, data export, delete account, Pro. |

### iOS platform features
- **Widgets:** "Days since last spot", badge progress, year stats; interactive "Start session" widget.
- **App Intents / Shortcuts / Siri:** "Log D-AIMA in Wingspot", "Start spotting session".
- **Control Center control** (iOS 18+): quick "Check in" button.
- **Live Activity:** active spotting session counter on Lock Screen / Dynamic Island; for flown check-ins a flight progress Live Activity (phase 3).
- **Apple Watch** (phase 3): quick check-in by registration dictation / last-seen types.
- **Share Extension:** share a photo from Photos → Wingspot check-in with EXIF prefill.

---

## 10. Reference data (the hard part)

The app lives or dies on good aircraft/airport data. Plan for it early.

| Data | Source options | Notes |
|---|---|---|
| **Airports** (≈ 70k incl. small fields) | [OurAirports](https://ourairports.com/data/) — public domain | IATA/ICAO, coordinates, elevation, runways, country. Filter to airports with IATA code or scheduled service for default search. |
| **Airport polygons** (geofences) | OpenStreetMap `aeroway=aerodrome` (ODbL) | For location verification. Fallback: radius from runway length. |
| **Aircraft types** | ICAO Doc 8643 designators (curate manually into your own table); Wikidata for specs | ~2,500 designators; you need: ICAO code, manufacturer, model, family, engine type/count, WTC category. |
| **Airlines / operators** | OpenFlights airlines (ODbL, partly outdated) + Wikidata + manual curation | ICAO/IATA codes, callsign, country, alliance, LCC/flag/cargo flags. |
| **Registrations → type/operator** | OpenSky aircraft database (check license), national registries (FAA, UK CAA G-INFO, etc. — many are open), community edits | Biggest effort. Start with OpenSky DB + FAA + G-INFO; allow users to submit corrections; unknown regs can still be checked in ("pending" → resolved later). |
| **Flight lookup** (flight number → route, reg) | AeroDataBox (RapidAPI), FlightAware AeroAPI, Cirium (enterprise) | Paid per call → server-side only, cache aggressively, limit for free users. |
| **Live/historic ADS-B** | adsb.lol (open, ODbL), OpenSky Network API (non-commercial terms — needs a commercial agreement for a paid app), ADS-B Exchange (commercial licensing) | Needed for "What's overhead?" and ADS-B verification. Verify license terms before shipping. |
| **Sunrise/sunset** | Computed locally (solar position algorithm) | For Night Owl etc., no API needed. |
| **Weather** | Apple WeatherKit (500k calls/month included) or METAR from aviationweather.gov | Optional badges + nice "conditions" on check-ins (METAR is very on-brand). |

**On-device database:** ship a compressed SQLite snapshot of airports, types, airlines and the most common ~500k registrations (~20–40 MB) so autocomplete works offline; update via delta downloads weekly.

---

## 11. Technical architecture

### 11.1 Stack recommendation

| Layer | Choice | Why |
|---|---|---|
| iOS app | **Swift 6, SwiftUI, iOS 18+** minimum (adopt iOS 26 Liquid Glass where available) | Modern concurrency, Observation, SwiftData stable. |
| Local persistence | **SwiftData** for user data + outbox; **GRDB/SQLite** read-only for the big reference DB | SwiftData is great for the user's own models; a 500k-row read-only lookup DB is faster & smaller in plain SQLite with FTS5. |
| Backend | **Supabase** (Postgres + PostGIS, Auth, Storage, Edge Functions, Realtime) | Relational data and geo queries fit Postgres perfectly; badge rules become SQL aggregates; Sign in with Apple supported; open source → no lock-in. |
| Alternative backend | Firebase (Firestore, Auth, Functions, Storage) | Faster start, but aggregations ("count distinct types for user") and geo queries are awkward in Firestore and cost more at scale. |
| Images | Supabase Storage + image transformation (or Cloudflare Images) | Thumbnails 400 px, feed 1080 px, original private. |
| Push | APNs via Edge Function | Badge unlocks, friend activity, salutes. |
| Analytics / crashes | TelemetryDeck (privacy-friendly) + Xcode Organizer / Sentry | GDPR-friendly. |
| Payments | StoreKit 2 | Subscriptions. |

### 11.2 App architecture

- **MV (Model-View) with `@Observable` stores** per feature, dependency injection via `Environment`. Keep it simple; no heavy framework needed.
- **Offline-first sync:** every write goes to SwiftData first with `syncState = .pending` → an `OutboxSyncer` (actor) pushes to the API when online → server returns canonical IDs, verification result and unlocked badges → local record updated, celebration shown (if offline, celebration appears with "badge pending sync").
- Badge evaluation is **server-authoritative**; the client shows *predicted* progress from local data for instant feedback.

```
Wingspot (Xcode project)
├── App/                      # App entry, root TabView, DI container
├── Features/
│   ├── CheckIn/              # Spotted, Flown, Airport flows, Session, BoardingPassScanner
│   ├── Feed/
│   ├── Explore/
│   ├── Badges/
│   ├── Profile/              # Stats, Collection, Map
│   ├── AircraftDetail/
│   ├── AirportDetail/
│   └── Settings/
├── Packages/ (local Swift packages)
│   ├── WingspotCore/         # Domain models, value types (Registration, ICAOType, GreatCircle)
│   ├── ReferenceData/        # GRDB access to bundled SQLite, FTS search, delta updates
│   ├── Persistence/          # SwiftData models + outbox
│   ├── APIClient/            # Supabase client wrapper, DTOs
│   ├── BCBP/                 # Boarding pass barcode parser (pure Swift, unit tested)
│   ├── BadgeEngine/          # Client-side predicted progress (shares rule JSON with server)
│   └── DesignSystem/         # Colors, typography, badge renderer, components
├── Widgets/                  # WidgetKit + Live Activity extension
├── ShareExtension/
└── Tests/
```

### 11.3 Server data model (Postgres)

```sql
-- Reference data
create table airports (
  id            serial primary key,
  icao          text unique,
  iata          text,
  name          text not null,
  city          text,
  country_code  char(2) not null,
  continent     char(2) not null,
  elevation_ft  int,
  location      geography(point) not null,
  geofence      geography(polygon),
  is_island     boolean default false,
  min_runway_m  int
);

create table aircraft_types (
  icao_code     text primary key,        -- 'A388'
  manufacturer  text not null,           -- 'Airbus'
  model         text not null,           -- 'A380-800'
  family        text,                    -- 'A380'
  engine_type   text,                    -- jet | turboprop | piston | helicopter
  engine_count  int,
  wtc           char(1),                 -- L M H J
  in_service_count int,                  -- for rarity badges
  entry_into_service date
);

create table operators (
  id            serial primary key,
  icao          text unique,
  iata          text,
  name          text not null,
  country_code  char(2),
  alliance      text,                    -- star | oneworld | skyteam | null
  category      text                     -- flag | lcc | cargo | charter | military | gov | private
);

create table aircraft (
  id            serial primary key,
  registration  text unique not null,    -- normalized 'D-AIMA'
  icao24        char(6),                 -- ADS-B hex
  type_icao     text references aircraft_types,
  operator_id   int references operators,
  msn           text,
  first_flight  date,
  livery        text,                    -- 'standard' | 'special' | 'retro'
  livery_name   text,
  is_sensitive  boolean default false,
  data_status   text default 'verified'  -- verified | pending | user_submitted
);

-- User data
create table profiles (
  id            uuid primary key references auth.users,
  username      text unique not null,
  display_name  text,
  avatar_url    text,
  home_airport  int references airports,
  xp            int default 0,
  is_private    boolean default false,
  post_delay_minutes int default 0,
  created_at    timestamptz default now()
);

create type checkin_kind as enum ('spotted', 'flown', 'airport');
create type verification as enum ('none', 'location', 'adsb', 'boarding_pass');

create table checkins (
  id            uuid primary key,          -- generated on device (offline-first)
  user_id       uuid not null references profiles,
  kind          checkin_kind not null,
  occurred_at   timestamptz not null,
  created_at    timestamptz default now(),
  aircraft_id   int references aircraft,
  type_icao     text references aircraft_types,   -- denormalized / fallback
  operator_id   int references operators,
  airport_id    int references airports,          -- spotted at / airport visit
  spot_location_id int references spotting_locations,
  location      geography(point),                 -- private
  phase         text,
  tags          text[] default '{}',
  note          text,
  rating        smallint check (rating between 1 and 5),
  session_id    uuid references sessions,
  verification  verification default 'none',
  visibility    text default 'public',            -- public | friends | private
  -- flown only
  flight_number text,
  origin_id     int references airports,
  destination_id int references airports,
  distance_km   int,
  cabin_class   text,
  seat          text
);
create index on checkins (user_id, occurred_at desc);
create index on checkins (airport_id, occurred_at desc);
create index on checkins (aircraft_id);

create table checkin_photos (id uuid primary key, checkin_id uuid references checkins on delete cascade,
                             storage_path text, width int, height int, position smallint);
create table sessions (id uuid primary key, user_id uuid references profiles, airport_id int references airports,
                       started_at timestamptz, ended_at timestamptz);
create table spotting_locations (id serial primary key, airport_id int references airports, name text,
                       location geography(point), description text, best_time text, legal_notes text,
                       created_by uuid references profiles, status text default 'pending');

create table badges (id text primary key, name text, description text, category text, kind text,
                     rule jsonb not null, levels int[], requires_verified boolean, hidden boolean,
                     valid_from timestamptz, valid_until timestamptz, art_url text);
create table user_badges (user_id uuid references profiles, badge_id text references badges, level int,
                          progress int, unlocked_at timestamptz, checkin_id uuid references checkins,
                          primary key (user_id, badge_id));

create table follows   (follower uuid references profiles, followee uuid references profiles,
                        created_at timestamptz default now(), primary key (follower, followee));
create table salutes   (user_id uuid references profiles, checkin_id uuid references checkins on delete cascade,
                        primary key (user_id, checkin_id));
create table comments  (id uuid primary key, checkin_id uuid references checkins on delete cascade,
                        user_id uuid references profiles, body text, created_at timestamptz default now());
create table reports   (id uuid primary key, reporter uuid references profiles, target_type text,
                        target_id text, reason text, status text default 'open');
create table blocks    (blocker uuid references profiles, blocked uuid references profiles, primary key (blocker, blocked));
```

Use **Row Level Security** everywhere: users write only their own rows; reads respect `visibility`, `is_private`, blocks and `post_delay_minutes`. Raw `location` is never exposed through public views.

### 11.4 Key API operations (Edge Functions / RPC)

| Operation | Description |
|---|---|
| `POST /checkins` (batch) | Upsert 1..n check-ins from the outbox (idempotent by client UUID). Returns canonical data, verification level, XP, unlocked badges, progress deltas. |
| `GET /feed?cursor=` | Friends feed, keyset pagination. |
| `GET /airports/{id}/activity` | Public recent activity, leaderboards. |
| `GET /aircraft/lookup?reg=` | Registration lookup incl. unknown → creates `pending` aircraft. |
| `GET /flights/lookup?number=&date=` | Server-side proxy to flight data provider, cached. |
| `GET /nearby?lat=&lon=` | ADS-B aircraft near user (Pro, phase 2). |
| `GET /refdata/delta?since=` | Delta updates for on-device reference DB. |
| `POST /badges/recompute` (internal) | Batch job after new badge rules / data fixes. |

---

## 12. Visual design direction

- **Tone:** clean "flight deck" feel — dark navy, white, signal orange accent (think cockpit instruments, runway markings), not airline-branded.
- **Typography:** SF Pro / SF Pro Rounded for badges, **SF Mono** for registrations, ICAO codes and flight numbers (they are codes — show them like codes).
- **Badges:** circular/shield patches inspired by **pilot mission patches and airline wings** — each category with its own shape (types = round patch, airports = tag/luggage label, flown = wings, time = clock bezel, events = shield). Leveled badges get a ring/stripe per level (like captain's stripes: 1–4 stripes, then gold).
- **Celebration:** contrail animation + haptic on badge unlock; respect *Reduce Motion*.
- **Accessibility:** Dynamic Type everywhere, VoiceOver labels for badges ("Superjumbo badge, unlocked 3 May 2026"), colorblind-safe badge colors (shape + text, not color only).

---

## 13. Monetization

Free app with an optional **Wingspot Pro** subscription (e.g. €3.99/month · €29.99/year, family sharing on).

| Free | Pro |
|---|---|
| Unlimited check-ins, all badges | Everything free + |
| 4 photos per check-in | 10 photos, full resolution storage |
| Basic stats | Advanced stats, charts, year filters, CSV/JSON export |
| 5 flight lookups / month | Unlimited flight lookups |
| — | "What's overhead?" live ADS-B |
| — | Wishlist alerts at nearby airports |
| — | Custom app icons, profile themes, Pro badge frame |
| Non-intrusive ads? (decide; ads hurt a hobby community — recommend **no ads**) | — |

Never paywall **badges** or **check-ins** — that is the core loop and the social proof.

Later: partnerships with airshows/airports (event badges), spotting-guide content, merch (embroidered patches of earned badges — a very natural fit).

---

## 14. Roadmap

### Phase 0 — Foundations (2–3 weeks)
- Xcode project, packages, CI (Xcode Cloud or GitHub Actions + Fastlane).
- Supabase project, schema, RLS, Sign in with Apple.
- Reference data pipeline: scripts to import OurAirports, ICAO types, operators, initial registrations → Postgres + generate on-device SQLite.

### Phase 1 — MVP (8–10 weeks) → TestFlight
- Auth, onboarding, profile.
- Check-in: Spotted (reg/type autocomplete, location, tags, 1 photo), Airport, Flown (manual + **boarding pass scan**).
- Offline outbox + sync.
- Badge engine (server) with ~40 launch badges, XP & levels, celebration screen.
- Profile: stats, collection lists, badges tab, airports map.
- Follow, feed, salutes, comments, report/block.
- Airport detail page (info + recent public activity).
- Settings, privacy controls, account deletion, data export.

### Phase 2 — Spotter power (6–8 weeks) → App Store 1.0 / 1.1
- Spotting sessions + Live Activity, batch mode.
- Photo import with EXIF prefill, Share Extension.
- Flight number lookup.
- Spotting locations (user-contributed + moderation).
- Airport leaderboards.
- Widgets, App Intents.
- Wingspot Pro (StoreKit 2).
- "What's overhead?" (ADS-B) + ADS-B verification (after licensing is settled).

### Phase 3 — Growth
- Seasonal events & time-limited badges, Year in Review.
- Wishlists & alerts.
- Apple Watch app.
- On-device aircraft type recognition from photos (Core ML; train on community photos with consent).
- Localization (DE, EN first; then FR, ES, NL, JA).
- Android / web profile pages (shareable public profile URLs for virality).

---

## 15. Success metrics

| Metric | Target (first 6 months) |
|---|---|
| Time to first check-in after install | < 3 min median |
| Check-in completion time (spotted) | < 10 s median |
| D1 / D7 / D30 retention | 45% / 25% / 15% |
| Check-ins per weekly active user | ≥ 8 |
| % users with ≥ 1 friend | ≥ 40% |
| Pro conversion | 3–5% of MAU |

---

## 16. Open questions / decisions to make

1. **Backend:** Supabase (recommended) vs. Firebase vs. CloudKit (CloudKit is free and private but makes social/global features and Android later very hard → not recommended for a social app).
2. **Registration data licensing:** which sources can be used commercially? Budget for a commercial data source vs. community-built database.
3. **ADS-B provider & license** for live/verification features.
4. **Flight lookup provider** and cost per lookup → defines free-tier limits.
5. **Moderation:** who reviews reports and spotting locations at launch (you alone? community moderators?).
6. **Pilot logbook** — separate track for private/commercial pilots (hours, PIC)? Could be a strong niche, but out of scope for MVP.
7. **Name & trademark check** for "Wingspot" in your target markets + App Store name availability.

---

## 17. First development steps

1. Create the Xcode project `Wingspot` (iOS 18+, SwiftUI, Swift 6 language mode) with the package structure from §11.2.
2. Write `WingspotCore` value types + unit tests: `Registration` normalization (country prefixes, e.g. `DAIMA` → `D-AIMA`, `N123AB` stays), `GreatCircle.distance`, `ICAOType`.
3. Build the `BCBP` parser package with test fixtures (a self-contained, satisfying first module).
4. Script the reference data import (OurAirports + ICAO types) into an SQLite file and wire up `ReferenceData` with FTS5 search.
5. Build the Spotted check-in screen against local data only (SwiftData), including the result/celebration screen with client-side badge prediction.
6. Add Supabase: auth, schema, `POST /checkins`, server badge evaluation.
7. Feed + profile → first TestFlight with friends from the spotting community.
