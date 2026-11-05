# Graph Report - wingspot  (2026-11-05)

## Corpus Check
- 91 files · ~38,563 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 17 file(s) not represented in the graph (top: .csv 5, (none) 3, .xcstrings 2)

## Summary
- 933 nodes · 1774 edges · 63 communities (53 shown, 10 thin omitted)
- Extraction: 92% EXTRACTED · 8% INFERRED · 0% AMBIGUOUS · INFERRED: 142 edges (avg confidence: 0.83)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `2d7044e4`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- base
- CodingKeys
- RootView
- Android Project Structure
- api.test.js
- AccountStore
- http.ts
- Airport Visit Check-in
- build
- ios.yml
- BuildRefdataTests
- Swift Package Manifests
- steps
- contracts.yml
- Reference data pipeline
- CLAUDE.md
- Equatable
- .mcp.json
- .init
- faa_aircraft_types.py
- GeoCoordinate
- ReferenceDatabase
- CheckInResultView
- Registration
- Build work
- String
- WingspotCore
- View
- .sendSignInLink
- Foundation
- ProfileEditorView
- ReferenceSearchView
- CodingKeys
- Cross-platform Contract Rules
- AircraftType
- Check-in Verification Levels
- Wingspot Repository
- project.yml
- CheckInKind
- options
- packages
- Supabase
- .body
- Code Sharing Strategy (Native Codebases, Shared Contracts)
- Wingspot
- ProfileDetailsView
- Badge System
- write_batches
- check-strings.sh
- AccountError
- OnboardingView
- build_refdata.py
- FaaAircraftTypesTests
- Sendable
- BCBPError
- .fts
- APIClientTests.swift
- SpottedResult
- DistanceVector
- LocalCheckIn
- test
- EmailSignInView
- AppKit

## God Nodes (most connected - your core abstractions)
1. `AccountStore` - 30 edges
2. `FakeBackend` - 29 edges
3. `Profile` - 27 edges
4. `GeoCoordinate` - 24 edges
5. `BuildRefdataTests` - 23 edges
6. `SpottedCheckInView` - 22 edges
7. `build()` - 20 edges
8. `Registration` - 20 edges
9. `AccountError` - 19 edges
10. `base` - 19 edges

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

## Communities (63 total, 10 thin omitted)

### Community 0 - "base"
Cohesion: 0.11
Nodes (18): ASSETCATALOG_COMPILER_APPICON_NAME, ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME, CODE_SIGN_STYLE, CURRENT_PROJECT_VERSION, DEVELOPMENT_TEAM, GENERATE_INFOPLIST_FILE, INFOPLIST_FILE, INFOPLIST_KEY_CFBundleDisplayName (+10 more)

### Community 1 - "CodingKeys"
Cohesion: 0.15
Nodes (9): CodingKeys, displayName, homeAirport, id, username, ProfileDetails, ProfileRow, ProfileUpdate (+1 more)

### Community 2 - "RootView"
Cohesion: 0.18
Nodes (9): AppTab, badges, checkIn, explore, feed, profile, RootView, .isSetupPresented (+1 more)

### Community 3 - "Android Project Structure"
Cohesion: 0.25
Nodes (7): Android App (Kotlin / Jetpack Compose), Android Project Structure, badges Table, Client Badge Progress Predictor, Offline Outbox Sync, POST /v1/checkins, Roadmap (iOS First, Android Second)

### Community 4 - "api.test.js"
Cohesion: 0.09
Nodes (17): ajv, assertError(), assertMatches(), spec, status, devDependencies, ajv@8.17.1, ajv-formats@3.0.1 (+9 more)

### Community 5 - "AccountStore"
Cohesion: 0.07
Nodes (15): AccountBackend, AccountStore, .needsProfileSetup, .profile, State, loading, signedIn, signedOut (+7 more)

### Community 6 - "http.ts"
Cohesion: 0.28
Nodes (16): invalid(), isOptionalText(), register(), unregister(), validate(), apiKey(), authenticate(), Authenticated (+8 more)

### Community 7 - "Airport Visit Check-in"
Cohesion: 0.40
Nodes (5): Airport Visit Check-in, Batch Mode Spotting Session, Flown Check-in, Spotted Check-in, Spotting Locations

### Community 8 - "build"
Cohesion: 0.14
Nodes (7): build(), _curated_keywords(), InputError, _load_airports(), _load_types(), _rows(), InvalidInputTests

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

### Community 16 - "Equatable"
Cohesion: 0.20
Nodes (7): APIClient, APIError, unexpectedStatus, MinimumVersion, RefdataManifest, RemoteConfig, configRequestsTheContractPath()

### Community 18 - ".init"
Cohesion: 0.14
Nodes (6): FieldScanner, Substring, .trimmed, BoardingPass, Leg, BCBPTests

### Community 19 - "faa_aircraft_types.py"
Cohesion: 0.15
Nodes (12): choose_name(), _csv_rows(), generate(), InputError, _keyed(), main(), maker_name(), parse_order() (+4 more)

### Community 20 - "GeoCoordinate"
Cohesion: 0.06
Nodes (27): CoreLocation, Airport, .code, anExactAirportCodeComesFirst(), anExactTypeCodeComesFirst(), database(), emptyOrSymbolOnlySearchesFindNothing(), findsAnAirportByID() (+19 more)

### Community 21 - "ReferenceDatabase"
Cohesion: 0.09
Nodes (24): CryptoKit, ReferenceDatabase, ReferenceDataError, checksumMismatch, downloadFailed, insecureURL, sizeMismatch, unsupportedSchema (+16 more)

### Community 22 - "CheckInResultView"
Cohesion: 0.22
Nodes (5): CheckInResultView, .body, .detail, .headline, .isFirstTime

### Community 23 - "Registration"
Cohesion: 0.17
Nodes (14): CheckInStore, SpottedDraft, .hasAircraft, aCheckInWithoutAircraftIsRejected(), aDifferentRegistrationIsANewSighting(), aSavedCheckInWaitsForSync(), aTypeOnlyCheckInCountsThatType(), checkInsSurviveReopeningTheStore() (+6 more)

### Community 24 - "Build work"
Cohesion: 0.07
Nodes (26): Before each milestone, Decisions, Milestones, Phase 1 plan: iOS MVP to first TestFlight, Accounts and services, After Phase 1, Backend, Before real users sign up (+18 more)

### Community 25 - "String"
Cohesion: 0.17
Nodes (5): String, .droppingLeadingZeros, AircraftTypeChoice, RealSnapshotTests, NationalityPrefix

### Community 26 - "WingspotCore"
Cohesion: 0.20
Nodes (8): Account, Observation, OSLog, Persistence, ReferenceData, SwiftData, SwiftUI, WingspotCore

### Community 28 - ".sendSignInLink"
Cohesion: 0.15
Nodes (4): EmailAddress, Username, ProfileRulesTests, .normalizedUsername

### Community 29 - "Foundation"
Cohesion: 0.17
Nodes (4): Foundation, TestVectors, TestVectors, PDFKit

### Community 30 - "ProfileEditorView"
Cohesion: 0.28
Nodes (3): ProfileEditorView, .airportLabel, .body

### Community 31 - "ReferenceSearchView"
Cohesion: 0.20
Nodes (8): AirportSearchView, .body, ReferenceSearchView, .body, .placeholder, TypeSearchView, .body, .form

### Community 32 - "CodingKeys"
Cohesion: 0.25
Nodes (8): CodingKeys, dataVersion, featureFlags, minimumVersion, schemaVersion, sha256, sizeBytes, url

### Community 33 - "Cross-platform Contract Rules"
Cohesion: 0.22
Nodes (10): Live and Historic ADS-B Data, Shared Deep Link Scheme, devices Table, entitlements Table, Flight Lookup Provider, GET /v1/config, GET /v1/me/entitlements, Unified Push Notification Model (+2 more)

### Community 34 - "AircraftType"
Cohesion: 0.20
Nodes (5): GRDB, AircraftType, .id, .name, Fixture

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

### Community 42 - ".body"
Cohesion: 0.25
Nodes (5): .body, CheckInSheet, .body, PlaceholderScreen, .body

### Community 43 - "Code Sharing Strategy (Native Codebases, Shared Contracts)"
Cohesion: 0.43
Nodes (6): Contracts Folder, contracts/test-vectors, Design Tokens (contracts/design-tokens.json), Kotlin Multiplatform (Later Option), OpenAPI Spec (contracts/openapi.yaml), Shared Test Vectors

### Community 44 - "Wingspot"
Cohesion: 0.20
Nodes (10): Debug, Release, package, Wingspot, configFiles, dependencies, platform, settings (+2 more)

### Community 45 - "ProfileDetailsView"
Cohesion: 0.25
Nodes (7): AirportKey, ProfileDetailsView, .body, ProfileScreen, .body, .profileMissing, .signedOut

### Community 46 - "Badge System"
Cohesion: 0.40
Nodes (5): Badge System, Core Loop (See, Check In, Reward, Social), Friends and Social Feed, User Level and XP, Wingspot App Concept

### Community 47 - "write_batches"
Cohesion: 0.18
Nodes (6): _airport_row(), InputError, _literal(), _upsert(), write_batches(), PostgresImportTests

### Community 49 - "AccountError"
Cohesion: 0.17
Nodes (10): AccountError, invalidEmail, invalidLink, invalidUsername, notConfigured, offline, tooManyRequests, unknown (+2 more)

### Community 51 - "build_refdata.py"
Cohesion: 0.21
Nodes (3): _airport(), main(), main()

### Community 53 - "Sendable"
Cohesion: 0.23
Nodes (9): BCBP, BCBPVector, .testDescription, BCBPVectors, Expected, Leg, RegistrationVector, .testDescription (+1 more)

### Community 54 - "BCBPError"
Cohesion: 0.18
Nodes (10): BCBPError, .code, invalidField, invalidFormatCode, invalidLegCount, truncated, CheckInError, missingAircraft (+2 more)

### Community 56 - "APIClientTests.swift"
Cohesion: 0.22
Nodes (7): client(), configDecodesTheContractShape(), configIgnoresUnknownFields(), manifestDecodesTheContractShape(), manifestServerErrorsThrow(), noPublishedSnapshotIsNotAnError(), Testing

### Community 57 - "SpottedResult"
Cohesion: 0.27
Nodes (5): History, firstTime, seenBefore, Place, SpottedResult

### Community 58 - "DistanceVector"
Cohesion: 0.29
Nodes (6): DistanceVector, .testDescription, DistanceVectors, GreatCircleTests, Point, .coordinate

### Community 59 - "LocalCheckIn"
Cohesion: 0.39
Nodes (3): LocalCheckIn, SyncState, pending

### Community 60 - "test"
Cohesion: 0.50
Nodes (4): package, config, targets, test

### Community 61 - "EmailSignInView"
Cohesion: 0.40
Nodes (3): EmailSignInView, .body, .form

## Ambiguous Edges - Review These
- `Shared Deep Link Scheme` → `GET /v1/config`  [AMBIGUOUS]
  docs/CONCEPT.md · relation: conceptually_related_to

## Knowledge Gaps
- **94 isolated node(s):** `PDFKit`, `invalidEmail`, `invalidUsername`, `usernameTaken`, `invalidLink` (+89 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 308 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **10 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `String` to `CodingKeys`, `AccountStore`, `Equatable`, `.init`, `GeoCoordinate`, `ReferenceDatabase`, `CheckInResultView`, `Registration`, `.sendSignInLink`, `Foundation`, `ProfileEditorView`, `CodingKeys`, `AircraftType`, `CheckInKind`, `.body`, `ProfileDetailsView`, `OnboardingView`, `Sendable`, `BCBPError`, `.fts`, `APIClientTests.swift`, `SpottedResult`, `DistanceVector`, `LocalCheckIn`, `EmailSignInView`?**
  _High betweenness centrality (0.148) - this node is a cross-community bridge._
- **Are the 13 inferred relationships involving `AccountStore` (e.g. with `.aBadLinkKeepsTheUserSignedOutAndReportsIt()` and `.aSignInLinkSignsInAndAsksForAUsername()`) actually correct?**
  _`AccountStore` has 13 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PDFKit`, `invalidEmail`, `invalidUsername` to the rest of the system?**
  _94 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `base` be split into smaller, more focused modules?**
  _Cohesion score 0.1111111111111111 - nodes in this community are weakly interconnected._
- **Why does `Foundation` connect `Foundation` to `CodingKeys`, `AircraftType`, `AccountStore`, `Equatable`, `.init`, `GeoCoordinate`, `Sendable`, `ReferenceDatabase`, `Registration`, `APIClientTests.swift`, `WingspotCore`, `LocalCheckIn`, `.sendSignInLink`?**
  _High betweenness centrality (0.025) - this node is a cross-community bridge._
- **Should `api.test.js` be split into smaller, more focused modules?**
  _Cohesion score 0.0873015873015873 - nodes in this community are weakly interconnected._

### Low-confidence Hints
_AMBIGUOUS edges — the extractor was unsure. Verify before acting on these._

- **What is the exact relationship between `Shared Deep Link Scheme` and `GET /v1/config`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._