# Phase 1 plan: iOS MVP to first TestFlight

This is the working plan for Phase 1 in concept §14. Where it differs from the concept, this file wins until the concept is updated. Open items are tracked in [TODO.md](TODO.md).

## Milestones

Each milestone is its own pull request with tests. Hosted only changes when a deploy is approved. From Milestone 2 on, all new text ships in German and English.

| # | Build | Done when |
|---|---|---|
| 1 | **Offline Spotted check-in:** reference database on the device, type and airport search, local saving, result screen | You can log a plane in airplane mode and see "First time seeing D-AIMA" |
| 2 | **Languages, sign-in and profile:** string catalog with Milestone 1's text in German, then email link and Apple, onboarding, home airport | A new user can sign up and edit their profile, in German and in English |
| 3 | **Sync:** `POST /v1/checkins`, offline outbox, retries that can't create duplicates | A check-in made offline reaches the server exactly once |
| 4 | **Badges and XP:** badge text stored by language, rule engine, about 40 badges, levels, celebration screen | A check-in unlocks the right badge, confirmed by tests, and its name appears in the phone's language |
| 5 | **Other check-ins:** Airport, Flown, boarding pass scan, one photo | All three types sync, and passenger name and booking code never leave the device |
| 6 | **Your profile:** stats, collection lists, badges tab, airports map | Your stats match your check-ins |
| 7 | **Social:** follow, feed, salutes, comments, report, block | Two test accounts can interact, and block and privacy rules hold |
| 8 | **Airport page and settings:** public activity, privacy controls, account deletion, data export | Deleting an account removes that user's data |
| 9 | **Release:** deploy to hosted, crash reporting, TestFlight build | Friends can install it and use it for real |

## Decisions

1. **Registrations:** a user's type and airline stay on their own check-in, and the shared `aircraft` row holds only the registration. One user's typo can't affect anyone else's badges. Sharing by agreement can come later.
2. **Sign-in:** Apple and email only at first. Google waits until after the first TestFlight.
3. **Photos:** the phone converts to JPEG and removes location data before upload, and originals aren't stored.
4. **Badge progress:** offline, the result screen shows only first-seen and seen-count info from local data, and badges appear after sync. Predicted progress waits until Android needs the shared test files.
5. **Moderation:** the project owner reviews reports directly in the database at launch.
6. **Left for later:** push notifications, universal links, weekly data updates (full snapshot downloads instead) and full airport outlines for location checks (a simple radius for now).
7. **Creating aircraft:** `POST /v1/checkins` creates missing `aircraft` rows. `GET /v1/aircraft/lookup` only reads.
8. **Languages:** German and English from the first TestFlight, following the phone's language, with English as the fallback (concept §11.5). Airport names, aircraft names and user content aren't translated.
9. **Signing in is optional:** check-ins work without an account and offline, so onboarding offers "Not now". Local check-ins stay on the device when the user signs out.
10. **Sync rules (milestone 3):**
    - Upload is `POST /v1/checkins`, up to 50 at a time, idempotent by the id the phone generated. If a response is lost, the retry hears `stored` again and nothing is duplicated.
    - Each item is judged alone. Only the server's answer for an item can reject it: it is then marked `rejected` on the phone, stays there, and is never sent again. The answer carries a code, such as `unknown_type`.
    - Any failed request leaves everything waiting, whatever the reason: no network, a server error, a missing endpoint before a deploy, or an expired token. It is tried again with growing pauses (5 s, 30 s, 2 min, 10 min), and again when the app comes to the foreground, after sign-in and when the network returns.
    - Check-ins made while signed out belong to whoever signs in next. Check-ins made while signed in belong to that account, and another account never uploads them.
    - Uploaded check-ins are `private` until privacy settings exist (milestone 8). Raw location is stored but never shown to others.
    - Hosted has only 22 aircraft types until ICAO answers, so a check-in with another type is rejected as `unknown_type`.
11. **Badges and XP (milestone 4):**
    - Badges are rows with a rule, levels and text in German and English. The server works out every badge after an upload and from `GET /v1/me/progress`. Levels never go down.
    - XP is recalculated from the data each time (10 per check-in, 15 per new registration, 30 per new type, 40 per new airport, and 50 times the level for each badge level), so repeating it never counts twice. Level L starts at 50 × L × (L − 1) XP.
    - A broken badge rule never fails an upload. The check-ins are stored and the answer has no badge data.
    - The app celebrates the difference between what the server says is unlocked and what it has already shown. The upload answer is only a fast path, because it can be lost.
    - "Local time" is estimated from the airport's longitude, because the airport data has no time zones.
12. **Airport check-ins (milestone 5):**
    - An airport check-in needs an airport and carries a reason (spotting, departing, arriving, transit, working, museum or airshow). Aircraft fields are ignored.
    - The server rejects one without an airport as `missing_airport`, and an unknown reason as `invalid_context`.
    - Every check-in counts for badges and XP, so an airport visit counts towards the airport badges, streaks and the 10 XP per check-in.
    - "First time at this airport" looks at earlier check-ins of any kind at that airport.
13. **Flown check-ins (milestone 5):**
    - A flight needs two different airports and a date. Flight number, aircraft (registration or type), cabin and seat are optional. The flight date is `occurred_at`: today keeps the real time, any other day is midday.
    - The server works out `distance_km` from the two airports and tidies the flight number and seat. Bad input is rejected as `missing_route`, `invalid_route`, `invalid_flight_number`, `invalid_cabin` or `invalid_seat`.
    - A flight counts like any check-in for XP and for the aircraft badges if it has an aircraft. Its airports don't count for the airport badges yet.

## Before each milestone

| Before | Needed |
|---|---|
| Milestone 2 | Sign in with Apple switched on in Supabase, with `site.wingspot.ios` as Client ID. The iPhone app needs no Services ID or key |
| Milestone 9 | Custom email sending, so sign-up emails reach testers, in German and English |
| Milestone 9 | Leaked password protection turned on in Supabase |
| Milestone 9 | Privacy policy and Impressum on `wingspot.site`, in German and English |
| Milestone 9 | A decision on aircraft types if ICAO hasn't answered, because hosted has only 22 |
