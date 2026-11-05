# Graph Report - wingspot  (2026-11-05)

## Corpus Check
- 103 files · ~54,281 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 17 file(s) not represented in the graph (top: .csv 5, (none) 3, .xcstrings 2)

## Summary
- 1076 nodes · 2212 edges · 61 communities (49 shown, 12 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 215 edges (avg confidence: 0.84)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `94596720`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- base
- Sendable
- View
- Android Project Structure
- api.test.js
- UUID
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
- Equatable
- faa_aircraft_types.py
- ReferenceDatabaseTests.swift
- WingspotApp
- SpottedCheckInView
- Registration
- Launch badges
- WingspotCore
- GeoCoordinate
- AircraftType
- String
- Foundation
- .init
- ReferenceSearchView
- AppTab
- Cross-platform Contract Rules
- APIClientTests.swift
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
- Leg
- .makeDatabase
- FaaAircraftTypesTests
- CheckInUploadItem
- RealSnapshotTests
- Code Sharing Strategy (Native Codebases, Shared Contracts)
- LocationProvider.swift
- test
- AppKit
- FakeServer
- ProfileEditorView

## God Nodes (most connected - your core abstractions)
1. `AccountStore` - 36 edges
2. `FakeBackend` - 33 edges
3. `FakeServer` - 30 edges
4. `CheckInOutbox` - 28 edges
5. `Profile` - 27 edges
6. `save()` - 26 edges
7. `GeoCoordinate` - 24 edges
8. `BuildRefdataTests` - 23 edges
9. `SpottedCheckInView` - 23 edges
10. `makeContext()` - 21 edges

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

## Communities (61 total, 12 thin omitted)

### Community 0 - "base"
Cohesion: 0.11
Nodes (18): ASSETCATALOG_COMPILER_APPICON_NAME, ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME, CODE_SIGN_STYLE, CURRENT_PROJECT_VERSION, DEVELOPMENT_TEAM, GENERATE_INFOPLIST_FILE, INFOPLIST_FILE, INFOPLIST_KEY_CFBundleDisplayName (+10 more)

### Community 1 - "Sendable"
Cohesion: 0.13
Nodes (17): BCBP, ProfileRow, BCBPVector, .testDescription, BCBPVectors, Expected, Leg, MinimumVersion (+9 more)

### Community 2 - "View"
Cohesion: 0.09
Nodes (12): RootView, .body, .isSetupPresented, .tabSelection, SignInLinkAlert, View, OnboardingView, .body (+4 more)

### Community 3 - "Android Project Structure"
Cohesion: 0.25
Nodes (7): Android App (Kotlin / Jetpack Compose), Android Project Structure, badges Table, Client Badge Progress Predictor, Offline Outbox Sync, POST /v1/checkins, Roadmap (iOS First, Android Second)

### Community 4 - "api.test.js"
Cohesion: 0.09
Nodes (17): ajv, assertError(), assertMatches(), spec, status, devDependencies, ajv@8.17.1, ajv-formats@3.0.1 (+9 more)

### Community 5 - "UUID"
Cohesion: 0.05
Nodes (25): AccountBackend, AccountError, invalidEmail, invalidLink, invalidUsername, notConfigured, offline, tooManyRequests (+17 more)

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
Nodes (24): CodingKeys, displayName, homeAirport, id, username, ProfileDetails, ProfileUpdate, CodingKeys (+16 more)

### Community 18 - "Equatable"
Cohesion: 0.15
Nodes (12): State, loading, signedIn, signedOut, OutboxOutcome, finished, idle, retryLater (+4 more)

### Community 19 - "faa_aircraft_types.py"
Cohesion: 0.05
Nodes (28): _airport(), build(), _curated_keywords(), InputError, _load_airports(), _load_types(), main(), _rows() (+20 more)

### Community 20 - "ReferenceDatabaseTests.swift"
Cohesion: 0.27
Nodes (13): anExactAirportCodeComesFirst(), anExactTypeCodeComesFirst(), database(), emptyOrSymbolOnlySearchesFindNothing(), findsAnAirportByID(), findsHyphenatedNamesHoweverTheyAreTyped(), findsTypesByMakerAndModel(), largeAirportsRankFirst() (+5 more)

### Community 21 - "WingspotApp"
Cohesion: 0.08
Nodes (26): CryptoKit, ReferenceDatabase, ReferenceDataError, checksumMismatch, downloadFailed, insecureURL, sizeMismatch, unsupportedSchema (+18 more)

### Community 22 - "SpottedCheckInView"
Cohesion: 0.19
Nodes (7): NearestKey, SpottedCheckInView, .body, .canSave, .hasInput, .registration, .status

### Community 23 - "Registration"
Cohesion: 0.13
Nodes (15): AircraftTypeChoice, CheckInStore, SpottedDraft, .hasAircraft, aCheckInWithoutAircraftIsRejected(), aDifferentRegistrationIsANewSighting(), aSavedCheckInWaitsForSync(), aTypeOnlyCheckInCountsThatType() (+7 more)

### Community 24 - "Launch badges"
Cohesion: 0.05
Nodes (40): Aircraft types (8), Airports (9), Countries (6), Decisions, Dormant until the data exists, Hidden (3), How badges work, Later, when the data exists (+32 more)

### Community 25 - "WingspotCore"
Cohesion: 0.30
Nodes (6): Account, Persistence, ReferenceData, SwiftData, SwiftUI, WingspotCore

### Community 26 - "GeoCoordinate"
Cohesion: 0.27
Nodes (3): GeoCoordinate, GreatCircle, GreatCircleTests

### Community 27 - "AircraftType"
Cohesion: 0.22
Nodes (4): AircraftType, .id, .name, SearchQuery

### Community 28 - "String"
Cohesion: 0.12
Nodes (8): EmailAddress, Username, ProfileRulesTests, String, .droppingLeadingZeros, Place, NationalityPrefix, .normalizedUsername

### Community 29 - "Foundation"
Cohesion: 0.08
Nodes (10): Foundation, GRDB, TestVectors, Fixture, TestVectors, Observation, OSLog, PDFKit (+2 more)

### Community 30 - ".init"
Cohesion: 0.40
Nodes (3): FieldScanner, Substring, .trimmed

### Community 31 - "ReferenceSearchView"
Cohesion: 0.20
Nodes (8): AirportSearchView, .body, ReferenceSearchView, .body, .placeholder, TypeSearchView, .body, .form

### Community 32 - "AppTab"
Cohesion: 0.33
Nodes (6): AppTab, badges, checkIn, explore, feed, profile

### Community 33 - "Cross-platform Contract Rules"
Cohesion: 0.22
Nodes (10): Live and Historic ADS-B Data, Shared Deep Link Scheme, devices Table, entitlements Table, Flight Lookup Provider, GET /v1/config, GET /v1/me/entitlements, Unified Push Notification Model (+2 more)

### Community 34 - "APIClientTests.swift"
Cohesion: 0.36
Nodes (8): client(), configDecodesTheContractShape(), configIgnoresUnknownFields(), manifestDecodesTheContractShape(), manifestServerErrorsThrow(), noPublishedSnapshotIsNotAnError(), uploadFailsOnAnyStatusButOK(), uploadReadsRejectionsAndIgnoresUnknownFields()

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
Cohesion: 0.33
Nodes (3): EmailSignInView, .body, .form

### Community 49 - "BCBPError"
Cohesion: 0.16
Nodes (8): BCBPError, .code, invalidField, invalidFormatCode, invalidLegCount, truncated, BoardingPass, BCBPTests

### Community 53 - "CheckInUploadItem"
Cohesion: 0.12
Nodes (11): APIClient, APIError, unexpectedStatus, CheckInUploadItem, CheckInUploadResult, .isRejected, .isStored, RefdataManifest (+3 more)

### Community 55 - "Code Sharing Strategy (Native Codebases, Shared Contracts)"
Cohesion: 0.43
Nodes (6): Contracts Folder, contracts/test-vectors, Design Tokens (contracts/design-tokens.json), Kotlin Multiplatform (Later Option), OpenAPI Spec (contracts/openapi.yaml), Shared Test Vectors

### Community 60 - "test"
Cohesion: 0.50
Nodes (4): package, config, targets, test

### Community 279 - "FakeServer"
Cohesion: 0.10
Nodes (15): CheckInOutbox, CheckInUploader, CheckInSyncCoordinator, CheckInOutboxTests, CheckInSyncCoordinatorTests, FakeServer, Fault, loseAnswer (+7 more)

### Community 532 - "ProfileEditorView"
Cohesion: 0.28
Nodes (3): ProfileEditorView, .airportLabel, .body

## Ambiguous Edges - Review These
- `Shared Deep Link Scheme` → `GET /v1/config`  [AMBIGUOUS]
  docs/CONCEPT.md · relation: conceptually_related_to

## Knowledge Gaps
- **118 isolated node(s):** `PDFKit`, `invalidEmail`, `invalidUsername`, `usernameTaken`, `invalidLink` (+113 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 353 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **12 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `String` to `Sendable`, `View`, `UUID`, `LocalCheckIn`, `CodingKeys`, `Equatable`, `ReferenceDatabaseTests.swift`, `WingspotApp`, `ProfileEditorView`, `Registration`, `FakeServer`, `SpottedCheckInView`, `AircraftType`, `Foundation`, `.init`, `APIClientTests.swift`, `CheckInKind`, `Airport`, `ProfileDetailsView`, `CheckInResultView`, `EmailSignInView`, `BCBPError`, `Leg`, `.makeDatabase`, `CheckInUploadItem`, `RealSnapshotTests`?**
  _High betweenness centrality (0.156) - this node is a cross-community bridge._
- **Are the 16 inferred relationships involving `AccountStore` (e.g. with `.aBadLinkKeepsTheUserSignedOutAndReportsIt()` and `.aSignInLinkSignsInAndAsksForAUsername()`) actually correct?**
  _`AccountStore` has 16 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PDFKit`, `invalidEmail`, `invalidUsername` to the rest of the system?**
  _118 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `base` be split into smaller, more focused modules?**
  _Cohesion score 0.1111111111111111 - nodes in this community are weakly interconnected._
- **Why does `SpottedCheckInView` connect `SpottedCheckInView` to `View`, `Airport`, `Equatable`, `Registration`, `FakeServer`, `WingspotCore`, `GeoCoordinate`, `AircraftType`, `ReferenceSearchView`?**
  _High betweenness centrality (0.033) - this node is a cross-community bridge._
- **Should `Sendable` be split into smaller, more focused modules?**
  _Cohesion score 0.1339031339031339 - nodes in this community are weakly interconnected._

### Low-confidence Hints
_AMBIGUOUS edges — the extractor was unsure. Verify before acting on these._

- **What is the exact relationship between `Shared Deep Link Scheme` and `GET /v1/config`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._