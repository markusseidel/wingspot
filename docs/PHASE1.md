# Phase 1 plan: iOS MVP to first TestFlight

This is the working plan for Phase 1 in concept §14. Where it differs from the concept, this file wins until the concept is updated. Open items are tracked in [TODO.md](TODO.md).

## Milestones

Each milestone is its own pull request with tests. Hosted only changes when a deploy is approved.

| # | Build | Done when |
|---|---|---|
| 1 | **Offline Spotted check-in:** reference database on the device, type and airport search, local saving, result screen | You can log a plane in airplane mode and see "First time seeing D-AIMA" |
| 2 | **Sign-in and profile:** email link and Apple, onboarding, home airport | A new user can sign up and edit their profile |
| 3 | **Sync:** `POST /v1/checkins`, offline outbox, retries that can't create duplicates | A check-in made offline reaches the server exactly once |
| 4 | **Badges and XP:** rule engine, about 40 badges, levels, celebration screen | A check-in unlocks the right badge, confirmed by tests |
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

## Before each milestone

| Before | Needed |
|---|---|
| Milestone 2 | Apple Developer Program membership |
| Milestone 2 | Final app ID. It's `app.wingspot.ios` today, and `site.wingspot.ios` is suggested. It can't be changed once the app is in App Store Connect |
| Milestone 9 | Custom email sending, so sign-up emails reach testers |
| Milestone 9 | Leaked password protection turned on in Supabase |
| Milestone 9 | Privacy policy and Impressum on `wingspot.site` |
| Milestone 9 | A decision on aircraft types if ICAO hasn't answered, because hosted has only 22 |
