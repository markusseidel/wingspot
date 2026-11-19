# Extended statistics

A plan for a statistics view that goes beyond the numbers on the profile. It is a plan only: no code changes with this document. It fits the "Advanced stats, charts, year filters" line of Wingspot Pro in [CONCEPT.md](CONCEPT.md) §13, and it should be the main reason to pay for Pro (see "Free and Pro").

## 1. Goals

- Give a logbook keeper something to look at and to show: "my year in flying", "my favourite seat", "my most flown route".
- Work offline, from the check-ins on the device, like the profile stats do today (`CheckInStats` on iOS, `Stats.kt` on Android).
- Look the same and give the same numbers on iOS and Android (see the parity rule).
- Be a believable Pro feature: free users see that it exists and a small taste of it, Pro users get the depth.
- Cost nothing to run: no new server calls, no new data collection.

## 2. What exists today

| Where | What |
|---|---|
| Profile tab, stats card | Check-ins, sightings, airport visits, flights, aircraft, types, airports, distance flown (PR #168) |
| `CheckInStats` (iOS), `CheckInStats.of` (Android) | One pass over the local check-ins. Leaves out check-ins the server refused. Keeps `routes` so distance can be worked out from airport coordinates |
| `Collections` | Lists of aircraft, types and airports with counts |
| Local check-in fields | kind, registration, type, airport, route (origin, destination), flight number, cabin, seat, date, visit context, photos |
| Not on the device | Airline (no operator field on check-ins yet), flight duration, aircraft age, seat position (window or aisle) |

The new view only uses data that is already on the device. Anything that needs new data is in "Later".

## 3. The statistics

Grouped by what they are about. Each has a source field, the rule, and what it shows. "Tier" says Free (shown in the free summary) or Pro.

### 3.1 Flights

| Statistic | Rule | Tier |
|---|---|---|
| Distance flown | Already exists. Keep it on the profile. In the new view: split by year | Free |
| Longest flight | The flight with the largest great-circle distance, with its route and date | Free |
| Shortest flight | Same, smallest. Flights with the same airport twice are left out | Pro |
| Average flight distance | Distance flown divided by flights | Pro |
| Most flown route | Route (origin to destination) with the most flights. Option "either direction" counts LHR-JFK and JFK-LHR together. Default: either direction | Free |
| Top routes | The ten most flown routes with counts | Pro |
| Most flown flight number | Flight number with the most flights, with its route | Pro |
| Times around the world | Distance flown divided by 40 075 km | Free |
| To the moon | Distance flown divided by 384 400 km, shown as a percentage | Pro |
| Domestic and international | Share of flights where both airports have the same country (the reference data has a country per airport) | Pro |
| Continents visited | Distinct continents of the airports | Pro |
| Countries visited | Distinct countries of the airports, with a list | Free (count), Pro (list) |

### 3.2 Seat and cabin

This is the part the owner asked for. All of it comes from the `seat` and `cabin` fields on flown check-ins.

| Statistic | Rule | Tier |
|---|---|---|
| Most used seat | The most common full seat such as `34K`, with the count. Ties: the most recent wins | Free |
| Favourite seat letter | The letter at the end of the seat, `K` in `34K` | Pro |
| Favourite row range | Front (rows 1 to 10), middle (11 to 30), back (31 and up). Cut-offs are approximate because aircraft differ | Pro |
| Window, middle or aisle | Only a guess: it needs the seat layout of the type, which the app does not have. Not in the first version. See "Later" | Later |
| Most flown cabin | The cabin with the most flights, with its share | Free |
| Cabin split | A bar of economy, premium economy, business and first | Pro |
| Cabin by year | How the split changed over the years | Pro |
| Seats you have sat in | Count of distinct seats | Pro |
| Flights without a seat or cabin | How many flights have none. A hint that opens the edit screen, so the numbers get better | Free |

Seat parsing rule: trim, upper case, then split into a number of one to three digits and a letter. Anything that doesn't match (for example `JUMP`, or a seat with no row) counts for "most used seat" only, not for letter or row range. Write the parser once as a pure function with a shared test file for both apps (see "Parity and tests").

### 3.3 Aircraft and types

| Statistic | Rule | Tier |
|---|---|---|
| Most seen aircraft | The registration with the most check-ins (spotted and flown) | Free |
| Most seen type | The type with the most check-ins | Free |
| Top types | Ten most seen types with counts, as a bar chart | Pro |
| Flown types | Types you have flown, with the count of flights | Pro |
| Types flown and not yet spotted, spotted and not yet flown | Two lists from set differences. A nice "what's missing" view | Pro |
| New registrations per month | Registrations seen for the first time, by month | Pro |
| Manufacturers | Share of Airbus, Boeing, Embraer and so on, from the type's manufacturer | Pro |
| Country of registration | Share by prefix (D for Germany). Needs the prefix table, which the phone already has (see BADGES.md) | Pro |

### 3.4 Airports

| Statistic | Rule | Tier |
|---|---|---|
| Most visited airport | Airport with the most check-ins of any kind, with a flight counting for both ends | Free |
| Top airports | Ten airports with counts | Pro |
| Home airport guess | The airport with the most spotted and airport check-ins. Shown as "your home base" | Pro |
| Airports by kind | How many you spotted at, visited, flew from, flew to | Pro |
| Map | Visited airports as dots and flown routes as lines on a world map. Only shown if the map component exists on both apps | Pro |

### 3.5 Time

| Statistic | Rule | Tier |
|---|---|---|
| Year picker | All, or one year. Every number on the page follows it | Pro |
| Check-ins per month | Bar chart for the chosen year | Pro |
| Check-ins by weekday | Seven bars | Pro |
| Check-ins by hour of the day | 24 bars, in the phone's local time | Pro |
| Busiest day | The day with the most check-ins | Free |
| Longest streak | Most days in a row with at least one check-in, and the current streak | Free |
| Year in review | One card per year: check-ins, distance, new aircraft, new airports, top type, top seat. Can be shared as an image (see 5.3) | Pro |

Time zones: check-ins have a UTC moment. For weekday and hour use the phone's time zone, as the check-in lists do. A later improvement is the airport's local time, which the airport data can't give yet (see BADGES.md, "Local time").

### 3.6 Spotting

| Statistic | Rule | Tier |
|---|---|---|
| Sightings per session | Average spotted check-ins per day with at least one | Pro |
| Best spotting day | Day with the most distinct registrations | Pro |
| Visit contexts | Split of why you were at the airport (the `visitContext` field) | Pro |

## 4. Free and Pro

The concept says never to paywall check-ins, badges or the basic gallery, and that Pro adds depth rather than access (CONCEPT §13). So:

- **Free** keeps the profile card as it is, and gets a short "Highlights" page with the lines marked Free above: most used seat, most flown cabin, longest flight, most flown route, most seen aircraft and type, most visited airport, longest streak, busiest day. These are single facts, they are fun, and they show what Pro would add.
- **Pro** opens the full view: year filter, charts, top lists, lists of what is missing, year in review, share images.
- Below the free highlights, show the Pro sections as a locked preview: real chart shapes with the data blurred, and one line saying what is inside. Never show a fake number.
- The numbers are always worked out on the phone. Pro status comes from the entitlement endpoint (`/v1/me/entitlements`, CONCEPT §11.5), never from the local store receipt alone.
- Until Pro billing exists (it is open in TODO.md, Phase 2), ship the whole view unlocked to everyone, behind a single `isPro` check that is always true. That gives testers the feature, gives us feedback, and means the paywall is one switch later. Tell testers it will become a Pro feature, so nobody is surprised.

Open question for the owner: is the free highlights page what you want, or should the whole view be Pro with only a teaser? The plan above is the softer option and is better for growth.

## 5. Design

### 5.1 Where it lives

- A "More statistics" row under the stats card on the profile tab leads to the view.
- Top of the view: the year picker (a segmented control or menu: All, 2026, 2025 and so on, only years with check-ins).
- Then sections in this order: Highlights, Flights, Seat and cabin, Aircraft and types, Airports, Time.
- Each section is a card: a headline number, a small chart or list, and a "Show all" row for the long lists.
- Empty states: a section with no data says what check-in would fill it ("Check in a flight with a seat to see your favourite seat"). Never show zeros as if they were results.
- Units follow the distance setting (km, mi, nm) as the stats card does.

### 5.2 Charts

- iOS: Swift Charts (`import Charts`), available in the iOS versions the app supports.
- Android: Compose has no chart library in the dependencies. Prefer a small set of own composables (bar chart, horizontal bar list, stacked bar) drawn with Canvas, to avoid a dependency and keep both apps looking alike. Three shapes cover everything above.
- Both: accessible. Every chart has a text summary for VoiceOver and TalkBack, and bars have labels, so it never relies on colour alone.
- Colours: use the app's existing palette. One accent for the main series, grey for the rest.

### 5.3 Sharing

- "Year in review" and "Highlights" get a Share button that renders the card as an image with the app name on it. iOS uses `ImageRenderer`, Android draws the composable into a bitmap. Share sheet only; nothing is uploaded.
- The image shows no account name unless the user turns that on. Only own data, so no privacy question beyond the user's own choice to share.

## 6. Architecture

### 6.1 Compute

- A new pure type `ExtendedStats` next to `CheckInStats` (Swift package `Persistence` on iOS, `core` module on Android). Input: the counted check-ins, plus lookups for airports (coordinates, country, continent) and types (manufacturer). Output: plain values and arrays for the view.
- It takes the year as an optional parameter and filters first, so every number follows the picker.
- One pass over the check-ins collecting counters in dictionaries, then small sort steps for the top lists. Check-ins number in the hundreds or low thousands, so this is fast. Run it off the main thread and cache the result per year until the check-ins change.
- Reuse `CheckInStats.counted` so refused check-ins stay out, exactly as on the profile.
- Reference data (airport country and continent, type manufacturer) comes from the existing reference database, as the distance stat already does. If the reference data lacks continent, derive it from the country with a small table written once and shared by both apps.

### 6.2 Data

- No server change and no migration for the first version. Everything above comes from fields that are already in the local store.
- The seat is stored upper case and trimmed on the server; the local value may differ slightly, so the parser normalises again.
- Check-ins from friends are not part of this view: it is about your own logbook.

### 6.3 Parity and tests

- Rules that both apps must agree on live in one shared test file with fixtures (JSON), as the registration rules do: seat parsing, row ranges, streaks, either-direction routes, tie-breaking. Both apps load it and must give the same results.
- Unit tests per statistic: empty input, one check-in, ties, check-ins around midnight and a year change, refused check-ins, signed-out check-ins, flights whose airports are unknown.
- A fixture with a few years of generated check-ins checks the year filter and the time charts.
- UI check on a simulator and an emulator with a seeded local database, in light and dark mode, German and English, and at the largest text size.

### 6.4 Strings

- All titles, empty-state lines and chart summaries in English and German, in the string catalog on iOS and `strings.xml` on Android, like today. Cabin names reuse the existing cabin strings.

## 7. Delivery in steps

Each step is a PR on both platforms, small enough to ship to testers.

1. **Foundation.** `ExtendedStats` with flights, seat and cabin and the Highlights list, plus the view with the year picker and the free highlights. Shared fixtures. Unlocked for everyone. This is the part the owner described.
2. **Aircraft, types and airports.** The top lists and "flown but not spotted" lists. Needs the manufacturer and country lookups.
3. **Time.** Month, weekday and hour charts, streaks, best days. Own chart composables on Android.
4. **Year in review and sharing.** The card and the share image.
5. **Pro gate.** After Pro billing exists: the entitlement check, the locked previews and the paywall. Until then nothing changes for users.
6. **Map.** Only when a map component exists on both apps.

Estimate: steps 1 to 3 are each about the size of the "distance flown" plus "recent suggestions" work together; step 4 is smaller; the gate depends on the billing work in TODO.md.

## 8. Later: data that would add more

| Idea | What it needs |
|---|---|
| Window, middle or aisle | A seat layout per aircraft type. Could come from an open data set or be entered for the most common types. Wrong guesses would look bad, so only show it for types with a known layout |
| Airline statistics (most flown airline, alliances) | An airline field on flown check-ins and the operator import (see BADGES.md, "What the server needs") |
| Time in the air | Flight duration. Estimate from distance (distance divided by 800 km/h plus 30 minutes), clearly marked as an estimate, or take it from a flight lookup if that ships |
| Delays and punctuality | Flight lookup data. Out of scope |
| CO2 estimate | A per-distance factor. Sensitive: it can look like a guilt tool in a hobby app, and the numbers are contested. Leave out unless testers ask |
| Compare with friends | Needs friends' check-ins, which are private by default. Would be opt-in and server-side |

## 9. Risks

- **Too few data points.** Most statistics need seat, cabin or route, which users often skip. Mitigation: the empty states and the "flights without a seat or cabin" hint push users to fill them in, and the check-in edit screens already allow it later.
- **Looking wrong.** A statistic based on a few guesses (row range, home airport) can be wrong. Label guesses as such, and keep them in Pro, where the user has the context.
- **Two apps drift.** The shared fixtures and the same step order on both platforms prevent it.
- **Paywall backlash.** The free highlights and the rule never to hide check-ins or badges keep the free app complete. Testers get everything until billing exists.
- **Performance.** Not expected with the sizes involved; measured with a generated store of 10 000 check-ins before step 3 ships.

## 10. Decisions for the owner

1. Free highlights plus Pro depth (this plan), or everything Pro with a teaser?
2. Ship step 1 unlocked to testers first (recommended), so it can be judged before billing exists?
3. Which statistics matter most? The list is long; steps 1 to 3 can be cut to what you like best.
4. Should "most flown route" count both directions as one (recommended)?
5. Is a share image for the year in review wanted, or later?
