# Wingspot — App Concept

> Log every aircraft you spot or fly on, every airport you visit — and earn badges for it.

Version 0.2 · November 2026 · Status: Draft for development kickoff
Platforms: native iOS (Swift/SwiftUI) and native Android (Kotlin/Jetpack Compose) on one shared backend

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
6. **One backend, native clients.** iOS and Android are fully native apps that feel at home on their platform. All business rules (badges, XP, verification, entitlements) live on the server; clients only render, cache and predict. Nothing in the backend may depend on a single platform.

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
| Photo(s) | Optional | Up to 4 (Pro: 10). The phone removes location data and uploads a JPEG, and originals aren't stored. |
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

**Fast path: boarding pass scan.** The IATA *BCBP* barcode (PDF417/Aztec/QR) contains name, PNR, from, to, carrier, flight number, date (Julian), seat and class. Scan from camera or a screenshot, fully on-device (iOS: Vision framework · Android: ML Kit Barcode Scanning, bundled model) → prefilled check-in. The passenger name and PNR are **never stored or uploaded**.

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
Badges are **data, not code**. Each badge is a JSON rule evaluated server-side after each check-in (and recomputed in batch when the reference data changes). Names and descriptions are stored in each language in the backend, because a new badge can't wait for an app update.

```json
{
  "id": "triple_seven_collector",
  "name": { "en": "Triple Seven Collector", "de": "Triple-Seven-Sammler" },
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
- **User-generated content** (App Store Guideline 1.2, Google Play UGC policy): report & block users, report content, moderation queue, EULA with zero-tolerance policy, filtering of offensive text. One moderation system on the server serves both apps.
- **Sign-in:** Sign in with Apple, Sign in with Google and email (magic link). On iOS, Sign in with Apple must be offered once Google login exists (Guideline 4.8). Both providers are available on both platforms (Apple via web OAuth on Android), so a user can switch phones and keep their account.
- **Account deletion:** in-app on both platforms, plus a public web URL for deletion requests (required by Google Play).
- **Photos:** EXIF GPS stripped from public versions; users keep copyright; license grant to display only.
- **GDPR:** data export (JSON/CSV), account deletion inside the app (Guideline 5.1.1(v)), minimal analytics.
- **Naming & branding:** "Wingspot" is your own brand; don't use names, logos or styling of existing apps/sites (e.g. beer check-in apps or Planespotters.net) in store listing or UI. Airline logos are trademarks — use airline names + ICAO codes and neutral colored tail markers instead of real logos unless licensed.

---

## 9. Information architecture & screens

The information architecture is identical on both platforms; the visual implementation follows each platform's conventions (iOS: tab bar, sheets, SF Symbols, Liquid Glass · Android: Material 3 navigation bar, bottom sheets, Material Symbols, dynamic color as an option). Screen names and IDs are shared so analytics, deep links and the spec stay aligned.

### Main navigation (5 destinations)
1. **Feed** — friends + "near me".
2. **Explore** — search (reg, type, airline, airport, user), airports near me, trending rare aircraft, map.
3. **➕ Check in** — center action button → sheet with three options: *Spotted · Flown · Airport*. Long-press = last used mode.
4. **Badges** — earned, in progress (sorted by "closest to unlock"), catalog, events.
5. **Profile** — stats, collection, map, settings.

### Key screens

| Screen | Purpose / notes |
|---|---|
| Onboarding | 3 screens value prop → sign in (Apple / email, can be skipped) → choose username and home airport → permissions (location "when in use", notifications) asked **in context**, not upfront. |
| Check-in: Spotted | Big registration field with live autocomplete (local DB) · type fallback · location chip · tags · photo · "Check in" button. Keyboard optimized for regs (uppercase, dash auto-insert per country prefix: `DAIMA` → `D-AIMA`). |
| Check-in: Flown | Scan boarding pass (primary) · or flight number + date · or manual route. |
| Check-in: Airport | Nearest airports list, context picker, spotting location picker. |
| Check-in result | Celebration screen: new reg/type/airport chips, XP gain, badges unlocked (animated + haptic), progress to next badge, share card. |
| Aircraft detail (registration) | Photo gallery from community, type, operator history, first flight / age (as far as users have entered them, see §10), "you've seen it N times", map of where it was spotted by everyone. |
| Aircraft type detail | Family, manufacturer, specs, your regs of this type, % of known fleet seen. |
| Airport detail | See §6.3. |
| Badge detail | Art, description, levels, your progress, rarity ("3.2% of users have this"), recent earners among friends. |
| Session | Live counter during a spotting session, list of entries, end session → summary post. |
| Stats | Charts: check-ins over time, top types/airlines/airports, km per year, heatmap calendar. |
| Settings | Privacy (default visibility, post delay), units (km/nm/mi), notifications, data export, delete account, Pro. |

### Platform features

| Feature | iOS | Android |
|---|---|---|
| Home screen widgets | WidgetKit: "days since last spot", badge progress, year stats, interactive "Start session" | Jetpack Glance widgets with the same content |
| Voice / shortcuts | App Intents, Shortcuts, Siri: "Log D-AIMA in Wingspot" | App Actions / Gemini, static & dynamic app shortcuts |
| Quick check-in control | Control Center control (iOS 18+) | Quick Settings tile |
| Ongoing session | Live Activity on Lock Screen / Dynamic Island | Ongoing notification (Live Updates / progress-style notification on Android 16+) |
| Share a photo into the app | Share Extension | Share intent (`ACTION_SEND` for images) |
| Watch (phase 3) | watchOS app | Wear OS app |
| Deep links | Universal Links | Android App Links |

Both platforms register the same link scheme: `https://wingspot.site/u/{username}`, `/c/{checkinId}`, `/a/{icao}`, `/r/{registration}`, `/b/{badgeId}`. The domain hosts both `apple-app-site-association` and `assetlinks.json`, and a lightweight web page for each link so shared links work without the app installed.

---

## 10. Reference data (the hard part)

The app lives or dies on good aircraft/airport data. Plan for it early.

| Data | Source options | Notes |
|---|---|---|
| **Airports** (≈ 70k incl. small fields) | [OurAirports](https://ourairports.com/data/) — public domain | IATA/ICAO, coordinates, elevation, runways, country. Filter to airports with IATA code or scheduled service for default search. |
| **Airport polygons** (geofences) | OpenStreetMap `aeroway=aerodrome` (ODbL) | For location verification. Fallback: radius from runway length. |
| **Aircraft types** | ICAO Doc 8643 designators (curate manually into your own table); Wikidata for specs | ~2,500 designators; you need: ICAO code, manufacturer, model, family, engine type/count, WTC category. |
| **Airlines / operators** | Decided: Wikidata (CC0) + manual curation | ICAO/IATA codes, callsign, country, alliance, LCC/flag/cargo flags. OpenFlights isn't used, because its ODbL terms may require sharing the improved data and it's partly outdated. |
| **Registrations → type/operator** | Decided: user-entered, with no preloaded registry | The `aircraft` table starts empty and fills from check-ins, marked `user_submitted`. Any registration can be checked in, and the type and operator stay unknown until someone enters them. National registries may be added country by country later, once each one's terms are checked. |
| **Flight lookup** (flight number → route, reg) | AeroDataBox (RapidAPI), FlightAware AeroAPI, Cirium (enterprise) | Paid per call → server-side only, cache aggressively, limit for free users. |
| **Live/historic ADS-B** | adsb.lol (open, ODbL), OpenSky Network API (non-commercial terms — needs a commercial agreement for a paid app), ADS-B Exchange (commercial licensing) | Needed for "What's overhead?" and ADS-B verification. Verify license terms before shipping. |
| **Sunrise/sunset** | Computed locally (solar position algorithm) | For Night Owl etc., no API needed. |
| **Weather** | METAR from aviationweather.gov, or Apple WeatherKit **REST API** called from the server | Fetched server-side and attached to the check-in, so both apps get the same data. Optional badges + nice "conditions" on check-ins (METAR is very on-brand). |

**On-device database:** a server-side pipeline builds one compressed SQLite snapshot of airports, types and airlines, with an FTS5 search index. Registrations aren't preloaded (see the table above). **The same file is used by both apps** (iOS via GRDB, Android via Room/`SupportSQLiteDatabase` opened from a prepackaged file), downloaded on first launch or bundled, and updated via weekly delta downloads. The schema of this file is versioned (`refdata_schema_version`) and part of the shared contract (§11.5).

---

## 11. Technical architecture

### 11.1 Stack recommendation

| Layer | iOS | Android | Shared / server |
|---|---|---|---|
| Language & UI | **Swift 6, SwiftUI, iOS 18+** (adopt iOS 26 Liquid Glass where available) | **Kotlin, Jetpack Compose, Material 3, minSdk 28** (Android 9+, ~95% of devices) | — |
| Architecture | MV with `@Observable` stores | MVVM: `ViewModel` + `StateFlow`, Hilt for DI | Same feature modules & naming on both |
| User data + outbox | SwiftData | Room | Same outbox semantics (§11.2) |
| Reference DB (read-only) | GRDB + SQLite FTS5 | Room / SQLite FTS5 (prepackaged DB) | **One SQLite file** built by the data pipeline |
| Background sync | `BGTaskScheduler` + sync on foreground | WorkManager (network constraint, backoff) | Idempotent batch endpoint |
| Networking | `supabase-swift` + URLSession | `supabase-kt` + Ktor | **OpenAPI spec** for Edge Functions (§11.5) |
| Auth | Sign in with Apple (native), Google, email | Credential Manager (Google), Apple via web OAuth, email | Supabase Auth: one account, many providers |
| Camera / barcode | AVFoundation + Vision | CameraX + ML Kit Barcode Scanning | Shared BCBP test fixtures |
| Maps | MapKit | Google Maps Compose (or MapLibre for one style on both) | Server returns GeoJSON for routes/locations |
| Push | APNs | Firebase Cloud Messaging (FCM) | One `send-notification` function fans out by platform; FCM can also deliver to APNs if preferred |
| Purchases | StoreKit 2 | Google Play Billing Library | Server-side `entitlements` table, fed by App Store Server Notifications v2 + Google Real-time Developer Notifications (or RevenueCat) |
| Analytics / crashes | TelemetryDeck + Sentry | TelemetryDeck + Sentry | **Shared event catalog** (same event names & properties) |
| Backend | — | — | **Supabase** (Postgres + PostGIS, Auth, Storage, Edge Functions, Realtime) |
| Images | — | — | Supabase Storage + image transformation; clients upload via signed URLs |

**Why Supabase for two native apps:** it has first-party SDKs for both Swift and Kotlin, keeps all logic in Postgres/Edge Functions where both clients get it for free, and relational data plus PostGIS fit the badge aggregates and geofences.
**Alternative:** Firebase (Firestore, Auth, Functions) — also cross-platform, but aggregations ("count distinct types for user") and geo queries are awkward in Firestore and cost more at scale. **Not** CloudKit: it ties the social graph to Apple accounts and rules out Android.

### 11.1a Code sharing strategy
**Decision: two fully native codebases, shared contracts — no shared UI.**

| What | How it is shared |
|---|---|
| API | OpenAPI 3.1 spec → generated DTOs/clients for Swift (`swift-openapi-generator`) and Kotlin (`openapi-generator`, kotlinx.serialization) |
| Database types | `supabase gen types` for direct table access where used; otherwise only via the API |
| Badge rules | JSON from the server (`GET /badges`); client progress predictors implemented in both languages, validated against shared **golden test files** (input check-ins → expected progress) |
| BCBP parser | Implemented in Swift and Kotlin, both tested against the same fixture set (real-world anonymized barcodes) |
| Registration normalization, great-circle distance | Same: two small implementations, one shared test-vector file |
| Reference data | One SQLite file, one schema |
| Strings | The iOS string catalog (`Localizable.xcstrings`) is the one source. Android's `strings.xml` is generated from it when Android starts |
| Design tokens | Colors, spacing, typography, badge art defined once (`contracts/design-tokens.json`, SVG badge art) → exported to Asset Catalog and Compose theme |
| Analytics | `contracts/analytics-events.yaml` → generated constants for both |

*Option for later:* the pure-logic parts (BCBP, badge predictor, registration rules) are good candidates for **Kotlin Multiplatform** if maintaining two implementations becomes a burden. Start without it — the shared test vectors already guarantee identical behavior and keep the iOS build free of a KMP toolchain.

### 11.2 App architecture

Both apps follow the same layered structure and feature split, so a feature spec maps 1:1 to both codebases.

- **iOS:** MV with `@Observable` stores per feature, dependency injection via `Environment`.
- **Android:** MVVM with `ViewModel` + `StateFlow`, Hilt, Navigation Compose; one Gradle module per feature.
- **Offline-first sync (identical semantics on both):** every write goes to the local DB first with `syncState = pending` → an outbox syncer (Swift actor / WorkManager worker) pushes batches to `POST /v1/checkins` when online → server returns canonical data, verification result, XP and unlocked badges → local record updated, celebration shown (if offline: "badge pending sync"). Check-in IDs are UUIDv7 generated on the device, so retries are idempotent.
- Badge evaluation is **server-authoritative**; the client shows *predicted* progress from local data for instant feedback.
- A user can use iOS and Android with the same account (switching phones, or a phone and a tablet): the server is the source of truth, the local DB is a cache + outbox.

### Repository layout (monorepo)

```
wingspot/
├── docs/                     # This concept, feature specs, ADRs
├── contracts/                # Single source of truth shared by all clients
│   ├── openapi.yaml          # API contract (versioned /v1)
│   ├── badge-rules/          # Badge JSON + golden test files
│   ├── test-vectors/         # BCBP barcodes, registrations, distances
│   ├── design-tokens.json    # Colors, spacing, typography
│   ├── badge-art/            # SVG badge artwork
│   └── analytics-events.yaml
├── backend/
│   ├── supabase/             # migrations/, functions/ (Edge Functions), seed.sql, config.toml
│   └── refdata-pipeline/     # Import scripts → Postgres + on-device SQLite snapshot
├── ios/                      # Xcode project (structure below)
└── android/                  # Gradle project (structure below)
```

CI runs per folder (path filters): contract changes trigger codegen and the tests of **both** apps and the backend, so a breaking API change fails before it ships.

### iOS project

```
ios/Wingspot (Xcode project)
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

### Android project

```
android/ (Gradle, version catalog)
├── app/                      # Application, MainActivity, NavHost, Hilt setup
├── feature/
│   ├── checkin/              # Spotted, Flown, Airport, Session, BoardingPassScanner
│   ├── feed/  explore/  badges/  profile/
│   ├── aircraftdetail/  airportdetail/  settings/
├── core/
│   ├── model/                # Domain models (Registration, IcaoType, GreatCircle)
│   ├── refdata/              # Prepackaged SQLite, FTS search, delta updates
│   ├── database/             # Room entities + outbox
│   ├── network/              # Generated OpenAPI client, supabase-kt wrapper
│   ├── bcbp/                 # Boarding pass parser (pure Kotlin, unit tested)
│   ├── badgeengine/          # Predicted progress
│   ├── designsystem/         # Compose theme from design tokens, badge renderer
│   └── sync/                 # WorkManager outbox worker
├── widget/                   # Glance widgets
└── wear/                     # Wear OS (phase 3)
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
  data_status   text default 'user_submitted'  -- verified | pending | user_submitted
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

create table badges (id text primary key, name jsonb not null, description jsonb, category text, kind text,  -- text by language: {"en": "...", "de": "..."}
                     rule jsonb not null, levels int[], requires_verified boolean, hidden boolean,
                     valid_from timestamptz, valid_until timestamptz, art_url text);
create table user_badges (user_id uuid references profiles, badge_id text references badges, level int,
                          progress int, unlocked_at timestamptz, checkin_id uuid references checkins,
                          primary key (user_id, badge_id));

-- Devices & push (one row per installed app instance)
create type platform as enum ('ios', 'android');
create table devices (
  id            uuid primary key,          -- generated by the app on first launch
  user_id       uuid not null references profiles on delete cascade,
  platform      platform not null,
  push_token    text,                      -- APNs token (ios) or FCM token (android)
  push_env      text,                      -- 'sandbox' | 'production' (APNs only)
  app_version   text not null,
  os_version    text,
  locale        text,
  last_seen_at  timestamptz default now(),
  unique (platform, push_token)
);

-- Notification preferences are per user, not per device
create table notification_prefs (
  user_id       uuid primary key references profiles on delete cascade,
  salutes       boolean default true,
  comments      boolean default true,
  new_followers boolean default true,
  friend_badges boolean default false,
  wishlist_alerts boolean default false,
  airport_geofence boolean default false
);

-- Subscriptions: one entitlement per user, regardless of the store it was bought in
create type store as enum ('app_store', 'play_store', 'promo');
create table entitlements (
  user_id       uuid references profiles on delete cascade,
  entitlement   text not null,             -- 'pro'
  store         store not null,
  product_id    text not null,             -- e.g. 'pro_yearly'
  original_transaction_id text not null,   -- App Store originalTransactionId / Play purchaseToken
  status        text not null,             -- active | grace_period | billing_retry | expired | revoked
  expires_at    timestamptz,
  auto_renew    boolean,
  updated_at    timestamptz default now(),
  primary key (user_id, entitlement, store)
);
create table store_events (                 -- raw webhook payloads for audit & replay
  id            uuid primary key,
  store         store not null,
  payload       jsonb not null,
  received_at   timestamptz default now(),
  processed_at  timestamptz
);

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

Use **Row Level Security** everywhere: users write only their own rows; reads respect `visibility`, `is_private`, blocks and `post_delay_minutes`. Raw `location` is never exposed through public views. `entitlements` and `store_events` are writable only by the service role (webhooks), never by clients.

**Client rule:** apps read simple, public data (profiles, feed views, airports) directly through Supabase with RLS, but **every write with business logic goes through an Edge Function** (check-ins, badges, purchases, reports). This keeps rules in one place instead of two clients.

### 11.4 Key API operations (Edge Functions / RPC)

All endpoints are versioned under `/v1` and described in `contracts/openapi.yaml`.

| Operation | Description |
|---|---|
| `POST /v1/checkins` (batch) | Upsert 1..n check-ins from the outbox (idempotent by client UUID). Returns canonical data, verification level, XP, unlocked badges, progress deltas. |
| `GET /v1/feed?cursor=` | Friends feed, keyset pagination. |
| `GET /v1/airports/{id}/activity` | Public recent activity, leaderboards. |
| `GET /v1/aircraft/lookup?reg=` | Registration lookup. Read-only, because `POST /v1/checkins` creates missing aircraft. |
| `GET /v1/flights/lookup?number=&date=` | Server-side proxy to flight data provider, cached; free-tier quota checked against `entitlements`. |
| `GET /v1/nearby?lat=&lon=` | ADS-B aircraft near user (Pro, phase 2). |
| `GET /v1/badges` | Badge catalog incl. rule JSON and art URLs (ETag-cached). |
| `GET /v1/refdata/manifest` · `/v1/refdata/delta?since=` | Current snapshot URL + schema version; delta updates for the on-device DB. |
| `POST /v1/devices` | Register/refresh a device and its push token (called on launch and token change). |
| `DELETE /v1/devices/{id}` | Unregister on sign-out. |
| `GET /v1/me/entitlements` | Current Pro status, valid across both platforms. |
| `POST /v1/purchases/verify` | Client sends a fresh App Store signed transaction or a Play purchase token right after purchase; server verifies with the store and updates `entitlements`. |
| `POST /webhooks/app-store` | App Store Server Notifications v2 (renewals, refunds, expiry). |
| `POST /webhooks/play` | Google Play Real-time Developer Notifications via Pub/Sub push. |
| `GET /v1/config` | Remote config: minimum supported app version per platform, feature flags, kill switches. |
| `POST /badges/recompute` (internal) | Batch job after new badge rules / data fixes. |

### 11.5 Cross-platform contract rules

- **Versioning:** breaking changes only in a new API version (`/v2`); `/v1` stays alive until both apps' minimum versions (`/v1/config`) no longer use it. Additive changes (new fields, new badge kinds) must be ignored safely by older clients — unknown badge `kind` or check-in `tag` values are rendered generically, never crash.
- **Minimum app version:** `/v1/config` returns `min_version` per platform; apps below it show a "please update" screen. Needed because iOS and Android releases ship at different times.
- **Feature flags:** new features are enabled per platform, so one app can ship a feature before the other without diverging backend behavior.
- **Push payloads:** one notification model on the server (`type`, `title_key`, `body_args`, `deep_link`), rendered per platform. Localized on the server using the user's `locale` so both apps show identical texts. Send logic: look up the user's `devices`, send APNs to iOS tokens and FCM to Android tokens, delete tokens the stores report as invalid.
- **Languages:** German and English from the first TestFlight, with English as the fallback for any other language.
  - Apps follow the phone's language, which the system can also set per app, so there's no language setting of our own.
  - The API returns badge text in all languages, so changing language also works offline.
  - API errors carry a fixed `code`, and apps show their own text for it. `message` is for debugging only.
  - Sign-up emails and shared-link pages come in both languages.
  - Airport names, aircraft names and user content aren't translated. German airport names are added as search terms.
- **Entitlements:** a user who buys Pro on iOS has Pro on Android too (and vice versa). Clients **never** decide Pro status from the local store receipt alone; they ask `/v1/me/entitlements`. The "Manage subscription" link points to the store the purchase was made in.
- **Time & units:** all timestamps UTC ISO-8601 with the airport's/location's IANA time zone stored next to it (needed for "Early Bird"/"Red-Eye" rules); distances in km on the wire, converted for display.
- **Images:** clients request a signed upload URL, upload directly to storage, then reference the path in the check-in. HEIC (iOS) is converted to JPEG/AVIF server-side so Android and the web can always display it.
- **Parity checklist:** every feature spec in `docs/` lists iOS and Android status; a feature counts as "done" for a release only when the platform it targets is done, and the backend never assumes both have it.

---

## 12. Visual design direction

- **Tone:** clean "flight deck" feel — dark navy, white, signal orange accent (think cockpit instruments, runway markings), not airline-branded.
- **Brand vs. platform:** brand elements (colors, badge art, celebration moments, typography for codes) are identical on both platforms and come from `contracts/design-tokens.json` and `contracts/badge-art/`; controls, navigation and system patterns follow each platform (HIG on iOS, Material 3 on Android).
- **Typography:** iOS: SF Pro / SF Pro Rounded, **SF Mono** for registrations, ICAO codes and flight numbers. Android: Roboto Flex / system font, **JetBrains Mono or Roboto Mono** for codes. (They are codes — show them like codes on both.)
- **Badges:** circular/shield patches inspired by **pilot mission patches and airline wings** — each category with its own shape (types = round patch, airports = tag/luggage label, flown = wings, time = clock bezel, events = shield). Leveled badges get a ring/stripe per level (like captain's stripes: 1–4 stripes, then gold).
- **Celebration:** contrail animation + haptic on badge unlock; respect *Reduce Motion* (iOS) / *Remove animations* (Android).
- **Accessibility:** Dynamic Type / font scaling everywhere, VoiceOver and TalkBack labels for badges ("Superjumbo badge, unlocked 3 May 2026"), colorblind-safe badge colors (shape + text, not color only).

---

## 13. Monetization

Free app with an optional **Wingspot Pro** subscription (e.g. €3.99/month · €29.99/year), sold through the App Store (StoreKit 2, Family Sharing on) and Google Play (Play Billing, same product IDs `pro_monthly` / `pro_yearly`, same price points). **Pro is tied to the Wingspot account, not to the store:** bought once, it unlocks Pro on every platform the user signs in on (see §11.5).

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

**Platform sequencing:** the backend is built platform-neutral from day one, but the clients ship **iOS first, Android second** (a solo/small team should not build two apps in parallel before the core loop is proven). Android starts once the iOS MVP is in TestFlight and the API contract is stable; it targets feature parity with iOS 1.0 rather than chasing the latest iOS features. If you have a second developer, Android can start at Phase 1 against the same contract.

### Phase 0 — Foundations (2–3 weeks)
- Monorepo layout (§11.2), `contracts/` with a first `openapi.yaml`, CI with path filters (GitHub Actions; Fastlane for iOS, Gradle Play Publisher for Android later).
- Supabase project, migrations, RLS, Auth with Apple, Google and email.
- `devices`, `entitlements` and `/v1/config` from the start, even if only iOS uses them at first.
- Reference data pipeline: scripts to import OurAirports, ICAO types, operators → Postgres + generate the shared on-device SQLite.
- Shared test vectors (registrations, distances, BCBP fixtures).

### Phase 1 — iOS MVP (8–10 weeks) → TestFlight
- Auth, onboarding, profile.
- Check-in: Spotted (reg/type autocomplete, location, tags, 1 photo), Airport, Flown (manual + **boarding pass scan**).
- Offline outbox + sync.
- Badge engine (server) with ~40 launch badges, XP & levels, celebration screen.
- Profile: stats, collection lists, badges tab, airports map.
- Follow, feed, salutes, comments, report/block.
- Airport detail page (info + recent public activity).
- Settings, privacy controls, account deletion, data export.
- German and English throughout (§11.5).

### Phase 2 — Spotter power (6–8 weeks) → App Store 1.0 / 1.1
- Spotting sessions + Live Activity, batch mode.
- Photo import with EXIF prefill, Share Extension.
- Flight number lookup.
- Spotting locations (user-contributed + moderation).
- Airport leaderboards.
- Widgets, App Intents.
- Wingspot Pro (StoreKit 2 + server-side entitlements and App Store webhooks).
- "What's overhead?" (ADS-B) + ADS-B verification (after licensing is settled).

### Phase 2b — Android 1.0 (10–12 weeks, can overlap with Phase 2) → Play closed testing
- Gradle project (§11.2), design system from shared tokens, generated API client.
- Port core modules against shared test vectors: registration rules, great-circle, BCBP, badge predictor.
- Feature parity with iOS 1.0: auth, all check-in types incl. boarding pass scan (ML Kit), offline outbox (Room + WorkManager), badges, feed, profile, airport pages, settings, account deletion.
- FCM push, Google Play Billing + Real-time Developer Notifications → same `entitlements`.
- Glance widget, Quick Settings tile, App Links.
- Google Play requirements: closed test with ≥ 12 testers for 14 days (new personal developer accounts), Data safety form, target the current API level.

### Phase 3 — Growth
- Seasonal events & time-limited badges, Year in Review.
- Wishlists & alerts.
- Apple Watch and Wear OS apps.
- On-device aircraft type recognition from photos (one model trained on community photos with consent, exported to Core ML for iOS and TensorFlow Lite/LiteRT for Android).
- More languages (FR, ES, NL, JA) from the shared string catalog.
- Web profile and check-in pages (the deep-link landing pages grown into shareable public profiles for virality).

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
| Crash-free sessions | ≥ 99.5% on each platform |

All metrics are tracked per platform from the shared event catalog, so iOS and Android can be compared directly.

---

## 16. Open questions / decisions to make

1. **Backend:** Supabase (recommended) vs. Firebase. CloudKit is ruled out because of the Android app.
2. **Android timing:** after the iOS MVP (recommended for a solo developer) or in parallel with a second developer?
3. **Purchase backend:** own webhook handling for both stores vs. RevenueCat (faster, free up to a revenue threshold, but an extra dependency).
4. **Kotlin Multiplatform** for the shared pure-logic modules — revisit after Android 1.0 if keeping two implementations in sync becomes painful.
5. **Maps on Android:** Google Maps (familiar, needs API key/billing) vs. MapLibre (open, can use one map style on both platforms).
6. **Registration data licensing:** decided. Registrations are user-entered, with no commercial data source (§10). At launch, a user's type and operator stay on their own check-ins, and the shared `aircraft` row holds only the registration ([PHASE1.md](PHASE1.md)). Still open: sharing entries once several users agree.
7. **ADS-B provider & license** for live/verification features.
8. **Flight lookup provider** and cost per lookup → defines free-tier limits.
9. **Moderation:** decided for launch: the project owner reviews reports. Community moderators can come later.
10. **Pilot logbook** — separate track for private/commercial pilots (hours, PIC)? Could be a strong niche, but out of scope for MVP.
11. **Name & trademark check** for "Wingspot" in your target markets + App Store and Google Play name availability, plus the `wingspot.site` domain for deep links.

---

## 17. First development steps

1. Set up the monorepo (`contracts/`, `backend/`, `ios/`, `android/`) from §11.2; leave `android/` as a placeholder for now.
2. Write the shared test vectors first: registrations (`DAIMA` → `D-AIMA`, `N123AB` stays), great-circle distances, BCBP barcodes. Both apps will be tested against them.
3. Create the Xcode project `Wingspot` (iOS 18+, SwiftUI, Swift 6 language mode) and implement `WingspotCore` (`Registration`, `GreatCircle`, `ICAOType`) and the `BCBP` parser against the test vectors.
4. Script the reference data import (OurAirports + ICAO types) into the shared SQLite file and wire up `ReferenceData` with FTS5 search.
5. Build the Spotted check-in screen against local data only (SwiftData), including the result/celebration screen with client-side badge prediction.
6. Add Supabase: migrations, auth (Apple, Google, email), `devices`, `/v1/config`, `POST /v1/checkins` with server badge evaluation — written into `openapi.yaml` first, then implemented.
7. Feed + profile → first TestFlight with friends from the spotting community.
8. Once the contract is stable: start the Android project against the same `openapi.yaml`, test vectors and SQLite file.
