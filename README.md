# Wingspot

A social logbook for planespotters and aviation enthusiasts, as native iOS and Android apps on one shared backend. Check in aircraft you see or fly on and airports you visit, and earn badges.

See the full app concept in [docs/CONCEPT.md](docs/CONCEPT.md).

## Repository layout

| Folder | Content |
|---|---|
| `docs/` | App concept |
| `contracts/` | API spec, reference database schema and shared test vectors (and later badge rules, design tokens) used by all clients |
| `ios/` | iOS app (SwiftUI) and local Swift packages `WingspotCore` and `BCBP` |
| `backend/` | Supabase backend (database, access rules, Edge Functions) and reference data pipeline |
| `android/` | Android app (planned) |

## iOS development

Requires Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
cd ios
xcodegen generate      # after adding/removing files or changing project.yml
open Wingspot.xcodeproj
```

Run the package tests without a simulator:

```bash
swift test --package-path ios/Packages/WingspotCore
swift test --package-path ios/Packages/BCBP
```
