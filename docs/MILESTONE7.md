# Milestone 7: social (plan)

Done when: two test accounts can follow each other, see each other's check-ins in the feed, salute and comment, and report and block, and the block and privacy rules hold ([PHASE1.md](PHASE1.md)).

## What already exists

The database has the social tables and the access rules since the first migration: `follows`, `salutes`, `comments`, `reports`, `blocks`, with row level security. The helper functions `is_blocked`, `are_friends` and `can_view_checkin_row` decide who sees what (visibility `private`, `friends` or `public`, the author's private profile, and the post delay). Blocking removes follows in both directions. `reports` has no client access, so reports must go through a function.

What is missing: a feed query, counts, a way to find people, a visibility setting, photos for other viewers, reporting, and all of the app screens.

## Decisions to make first

1. **Default visibility.** Uploads are `private` today. Recommended: a profile setting "Share my check-ins" with three choices (only me, friends, everyone), default **only me**, so nobody shares by accident. New profile column `default_visibility`, used when the app sends no visibility. A button changes the older check-ins too. The full privacy settings stay in Milestone 8.
2. **Follow rules.** Recommended: following is instant, with no approval. A private profile shows its content only to mutual followers (this is how the rules are written already).
3. **Photos for other people.** Recommended: feed and profiles without photos first, then photos as the last step, because the photo bucket is private and needs its own read rule that follows the check-in's visibility.
4. **Text rules.** Apple requires, before the App Store and external testers see user content: a terms of use that users accept, a way to report, a way to block, and filtering of offensive text. Recommended: a simple word list on the server for comments and notes, and the project owner reviews reports in the database (as decided for launch).

## Steps, each its own pull request

| # | Step | Notes |
|---|---|---|
| 7a | **Backend: feed, counts, visibility, report** | `default_visibility` column; `GET /v1/feed?cursor=` as an RPC with keyset paging over check-ins of people you follow that you may see; salute and comment counts on each item; a `report` function (target kind, id, reason); word filter for comments; database tests with several users (blocked, private profile, friends only, post delay); OpenAPI update. Deploy to hosted after approval. |
| 7b | **App: people and follows** | Search by username, public profile screen (name, level, stats, home airport, recent check-ins you may see), follow and unfollow, followers and following lists, block and unblock. The profile gets the "Share my check-ins" setting. |
| 7c | **App: Feed tab** | Replaces the placeholder: cards for check-ins (aircraft, airport, flight), who and when, pull to refresh, paging. Online only. Empty state that points to finding people. |
| 7d | **App: salutes and comments** | Salute button with count, comment list and field, delete your own comment (or any comment on your own check-in). |
| 7e | **App: report, terms, filtering** | Report a user, a check-in or a comment; acceptance of the terms on first use of social features; the terms text, in German and English, goes on `wingspot.site` with the privacy policy. |
| 7f | **Photos in the feed** | Storage read rule that follows `can_view_checkin`, signed URLs in the feed and profile, report for photos. Optional for the first friends test. |

7a must come first. 7b and 7c can follow in either order. 7e must be done before testers who are not friends see each other's content.

## Tests

- Database: for every rule, one test per user relation (self, stranger, follower, mutual friend, blocked either way) and per visibility. Existing `access_test.sql` is the place.
- API: the feed with two accounts on the local stack.
- App: the feed paging and the follow state in unit tests with a fake server; screens checked in the Simulator with two local test accounts.

## Risks

- **Leaks through counts.** Salute and comment counts must follow the same rule as the check-in, or they reveal private activity.
- **Location.** The feed shows the airport, never the raw location.
- **Sensitive aircraft** (military, government, blocked registrations, concept §8) stay out of anything public. Needs a flag on aircraft before `everyone` is offered. Check what the data has.
- **Cost.** The feed query needs an index on `(user_id, occurred_at desc)`, which exists, and a limit on how many people it merges.
- **No push notifications** yet. Salutes and comments show only when the app is opened.
