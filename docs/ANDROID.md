# Wingspot for Android: concept, effort and costs

Status: proposal, 9 Nov 2026. Nothing here is decided. Numbers are estimates from the size of the iOS app and common market rates, not quotes. Prices change; check them before you commit.

## 1. Summary

- **What:** a native Android app (Kotlin, Jetpack Compose) with the same features as the iOS app today, on the same Supabase backend and the same account.
- **Recommendation:** build it **after the iOS friends test and the first App Store submission**, not before. A second app doubles the cost of every later feature, and the friends test will tell us which features are worth doubling.
- **Effort:** about **700 to 940 hours** of focused work for feature parity (18 to 31 weeks for one experienced developer working 30 to 40 hours a week), or **440 to 620 hours** when AI-assisted, as the iOS app was built (11 to 21 weeks). On top comes at least **2 weeks of calendar time** that no amount of work shortens, because of Google Play's rules for new apps (section 8).
- **Cash cost:** with the AI-assisted way of working, **about 25 USD plus optional test phones (300 to 900 euros)** in the first year, on top of the tools you already pay for. With a freelancer, **about 50,000 to 95,000 euros**. With an agency, **80,000 to 150,000 euros**.
- **Upkeep:** every feature costs roughly 1.7 times as much once there are two apps, and Android needs a yearly round of OS and Play-policy updates (about 10 to 15 percent of the build effort a year).

## 2. What the iOS app has today (the target)

Android 1.0 should match this, not chase newer iOS features.

| Area | Built on iOS |
|---|---|
| Check-ins | Spotted, Airport and Flown; offline first, uploaded later; photos (stripped of metadata and shrunk on the phone); boarding pass scan (on the phone, no name or booking code) |
| Profile | Stats, collections (aircraft, types, airports), 36 badges with progress, airports map, settings (sharing, privacy, distance unit, notifications), data export, account deletion |
| Social | People search, follow and block, sharing choice (only me, friends, everyone), feed with photos, salutes, comments with word filter, reports, community rules, person page with check-ins, airport page |
| Explore | Search for people, airports and types; airports near you; busy airports |
| Push | New follower, salute, comment; German and English; tap opens the right screen |
| Languages | German and English |

Size for scale: about 11,600 lines of Swift (app, packages and tests) and about 5,000 lines of SQL and TypeScript on the server, built in the first week.

## 3. What carries over and what is rebuilt

**Carries over unchanged (this is the big saving)**
- The whole backend: database, access rules, Edge functions, sync endpoint, badge rules, reports, export and deletion. All business rules live on the server.
- The API contract `contracts/openapi.yaml` and the shared test vectors in `contracts/test-vectors/` (boarding pass parsing, distances, registrations). The Android code is tested against the same files.
- The reference data: one SQLite file with airports and aircraft types, the same on both platforms (Room or plain SQLite with FTS5).
- Accounts: one account works on both phones.
- Texts: the iOS string catalog is the source; `strings.xml` is generated from it by a small script.

**Rebuilt natively (about 100 percent new code)**
- All screens (Compose, Material 3), navigation, the local database and the upload queue, the boarding pass parser (Kotlin version of `BCBP`), great-circle distance, registration rules, the badge screens, the map.

**Small backend changes Android needs**
1. `send-push` learns **Firebase Cloud Messaging (FCM)**: sign in with a Google service account, send through the FCM HTTP v1 API, remove dead tokens. The text writing (`render`) is reused as is.
2. `queue_notification` and `claim_notifications` currently look for iOS devices only; they must include Android devices and pass the platform along.
3. **Sign in with Apple on Android** goes through Apple's web flow: a Services ID and a signing key in Supabase. Apple's client secret for the web flow expires after at most 6 months and must be renewed, a recurring chore. (Alternative: offer only Google and email on Android; users who signed up with Apple on iPhone can still use email with the same address if they used the real one, but a relay address would not match. Decide before launch.)
4. App Links: `assetlinks.json` on `wingspot.site`, and the web pages behind shared links (also needed for iOS Universal Links, not built yet).
5. New shared files in `contracts/`: design tokens (colors, spacing), badge visuals, and golden files for predicted badge progress (the iOS app has no shared predictor yet, so this is new work on both sides, or Android shows server progress only at first).

## 4. Technical choices

| Topic | Choice | Why |
|---|---|---|
| Language and UI | Kotlin, Jetpack Compose, Material 3 | Standard, best tooling, matches the concept |
| minSdk | 28 (Android 9) | About 95 percent of devices; lower costs extra testing for little gain |
| Structure | One app module, feature modules and `core` modules as in the concept (`core:bcbp`, `core:refdata`, `core:database`, `core:network`, `core:sync`, `feature:*`) | Mirrors the iOS packages, so a feature spec maps one to one |
| Local data | Room (check-ins, outbox, badge acknowledgements) | Counterpart of SwiftData; same outbox rules |
| Reference data | Prepackaged SQLite downloaded on first start, FTS5 search | Same file as iOS |
| Background upload | WorkManager with network constraint and backoff | Counterpart of the iOS sync coordinator |
| Network | supabase-kt and Ktor, DTOs from the OpenAPI file | Same endpoints as iOS |
| Sign-in | Credential Manager for Google; email link; Apple through the web flow | See section 3 |
| Camera and barcodes | CameraX and ML Kit Barcode Scanning (bundled model) | Counterpart of Vision; works offline |
| Photos | Photo Picker; strip metadata and shrink on the phone | Same rules as iOS |
| Maps | **Open decision:** Google Maps Compose (simplest, free for mobile maps at the time of writing, needs an API key) or MapLibre (open, one style on both platforms, needs a tile provider, 0 to a few dozen euros a month at our size) | Recommendation: Google Maps for 1.0, revisit later |
| Push | FCM | Standard |
| Crashes | Android vitals in Play Console (no code, no privacy text change) | Same reasoning as iOS |
| Testing | JUnit and the shared test vectors, Compose UI tests for the main flows, Robolectric where useful | The boarding pass and distance logic must match iOS exactly |
| Application ID | `site.wingspot.android` | Cannot be changed after the first upload |

**Options considered and not recommended now**
- **Kotlin Multiplatform for the shared logic:** attractive in theory, but the iOS side is finished in Swift; moving it would be a rewrite for little gain. Revisit if keeping two parser and rule implementations in sync becomes painful.
- **Flutter or React Native for both:** would mean rewriting the working iOS app and giving up native behavior.
- **A web app (PWA) for Android users:** cheapest (4 to 6 weeks), but no reliable offline upload in the background, no Play Store presence, weaker camera and notification behavior. Only worth it as a stopgap if Android demand is unclear.
- **Waiting:** a legitimate choice. The friends test may show that iOS alone is enough for a while.

## 5. Plan by milestone

Hours are focused work for an experienced Android developer; the AI-assisted column is what we saw on iOS (the model writes and tests code, the owner reviews, tests on devices and decides).

| Step | Content | Manual hours | AI-assisted hours |
|---|---|---|---|
| A0 | Gradle project, CI (GitHub Actions), design system from tokens, generated API client, strings script, sign-in with email | 70 to 90 | 40 to 60 |
| A1 | Sign-in with Google and Apple (web), profile setup, onboarding, terms and community rules | 50 to 70 | 30 to 45 |
| A2 | Reference data download and search, check-ins Spotted, Airport and Flown, local database, outbox and WorkManager sync | 140 to 180 | 90 to 120 |
| A3 | Boarding pass scan (camera and screenshot, ML Kit), photos on check-ins | 60 to 80 | 35 to 50 |
| A4 | Profile: stats, collections, badges screen and celebration, airports map | 90 to 120 | 60 to 80 |
| A5 | Social: people, follow, block, sharing and privacy settings, feed, salutes, comments, reports, person and airport pages, export, deletion | 130 to 170 | 85 to 115 |
| A6 | Push: FCM in the app and in `send-push`, Android devices in the outbox, settings, tap handling | 40 to 60 | 25 to 40 |
| A7 | Explore: search, nearby, busy airports (and 11c to 11e as they land on iOS) | 40 to 60 | 25 to 40 |
| A8 | Polish: accessibility (TalkBack), dark mode, tablets and foldables, German and English review, device testing, Play listing and Data safety form, release | 80 to 110 | 50 to 70 |
| | **Total** | **700 to 940** | **440 to 620** |

These hours assume parity with the iOS app as of today, not every future feature. The ranges are wide on purpose: the first spike (section 10) will narrow them.

**Calendar:** one developer at 30 to 40 hours a week: about 18 to 31 weeks manual, 11 to 21 weeks AI-assisted. Closed testing on Google Play adds at least 2 more weeks at the end (section 8) and can overlap with A8.

## 6. Costs

**One-time**
| Item | Cost |
|---|---|
| Google Play Developer account | 25 USD, once |
| Two test phones (for example a recent Pixel and a mid-range Samsung); the emulator covers the rest | 300 to 900 euros, or 0 with Firebase Test Lab's free quota and emulators first |
| Developer account verification and, if you choose an organization account, a D-U-N-S number | 0 euros, but days to weeks of waiting |

**Running (per month)**
| Item | Cost |
|---|---|
| Supabase | Already running for iOS. The Pro plan (25 USD) is wanted anyway for backups and leaked-password protection, and carries both apps |
| Firebase Cloud Messaging | Free |
| Google Maps SDK for Android (mobile maps) | Free at the time of writing; check the current pricing page. MapLibre instead: tile provider 0 to about 50 euros |
| Apple Developer Program | Already paid (99 USD a year); also needed for Apple sign-in on Android |
| Crash reports | Play Console, free |

**Labor, three ways**
| Way | Effort | Cost |
|---|---|---|
| AI-assisted as on iOS (the model builds and tests, the owner reviews and tests on devices) | 440 to 620 model-assisted hours, of which the owner's own time is roughly 80 to 150 hours of review, device testing and decisions | Your time and your tool subscription; no third-party labor |
| Freelance Android developer | 700 to 940 hours at 70 to 100 euros an hour (German market, experienced) | about 50,000 to 95,000 euros (a developer who also uses AI tools can land at the low end) |
| Agency | 700 to 940 hours at 100 to 140 euros an hour plus about 15 percent project management | about 80,000 to 150,000 euros |

**Upkeep after launch (per year)**
- About 10 to 15 percent of the build effort: yearly Android and Play-policy changes (the target API level must be raised every year), library updates, device-specific bugs.
- Every new feature on both platforms costs about 1.7 times the iOS-only price. Plan features with that in mind, or let Android follow a release behind.
- Support: more device types means more bug reports that cannot be reproduced; plan time for it.

## 7. Risks

| Risk | What helps |
|---|---|
| Device fragmentation (manufacturer battery rules can delay push and background uploads) | WorkManager and high-priority FCM; test on a Samsung and a Xiaomi or similar early; keep upload-on-open as a fallback |
| Boarding pass scanning differs between phones and cameras | Shared test vectors for the parser; scan from a screenshot as well as the camera; test with real passes |
| Apple sign-in on Android is clumsy and its secret expires | Offer it, but make Google and email work first; put the renewal in the calendar, or skip Apple on Android |
| Double work on every feature | Keep one feature spec for both; ship Android a release behind; hold a parity checklist as the concept says |
| Play closed test (12 testers, 14 days) delays launch | Start recruiting testers early; see section 8 |
| Badge visuals use SF Symbols on iOS | Choose Material Symbols or custom SVG badge art once, in `contracts/`, and use it on both |
| The owner cannot review Kotlin code well | Rely on the shared test vectors, a CI that builds and tests every PR, and a short code review by a freelancer at the end (about 2,000 to 4,000 euros) |

## 8. Google Play rules that set the calendar

- A new personal developer account must run a **closed test with at least 12 testers for 14 days in a row** before it can publish to production. Organization accounts have been exempt from this; check the current rules when you start.
- A **Data safety** form (what the app collects) and a privacy policy URL are required. The privacy draft in this repository already covers the content; the form follows the same facts as the App Privacy answers in [TESTFLIGHT.md](TESTFLIGHT.md).
- New apps must **target the current API level**; this rises every year.
- App content declarations (user-generated content: reporting and blocking must be in the app, which they are).
- Review usually takes a few days for the first release.

## 9. Prerequisites and decisions

Before starting:
1. Friends test on iOS done, and the iOS 1.0 scope settled (so the target stops moving).
2. Decide: **Google Maps or MapLibre**, **Apple sign-in on Android or not**, **personal or organization Play account**, **AI-assisted or freelancer**.
3. Backend: FCM sender and Android devices in the push outbox (step A6 can bring these, but they are small and can go first).
4. Shared files in `contracts/`: design tokens, badge visuals, strings export script.
5. Two testers with Android phones (also for the 12-tester closed test).

## 10. Suggested sequence

1. Now: friends test and iOS 1.0 (Milestones 9 and 11).
2. Then a one-week **spike**: Gradle project, CI, generated API client, email sign-in, reference data search and one check-in type uploading through the real outbox, on a real phone. This answers the open questions (Maps, WorkManager behavior, ML Kit quality) for about 40 to 60 hours and decides whether to go on.
3. A1 to A8 as in section 5, with a Play closed test running from the end of A5 so the 14 days are not wasted.
4. Android 1.0 to production, then feature work on both platforms.


## Spike log (started)

The Gradle project is in [android/](../android/README.md). What it has shown so far:

- **Tooling:** JDK 17, Gradle 9.8, Android Gradle Plugin 9.5, Kotlin 2.4, Compose BOM 2026.09. The newest library versions require `compileSdk` 37, so the SDK platform 37 is needed. The project builds from the command line, with no Android Studio.
- **Shared logic carries over cheaply:** the boarding pass parser, the registration rules (about 150 prefixes) and the distance maths were ported to plain Kotlin in a few hours, and pass the same vector files the iPhone app uses (15 boarding passes, 48 registrations, 8 distances). This confirms the "what carries over" section.
- **Sign-in:** the email link flow (PKCE) is built against the real Supabase auth endpoints and tested with a fake server. The link opens the app through the `wingspot://auth-callback` address, which is already allowed for the iPhone app. The full round trip with a real email has not been tried yet.
- **On the emulator (Android 15):** the sign-in screen, the signed-in screen, and the registration check ("hbjna" becomes HB-JNA, CH) render and work, in English and German strings.
- **Not tried yet:** reference data and search, check-ins with the outbox and WorkManager, the camera scan (ML Kit), maps, push, a real phone.
