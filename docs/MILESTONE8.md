# Milestone 8: airport page and settings (plan)

Done when: a person can see an airport's public activity, set who sees what, export their data and delete their account, and deleting removes everything of theirs ([PHASE1.md](PHASE1.md)).

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

| # | Step | Notes |
|---|---|---|
| 8a | **Account deletion** | `DELETE /v1/me` Edge Function: removes the person's photo files, then the auth user (the database does the rest). App: "Delete account" in the profile, two confirmations, then signs out and removes this account's data from the phone. Database and API tests that nothing is left. |
| 8b | **Data export** | `GET /v1/me/export` returns one JSON document; the app offers it with the share sheet. |
| 8c | **Privacy settings screen** | Moves "Share my check-ins" in, adds private profile, post delay and units (km, nm, mi). |
| 8d | **Check-ins on a person's page** | New function with paging that follows the visibility rules; list on the person page and a per-profile report. |
| 8e | **Airport page** | Airport info and recent public activity there, opened from the map, collections and feed cards. |

## Risks

- **A stolen access token could delete an account.** The app confirms twice, and the function acts only on the signed-in user. If this worries you later, require a fresh sign-in first.
- **Orphaned photo files.** Files uploaded but never registered have no database row. The function lists the whole folder instead of trusting the rows.
- **Hosted data is real.** The deletion is tested on the local stack only, then on a throwaway hosted account after you approve the deploy.
