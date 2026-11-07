# Milestone 8: airport page and settings (plan)

Done when: a person can see an airport's public activity, set who sees what, export their data and delete their account, and deleting removes everything of theirs ([PHASE1.md](PHASE1.md)). Export and deletion must work on hosted with a throwaway account, privacy settings must change what a second account sees, and person and airport pages must show only what the rules allow.

## What already exists

- Deleting a row in `auth.users` removes the profile and, through foreign keys, check-ins, photo rows, salutes, comments, follows, blocks, devices, badges and entitlements. Reports keep their text but lose the reporter.
- Not covered by the database: the photo files in the `photos` bucket (one folder per user), and the app's own copy on the phone.
- `profiles` already has `is_private` and `post_delay_minutes`. The "Share my check-ins" setting (default visibility) came with Milestone 7.

## Decisions

1. **Deletion is immediate.** No grace period: Apple wants deletion inside the app, and a grace period means keeping data the person asked us to remove. The app asks twice (a warning, then a confirmation).
2. **Deleting removes the account's check-ins from the phone too.** Check-ins made while signed out stay. The text says so before the person confirms.
3. **Sign in with Apple.** Apple requires that the app revokes the Apple token when the account is deleted. Sign in with Apple isn't switched on at the backend yet, so this waits for that step and is tracked in TODO.
4. **Export is a JSON file** the person can save or share, built on the server from their own rows (profile, check-ins, photo list, comments, salutes, follows, blocks). Photo files are not part of it for now.
5. **A person's page shows their check-ins** as far as the visibility rules allow, with a new function, because the feed only covers people you follow.

## Steps, each its own pull request

I deploy to hosted only on the owner's word.

### 8a. Account deletion (done, function deployed)

`DELETE /v1/me` removes the photo files and the auth user; the app signs out and clears the account's data from the phone. Still to try on hosted with a throwaway account.

### 8b. Data export

- **Server:** the database function `export_my_data()` (called like `get_feed`, so no Edge Function and no OpenAPI entry) returns one JSON document from the caller's own rows: profile, check-ins, photo list (ID, size, check-in), comments, salutes, follows, blocks, badge progress and the sharing setting. It leaves out other people's data and push tokens. The location stays in the check-in rows, since it is the person's own data.
- **App:** "Export my data" in the profile builds the file and offers it with the share sheet.
- **Tests:** an API test with two users (nothing of the other person leaks) and one Account test. Add it to OpenAPI.
- **Open choice:** photo files are not included, only the list. A zip with the photos is possible later.
- **Docs:** update the privacy draft, where export is marked to-do.

### 8c. Privacy settings screen

- **Server:** the columns `is_private` and `post_delay_minutes` exist, but a client can't change them yet. Add a small `set_privacy(is_private, post_delay_minutes)` function, or a column grant. A database test that a post delay of 60 minutes hides a fresh public check-in from strangers but not from friends or the owner.
- **App:** a "Privacy" screen that takes over "Share my check-ins" and adds private profile (with an explanation of who sees what) and post delay (none, 1 hour, 6 hours, 24 hours).
- **Units:** a local setting for km, nautical miles or miles, used where distances show: the feed card, flights and stats. Distances stay in km in the database.
- **Strings:** German and English.

### 8d. Check-ins on a person's page (needs a migration)

- **Server:** `get_person_checkins(target, before_time, before_id, page_size)`, with the same rules and sensitive-aircraft handling as `get_feed`, plus the counts. A database test per relation (self, follower, mutual friend, stranger, blocked) and per visibility.
- **App:** the person page lists their visible check-ins with paging, reusing the feed card (salute, comment, report, photos). A private profile shows a lock message if you aren't mutual. Your own profile can show the same list.

### 8e. Airport page (needs a migration)

- **Server:** `get_airport_activity(airport_id, ...)` returns recent public check-ins at the airport, with the same hiding rules, and a few counts: check-ins this month, distinct aircraft, top spotters among people you may see.
- **App:** an airport page with code, name, country, a small map, your own visits and the recent activity. It opens from the airport map, the collections list, and an airport on a feed card or check-in result.
- **Left out for now:** spotting locations, leaderboards and "rare today" (Phase 2).

## Risks

- **A stolen access token could delete an account.** The app confirms twice, and the function acts only on the signed-in user. If this worries you later, require a fresh sign-in first.
- **Orphaned photo files.** Files uploaded but never registered have no database row. The function lists the whole folder instead of trusting the rows.
- **Hosted data is real.** The deletion is tested on the local stack only, then on a throwaway hosted account after you approve the deploy.
