# Graph Report - wingspot  (2026-11-04)

## Corpus Check
- 76 files · ~32,371 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 13 file(s) not represented in the graph (top: .csv 5, (none) 3, .toml 1)

## Summary
- 741 nodes · 1350 edges · 49 communities (40 shown, 9 thin omitted)
- Extraction: 94% EXTRACTED · 6% INFERRED · 0% AMBIGUOUS · INFERRED: 81 edges (avg confidence: 0.87)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `38842a12`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- base
- Sendable
- AppTab
- Android Project Structure
- api.test.js
- build_refdata.py
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
- RefdataManifest
- .mcp.json
- .init
- FaaAircraftTypesTests
- GeoCoordinate
- ReferenceDatabase
- SpottedResult
- Registration
- Build work
- String
- test_build_refdata.py
- Foundation
- write_batches
- SpottedCheckInView
- WingspotCore
- ReferenceSearchView
- build
- Cross-platform Contract Rules
- Airport
- Check-in Verification Levels
- Wingspot Repository
- Wingspot
- CheckInKind
- project.yml
- packages
- Supabase
- View
- Code Sharing Strategy (Native Codebases, Shared Contracts)
- Wingspot
- Leg
- Badge System
- RealSnapshotTests

## God Nodes (most connected - your core abstractions)
1. `GeoCoordinate` - 24 edges
2. `BuildRefdataTests` - 23 edges
3. `SpottedCheckInView` - 22 edges
4. `build()` - 20 edges
5. `Registration` - 20 edges
6. `SpottedDraft` - 18 edges
7. `Airport` - 16 edges
8. `base` - 16 edges
9. `write_batches()` - 15 edges
10. `FaaAircraftTypesTests` - 15 edges

## Surprising Connections (you probably didn't know these)
- `BCBP Swift Package` --implements--> `BCBP Parser`  [INFERRED]
  README.md → docs/CONCEPT.md
- `contracts/test-vectors` --implements--> `Shared Test Vectors`  [INFERRED]
  contracts/README.md → docs/CONCEPT.md
- `Wingspot Repository` --references--> `Wingspot App Concept`  [EXTRACTED]
  README.md → docs/CONCEPT.md
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

## Communities (49 total, 9 thin omitted)

### Community 0 - "base"
Cohesion: 0.13
Nodes (15): ASSETCATALOG_COMPILER_APPICON_NAME, ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME, CODE_SIGN_STYLE, CURRENT_PROJECT_VERSION, GENERATE_INFOPLIST_FILE, INFOPLIST_FILE, INFOPLIST_KEY_CFBundleDisplayName, INFOPLIST_KEY_UIApplicationSceneManifest_Generation (+7 more)

### Community 1 - "Sendable"
Cohesion: 0.10
Nodes (17): BCBP, BCBPTests, BCBPVector, .testDescription, BCBPVectors, Expected, Leg, DistanceVector (+9 more)

### Community 2 - "AppTab"
Cohesion: 0.22
Nodes (8): AppTab, badges, checkIn, explore, feed, profile, RootView, .tabSelection

### Community 3 - "Android Project Structure"
Cohesion: 0.25
Nodes (7): Android App (Kotlin / Jetpack Compose), Android Project Structure, badges Table, Client Badge Progress Predictor, Offline Outbox Sync, POST /v1/checkins, Roadmap (iOS First, Android Second)

### Community 4 - "api.test.js"
Cohesion: 0.09
Nodes (17): ajv, assertError(), assertMatches(), spec, status, devDependencies, ajv@8.17.1, ajv-formats@3.0.1 (+9 more)

### Community 5 - "build_refdata.py"
Cohesion: 0.27
Nodes (6): _airport(), _curated_keywords(), InputError, _load_airports(), _load_types(), _rows()

### Community 6 - "http.ts"
Cohesion: 0.28
Nodes (16): invalid(), isOptionalText(), register(), unregister(), validate(), apiKey(), authenticate(), Authenticated (+8 more)

### Community 7 - "Airport Visit Check-in"
Cohesion: 0.40
Nodes (5): Airport Visit Check-in, Batch Mode Spotting Session, Flown Check-in, Spotted Check-in, Spotting Locations

### Community 8 - "faa_aircraft_types.py"
Cohesion: 0.14
Nodes (12): choose_name(), _csv_rows(), generate(), InputError, _keyed(), main(), maker_name(), parse_order() (+4 more)

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

### Community 16 - "RefdataManifest"
Cohesion: 0.05
Nodes (32): BCBPError, .code, invalidField, invalidFormatCode, invalidLegCount, truncated, CheckInError, missingAircraft (+24 more)

### Community 18 - ".init"
Cohesion: 0.36
Nodes (4): FieldScanner, Substring, .trimmed, BoardingPass

### Community 20 - "GeoCoordinate"
Cohesion: 0.09
Nodes (18): CoreLocation, Fixture, anExactAirportCodeComesFirst(), anExactTypeCodeComesFirst(), database(), emptyOrSymbolOnlySearchesFindNothing(), findsHyphenatedNamesHoweverTheyAreTyped(), findsTypesByMakerAndModel() (+10 more)

### Community 21 - "ReferenceDatabase"
Cohesion: 0.13
Nodes (20): ReferenceDatabase, ReferenceDataError, checksumMismatch, downloadFailed, insecureURL, sizeMismatch, unsupportedSchema, ReferenceDataStore (+12 more)

### Community 22 - "SpottedResult"
Cohesion: 0.10
Nodes (13): History, firstTime, seenBefore, SpottedResult, LocalCheckIn, SyncState, pending, UUID (+5 more)

### Community 23 - "Registration"
Cohesion: 0.17
Nodes (14): CheckInStore, Place, SpottedDraft, .hasAircraft, aCheckInWithoutAircraftIsRejected(), aDifferentRegistrationIsANewSighting(), aSavedCheckInWaitsForSync(), aTypeOnlyCheckInCountsThatType() (+6 more)

### Community 24 - "Build work"
Cohesion: 0.11
Nodes (17): Accounts and services, After Phase 1, Backend, Before real users sign up, Build work, Decisions still open, Do next, Draft: email to ICAO (+9 more)

### Community 25 - "String"
Cohesion: 0.19
Nodes (5): String, .droppingLeadingZeros, AircraftTypeChoice, SearchQuery, NationalityPrefix

### Community 26 - "test_build_refdata.py"
Cohesion: 0.17
Nodes (4): main(), InputError, main(), _upsert()

### Community 27 - "Foundation"
Cohesion: 0.14
Nodes (6): CryptoKit, Foundation, GRDB, TestVectors, TestVectors, PDFKit

### Community 28 - "write_batches"
Cohesion: 0.26
Nodes (4): _airport_row(), _literal(), write_batches(), PostgresImportTests

### Community 29 - "SpottedCheckInView"
Cohesion: 0.19
Nodes (7): NearestKey, SpottedCheckInView, .body, .canSave, .hasInput, .registration, .status

### Community 30 - "WingspotCore"
Cohesion: 0.23
Nodes (8): Observation, OSLog, Persistence, ReferenceData, SwiftData, SwiftUI, Testing, WingspotCore

### Community 31 - "ReferenceSearchView"
Cohesion: 0.22
Nodes (8): AirportSearchView, .body, ReferenceSearchView, .body, .placeholder, TypeSearchView, .body, .form

### Community 33 - "Cross-platform Contract Rules"
Cohesion: 0.22
Nodes (10): Live and Historic ADS-B Data, Shared Deep Link Scheme, devices Table, entitlements Table, Flight Lookup Provider, GET /v1/config, GET /v1/me/entitlements, Unified Push Notification Model (+2 more)

### Community 34 - "Airport"
Cohesion: 0.24
Nodes (5): AircraftType, .id, .name, Airport, .code

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

### Community 39 - "project.yml"
Cohesion: 0.22
Nodes (8): iOS, name, options, bundleIdPrefix, createIntermediateGroups, deploymentTarget, settings, targets

### Community 40 - "packages"
Cohesion: 0.22
Nodes (9): path, packages, BCBP, Persistence, ReferenceData, WingspotCore, path, path (+1 more)

### Community 41 - "Supabase"
Cohesion: 0.25
Nodes (8): refdata-pipeline, Supabase Backend Project, CloudKit (Ruled Out), Firebase (Alternative), On-device SQLite Snapshot, Row Level Security, Safety, Privacy and Legal Rules, Supabase

### Community 42 - "View"
Cohesion: 0.29
Nodes (5): .body, CheckInSheet, .body, PlaceholderScreen, .body

### Community 43 - "Code Sharing Strategy (Native Codebases, Shared Contracts)"
Cohesion: 0.43
Nodes (6): Contracts Folder, contracts/test-vectors, Design Tokens (contracts/design-tokens.json), Kotlin Multiplatform (Later Option), OpenAPI Spec (contracts/openapi.yaml), Shared Test Vectors

### Community 44 - "Wingspot"
Cohesion: 0.29
Nodes (7): package, Wingspot, dependencies, platform, settings, sources, type

### Community 46 - "Badge System"
Cohesion: 0.40
Nodes (5): Badge System, Core Loop (See, Check In, Reward, Social), Friends and Social Feed, User Level and XP, Wingspot App Concept

## Ambiguous Edges - Review These
- `Shared Deep Link Scheme` → `GET /v1/config`  [AMBIGUOUS]
  docs/CONCEPT.md · relation: conceptually_related_to

## Knowledge Gaps
- **70 isolated node(s):** `PDFKit`, `.trimmed`, `.droppingLeadingZeros`, `invalidFormatCode`, `invalidLegCount` (+65 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 247 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **9 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `String` to `Sendable`, `Airport`, `CheckInKind`, `View`, `Leg`, `RealSnapshotTests`, `RefdataManifest`, `.init`, `GeoCoordinate`, `ReferenceDatabase`, `SpottedResult`, `Registration`, `Foundation`, `SpottedCheckInView`, `ReferenceSearchView`?**
  _High betweenness centrality (0.108) - this node is a cross-community bridge._
- **Are the 6 inferred relationships involving `GeoCoordinate` (e.g. with `aSavedCheckInWaitsForSync()` and `.suggestsFrankfurtOnTheAirportFence()`) actually correct?**
  _`GeoCoordinate` has 6 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PDFKit`, `.trimmed`, `.droppingLeadingZeros` to the rest of the system?**
  _70 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `base` be split into smaller, more focused modules?**
  _Cohesion score 0.13333333333333333 - nodes in this community are weakly interconnected._
- **Why does `Foundation` connect `Foundation` to `Sendable`, `RefdataManifest`, `UUIDv7Tests.swift`, `.init`, `GeoCoordinate`, `ReferenceDatabase`, `SpottedResult`, `Registration`, `String`, `WingspotCore`?**
  _High betweenness centrality (0.022) - this node is a cross-community bridge._
- **Should `Sendable` be split into smaller, more focused modules?**
  _Cohesion score 0.09803921568627451 - nodes in this community are weakly interconnected._

### Low-confidence Hints
_AMBIGUOUS edges — the extractor was unsure. Verify before acting on these._

- **What is the exact relationship between `Shared Deep Link Scheme` and `GET /v1/config`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._