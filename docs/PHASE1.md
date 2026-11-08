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
14. **Boarding pass scan (milestone 5):**
    - The Flown screen can read a boarding pass with the camera or from a picture. It fills in the route, date, flight number and seat. The cabin stays as it is, because the booking class letter means different things at different airlines.
    - Reading happens on the device. The barcode text goes only to the parser, which skips the passenger name and booking code, so neither is stored or uploaded. Nothing from the pass is sent except what the user saves in the form.
    - A pass with several flights asks which one. Airports are matched by IATA code in the downloaded data.
15. **Photos (milestone 5):**
    - One photo can be added to a Spotted, Airport or Flown check-in. It is chosen from the photo library, because spotters shoot with real cameras. Airport and Flown check-ins take one photo the same way.
    - The phone shrinks it to 2048 pixels on the long side, turns it upright, and writes a new JPEG with **no metadata**: the location, camera and date of the original are not carried over, and the original is not kept. It is saved on the device with the check-in.
    - The photo goes up only after its check-in is stored, to a private bucket (`photos/{user}/{check-in}/{photo}.jpg`) through `PUT /v1/checkins/{id}/photos/{id}`. The server refuses a JPEG with EXIF, XMP or other metadata segments, files over 3 MB, and a fifth photo on a check-in. Only the owner can read it until sharing exists (milestone 7).
    - A failed request leaves the photo waiting. Only the server's answer can reject it, as with check-ins.
16. **Sharing, feed and reports (milestone 7a):**
    - Each account has a sharing choice (`default_visibility`: only me, friends or everyone), which starts as **only me**. A check-in the app sends without a visibility gets it. `set_sharing` changes the choice and can apply it to all earlier check-ins.
    - `get_feed` returns the caller's own check-ins and those of people they follow, newest first, with salute and comment counts. It runs as the caller, so visibility, private profiles, blocks and the post delay decide what shows, and the counts follow the same rules. Paging uses the last row's time and id. The registration of a sensitive aircraft is hidden from other people. Raw location is never returned.
    - `report` stores a report of a user, check-in, comment or photo after checking the caller can see it. Reports can't be read by users, so the project owner reviews them in the database. It allows 20 reports an hour, and a repeat of an open report adds nothing.
    - A word filter refuses comments with a blocked word (whole words, any case). Words live in `private.blocked_words`, and the owner can add more with plain SQL.
    - These are database functions called directly (like `get_profile`), so they aren't in `openapi.yaml`.
17. **People (milestone 7b):**
    - Search finds usernames that contain the typed text (at least two letters). Following is instant. A block ends the follows between the two and hides their profiles from each other, so `get_blocks` is how the app lists and undoes blocks.
    - The profile has a "Share my check-ins" setting (only me, friends, everyone) that asks whether to change earlier check-ins too. It needs a network. A person's page shows their name and relation, with follow and block. Their check-ins come with the feed (7c).
18. **Feed tab (milestone 7c):**
    - The tab shows `get_feed`: your own check-ins and those of people you follow, newest first, 30 at a time, loading older ones near the end of the list. Pull to refresh. It needs a network and keeps the old list when a refresh fails.
    - Paging sends back the time exactly as the server sent it, because rounding it would skip or repeat check-ins.
    - A card shows who, when, the kind, the registration or route, details and the salute and comment counts. Tapping a name opens that person's page. Salutes and comments themselves come in 7d. Photos come in 7f.
19. **Salutes and comments (milestone 7d):**
    - The salute button on a feed card changes at once and goes back if the request fails. Salutes and comments are written straight to their tables, where the database rules check that the person may see the check-in.
    - The comments screen lists comments oldest first with the author's name, takes new ones (1 to 2000 characters), and lets you delete your own, or any comment under your own check-in, by swiping. A comment the word filter refuses shows a message and stays in the field. The count on the card follows the screen.
20. **Reports and community rules (milestone 7e):**
    - Reports go through the server's `report` function, for a person (profile page), a check-in (menu on a feed card) and a comment (swipe). Reasons: spam, offensive, private information, other, plus optional details. You can't report your own content. Photo reports come with 7f.
    - Before the feed, People, or sharing with anyone but yourself, a screen with the community rules asks for agreement once per account and rules version. The agreement is kept on the device for now; raise `TermsStore.currentVersion` to ask everyone again. A server-side record can be added later if proof of agreement is needed.
    - The full terms of use for `wingspot.site` are drafted in [TERMS-DRAFT.md](TERMS-DRAFT.md).
21. **Photos in the feed (milestone 7f):**
    - A photo can be seen by whoever can see its check-in (same rules as before: yourself, friends, public, blocks respected). Photos of sensitive aircraft stay with their owner, because a photo can show the registration. The photo bucket stays private; the app asks storage for a signed link (valid for an hour) for each photo it may read, and a refresh signs again.
    - The feed loads the cards first and the photos after; if the photos fail, the cards stay as they are. A card shows up to four photos in a strip. Press and hold a photo of someone else to report it.
    - Photos on a person's page and tapping a photo to enlarge it are not part of this step.
22. **Account deletion (milestone 8a):**
    - Profile has "Delete account", with two confirmations. `DELETE /v1/me` removes the person's photo files (the whole folder, not just registered photos) and then the auth user; the database removes everything else by cascade. It is immediate, with no grace period, and safe to repeat after a failure. Reports the person filed stay, without their name.
    - The app then signs out and removes that account's check-ins, photos waiting for upload and badge records from the phone. Check-ins made while signed out stay.
    - Plan for the rest of the milestone: [MILESTONE8.md](MILESTONE8.md).
23. **Data export (milestone 8b):**
    - The database function `export_my_data()` returns one JSON document of the caller's own rows: profile, notification settings, check-ins (with registration, airport codes and the position as latitude and longitude), the photo list, comments written, salutes given, who they follow and who follows them, blocked usernames, badges, reports filed, devices and entitlements. It never includes push tokens, storage paths or anything written by other people. Photo files are not included.
    - The profile has "Export my data": the app pretty-prints the document into a temporary file, opens the share sheet, and deletes the file afterwards.
24. **Settings (milestone 8c):**
    - Profile has a "Settings" screen with: who sees new check-ins (the setting from Milestone 7), a private profile switch, a delay for public check-ins (none, 1, 6 or 24 hours), and the distance unit (kilometres, nautical miles or miles).
    - The server already let an account change its own `is_private` and `post_delay_minutes`, so no migration was needed; a database test now covers what they do. A private profile hides its public check-ins from strangers, and the delay holds public check-ins back from strangers while friends and the owner see them at once.
    - The distance unit is kept on the phone only. Distances are stored in kilometres and shown in the chosen unit in the feed and after a flight check-in.
25. **Check-ins on a person's page (milestone 8d):**
    - The database function `get_person_checkins(target, before_time, before_id, page_size)` returns one person's check-ins in the same shape as the feed, with the same rules: it runs as the caller, so own, friends-only, public (with the author's delay and private profile) and blocked are decided by the check-in rules, and the registration of a sensitive aircraft is hidden from others.
    - A person's page shows those check-ins with the feed's cards (salute, comment, report, photos) and paging. A private profile you aren't a friend of says so.
26. **Airport page (milestone 8e):**
    - Two database functions, both running as the caller so the check-in rules decide what counts: `get_airport_checkins(airport, before_time, before_id, page_size)` lists the visits and spotted aircraft at an airport in the feed's shape (flights are left out), and `get_airport_activity(airport)` gives the check-ins and different aircraft of the last 30 days and the three most active people. A sensitive aircraft of someone else is neither shown nor counted.
    - The page shows the airport (code, name, city, small map), your own check-ins there, the counts, and the recent check-ins with the feed's cards. It opens from the airports list in Collections, a marker on the airports map, and the airport title of an airport check-in card. Country, spotting locations, leaderboards and "rare today" are left for Phase 2; opening it from the check-in result screen is not done yet.
    - Feed items now carry the airport's ID.
27. **Push notifications, server side (milestone 10b):**
    - Follows, salutes and comments add a row to an outbox (`notifications`) unless the actor is the recipient, either has blocked the other, the recipient switched that kind off, no iPhone is registered, the recipient already got 30 in 24 hours, or the same thing happened within the hour (comments always count).
    - The Edge function `send-push` is called by the database (a call per new row and a job every minute) with a shared secret, never by the app. It writes German or English from the device's language, sends through Apple's push service with the key stored as server secrets, removes tokens Apple says are dead, and retries a failed send up to 5 times within a day. Without the key it does nothing and rows wait.
    - Texts hold the actor's name and a short snippet only. Several salutes on one check-in replace each other on the phone.

## Before each milestone

| Before | Needed |
|---|---|
| Milestone 2 | Sign in with Apple switched on in Supabase, with `site.wingspot.ios` as Client ID. The iPhone app needs no Services ID or key |
| Milestone 9 | Custom email sending, so sign-up emails reach testers, in German and English |
| Milestone 9 | Leaked password protection turned on in Supabase |
| Milestone 9 | Privacy policy and Impressum on `wingspot.site`, in German and English |
| Milestone 9 | A decision on aircraft types if ICAO hasn't answered, because hosted has only 22 |
