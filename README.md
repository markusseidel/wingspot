# Wingspot

A logbook for planespotters and aviation fans. Log the aircraft you see, the flights you take and the airports you visit, earn badges, and follow friends.

Wingspot is a native app for **iPhone** and **Android**, with one shared backend. Both apps are in a closed beta (TestFlight and an Android test build).

## What you can do

- **Check in** aircraft you spotted, flights you took and airports you visited. It works offline and without an account.
- **Add photos**, scan a **boarding pass**, or import your flights from **Flightradar24 (KML)** with the real route.
- **Collect badges** and see your stats, collections and maps.
- **Follow friends**, see their check-ins in a feed, salute and comment, and take over a flight a friend tagged you on.
- **Back up** what is only on your phone into one open file, and restore it on any phone.

## What's in this repository

| Folder | What it is |
|---|---|
| [`ios/`](ios) | The iPhone app (SwiftUI) |
| [`android/`](android) | The Android app (Kotlin, Jetpack Compose) |
| [`backend/`](backend) | The server: Supabase database, rules and functions |
| [`contracts/`](contracts) | What the apps and the server share: API, data formats, test files |
| [`docs/`](docs) | Ideas, plans and decisions |

## Getting started

**iPhone app** — needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
cd ios && xcodegen generate && open Wingspot.xcodeproj
```

**Android app** — needs JDK 17 and the Android SDK:

```bash
cd android && ./gradlew :app:assembleDebug
```

**Backend** — needs the [Supabase CLI](https://supabase.com/docs/guides/local-development) and Docker:

```bash
supabase start --workdir backend
supabase test db --workdir backend
```

More detail: [android/README.md](android/README.md), [backend/README.md](backend/README.md), [contracts/README.md](contracts/README.md).

## Good to know

- Every change lands on **both apps**, so they stay the same.
- Pull requests are checked automatically (tests for each app and the backend).
- Found a security problem? See [SECURITY.md](SECURITY.md).
- A good place to start reading is [docs/CONCEPT.md](docs/CONCEPT.md).

## License

[MIT](LICENSE)
