# Graph Report - wingspot  (2026-11-05)

## Corpus Check
- 111 files · ~58,162 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 17 file(s) not represented in the graph (top: .csv 5, (none) 3, .xcstrings 2)

## Summary
- 1219 nodes · 2612 edges · 67 communities (56 shown, 11 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 255 edges (avg confidence: 0.84)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `d42215bf`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- base
- Sendable
- View
- Android Project Structure
- api.test.js
- AccountStore
- http.ts
- Airport Visit Check-in
- LocalCheckIn
- ios.yml
- BuildRefdataTests
- PackageDescription
- steps
- contracts.yml
- Reference data pipeline
- CLAUDE.md
- CodingKeys
- .mcp.json
- SpottedResult
- faa_aircraft_types.py
- ReferenceDatabaseTests.swift
- WingspotApp
- SpottedCheckInView
- Registration
- Launch badges
- WingspotCore
- GeoCoordinate
- String
- .isPlausible
- Foundation
- UserProgress
- ReferenceSearchView
- RootView
- Cross-platform Contract Rules
- build
- Check-in Verification Levels
- Wingspot Repository
- project.yml
- CheckInKind
- options
- packages
- Supabase
- Airport
- ProfileDetailsView
- Wingspot
- CheckInResultView
- Badge System
- EmailSignInView
- check-strings.sh
- BCBPError
- write_batches
- ReferenceDatabase.swift
- FaaAircraftTypesTests
- Equatable
- UUID
- Code Sharing Strategy (Native Codebases, Shared Contracts)
- LocationProvider.swift
- BadgeProgress
- Rank
- .body
- test
- .color
- Testing
- AppKit
- FakeServer
- ProfileEditorView

## God Nodes (most connected - your core abstractions)
1. `AccountStore` - 36 edges
2. `FakeBackend` - 33 edges
3. `FakeServer` - 31 edges
4. `CheckInOutbox` - 29 edges
5. `Profile` - 27 edges
6. `save()` - 27 edges
7. `WingspotCore` - 24 edges
8. `GeoCoordinate` - 24 edges
9. `UserProgress` - 24 edges
10. `BuildRefdataTests` - 23 edges

## Surprising Connections (you probably didn't know these)
- `BCBP Swift Package` --implements--> `BCBP Parser`  [INFERRED]
  README.md → docs/CONCEPT.md
- `contracts/test-vectors` --implements--> `Shared Test Vectors`  [INFERRED]
  contracts/README.md → docs/CONCEPT.md
- `.body` --calls--> `SpottedCheckInView`  [INFERRED]
  ios/Wingspot/Features/CheckIn/CheckInSheet.swift → ios/Wingspot/Features/CheckIn/SpottedCheckInView.swift
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

## Communities (67 total, 11 thin omitted)

### Community 0 - "base"
Cohesion: 0.11
Nodes (18): ASSETCATALOG_COMPILER_APPICON_NAME, ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME, CODE_SIGN_STYLE, CURRENT_PROJECT_VERSION, DEVELOPMENT_TEAM, GENERATE_INFOPLIST_FILE, INFOPLIST_FILE, INFOPLIST_KEY_CFBundleDisplayName (+10 more)

### Community 1 - "Sendable"
Cohesion: 0.13
Nodes (12): BCBP, BCBPVector, .testDescription, BCBPVectors, Expected, Leg, RegistrationTests, RegistrationVector (+4 more)

### Community 2 - "View"
Cohesion: 0.18
Nodes (6): SignInLinkAlert, View, BadgeRow, BadgesScreen, .body, LevelHeader

### Community 3 - "Android Project Structure"
Cohesion: 0.25
Nodes (7): Android App (Kotlin / Jetpack Compose), Android Project Structure, badges Table, Client Badge Progress Predictor, Offline Outbox Sync, POST /v1/checkins, Roadmap (iOS First, Android Second)

### Community 4 - "api.test.js"
Cohesion: 0.09
Nodes (17): ajv, assertError(), assertMatches(), spec, status, devDependencies, ajv@8.17.1, ajv-formats@3.0.1 (+9 more)

### Community 5 - "AccountStore"
Cohesion: 0.05
Nodes (20): AccountBackend, AccountError, invalidEmail, invalidLink, invalidUsername, notConfigured, offline, tooManyRequests (+12 more)

### Community 6 - "http.ts"
Cohesion: 0.24
Nodes (21): invalid(), shapeProblem(), upload(), invalid(), isOptionalText(), register(), unregister(), validate() (+13 more)

### Community 7 - "Airport Visit Check-in"
Cohesion: 0.40
Nodes (5): Airport Visit Check-in, Batch Mode Spotting Session, Flown Check-in, Spotted Check-in, Spotting Locations

### Community 8 - "LocalCheckIn"
Cohesion: 0.16
Nodes (13): LocalCheckIn, SyncState, pending, rejected, synced, CheckInHistoryView, .body, .checkIns (+5 more)

### Community 9 - "ios.yml"
Cohesion: 0.09
Nodes (23): runs-on, steps, jobs, app, packages, package, name, on (+15 more)

### Community 12 - "steps"
Cohesion: 0.09
Nodes (23): jobs, refdata-pipeline, supabase, name, on, pull_request, push, permissions (+15 more)

### Community 13 - "contracts.yml"
Cohesion: 0.12
Nodes (15): jobs, openapi, name, on, pull_request, push, runs-on, steps (+7 more)

### Community 14 - "Reference data pipeline"
Cohesion: 0.25
Nodes (7): Build, Data sources, Load into Postgres, Publish, Reference data pipeline, Test, Update aircraft types

### Community 16 - "CodingKeys"
Cohesion: 0.07
Nodes (23): CodingKeys, displayName, homeAirport, id, username, ProfileDetails, ProfileUpdate, .nextTarget (+15 more)

### Community 18 - "SpottedResult"
Cohesion: 0.27
Nodes (5): History, firstTime, seenBefore, Place, SpottedResult

### Community 19 - "faa_aircraft_types.py"
Cohesion: 0.14
Nodes (12): choose_name(), _csv_rows(), generate(), InputError, _keyed(), main(), maker_name(), parse_order() (+4 more)

### Community 20 - "ReferenceDatabaseTests.swift"
Cohesion: 0.27
Nodes (13): anExactAirportCodeComesFirst(), anExactTypeCodeComesFirst(), database(), emptyOrSymbolOnlySearchesFindNothing(), findsAnAirportByID(), findsHyphenatedNamesHoweverTheyAreTyped(), findsTypesByMakerAndModel(), largeAirportsRankFirst() (+5 more)

### Community 21 - "WingspotApp"
Cohesion: 0.08
Nodes (24): CryptoKit, ReferenceDatabase, ReferenceDataError, checksumMismatch, downloadFailed, insecureURL, sizeMismatch, unsupportedSchema (+16 more)

### Community 22 - "SpottedCheckInView"
Cohesion: 0.17
Nodes (8): LocationProvider, NearestKey, SpottedCheckInView, .body, .canSave, .hasInput, .registration, .status

### Community 23 - "Registration"
Cohesion: 0.18
Nodes (14): AircraftTypeChoice, CheckInStore, SpottedDraft, .hasAircraft, aCheckInWithoutAircraftIsRejected(), aDifferentRegistrationIsANewSighting(), aSavedCheckInWaitsForSync(), aTypeOnlyCheckInCountsThatType() (+6 more)

### Community 24 - "Launch badges"
Cohesion: 0.05
Nodes (41): Aircraft types (8), Airports (9), Countries (6), Decisions, Dormant until the data exists, Hidden (3), How badges work, Later, when the data exists (+33 more)

### Community 25 - "WingspotCore"
Cohesion: 0.23
Nodes (6): Account, Persistence, ReferenceData, SwiftData, SwiftUI, WingspotCore

### Community 26 - "GeoCoordinate"
Cohesion: 0.17
Nodes (8): GeoCoordinate, GreatCircle, DistanceVector, .testDescription, DistanceVectors, GreatCircleTests, Point, .coordinate

### Community 27 - "String"
Cohesion: 0.12
Nodes (6): ProfileRow, String, .droppingLeadingZeros, SearchQuery, RealSnapshotTests, NationalityPrefix

### Community 28 - ".isPlausible"
Cohesion: 0.20
Nodes (4): EmailAddress, Username, ProfileRulesTests, .normalizedUsername

### Community 29 - "Foundation"
Cohesion: 0.13
Nodes (7): Foundation, TestVectors, TestVectors, Observation, OSLog, PDFKit, Supabase

### Community 30 - "UserProgress"
Cohesion: 0.12
Nodes (16): ProgressSource, CheckInError, missingAircraft, answer(), BadgeStoreTests, FakeSource, iso(), makeContext() (+8 more)

### Community 31 - "ReferenceSearchView"
Cohesion: 0.19
Nodes (8): AirportSearchView, .body, ReferenceSearchView, .body, .placeholder, TypeSearchView, .body, .form

### Community 32 - "RootView"
Cohesion: 0.18
Nodes (9): AppTab, badges, checkIn, explore, feed, profile, RootView, .isSetupPresented (+1 more)

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

### Community 37 - "project.yml"
Cohesion: 0.20
Nodes (9): targets, name, config, schemes, Wingspot, settings, targets, build (+1 more)

### Community 38 - "CheckInKind"
Cohesion: 0.20
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

### Community 42 - "Airport"
Cohesion: 0.19
Nodes (5): AircraftType, .id, .name, Airport, .code

### Community 43 - "ProfileDetailsView"
Cohesion: 0.25
Nodes (7): AirportKey, ProfileDetailsView, .body, ProfileScreen, .body, .profileMissing, .signedOut

### Community 44 - "Wingspot"
Cohesion: 0.20
Nodes (10): Debug, Release, package, Wingspot, configFiles, dependencies, platform, settings (+2 more)

### Community 45 - "CheckInResultView"
Cohesion: 0.22
Nodes (5): CheckInResultView, .body, .detail, .headline, .isFirstTime

### Community 46 - "Badge System"
Cohesion: 0.40
Nodes (5): Badge System, Core Loop (See, Check In, Reward, Social), Friends and Social Feed, User Level and XP, Wingspot App Concept

### Community 47 - "EmailSignInView"
Cohesion: 0.18
Nodes (5): EmailSignInView, .body, .form, OnboardingView, .body

### Community 49 - "BCBPError"
Cohesion: 0.11
Nodes (12): FieldScanner, Substring, .trimmed, BCBPError, .code, invalidField, invalidFormatCode, invalidLegCount (+4 more)

### Community 50 - "write_batches"
Cohesion: 0.13
Nodes (7): _airport_row(), InputError, _literal(), main(), _upsert(), write_batches(), PostgresImportTests

### Community 51 - "ReferenceDatabase.swift"
Cohesion: 0.22
Nodes (3): GRDB, Fixture, refusesAnUnsupportedSchema()

### Community 53 - "Equatable"
Cohesion: 0.06
Nodes (40): APIClient, APIError, unexpectedStatus, CheckInUploadItem, CheckInUploadResult, .isRejected, .isStored, CodingKeys (+32 more)

### Community 54 - "UUID"
Cohesion: 0.18
Nodes (6): BadgeAccount, BadgeAck, BadgeStore, Celebration, .id, UUID

### Community 55 - "Code Sharing Strategy (Native Codebases, Shared Contracts)"
Cohesion: 0.43
Nodes (6): Contracts Folder, contracts/test-vectors, Design Tokens (contracts/design-tokens.json), Kotlin Multiplatform (Later Option), OpenAPI Spec (contracts/openapi.yaml), Shared Test Vectors

### Community 57 - "BadgeProgress"
Cohesion: 0.15
Nodes (9): BadgeProgress, .isComplete, .isSingle, LocalizedText, textFollowsThePhonesLanguageAndFallsBackToEnglish(), .body, BadgeIcon, localized() (+1 more)

### Community 58 - "Rank"
Cohesion: 0.15
Nodes (12): Rank, ace, cadet, captain, chiefPilot, firstOfficer, legend, seniorCaptain (+4 more)

### Community 59 - ".body"
Cohesion: 0.20
Nodes (6): .body, CelebrationView, CheckInSheet, .body, PlaceholderScreen, .body

### Community 60 - "test"
Cohesion: 0.50
Nodes (4): package, config, targets, test

### Community 279 - "FakeServer"
Cohesion: 0.09
Nodes (20): CheckInOutbox, CheckInUploader, OutboxOutcome, finished, idle, retryLater, CheckInSyncCoordinator, CheckInOutboxTests (+12 more)

### Community 532 - "ProfileEditorView"
Cohesion: 0.18
Nodes (7): State, loading, signedIn, signedOut, ProfileEditorView, .airportLabel, .body

## Ambiguous Edges - Review These
- `Shared Deep Link Scheme` → `GET /v1/config`  [AMBIGUOUS]
  docs/CONCEPT.md · relation: conceptually_related_to

## Knowledge Gaps
- **144 isolated node(s):** `PDFKit`, `invalidEmail`, `invalidUsername`, `usernameTaken`, `invalidLink` (+139 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 394 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **11 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `String` to `Sendable`, `View`, `AccountStore`, `LocalCheckIn`, `CodingKeys`, `SpottedResult`, `ReferenceDatabaseTests.swift`, `WingspotApp`, `ProfileEditorView`, `Registration`, `FakeServer`, `SpottedCheckInView`, `GeoCoordinate`, `.isPlausible`, `Foundation`, `UserProgress`, `CheckInKind`, `Airport`, `ProfileDetailsView`, `CheckInResultView`, `EmailSignInView`, `BCBPError`, `ReferenceDatabase.swift`, `Equatable`, `UUID`, `BadgeProgress`, `.body`, `.color`?**
  _High betweenness centrality (0.188) - this node is a cross-community bridge._
- **Are the 16 inferred relationships involving `AccountStore` (e.g. with `.aBadLinkKeepsTheUserSignedOutAndReportsIt()` and `.aSignInLinkSignsInAndAsksForAUsername()`) actually correct?**
  _`AccountStore` has 16 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PDFKit`, `invalidEmail`, `invalidUsername` to the rest of the system?**
  _144 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `base` be split into smaller, more focused modules?**
  _Cohesion score 0.1111111111111111 - nodes in this community are weakly interconnected._
- **Why does `UUID` connect `UUID` to `.v7`, `AccountStore`, `LocalCheckIn`, `SpottedResult`, `Equatable`, `Registration`, `String`, `FakeServer`, `Foundation`?**
  _High betweenness centrality (0.044) - this node is a cross-community bridge._
- **Should `Sendable` be split into smaller, more focused modules?**
  _Cohesion score 0.13438735177865613 - nodes in this community are weakly interconnected._

### Low-confidence Hints
_AMBIGUOUS edges — the extractor was unsure. Verify before acting on these._

- **What is the exact relationship between `Shared Deep Link Scheme` and `GET /v1/config`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._