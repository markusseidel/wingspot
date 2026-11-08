# Milestone 11: Entdecken (Explore tab) (plan)

Done when: the Explore tab (German: "Entdecken") is no longer a placeholder. You can search people, airports and aircraft types in one place, see airports near you and busy airports, and open pages for an airport, a type and a registration that show what you and others you may see have checked in.

Everything respects the access rules already in place: a check-in shows only to people allowed to see it (own, friends, public with the author's delay and private profile, nothing when blocked), and a sensitive aircraft's registration is never shown to others.

## What exists

- Airport page (8e): code, name, map, your visits, 30-day counts, recent check-ins.
- `get_airport_checkins` and `get_airport_activity` on the server; the feed card and `FeedStore` already take a scope (feed, person, airport).
- On the phone: airport and aircraft-type search (`searchAirports`, `searchTypes`), people search, location for the check-in suggestion.
- The tab itself is a placeholder text.

## 11a. Search and nearby (app only, no migration)

- One search field. Results in groups: **People** (existing search), **Airports** (local data, opens the airport page), **Aircraft types** (local data; opens the type page once 11c exists, until then the type is shown with your own count).
- Without text: **Airports near you**, sorted by distance from your location (asks for location once, in context; works offline), each opening the airport page. Without location permission: a short hint and the home airport if set.
- Needs the airport data on the phone; says so if it is missing, as the map does.

## 11b. Busy airports (needs a migration)

- `get_active_airports(days, limit)`: the airports with the most check-ins in the last days among check-ins the caller may see, with counts. Runs as the caller. A sensitive aircraft of someone else is not counted.
- Shown on the Explore tab as "Busy this week" and as markers on the Explore map (11e).

## 11c. Aircraft type page (needs a migration)

- `get_type_checkins(type_icao, ...)` and `get_type_activity(type_icao)`, built like the airport ones: recent visible check-ins of this type, and counts for 30 days (check-ins, airports, most active people).
- Page: type name and code, your own sightings (count, first and last time), the counts, recent check-ins with the feed's cards. Opens from search, Collections (types) and a feed card.

## 11d. Registration page (needs a migration)

- Search accepts a registration such as D-AIPC. `get_registration_checkins(registration, ...)` returns the visible check-ins of that aircraft. A sensitive aircraft is neither found nor shown to anyone but its owner, and a registration nobody may see gives the same answer as one that doesn't exist.
- Page: registration, type, your sightings, recent check-ins.

## 11e. Map

- A map on the Explore tab with the busy airports (11b) and your own airports; tapping a marker opens the airport page.

## Left out for now (need data or decisions)

- Trending or rare aircraft (needs rarity data), airline search (operator data is not on the phone), leaderboards, "What's overhead?" and ADS-B (provider and licence), spotting locations.

## Tests and release

- Database tests per access case (self, friend, stranger, blocked, sensitive aircraft) for each new function; API tests; Account package tests for the new store and backend calls; strings in English and German.
- Each step is its own pull request. Migrations are deployed only after you say so.
