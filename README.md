# Wingspot

A social logbook for planespotters and aviation enthusiasts, as native iOS and Android apps on one shared backend. Check in aircraft you see or fly on and airports you visit, collect badges, and follow friends.

The iOS app is in TestFlight (version 0.2.0). Android is planned.

## What the app does today

- **Check-ins:** spotted aircraft, airport visits and flights, saved offline first and uploaded later. Flights can be filled in by scanning a boarding pass; the scan runs on the device and never reads the passenger name or booking code.
- **Photos:** added to a check-in, shrunk and stripped of metadata on the device before upload.
- **Profile and collections:** stats, your aircraft, types and airports, and a map of the airports you visited.
- **Badges:** 36 launch badges, defined on the server, so new ones need no app update. See [docs/BADGES.md](docs/BADGES.md).
- **Social:** find people, follow and block them, choose who sees your check-ins, a feed of friends' check-ins, salutes and comments with a word filter. Reporting, terms of use and photos in the feed are next.

## Documentation

| File | Content |
|---|---|
| [docs/CONCEPT.md](docs/CONCEPT.md) | The app concept |
| [docs/PHASE1.md](docs/PHASE1.md) | Phase 1 scope and decisions |
| [docs/TODO.md](docs/TODO.md) | Milestone status and open tasks |
| [docs/MILESTONE7.md](docs/MILESTONE7.md) | Plan for the social features |
| [docs/BADGES.md](docs/BADGES.md) | The launch badges and their rules |
| [docs/PRIVACY-DRAFT.md](docs/PRIVACY-DRAFT.md) | Draft privacy policy (German and English) |
| [contracts/README.md](contracts/README.md) | API spec, schema and test vectors |
| [backend/README.md](backend/README.md) | Backend setup and tests |
| [SECURITY.md](SECURITY.md) | Reporting security issues |

## Repository layout

| Folder | Content |
|---|---|
| `docs/` | Concept, plans and drafts |
| `contracts/` | API spec (`openapi.yaml`), reference data schema, shared test vectors and the app icon source, used by all clients |
| `ios/` | The iOS app (SwiftUI, SwiftData, iOS 18) and its local Swift packages |
| `backend/` | Supabase backend (database migrations, access rules, Edge Functions), database and API tests, and the reference data pipeline |
| `android/` | Android app (planned) |

### iOS packages

| Package | Content |
|---|---|
| `WingspotCore` | Pure logic: badges and progress, shared rules |
| `BCBP` | Boarding pass parser |
| `Persistence` | Local check-ins and photos (SwiftData), sync outbox, stats |
| `ReferenceData` | Airports and aircraft types from the downloaded snapshot |
| `Account` | Sign-in, profile, people, feed, salutes and comments |

## iOS development

Requires Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The generated `Wingspot.xcodeproj` is tracked, so commit it when files are added or removed.

```bash
cd ios
xcodegen generate      # after adding/removing files or changing project.yml
open Wingspot.xcodeproj
```

Run the package tests without a simulator:

```bash
for p in WingspotCore BCBP Persistence ReferenceData Account; do
  swift test --package-path ios/Packages/$p
done
```

Strings live in `ios/Wingspot/Resources/Localizable.xcstrings` in English and German. After building, check them with `ios/scripts/check-strings.sh <derivedDataPath>`.

## Backend development

Requires the [Supabase CLI](https://supabase.com/docs/guides/local-development) and Docker. Run from the repo root:

```bash
supabase start --workdir backend
supabase db reset --local --workdir backend     # apply all migrations
supabase test db --workdir backend              # database and access-rule tests
supabase functions serve --workdir backend      # in a second terminal
cd backend/api-tests && npm test                # API tests against the local stack
```

See [backend/README.md](backend/README.md) for details. The hosted project is production: migrations are deployed only on purpose with `supabase db push --remote --yes --workdir backend`.

## Continuous integration

Pull requests run the workflows in `.github/workflows`. Each starts with a `changes` job and skips the real jobs when nothing relevant changed (a skipped job counts as passing). The required checks are `ios`, `supabase`, `refdata-pipeline` and `openapi`.

## License

[MIT](LICENSE)
