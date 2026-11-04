# Graph Report - wingspot  (2026-11-04)

## Corpus Check
- 80 files · ~33,772 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 15 file(s) not represented in the graph (top: .csv 5, (none) 3, .xcstrings 2)

## Summary
- 758 nodes · 1365 edges · 49 communities (41 shown, 8 thin omitted)
- Extraction: 94% EXTRACTED · 6% INFERRED · 0% AMBIGUOUS · INFERRED: 81 edges (avg confidence: 0.87)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `84e5a12d`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- base
- Sendable
- AppTab
- Android Project Structure
- api.test.js
- BCBPError
- http.ts
- Airport Visit Check-in
- faa_aircraft_types.py
- ios.yml
- BuildRefdataTests
- Swift Package Manifests
- steps
- contracts.yml
- Reference data pipeline
- CLAUDE.md
- WingspotApp
- .mcp.json
- String
- FaaAircraftTypesTests
- GeoCoordinate
- ReferenceDatabase
- CheckInResultView
- Foundation
- Build work
- Registration
- CodingKeys
- RegistrationVector
- DistanceVector
- SpottedCheckInView
- SpottedResult
- ReferenceSearchView
- NationalityPrefix
- Cross-platform Contract Rules
- Airport
- Check-in Verification Levels
- Wingspot Repository
- project.yml
- CheckInKind
- options
- packages
- Supabase
- PlaceholderScreen
- Code Sharing Strategy (Native Codebases, Shared Contracts)
- Wingspot
- Leg
- Badge System
- test
- check-strings.sh

## God Nodes (most connected - your core abstractions)
1. `GeoCoordinate` - 24 edges
2. `BuildRefdataTests` - 23 edges
3. `SpottedCheckInView` - 22 edges
4. `build()` - 20 edges
5. `Registration` - 20 edges
6. `SpottedDraft` - 18 edges
7. `base` - 18 edges
8. `Airport` - 16 edges
9. `write_batches()` - 15 edges
10. `FaaAircraftTypesTests` - 15 edges

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

## Communities (49 total, 8 thin omitted)

### Community 0 - "base"
Cohesion: 0.12
Nodes (17): ASSETCATALOG_COMPILER_APPICON_NAME, ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME, CODE_SIGN_STYLE, CURRENT_PROJECT_VERSION, GENERATE_INFOPLIST_FILE, INFOPLIST_FILE, INFOPLIST_KEY_CFBundleDisplayName, INFOPLIST_KEY_UIApplicationSceneManifest_Generation (+9 more)

### Community 1 - "Sendable"
Cohesion: 0.21
Nodes (9): BCBP, BCBPVector, .testDescription, BCBPVectors, Expected, Leg, MinimumVersion, RefdataManifest (+1 more)

### Community 2 - "AppTab"
Cohesion: 0.22
Nodes (8): AppTab, badges, checkIn, explore, feed, profile, RootView, .tabSelection

### Community 3 - "Android Project Structure"
Cohesion: 0.25
Nodes (7): Android App (Kotlin / Jetpack Compose), Android Project Structure, badges Table, Client Badge Progress Predictor, Offline Outbox Sync, POST /v1/checkins, Roadmap (iOS First, Android Second)

### Community 4 - "api.test.js"
Cohesion: 0.09
Nodes (17): ajv, assertError(), assertMatches(), spec, status, devDependencies, ajv@8.17.1, ajv-formats@3.0.1 (+9 more)

### Community 5 - "BCBPError"
Cohesion: 0.16
Nodes (8): BCBPError, .code, invalidField, invalidFormatCode, invalidLegCount, truncated, BoardingPass, BCBPTests

### Community 6 - "http.ts"
Cohesion: 0.28
Nodes (16): invalid(), isOptionalText(), register(), unregister(), validate(), apiKey(), authenticate(), Authenticated (+8 more)

### Community 7 - "Airport Visit Check-in"
Cohesion: 0.40
Nodes (5): Airport Visit Check-in, Batch Mode Spotting Session, Flown Check-in, Spotted Check-in, Spotting Locations

### Community 8 - "faa_aircraft_types.py"
Cohesion: 0.05
Nodes (28): _airport(), build(), _curated_keywords(), InputError, _load_airports(), _load_types(), main(), _rows() (+20 more)

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

### Community 16 - "WingspotApp"
Cohesion: 0.09
Nodes (15): CheckInError, missingAircraft, APIClient, APIError, unexpectedStatus, client(), configDecodesTheContractShape(), configIgnoresUnknownFields() (+7 more)

### Community 18 - "String"
Cohesion: 0.36
Nodes (5): FieldScanner, String, .droppingLeadingZeros, Substring, .trimmed

### Community 20 - "GeoCoordinate"
Cohesion: 0.08
Nodes (19): CoreLocation, RealSnapshotTests, anExactAirportCodeComesFirst(), anExactTypeCodeComesFirst(), database(), emptyOrSymbolOnlySearchesFindNothing(), findsHyphenatedNamesHoweverTheyAreTyped(), findsTypesByMakerAndModel() (+11 more)

### Community 21 - "ReferenceDatabase"
Cohesion: 0.08
Nodes (22): CryptoKit, ReferenceDatabase, ReferenceDataError, checksumMismatch, downloadFailed, insecureURL, sizeMismatch, unsupportedSchema (+14 more)

### Community 22 - "CheckInResultView"
Cohesion: 0.22
Nodes (5): CheckInResultView, .body, .detail, .headline, .isFirstTime

### Community 23 - "Foundation"
Cohesion: 0.06
Nodes (26): Foundation, GRDB, TestVectors, CheckInStore, LocalCheckIn, SyncState, pending, aCheckInWithoutAircraftIsRejected() (+18 more)

### Community 24 - "Build work"
Cohesion: 0.08
Nodes (23): Before each milestone, Decisions, Milestones, Phase 1 plan: iOS MVP to first TestFlight, Accounts and services, After Phase 1, Backend, Before real users sign up (+15 more)

### Community 25 - "Registration"
Cohesion: 0.17
Nodes (7): AircraftTypeChoice, Place, SpottedDraft, .hasAircraft, checkInsSurviveReopeningTheStore(), Registration, .description

### Community 26 - "CodingKeys"
Cohesion: 0.22
Nodes (8): CodingKeys, dataVersion, featureFlags, minimumVersion, schemaVersion, sha256, sizeBytes, url

### Community 27 - "RegistrationVector"
Cohesion: 0.32
Nodes (4): RegistrationTests, RegistrationVector, .testDescription, RegistrationVectors

### Community 28 - "DistanceVector"
Cohesion: 0.36
Nodes (5): DistanceVector, .testDescription, DistanceVectors, Point, .coordinate

### Community 29 - "SpottedCheckInView"
Cohesion: 0.21
Nodes (6): SpottedCheckInView, .body, .canSave, .hasInput, .registration, .status

### Community 30 - "SpottedResult"
Cohesion: 0.43
Nodes (4): History, firstTime, seenBefore, SpottedResult

### Community 31 - "ReferenceSearchView"
Cohesion: 0.20
Nodes (8): AirportSearchView, .body, ReferenceSearchView, .body, .placeholder, TypeSearchView, .body, .form

### Community 33 - "Cross-platform Contract Rules"
Cohesion: 0.22
Nodes (10): Live and Historic ADS-B Data, Shared Deep Link Scheme, devices Table, entitlements Table, Flight Lookup Provider, GET /v1/config, GET /v1/me/entitlements, Unified Push Notification Model (+2 more)

### Community 34 - "Airport"
Cohesion: 0.24
Nodes (6): AircraftType, .id, .name, Airport, .code, NearestKey

### Community 35 - "Check-in Verification Levels"
Cohesion: 0.24
Nodes (9): aircraft Table, airports Table, Anti-cheat Rules, checkins Table, OpenSky Aircraft Database, OpenStreetMap Aerodrome Polygons, OurAirports Dataset, Reference Data (+1 more)

### Community 36 - "Wingspot Repository"
Cohesion: 0.27
Nodes (10): BCBP Parser, Boarding Pass Scan, IATA BCBP Barcode, iOS Project Structure, Monorepo Layout, WingspotCore Module, BCBP Swift Package, Wingspot Repository (+2 more)

### Community 37 - "project.yml"
Cohesion: 0.25
Nodes (7): name, config, schemes, Wingspot, settings, targets, run

### Community 38 - "CheckInKind"
Cohesion: 0.20
Nodes (8): CheckInKind, airport, flown, .id, spotted, .subtitle, .systemImage, .title

### Community 39 - "options"
Cohesion: 0.29
Nodes (7): iOS, options, bundleIdPrefix, createIntermediateGroups, deploymentTarget, developmentLanguage, knownRegions

### Community 40 - "packages"
Cohesion: 0.22
Nodes (9): path, packages, BCBP, Persistence, ReferenceData, WingspotCore, path, path (+1 more)

### Community 41 - "Supabase"
Cohesion: 0.25
Nodes (8): refdata-pipeline, Supabase Backend Project, CloudKit (Ruled Out), Firebase (Alternative), On-device SQLite Snapshot, Row Level Security, Safety, Privacy and Legal Rules, Supabase

### Community 42 - "PlaceholderScreen"
Cohesion: 0.25
Nodes (5): .body, CheckInSheet, .body, PlaceholderScreen, .body

### Community 43 - "Code Sharing Strategy (Native Codebases, Shared Contracts)"
Cohesion: 0.43
Nodes (6): Contracts Folder, contracts/test-vectors, Design Tokens (contracts/design-tokens.json), Kotlin Multiplatform (Later Option), OpenAPI Spec (contracts/openapi.yaml), Shared Test Vectors

### Community 44 - "Wingspot"
Cohesion: 0.22
Nodes (9): targets, package, Wingspot, build, dependencies, platform, settings, sources (+1 more)

### Community 46 - "Badge System"
Cohesion: 0.40
Nodes (5): Badge System, Core Loop (See, Check In, Reward, Social), Friends and Social Feed, User Level and XP, Wingspot App Concept

### Community 47 - "test"
Cohesion: 0.50
Nodes (4): package, config, targets, test

## Ambiguous Edges - Review These
- `Shared Deep Link Scheme` → `GET /v1/config`  [AMBIGUOUS]
  docs/CONCEPT.md · relation: conceptually_related_to

## Knowledge Gaps
- **70 isolated node(s):** `PDFKit`, `.trimmed`, `.droppingLeadingZeros`, `invalidFormatCode`, `invalidLegCount` (+65 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 261 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **8 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `String` to `NationalityPrefix`, `Sendable`, `Airport`, `BCBPError`, `CheckInKind`, `PlaceholderScreen`, `Leg`, `WingspotApp`, `GeoCoordinate`, `ReferenceDatabase`, `CheckInResultView`, `Foundation`, `Registration`, `CodingKeys`, `RegistrationVector`, `DistanceVector`, `SpottedCheckInView`, `SpottedResult`?**
  _High betweenness centrality (0.099) - this node is a cross-community bridge._
- **Are the 6 inferred relationships involving `GeoCoordinate` (e.g. with `aSavedCheckInWaitsForSync()` and `.suggestsFrankfurtOnTheAirportFence()`) actually correct?**
  _`GeoCoordinate` has 6 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PDFKit`, `.trimmed`, `.droppingLeadingZeros` to the rest of the system?**
  _70 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `base` be split into smaller, more focused modules?**
  _Cohesion score 0.11764705882352941 - nodes in this community are weakly interconnected._
- **Why does `Foundation` connect `Foundation` to `Sendable`, `BCBPError`, `WingspotApp`, `String`, `GeoCoordinate`, `ReferenceDatabase`?**
  _High betweenness centrality (0.021) - this node is a cross-community bridge._
- **Should `api.test.js` be split into smaller, more focused modules?**
  _Cohesion score 0.0873015873015873 - nodes in this community are weakly interconnected._

### Low-confidence Hints
_AMBIGUOUS edges — the extractor was unsure. Verify before acting on these._

- **What is the exact relationship between `Shared Deep Link Scheme` and `GET /v1/config`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._