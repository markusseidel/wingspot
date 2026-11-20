# Social features plan

Seven features, one pull request each, one build at the end. Every PR carries backend, iOS and Android together, so the
apps never differ. Idea list and picks come from the owner's request of 2026-11-20.

## What already exists (so we don't build it twice)

- `notifications` is an outbox with push for iOS and Android. Kinds today: `follow`, `salute`, `comment`, plus tag
  notifications (migration `20261120500000_tag_notifications.sql`). Settings and per-person alert rules exist.
  There is **no screen that lists them**.
- Friend tags are done, including "add a friend's flight to my logbook" (`checkins.source_checkin_id`,
  `20261120600000_tag_copies_and_wingman.sql`). Feature 6 is therefore a polish job, not new ground.
- Profile images, levels, earned badges on friend profiles, badges on feed cards.
- Private profiles, block, report, word filter on comments.
- The Android manifest only knows the `wingspot://auth-callback` link. There are **no web links** into the app yet.

## Order of work

The numbers are the owner's list. The order follows what each one needs from the others.

| Step | Feature | Why here |
| --- | --- | --- |
| 1 | **7 Activity inbox** | Every later feature adds a notification kind. Build the screen once, first. |
| 2 | **5 Mentions and comment replies** | Uses the inbox. Small server change. |
| 3 | **6 Shared flights, polish** | Small. Uses the inbox for "Anna added your flight". |
| 4 | **3 Compare with a friend** | New read-only functions, reused by the leaderboard. |
| 5 | **4 Friends leaderboard** | Builds on the numbers from step 4. |
| 6 | **1 Invite friends** | Needs the one decision on web links (see "Decisions"). |
| 7 | **2 Share card** | Last, so it can show the leaderboard rank and badges that now exist. |

Each PR is merged when CI is green. Production gets all migrations once, at the end, and only on the owner's word.
Then one Android beta and one iOS build (`YYYYMMDDB`).

## 7. Activity inbox

**What:** a bell on the feed screen with an unread dot. The screen lists, newest first: new followers, salutes,
comments, mentions, replies, tags, "added your flight", friends' badges. A tap opens the check-in or the person.
Opening the screen marks nothing read; a "Mark all read" button does.

**Server**
- `notifications` gets `read_at timestamptz`. The inbox reads the caller's own rows (RLS already restricts to the
  recipient) through `get_notifications(before timestamptz, lim int)`, which joins the actor's name, the check-in title
  and the snippet, and drops rows from people the caller has since blocked.
- `mark_notifications_read()` sets `read_at` for the caller. `unread_notification_count()` for the dot.
- The push sender already reads `notifications`; a row that is read before it is sent is skipped.
- The `kind` check constraint is widened once, with every kind the later steps need (`mention`, `reply`,
  `tag_copy`, `friend_badge`), so later PRs do not touch it again.
- Every event is stored, also for people without a phone or with a kind switched off (`silent` rows, never pushed).
- Retention: rows older than 90 days are deleted by the existing cleanup job.

**Apps:** bell in the feed header, list screen, empty state, badge count on the app icon stays as it is.

**Tests:** pgTAP for visibility (only own rows, blocked actors hidden, read marks), API test for the three functions.

## 5. Mentions and comment replies

**What:** type `@` in a comment and pick a friend from the strip above the keyboard (the same friends the "With" list
offers). The name becomes a link to their profile and sends a `mention` notification. **Reply** under a comment puts
`@username ` at the start of the composer, so a reply is simply a mention of the person it answers (no separate
`reply` kind). A comment can be saluted like a check-in; its author gets a `comment_like` notification.

**Server** (`20261121300000_comment_mentions_and_salutes.sql`)
- `comment_mentions` is filled by a trigger that reads `@username` (lowercase letters, digits, underscore). Only mutual
  friends of the author who may see the check-in are kept, at most 5; anyone else is dropped silently.
- `comment_salutes` and `set_comment_salute(comment, on)`. `get_comment_extras(checkin)` returns salutes, whether the
  caller saluted, and the mentions of each comment in one call.
- Neither table has a foreign key to `profiles`. With one, PostgREST finds a second path from comments to profiles and
  the `comments?select=...,profiles(username)` read of every installed app fails (PGRST201). An API test guards this.
- Push texts for both kinds in English and German.

**Apps:** suggestions strip, mentions in the accent colour as links (tap opens the person), Reply and salute under
each comment, both kinds in the inbox.

**Privacy:** a mention never reveals a check-in the person could not see.

## 6. Shared flights, polish

**What exists:** "Add to my logbook" from a tagged check-in, and the "In your logbook" state of its button.

**What was added** (`20261121400000_tag_copy_notifications.sql`)
- The author gets a `tag_copy` notification when a tagged friend adds their flight or visit ("Max added your flight
  FRA → JFK to their logbook"), with push texts in English and German and the switch for being tagged.
- On the author's check-in page an "In their logbook" list names the friends who did (`get_checkin_copies`, only for the
  author, blocked people left out).

## 3. Compare with a friend

**What:** on a friend's profile, a "Compare" row opens a page with you and them side by side: total flights, distance,
countries, airports, airlines, aircraft types. Below it three lists: **in common**, **only you**, **only them** (airports
and countries first, others behind "show more"). Same page works for mutual friends whose profile you may see.

**Server:** `compare_with(target uuid)` returns the counts and the id lists, computed from the two users' visible
check-ins only (it follows `private.can_view_profile_content`, like `get_person_progress`). Returns null when the
profile is not visible. **Hidden badges are never part of the result.** Done in SQL, no client-side joins.

**Apps:** a new page reached from the profile card; a horizontal bar per number; the lists in expandable sections.

**As built** (`20261121500000_compare_with_friend.sql`): `compare_with` returns both sides' flights, distance, countries,
airports, airlines and aircraft types, and for each of the last four what is in common, only yours and only theirs.
The apps show it from a "Compare with you" button on the friend's profile.

**Keep in mind:** these per-user number queries are the same ones the extended statistics view needs. Put them in
shared SQL functions (`private.user_stat_counts`), so docs/EXTENDED-STATS.md and the leaderboard reuse them.

## 4. Friends leaderboard

**What:** a "Leaderboard" tab inside People: you and the people you follow, ranked by distance, countries or airports,
for this year or all time. Opt-in: a switch "Show me on friends' leaderboards" in Settings, **off by default**. Nobody
appears in someone else's board without it. Private profiles never appear unless the viewer follows them and the
switch is on.

**Server:** `profiles.show_on_leaderboard boolean default false`. `get_leaderboard(metric text, period text)` returns
only the caller plus people they follow who opted in, capped at 50 rows, reusing `private.user_stat_counts`. Yearly
numbers use the check-in's flight date, not its created date.

**Apps:** segmented controls for metric and period, rows with avatar, rank and value, your row highlighted. A short
first-time explanation when the switch is off.

**As built** (`20261121600000_friends_leaderboard.sql`): `get_leaderboard(metric, period)` with distance, flights, countries or
airports, this year or all time, at most 50 rows. The switch is `profiles.show_on_leaderboard`. iOS reaches it from
People, Android from the Profile tab; both have the switch on the screen itself.

**Tests:** pgTAP that opted-out people, blocked people and non-followed people never appear.

## 1. Invite friends

**What:** "Invite friends" in Profile and People: a share sheet with a personal link and a QR code. Opening the link
installs or opens the app and offers to follow the inviter. Also a "People you may know" list: people followed by
three or more of the people you follow, plus people who were tagged on a flight with you and have no link to you yet.

**Server**
- `profiles.invite_code text unique` (8 characters, generated once, can be reset in Settings).
- `follow_by_code(code)` follows the inviter (or sends a request for a private profile) and notifies them
  (`follow`). No code, no invite is stored for people who never signed up.
- `people_you_may_know(lim)` only returns people who allow it (`allow_suggestions`, default true, in Settings) and are
  not blocked.

**Apps:** share sheet with text, link and a QR image; Android and iOS handle the link (see decision 1); a landing
card "Anna invited you" after sign-in.

## 1b. How invite links were built (no web domain yet)

Decision 1 (a web domain) is still open, so the link is `wingspot://invite/CODE`, which opens the app on a phone that has
it. The invite screen also shows the code and a QR code of that link, and a friend can type the code in. The share text
carries the code and the link. When there is a domain, only the link text changes. Migration `20261121700000_invite_friends.sql`:
`get_my_invite_code`, `reset_my_invite_code`, `invite_owner`, `follow_by_code`, `people_you_may_know`, and
`profiles.allow_suggestions`. The codes are never readable through the table.

## 2. Share card

**What:** a "Share" button on a check-in, a badge and a level-up. It renders a nice image (route line or map,
airline and airport codes, distance, avatar, "Wingspot" mark) and opens the system share sheet.

**How:** the image is drawn on the phone (SwiftUI `ImageRenderer`, Compose `GraphicsLayer`/Bitmap), so no server
cost and nothing leaves the phone except what the person shares. Three templates now (flight, badge, level) and a
fourth one added for the year in review later, so the card view takes a model with title, big number, caption and
accent, not flight specifics.

**Privacy:** only offered for check-ins the person owns. Hidden badges can not be shared before they are earned and
never show their rule text. The card carries the invite link from step 1.

## Decisions for the owner

1. **Web links.** The invite link and share cards need an address. Options: (a) a small page on a domain you own
   with universal links (iOS) and app links (Android), best result and needs one static file and a DNS entry;
   (b) the `wingspot://` link only, which works in the apps but not in WhatsApp previews or for people without the
   app. Recommended: **(a)**. Until you decide, step 6 is built with (b) and the code path for (a) stubbed.
2. **Leaderboard default.** Off by default as planned, or on for everyone who is already public?
3. **Mention reach.** Mutual friends only (recommended) or anyone who can see the check-in.

## Parity, privacy, release rules

- Same change on iOS and Android in each PR, same texts in English and German, same look.
- No hidden badge names, rules or texts in code, tests, docs, PR text or tester texts.
- Every new function that returns other people's data follows `can_view_profile_content` and the block rules, and is
  added to the list in `access_test.sql`.
- Each PR runs pgTAP, API tests, Swift tests and Android tests, and gets simulator and emulator screenshots first.
- Migrations are pushed to production once at the end, only on the owner's word. One iOS build and one Android beta
  after that, with a tester text.

## Other ideas, kept in mind (not part of this plan)

| Idea | What this plan already prepares |
| --- | --- |
| Year in review | Shared stat functions (step 4), the generic share card (step 2). |
| CO2 estimate | Same stat functions can sum an estimate later; shown as a number on the card. |
| Trips | Compare and share card take a list of check-ins, so a trip is a later grouping. |
| Wishlist | Compare's "only them" lists are the natural source of "airports to visit". |
| Public profile page | The web link in decision 1 is the same domain. |
| Friends map | Needs the leaderboard opt-in as a template for a separate privacy switch. |
