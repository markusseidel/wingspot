# Graph Report - wingspot  (2026-11-06)

## Corpus Check
- 119 files · ~64,583 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 17 file(s) not represented in the graph (top: .csv 5, (none) 2, .xcstrings 2)

## Summary
- 1315 nodes · 2898 edges · 74 communities (59 shown, 15 thin omitted)
- Extraction: 89% EXTRACTED · 11% INFERRED · 0% AMBIGUOUS · INFERRED: 305 edges (avg confidence: 0.84)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `ea798e08`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- base
- Decodable
- View
- Android Project Structure
- api.test.js
- UUID
- http.ts
- Airport Visit Check-in
- build_refdata.py
- ios.yml
- BuildRefdataTests
- PackageDescription
- backend.yml
- contracts.yml
- Reference data pipeline
- CLAUDE.md
- Sendable
- .mcp.json
- Equatable
- faa_aircraft_types.py
- GeoCoordinate
- WingspotApp
- SpottedCheckInView
- CheckInStore
- Launch badges
- WingspotCore
- BCBPTests/TestVectors.swift
- String
- LocalCheckIn
- AirportCheckInView
- UserProgress
- ReferenceSearchView
- RootView
- Cross-platform Contract Rules
- build
- Check-in Verification Levels
- Wingspot Repository
- Wingspot
- CheckInKind
- options
- packages
- Supabase
- Rank
- CodingKeys
- Wingspot
- String
- Badge System
- EmailSignInView
- check-strings.sh
- .init
- write_batches
- BadgeIcon
- FaaAircraftTypesTests
- CodingKeys
- project.yml
- Code Sharing Strategy (Native Codebases, Shared Contracts)
- entitlements
- CodingKeys
- BadgeProgress
- RootView
- LocalizedText
- FlownCheckInView
- CabinClass
- AppKit
- VisitContext
- Registration
- BadgeIcon
- Leg
- WingspotCoreTests/TestVectors.swift
- extract_pdf.swift
- FakeServer
- ProfileEditorView

## God Nodes (most connected - your core abstractions)
1. `AccountStore` - 42 edges
2. `FakeBackend` - 38 edges
3. `FakeServer` - 34 edges
4. `CheckInOutbox` - 31 edges
5. `GeoCoordinate` - 28 edges
6. `Profile` - 27 edges
7. `save()` - 27 edges
8. `WingspotCore` - 26 edges
9. `Registration` - 26 edges
10. `CheckInStore` - 24 edges

## Surprising Connections (you probably didn't know these)
- `BCBP Swift Package` --implements--> `BCBP Parser`  [INFERRED]
  README.md → docs/CONCEPT.md
- `contracts/test-vectors` --implements--> `Shared Test Vectors`  [INFERRED]
  contracts/README.md → docs/CONCEPT.md
- `.detail` --calls--> `VisitContext`  [INFERRED]
  ios/Wingspot/Features/CheckIn/CheckInHistoryView.swift → ios/Packages/Persistence/Sources/Persistence/CheckInStore.swift
- `Android App (Kotlin / Jetpack Compose)` --conceptually_related_to--> `Android Project Structure`  [INFERRED]
  android/README.md → docs/CONCEPT.md
- `Wingspot Repository` --references--> `Android App (Kotlin / Jetpack Compose)`  [EXTRACTED]
  README.md → android/README.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Cross-platform Pro Entitlement** — docs_concept_wingspot_pro, docs_concept_entitlements_table, docs_concept_get_v1_me_entitlements, docs_concept_cross_platform_contract_rules [EXTRACTED 1.00]
- **Offline Check-in Sync Flow** — docs_concept_outbox_sync, docs_concept_post_v1_checkins, docs_concept_checkins_table, docs_concept_badge_engine, docs_concept_client_badge_predictor [EXTRACTED 1.00]
- **Shared Contract Artifacts** — contracts_readme_contracts, docs_concept_openapi_spec, docs_concept_shared_test_vectors, docs_concept_design_tokens, docs_concept_on_device_database [EXTRACTED 1.00]

## Communities (74 total, 15 thin omitted)

### Community 0 - "base"
Cohesion: 0.11
Nodes (18): ASSETCATALOG_COMPILER_APPICON_NAME, ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME, CODE_SIGN_STYLE, CURRENT_PROJECT_VERSION, DEVELOPMENT_TEAM, GENERATE_INFOPLIST_FILE, INFOPLIST_FILE, INFOPLIST_KEY_CFBundleDisplayName (+10 more)

### Community 1 - "Decodable"
Cohesion: 0.11
Nodes (15): BCBP, BCBPTests, BCBPVector, .testDescription, BCBPVectors, Expected, Leg, DistanceVector (+7 more)

### Community 2 - "View"
Cohesion: 0.21
Nodes (5): SignInLinkAlert, View, BadgeRow, BadgesScreen, LevelHeader

### Community 3 - "Android Project Structure"
Cohesion: 0.25
Nodes (7): Android App (Kotlin / Jetpack Compose), Android Project Structure, badges Table, Client Badge Progress Predictor, Offline Outbox Sync, POST /v1/checkins, Roadmap (iOS First, Android Second)

### Community 4 - "api.test.js"
Cohesion: 0.09
Nodes (17): ajv, assertError(), assertMatches(), spec, status, devDependencies, ajv@8.17.1, ajv-formats@3.0.1 (+9 more)

### Community 5 - "UUID"
Cohesion: 0.05
Nodes (16): AccountBackend, AccountStore, .needsProfileSetup, .profile, State, loading, signedIn, signedOut (+8 more)

### Community 6 - "http.ts"
Cohesion: 0.24
Nodes (21): invalid(), shapeProblem(), upload(), invalid(), isOptionalText(), register(), unregister(), validate() (+13 more)

### Community 7 - "Airport Visit Check-in"
Cohesion: 0.40
Nodes (5): Airport Visit Check-in, Batch Mode Spotting Session, Flown Check-in, Spotted Check-in, Spotting Locations

### Community 8 - "build_refdata.py"
Cohesion: 0.07
Nodes (20): CryptoKit, AccountError, appleUnavailable, invalidEmail, invalidLink, invalidUsername, notConfigured, offline (+12 more)

### Community 9 - "ios.yml"
Cohesion: 0.09
Nodes (23): runs-on, steps, jobs, app, packages, package, name, on (+15 more)

### Community 12 - "backend.yml"
Cohesion: 0.09
Nodes (23): jobs, refdata-pipeline, supabase, name, on, pull_request, push, permissions (+15 more)

### Community 13 - "contracts.yml"
Cohesion: 0.12
Nodes (15): jobs, openapi, name, on, pull_request, push, runs-on, steps (+7 more)

### Community 14 - "Reference data pipeline"
Cohesion: 0.25
Nodes (7): Build, Data sources, Load into Postgres, Publish, Reference data pipeline, Test, Update aircraft types

### Community 16 - "Sendable"
Cohesion: 0.16
Nodes (15): BCBPError, .code, invalidField, invalidFormatCode, invalidLegCount, truncated, BoardingPass, AirportResult (+7 more)

### Community 18 - "Equatable"
Cohesion: 0.09
Nodes (21): APIClient, APIError, unexpectedStatus, CheckInUploadItem, CheckInUploadResult, .isRejected, .isStored, RefdataManifest (+13 more)

### Community 19 - "faa_aircraft_types.py"
Cohesion: 0.14
Nodes (12): choose_name(), _csv_rows(), generate(), InputError, _keyed(), main(), maker_name(), parse_order() (+4 more)

### Community 20 - "GeoCoordinate"
Cohesion: 0.08
Nodes (20): GRDB, Fixture, RealSnapshotTests, anExactAirportCodeComesFirst(), anExactTypeCodeComesFirst(), database(), emptyOrSymbolOnlySearchesFindNothing(), findsAnAirportByID() (+12 more)

### Community 21 - "WingspotApp"
Cohesion: 0.08
Nodes (24): ReferenceDataError, checksumMismatch, downloadFailed, insecureURL, sizeMismatch, unsupportedSchema, ReferenceDataStore, SnapshotInstaller (+16 more)

### Community 22 - "SpottedCheckInView"
Cohesion: 0.11
Nodes (12): CheckInResultView, .body, .detail, .headline, .isFirstTime, NearestKey, SpottedCheckInView, .body (+4 more)

### Community 23 - "CheckInStore"
Cohesion: 0.25
Nodes (14): CheckInStore, SpottedDraft, .hasAircraft, aCheckInWithoutAircraftIsRejected(), aDifferentRegistrationIsANewSighting(), aFlightNeedsTwoDifferentAirports(), aSavedCheckInWaitsForSync(), aTypeOnlyCheckInCountsThatType() (+6 more)

### Community 24 - "Launch badges"
Cohesion: 0.05
Nodes (41): Aircraft types (8), Airports (9), Countries (6), Decisions, Dormant until the data exists, Hidden (3), How badges work, Later, when the data exists (+33 more)

### Community 25 - "WingspotCore"
Cohesion: 0.14
Nodes (11): Account, AuthenticationServices, Foundation, Observation, OSLog, Persistence, ReferenceData, SwiftData (+3 more)

### Community 27 - "String"
Cohesion: 0.20
Nodes (4): EmailAddress, Username, ProfileRulesTests, .normalizedUsername

### Community 28 - "LocalCheckIn"
Cohesion: 0.17
Nodes (13): LocalCheckIn, SyncState, pending, rejected, synced, CheckInHistoryView, .body, .checkIns (+5 more)

### Community 29 - "AirportCheckInView"
Cohesion: 0.13
Nodes (11): CoreLocation, AirportCheckInView, .body, AirportResultView, .body, .headline, .isFirstTime, NearestKey (+3 more)

### Community 30 - "UserProgress"
Cohesion: 0.09
Nodes (17): BadgeAck, BadgeStore, Celebration, .id, ProgressSource, answer(), BadgeStoreTests, FakeSource (+9 more)

### Community 31 - "ReferenceSearchView"
Cohesion: 0.17
Nodes (10): .form, .form, AirportSearchView, .body, ReferenceSearchView, .body, .placeholder, TypeSearchView (+2 more)

### Community 32 - "RootView"
Cohesion: 0.18
Nodes (9): AppTab, badges, checkIn, explore, feed, profile, AirportKey, ProfileDetailsView (+1 more)

### Community 33 - "Cross-platform Contract Rules"
Cohesion: 0.22
Nodes (10): Live and Historic ADS-B Data, Shared Deep Link Scheme, devices Table, entitlements Table, Flight Lookup Provider, GET /v1/config, GET /v1/me/entitlements, Unified Push Notification Model (+2 more)

### Community 34 - "build"
Cohesion: 0.12
Nodes (9): _airport(), build(), _curated_keywords(), InputError, _load_airports(), _load_types(), main(), _rows() (+1 more)

### Community 35 - "Check-in Verification Levels"
Cohesion: 0.24
Nodes (9): aircraft Table, airports Table, Anti-cheat Rules, checkins Table, OpenSky Aircraft Database, OpenStreetMap Aerodrome Polygons, OurAirports Dataset, Reference Data (+1 more)

### Community 36 - "Wingspot Repository"
Cohesion: 0.27
Nodes (10): BCBP Parser, Boarding Pass Scan, IATA BCBP Barcode, iOS Project Structure, Monorepo Layout, WingspotCore Module, BCBP Swift Package, Wingspot Repository (+2 more)

### Community 37 - "Wingspot"
Cohesion: 0.20
Nodes (10): targets, config, schemes, Wingspot, package, config, targets, build (+2 more)

### Community 38 - "CheckInKind"
Cohesion: 0.22
Nodes (8): CheckInKind, airport, flown, .id, spotted, .subtitle, .systemImage, .title

### Community 39 - "options"
Cohesion: 0.29
Nodes (7): iOS, options, bundleIdPrefix, createIntermediateGroups, deploymentTarget, developmentLanguage, knownRegions

### Community 40 - "packages"
Cohesion: 0.18
Nodes (11): path, path, packages, Account, BCBP, Persistence, ReferenceData, WingspotCore (+3 more)

### Community 41 - "Supabase"
Cohesion: 0.25
Nodes (8): refdata-pipeline, Supabase Backend Project, CloudKit (Ruled Out), Firebase (Alternative), On-device SQLite Snapshot, Row Level Security, Safety, Privacy and Legal Rules, Supabase

### Community 42 - "Rank"
Cohesion: 0.15
Nodes (12): Rank, ace, cadet, captain, chiefPilot, firstOfficer, legend, seniorCaptain (+4 more)

### Community 43 - "CodingKeys"
Cohesion: 0.12
Nodes (17): CodingKeys, airportID, dataVersion, featureFlags, id, kind, latitude, longitude (+9 more)

### Community 44 - "Wingspot"
Cohesion: 0.20
Nodes (10): Debug, Release, package, Wingspot, configFiles, dependencies, platform, settings (+2 more)

### Community 45 - "String"
Cohesion: 0.11
Nodes (11): String, .droppingLeadingZeros, AircraftTypeChoice, AircraftType, .id, .name, Airport, .code (+3 more)

### Community 46 - "Badge System"
Cohesion: 0.40
Nodes (5): Badge System, Core Loop (See, Check In, Reward, Social), Friends and Social Feed, User Level and XP, Wingspot App Concept

### Community 47 - "EmailSignInView"
Cohesion: 0.13
Nodes (10): AppleSignInButton, EmailSignInView, .body, .form, OnboardingView, .body, ProfileScreen, .body (+2 more)

### Community 49 - ".init"
Cohesion: 0.40
Nodes (3): FieldScanner, Substring, .trimmed

### Community 50 - "write_batches"
Cohesion: 0.13
Nodes (7): _airport_row(), InputError, _literal(), main(), _upsert(), write_batches(), PostgresImportTests

### Community 53 - "CodingKeys"
Cohesion: 0.15
Nodes (9): CodingKeys, displayName, homeAirport, id, username, ProfileDetails, ProfileRow, ProfileUpdate (+1 more)

### Community 54 - "project.yml"
Cohesion: 0.50
Nodes (3): name, settings, targets

### Community 55 - "Code Sharing Strategy (Native Codebases, Shared Contracts)"
Cohesion: 0.43
Nodes (6): Contracts Folder, contracts/test-vectors, Design Tokens (contracts/design-tokens.json), Kotlin Multiplatform (Later Option), OpenAPI Spec (contracts/openapi.yaml), Shared Test Vectors

### Community 56 - "entitlements"
Cohesion: 0.50
Nodes (4): path, properties, com.apple.developer.applesignin, entitlements

### Community 57 - "CodingKeys"
Cohesion: 0.12
Nodes (16): .nextTarget, CodingKeys, badges, category, description, hiddenRemaining, id, isHidden (+8 more)

### Community 58 - "BadgeProgress"
Cohesion: 0.31
Nodes (3): BadgeProgress, .isComplete, .isSingle

### Community 59 - "RootView"
Cohesion: 0.15
Nodes (7): RootView, .body, .isSetupPresented, .tabSelection, CelebrationView, PlaceholderScreen, .body

### Community 61 - "FlownCheckInView"
Cohesion: 0.14
Nodes (9): FlownCheckInView, .body, .canSave, .hasRegistrationInput, .hasRoute, .registration, FlownResultView, .body (+1 more)

### Community 62 - "CabinClass"
Cohesion: 0.20
Nodes (9): CabinClass, business, economy, first, premiumEconomy, FlownDraft, FlownResult, aFlightIsSavedWithItsRouteAndCountsRepeats() (+1 more)

### Community 64 - "VisitContext"
Cohesion: 0.20
Nodes (9): AirportDraft, VisitContext, arriving, departing, museum, spotting, transit, working (+1 more)

### Community 65 - "Registration"
Cohesion: 0.22
Nodes (4): Place, Registration, .description, RegistrationTests

### Community 66 - "BadgeIcon"
Cohesion: 0.47
Nodes (4): .body, BadgeIcon, localized(), .body

### Community 279 - "FakeServer"
Cohesion: 0.09
Nodes (20): CheckInOutbox, CheckInUploader, OutboxOutcome, finished, idle, retryLater, CheckInSyncCoordinator, CheckInOutboxTests (+12 more)

### Community 532 - "ProfileEditorView"
Cohesion: 0.28
Nodes (3): ProfileEditorView, .airportLabel, .body

## Ambiguous Edges - Review These
- `Shared Deep Link Scheme` → `GET /v1/config`  [AMBIGUOUS]
  docs/CONCEPT.md · relation: conceptually_related_to

## Knowledge Gaps
- **167 isolated node(s):** `PDFKit`, `invalidEmail`, `invalidUsername`, `usernameTaken`, `invalidLink` (+162 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 426 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **15 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `String` to `Decodable`, `View`, `UUID`, `build_refdata.py`, `Sendable`, `Equatable`, `GeoCoordinate`, `WingspotApp`, `ProfileEditorView`, `FakeServer`, `SpottedCheckInView`, `BCBPTests/TestVectors.swift`, `String`, `LocalCheckIn`, `AirportCheckInView`, `UserProgress`, `RootView`, `CheckInKind`, `CodingKeys`, `EmailSignInView`, `.init`, `BadgeIcon`, `CodingKeys`, `CodingKeys`, `BadgeProgress`, `RootView`, `LocalizedText`, `CabinClass`, `VisitContext`, `Registration`, `BadgeIcon`, `Leg`, `WingspotCoreTests/TestVectors.swift`?**
  _High betweenness centrality (0.218) - this node is a cross-community bridge._
- **Are the 19 inferred relationships involving `AccountStore` (e.g. with `.aBadLinkKeepsTheUserSignedOutAndReportsIt()` and `.aFailedAppleSignInChangesNothing()`) actually correct?**
  _`AccountStore` has 19 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PDFKit`, `invalidEmail`, `invalidUsername` to the rest of the system?**
  _167 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `base` be split into smaller, more focused modules?**
  _Cohesion score 0.1111111111111111 - nodes in this community are weakly interconnected._
- **Why does `UUID` connect `UUID` to `.saveAirport`, `Sendable`, `Equatable`, `CheckInStore`, `CodingKeys`, `FakeServer`, `CabinClass`, `LocalCheckIn`, `UserProgress`?**
  _High betweenness centrality (0.040) - this node is a cross-community bridge._
- **Should `Decodable` be split into smaller, more focused modules?**
  _Cohesion score 0.11396011396011396 - nodes in this community are weakly interconnected._

### Low-confidence Hints
_AMBIGUOUS edges — the extractor was unsure. Verify before acting on these._

- **What is the exact relationship between `Shared Deep Link Scheme` and `GET /v1/config`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._