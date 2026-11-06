# Graph Report - wingspot  (2026-11-06)

## Corpus Check
- 114 files · ~59,133 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 18 file(s) not represented in the graph (top: .csv 5, (none) 3, .xcstrings 2)

## Summary
- 1251 nodes · 2695 edges · 62 communities (52 shown, 10 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 270 edges (avg confidence: 0.84)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `f1317d84`
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
- AccountError
- ios.yml
- BuildRefdataTests
- PackageDescription
- steps
- contracts.yml
- Reference data pipeline
- CLAUDE.md
- build_refdata.py
- .mcp.json
- CheckInUploadResult
- faa_aircraft_types.py
- GeoCoordinate
- WingspotApp
- SpottedCheckInView
- Registration
- Launch badges
- Foundation
- Equatable
- String
- APIClientTests.swift
- .list
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
- Leg
- ProfileDetailsView
- Wingspot
- OutboxOutcome
- Badge System
- EmailSignInView
- check-strings.sh
- BCBPError
- write_batches
- NetworkMonitor
- FaaAircraftTypesTests
- CodingKeys
- project.yml
- Code Sharing Strategy (Native Codebases, Shared Contracts)
- entitlements
- BadgeProgress
- .body
- AppKit
- FakeServer
- ProfileEditorView

## God Nodes (most connected - your core abstractions)
1. `AccountStore` - 42 edges
2. `FakeBackend` - 38 edges
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
- `.body` --calls--> `Rank`  [INFERRED]
  ios/Wingspot/Features/Badges/BadgesScreen.swift → ios/Packages/WingspotCore/Sources/WingspotCore/Progress.swift
- `.body` --calls--> `SpottedCheckInView`  [INFERRED]
  ios/Wingspot/Features/CheckIn/CheckInSheet.swift → ios/Wingspot/Features/CheckIn/SpottedCheckInView.swift
- `Android App (Kotlin / Jetpack Compose)` --conceptually_related_to--> `Android Project Structure`  [INFERRED]
  android/README.md → docs/CONCEPT.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Cross-platform Pro Entitlement** — docs_concept_wingspot_pro, docs_concept_entitlements_table, docs_concept_get_v1_me_entitlements, docs_concept_cross_platform_contract_rules [EXTRACTED 1.00]
- **Offline Check-in Sync Flow** — docs_concept_outbox_sync, docs_concept_post_v1_checkins, docs_concept_checkins_table, docs_concept_badge_engine, docs_concept_client_badge_predictor [EXTRACTED 1.00]
- **Shared Contract Artifacts** — contracts_readme_contracts, docs_concept_openapi_spec, docs_concept_shared_test_vectors, docs_concept_design_tokens, docs_concept_on_device_database [EXTRACTED 1.00]

## Communities (62 total, 10 thin omitted)

### Community 0 - "base"
Cohesion: 0.11
Nodes (18): ASSETCATALOG_COMPILER_APPICON_NAME, ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME, CODE_SIGN_STYLE, CURRENT_PROJECT_VERSION, DEVELOPMENT_TEAM, GENERATE_INFOPLIST_FILE, INFOPLIST_FILE, INFOPLIST_KEY_CFBundleDisplayName (+10 more)

### Community 1 - "Sendable"
Cohesion: 0.14
Nodes (15): BCBP, BCBPVector, .testDescription, BCBPVectors, Expected, Leg, DistanceVector, .testDescription (+7 more)

### Community 2 - "View"
Cohesion: 0.18
Nodes (7): SignInLinkAlert, View, BadgeRow, .body, BadgeIcon, CelebrationView, .body

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

### Community 8 - "AccountError"
Cohesion: 0.07
Nodes (19): CryptoKit, AccountError, appleUnavailable, invalidEmail, invalidLink, invalidUsername, notConfigured, offline (+11 more)

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

### Community 16 - "build_refdata.py"
Cohesion: 0.18
Nodes (6): _airport(), _curated_keywords(), InputError, _load_airports(), _load_types(), _rows()

### Community 18 - "CheckInUploadResult"
Cohesion: 0.17
Nodes (6): CheckInUploadItem, CheckInUploadResult, .isRejected, .isStored, uploadSendsTheContractShapeWithTheToken(), APICheckInUploader

### Community 19 - "faa_aircraft_types.py"
Cohesion: 0.15
Nodes (12): choose_name(), _csv_rows(), generate(), InputError, _keyed(), main(), maker_name(), parse_order() (+4 more)

### Community 20 - "GeoCoordinate"
Cohesion: 0.10
Nodes (19): CoreLocation, anExactAirportCodeComesFirst(), anExactTypeCodeComesFirst(), database(), emptyOrSymbolOnlySearchesFindNothing(), findsAnAirportByID(), findsHyphenatedNamesHoweverTheyAreTyped(), findsTypesByMakerAndModel() (+11 more)

### Community 21 - "WingspotApp"
Cohesion: 0.08
Nodes (23): ReferenceDatabase, ReferenceDataError, checksumMismatch, downloadFailed, insecureURL, sizeMismatch, unsupportedSchema, ReferenceDataStore (+15 more)

### Community 22 - "SpottedCheckInView"
Cohesion: 0.11
Nodes (17): AircraftType, .id, .name, Airport, .code, AirportSearchView, .body, TypeSearchView (+9 more)

### Community 23 - "Registration"
Cohesion: 0.08
Nodes (24): AircraftTypeChoice, CheckInStore, History, firstTime, seenBefore, Place, SpottedDraft, .hasAircraft (+16 more)

### Community 24 - "Launch badges"
Cohesion: 0.05
Nodes (41): Aircraft types (8), Airports (9), Countries (6), Decisions, Dormant until the data exists, Hidden (3), How badges work, Later, when the data exists (+33 more)

### Community 25 - "Foundation"
Cohesion: 0.05
Nodes (29): Account, AuthenticationServices, Foundation, GRDB, TestVectors, LocalCheckIn, SyncState, pending (+21 more)

### Community 26 - "Equatable"
Cohesion: 0.24
Nodes (7): APIClient, APIError, unexpectedStatus, MinimumVersion, RefdataManifest, RemoteConfig, configRequestsTheContractPath()

### Community 27 - "String"
Cohesion: 0.05
Nodes (18): EmailAddress, Username, ProfileRulesTests, FieldScanner, String, .droppingLeadingZeros, Substring, .trimmed (+10 more)

### Community 28 - "APIClientTests.swift"
Cohesion: 0.30
Nodes (10): anUploadAnswerWithNewTopLevelFieldsStillDecodes(), client(), configDecodesTheContractShape(), configIgnoresUnknownFields(), manifestDecodesTheContractShape(), manifestServerErrorsThrow(), noPublishedSnapshotIsNotAnError(), progressFailsOnAnyStatusButOK() (+2 more)

### Community 30 - "UserProgress"
Cohesion: 0.16
Nodes (10): answer(), BadgeStoreTests, FakeSource, iso(), makeContext(), store(), UserProgress, .levelFraction (+2 more)

### Community 31 - "ReferenceSearchView"
Cohesion: 0.32
Nodes (3): ReferenceSearchView, .body, .placeholder

### Community 32 - "RootView"
Cohesion: 0.18
Nodes (9): AppTab, badges, checkIn, explore, feed, profile, RootView, .isSetupPresented (+1 more)

### Community 33 - "Cross-platform Contract Rules"
Cohesion: 0.22
Nodes (10): Live and Historic ADS-B Data, Shared Deep Link Scheme, devices Table, entitlements Table, Flight Lookup Provider, GET /v1/config, GET /v1/me/entitlements, Unified Push Notification Model (+2 more)

### Community 34 - "build"
Cohesion: 0.16
Nodes (3): build(), main(), InvalidInputTests

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
Cohesion: 0.33
Nodes (5): AirportKey, ProfileDetailsView, .body, LevelHeader, .body

### Community 44 - "Wingspot"
Cohesion: 0.20
Nodes (10): Debug, Release, package, Wingspot, configFiles, dependencies, platform, settings (+2 more)

### Community 45 - "OutboxOutcome"
Cohesion: 0.40
Nodes (4): OutboxOutcome, finished, idle, retryLater

### Community 46 - "Badge System"
Cohesion: 0.40
Nodes (5): Badge System, Core Loop (See, Check In, Reward, Social), Friends and Social Feed, User Level and XP, Wingspot App Concept

### Community 47 - "EmailSignInView"
Cohesion: 0.13
Nodes (10): AppleSignInButton, EmailSignInView, .body, .form, OnboardingView, .body, ProfileScreen, .body (+2 more)

### Community 49 - "BCBPError"
Cohesion: 0.16
Nodes (8): BCBPError, .code, invalidField, invalidFormatCode, invalidLegCount, truncated, BoardingPass, BCBPTests

### Community 50 - "write_batches"
Cohesion: 0.16
Nodes (7): _airport_row(), InputError, _literal(), main(), _upsert(), write_batches(), PostgresImportTests

### Community 53 - "CodingKeys"
Cohesion: 0.07
Nodes (26): CodingKeys, displayName, homeAirport, id, username, ProfileDetails, ProfileRow, ProfileUpdate (+18 more)

### Community 54 - "project.yml"
Cohesion: 0.50
Nodes (3): name, settings, targets

### Community 55 - "Code Sharing Strategy (Native Codebases, Shared Contracts)"
Cohesion: 0.43
Nodes (6): Contracts Folder, contracts/test-vectors, Design Tokens (contracts/design-tokens.json), Kotlin Multiplatform (Later Option), OpenAPI Spec (contracts/openapi.yaml), Shared Test Vectors

### Community 56 - "entitlements"
Cohesion: 0.50
Nodes (4): path, properties, com.apple.developer.applesignin, entitlements

### Community 57 - "BadgeProgress"
Cohesion: 0.05
Nodes (35): BadgeProgress, .isComplete, .isSingle, .nextTarget, CodingKeys, badges, category, description (+27 more)

### Community 59 - ".body"
Cohesion: 0.22
Nodes (5): .body, CheckInSheet, .body, PlaceholderScreen, .body

### Community 279 - "FakeServer"
Cohesion: 0.10
Nodes (16): CheckInOutbox, CheckInUploader, CheckInSyncCoordinator, CheckInOutboxTests, CheckInSyncCoordinatorTests, FakeServer, Fault, loseAnswer (+8 more)

### Community 532 - "ProfileEditorView"
Cohesion: 0.28
Nodes (3): ProfileEditorView, .airportLabel, .body

## Ambiguous Edges - Review These
- `Shared Deep Link Scheme` → `GET /v1/config`  [AMBIGUOUS]
  docs/CONCEPT.md · relation: conceptually_related_to

## Knowledge Gaps
- **145 isolated node(s):** `PDFKit`, `invalidEmail`, `invalidUsername`, `usernameTaken`, `invalidLink` (+140 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 400 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **10 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `String` to `Sendable`, `UUID`, `AccountError`, `CheckInUploadResult`, `GeoCoordinate`, `WingspotApp`, `SpottedCheckInView`, `Registration`, `FakeServer`, `Foundation`, `Equatable`, `ProfileEditorView`, `APIClientTests.swift`, `.list`, `UserProgress`, `CheckInKind`, `Leg`, `ProfileDetailsView`, `EmailSignInView`, `BCBPError`, `CodingKeys`, `BadgeProgress`, `.body`?**
  _High betweenness centrality (0.181) - this node is a cross-community bridge._
- **Are the 19 inferred relationships involving `AccountStore` (e.g. with `.aBadLinkKeepsTheUserSignedOutAndReportsIt()` and `.aFailedAppleSignInChangesNothing()`) actually correct?**
  _`AccountStore` has 19 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PDFKit`, `invalidEmail`, `invalidUsername` to the rest of the system?**
  _145 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `base` be split into smaller, more focused modules?**
  _Cohesion score 0.1111111111111111 - nodes in this community are weakly interconnected._
- **Why does `UUID` connect `UUID` to `CheckInUploadResult`, `CodingKeys`, `Registration`, `Foundation`, `String`, `FakeServer`?**
  _High betweenness centrality (0.043) - this node is a cross-community bridge._
- **Should `Sendable` be split into smaller, more focused modules?**
  _Cohesion score 0.14 - nodes in this community are weakly interconnected._

### Low-confidence Hints
_AMBIGUOUS edges — the extractor was unsure. Verify before acting on these._

- **What is the exact relationship between `Shared Deep Link Scheme` and `GET /v1/config`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._