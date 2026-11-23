# Release notes in the app: plan

Idea from the owner: a "What's new" entry under Profile > Settings, where every version or build that went out can be read, each with a short summary of the tester notes (later the release notes). Issue #315. Status: built and live (see "As built" at the end).

## Goal

- A tester or user opens **Settings > What's new** and sees the builds that went out, newest first, each with a short text in their language (German or English).
- It says which entry is the build they have installed.
- The text is the tester text that is already written for every build, shortened, so writing it stays a by-product of shipping and not extra work.
- The same screen later holds the real release notes for App Store and Play Store versions, with no change to the apps.

## What exists today

- **Tester texts** are written per build in English and German, and the Android notes go into the Firebase mail through `android-beta.yml` (`notes` input). The iOS text goes to TestFlight by hand. Nothing keeps them afterwards, so they are lost after the mail.
- **Announcements** (`public.announcements`, `get_announcements()`, `backend/scripts/post_announcement.sh`) already do most of the job: a row with English and German title and text, posted by the owner with a script that runs as the database owner, read through one public function, closed table (RLS on, no policy). The apps show them at the top of the feed. Release notes are a different thing (a history, tied to a build, per platform), so they get their own table, but they copy this pattern.
- **Version numbers.** iOS: `MARKETING_VERSION` 0.2.0 and `CURRENT_PROJECT_VERSION`, a build number `YYYYMMDDBB` (date plus two digits). Android: `versionName` 0.2.0 and `versionCode`, also date plus two digits from the workflow run. The two apps do not share build numbers, so an entry belongs to one platform.
- **Settings** (iOS `SettingsView`, Android settings page) have sections for sharing, tagging, notifications, privacy, units and the legal links. There is no About section and the app shows no version anywhere.

## Decisions

1. **Where the notes live: a table on the server, not inside the app.** A text bundled in the app can only describe builds up to the one the person has, and cannot be fixed or added after the build is out. A table lets a person on build 5 read what builds 6 and 7 changed (and a tester see what is coming in the build they are about to get), and the text can be corrected without a new build. It also works the same on iOS and Android and needs no store review. The cost: reading it needs a connection. The screen keeps the last list it loaded (on the phone) so it opens offline.
2. **One row per platform and build.** Columns: platform (`ios` or `android`), version name, build number, `released_at`, English and German title and text, `kind` (`beta` or `release`), `active`. A change that went out on both apps is two rows with the same text, written by two script calls. Unique on (platform, build). Reason: builds are different numbers on each platform, and a fix may ship on one first.
3. **Short text, in plain lists.** The text is a few lines (up to about 600 characters, English and German), written from the tester text: what changed for the person, no instructions to testers ("please try..."), no internal words. A small subset of formatting: one `-` bullet per line, shown as a bulleted list. Nothing else (no links or HTML), so the apps need no markdown library and the text cannot carry anything harmful.
4. **Hidden things stay out.** Hidden badge names, rules and texts never go into a note (the public repo and the public table must not reveal them). The script is run by the owner and a note is read by them before it goes live, so this is a written rule in the plan and in the script's help text, not code that tries to guess it.
5. **Posting is a script step of the release routine, not automatic at first.** `backend/scripts/post_release_note.sh` (like `post_announcement.sh`) is run after a build is out, with the build number, the English text and the German text. Later the iOS and Android build workflows can call it, so the note goes up with the build. For that the workflow needs a secret that can write; that is a bigger step (a service key in GitHub) and is a later decision, not part of the first version.
6. **Only entries of your own platform, only up to your build and one step ahead.** The list shows entries for the platform of the phone, newest first. Entries with a build number higher than the installed one are shown too, under a heading "Newer than your version", because a tester wants to know what the next build brings. This is easy to switch off later when real releases exist (then only versions the store shows).
7. **Beta and release are one list.** `kind` is only a label (a small "Beta" tag) and the grouping rule later: when the real releases start, a release entry can sum up the betas before it. No second screen.
8. **Not a notification.** No push and no badge on the screen for now. A small dot on the Settings row when there is an entry newer than the last one the person opened is an optional extra (see the end).

## Backend

One migration, one function, one script, tests. Nothing in the existing `checkins` or social functions changes.

- Table `public.release_notes`: `id uuid`, `platform text check in ('ios','android')`, `version text`, `build bigint`, `kind text check in ('beta','release') default 'beta'`, `title_en` / `body_en` (required, length limits like the announcements), `title_de` / `body_de` (both or neither), `released_at timestamptz default now()`, `active boolean default true`. Unique (`platform`, `build`). RLS on, no policy.
- `public.get_release_notes(platform text, limit int default 30)`: security definer, `set search_path = ''`, returns active rows of that platform, newest build first, at most 50. `revoke ... from public; grant execute ... to anon, authenticated` (a signed-out tester can read it too, as with the announcements). The platform is a parameter, not inferred, so each app asks for its own.
- Add the function to the list in `access_test.sql`.
- `backend/scripts/post_release_note.sh --local|--remote post <ios|android|both> <version> <build> "Title" "Text EN" "Titel" "Text DE"`, plus `list` and `off <platform> <build>`. One call per platform, because the build numbers differ (a change on both apps is two calls). Same quoting and `supabase db query` approach as `post_announcement.sh`.
- Contract: `contracts/openapi.yaml` gets `GET /rest/v1/rpc/get_release_notes` described the way `get_announcements` is.
- pgTAP: anon and authenticated can read; inactive rows are hidden; the platform filter works; ordering by build; the table itself is closed to clients; unique (platform, build); German both-or-neither.
- Deploy: database first (`supabase db push`), then the apps. Old app versions ignore the new function, so there is no compatibility issue.

## iOS

- Model `ReleaseNote` (version, build, kind, releasedAt, title and text in both languages, a `localized` helper that falls back to English), and `ReleaseNotesStore` in the Account package with a backend call to `get_release_notes("ios")`, the last result cached in the app's storage (a small JSON file or UserDefaults) so the screen opens offline.
- `Features/Settings/ReleaseNotesView`: a `List`, one row per note. The row's header line is "Version 0.2.0 (2026112308)" and the date; a "Beta" tag; the title; the text with bullets. The entry that matches the installed `CFBundleVersion` has a "Installed" tag. Entries above it sit under "Newer than your version". Pull to refresh; empty state "No release notes yet"; an error line with the cached list still shown.
- `SettingsView`: a new section at the bottom, above or inside a small "About" section: "What's new" (navigation link) and a line "Version 0.2.0 (2026112308)" read from the bundle. The About section is new on both apps, because the app shows no version today and a tester needs it when writing a bug report.
- Strings in `Localizable.xcstrings` (English and German); `check-strings.sh` passes.
- Tests: the store (ordering, installed marker, newer-than-installed split, fallback to English, cached list when offline) with a stub backend.

## Android

- The same model and store in the `core` module (`ReleaseNotes.kt`, call through the existing Supabase client, the last result in `Prefs` or a file), the screen in `ProfileScreens.kt` or a new `ReleaseNotesScreen.kt`, a route `Route.ReleaseNotes` opened from the settings page. Same texts, same layout rules, same tags. The installed build is `BuildConfig.VERSION_CODE`, the version name `BuildConfig.VERSION_NAME`.
- A version line in the new About section of the settings page, same wording as iOS.
- Strings in `values` and `values-de`. Unit tests next to the other core tests; a Compose test for the screen like the other screens.

## Order of work

1. Backend PR: migration, function, script, pgTAP, contract. Deploy.
2. iOS and Android in one PR each (the parity rule: both land together), against the production function, with the local stack for testing.
3. Backfill: post the notes of the last few builds (from the tester texts of this month) so the screen is not empty on day one. This is done by hand with the script, shortened.
4. Add "post the note" as a step to the release routine (the build instructions the owner and I already follow): after a build is uploaded, run the script with the shortened tester text, for both platforms.

## Not in the first version

- A "What's new" sheet that opens by itself after an update (it needs "which build was last seen" on the phone; easy to add on this table).
- A dot on the Settings row for an unread entry (same state).
- Posting from the build workflows (needs a write secret in GitHub).
- Links, images or full formatting in a note.
- Entries for the backend or the website (only app builds).
- Translations beyond German and English.

## Open questions for the owner (decided, see "As built")

1. Is it right that testers see the notes of builds newer than theirs ("Newer than your version")? This shows what the next TestFlight build brings. If not, drop the group.
2. Should a note be one entry per build, or one per day when several builds go out on the same day (like 2026112307 and 2026112308)? Per build is simplest and matches the tester mails; per day reads better. The recommendation is per build, and a later release entry sums the betas up.
3. Should the screen be open to signed-out users too? The plan says yes (the function is readable by `anon`), because the notes hold nothing private.
4. Name of the menu entry: "What's new" (the recommendation) or "Release notes".

## As built

Shipped in PRs #317 (backend), #318 (iOS), #319 (Android) and #321 (iOS fix). Live in production since 2026-11-23.

**Decisions on the open questions:** builds newer than the installed one are shown, under "Newer than your version"; one entry per build; the screen is readable signed out; the menu entry is "What's new" (German "Neuigkeiten"); the version line is in a new About section.

**Where it differs from the plan**
- The script posts one platform per call (no `both`). It is an upsert on (platform, build), so running it again for the same build replaces the text. `--release` marks a store release.
- There is no contract entry: `get_release_notes` is a database function called through `/rest/v1/rpc`, like `get_announcements`, which the OpenAPI file does not list either.
- iOS: `ReleaseNotesStore` in the Account package (cached in `UserDefaults`), `Features/Settings/ReleaseNotesView.swift` (the screen and `AboutSection`). Android: `ReleaseNotes.kt` in `core` (model, API, `groupReleaseNotes`), `ReleaseNotesPage` in `ProfileScreens.kt`, cache in `Prefs`, route `Route.ReleaseNotes`.
- The entry's date is the day of `released_at`. Pull to refresh is iOS only; Android loads when the page opens.
- A trap met on the way: a SwiftUI helper must not be called `tag`, because SwiftUI's own `.tag` modifier wins and draws the whole view inside the row (the black boxes in the first iOS build). The helper is `badge`.

**Release routine.** After every iOS and Android build, run
`backend/scripts/post_release_note.sh --remote post <ios|android> <version> <build> "Title" "- bullet\n- bullet" "Titel" "- Punkt"`
once per platform, with the tester text shortened: bullets of what changed for the person, no "please try" lines, never a hidden badge. The iOS build is `CURRENT_PROJECT_VERSION`; the Android build is the `versionCode` of the workflow run (date plus two digits). Check with `post_release_note.sh --remote list`.

**Backfilled:** iOS 2026112307 and 2026112308, Android 2026112305 and 2026112306. Earlier builds have no note.

**Not done (still "not in the first version")**
- A "What's new" sheet that opens after an update, and an unread dot on the Settings row. Both need a "last seen build" kept on the phone.
- Posting from the build workflows (needs a write secret in GitHub).
- Not yet checked by hand on the Android screen.
