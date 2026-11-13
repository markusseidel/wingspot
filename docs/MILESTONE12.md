# Milestone 12: Check-in page and alerts for people you follow (plan)

Done when: tapping a check-in of someone you follow opens a page about that check-in, not their profile. On a person's profile you can choose which of their check-ins (spotted, flown, airport visits) send you a push notification.

Everything respects the access rules already in place: a check-in shows, and notifies, only if the person may see it (own, friends, public with the author's delay and private profile, nothing when blocked).

## What exists

- Feed card (`FeedCard`): the name opens the profile. The title opens the registration, type or airport page, but a flight's title opens nothing. The rest of the card does nothing. Comments are a separate screen (`CommentsView`).
- A push for a comment or salute opens that comment screen (`PushRouter.checkIn`), or the Feed if the check-in is not in the list.
- Push: the `notifications` outbox, `queue_notification` (blocked users, per-kind switch, 30 a day, no repeats within an hour), `send-push` with English and German text, `notification_prefs` (salutes, comments, new followers).
- Access: `can_view_checkin_row` works for the signed-in caller (`auth.uid()`), so a trigger can't use it as it is.

## 12a. Check-in page (app only first)

Tapping a card, anywhere except its buttons and links, opens the page. The name still opens the profile, and it looks like a link on the page too.

The page shows:
- Who, and when: the author (opens the profile), the date and time.
- What: for a flight, the route as a big title with both airports (each opens its airport page), flight number, distance, aircraft registration and type. For a spotted aircraft, the registration (opens the registration page), the type (opens the type page) and the airport. For an airport visit, the airport and why they were there.
- Photos: larger than in the feed, with the existing tap-to-enlarge.
- Salute and comments on the same page, so the separate comments screen goes away.
- Your own flights: Edit details (the sheet from build 17) and the Flightradar24 links. Someone else's: Report.
- Opens from the Feed, a person's page, and the airport, type and registration pages, because they all use `FeedCard`.

No server change needed for this: the page uses the `FeedItem` the card already has.

## 12b. One check-in by id (needs a migration)

- `get_checkin(id)`: runs as the caller and returns the same shape as a feed row, plus cabin and seat (only for your own check-ins unless you decide otherwise, see questions), the airport IDs of a flight, and its photos. Nothing for a check-in the caller may not see, and the same answer as for one that doesn't exist.
- A push tap opens the page even when the check-in isn't in the Feed list, which today only works after the Feed reloads.
- Comment and salute pushes open the page instead of the comments screen.

## 12c. Alert rules on the server (needs a migration)

- Table `notification_rules`: watcher, target person, one switch each for spotted, flown and airport visits, created time. One row per pair. Row-level security: you read and write only your own rows. Removing a follow or blocking someone deletes the row; deleting an account removes it. The data export includes your rules.
- A trigger on new check-ins: for each rule of the author, if the watcher follows the author, may see the check-in right now (a variant of `can_view_checkin_row` that takes the viewer as a parameter), and the switch for that kind is on, queue a notification of a new kind `checkin`.
- Not sent for: edits (the trigger runs on insert only, so correcting a flight tells nobody), check-ins older than a day (an old flight added later), and the two airport visits that a flight creates (only the flight is announced).
- Existing limits stay: not yourself, not blocked, 30 a day, an iPhone registered. A new switch in `notification_prefs` turns all of these alerts off at once.
- `send-push` text, English and German, with the person's name: "Anna flew FRA → JFK", "Anna spotted D-AIMA (Airbus A380)", "Anna checked in at FRA". A tap opens the page from 12a.
- Tests for each access case (friend, follower of a public profile, stranger, blocked, private profile, delayed check-in), API tests, and the contract file.

## 12d. Alert rules in the app

- On a profile you follow: a section "Notify me" with three switches (Spotted, Flown, Airport visits). A change saves at once. The first switch you turn on asks for push permission if it hasn't been asked, with the existing explanation. If notifications are off in iOS, the section says so and links to Settings.
- Settings: "People you get alerts from" lists your rules and lets you turn them off, so no alert needs a trip to each profile.
- The other person is not told that you get alerts, and can't see the list. This goes into the privacy text.
- Strings in English and German, tests in the Account package.

## Decisions

1. **No filters.** A rule is three switches for the kind of check-in (spotted, flown, airport visits). Filters by type, registration or airline are left out.
2. **Everyone you follow** whose check-ins you may see, not only friends.
3. **Delayed public check-ins** send no alert in this version.
4. **Cabin and seat** stay private, shown only on your own check-ins.

## Order and release

- 12a, then 12b, 12c and 12d. Each is its own pull request; 12a needs no deploy.
- Migrations and the `send-push` function are deployed only after you say so. The iOS build comes after both.
- Android follows later, like the other social screens.
