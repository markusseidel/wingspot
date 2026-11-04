# Graph Report - wingspot  (2026-11-04)

## Corpus Check
- 90 files · ~37,813 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 16 file(s) not represented in the graph (top: .csv 5, (none) 3, .xcstrings 2)

## Summary
- 928 nodes · 1770 edges · 51 communities (43 shown, 8 thin omitted)
- Extraction: 92% EXTRACTED · 8% INFERRED · 0% AMBIGUOUS · INFERRED: 142 edges (avg confidence: 0.83)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `23d89eb0`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- base
- Decodable
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
- AccountError
- .mcp.json
- .init
- faa_aircraft_types.py
- Foundation
- ReferenceDatabase
- CheckInResultView
- Sendable
- Build work
- String
- WingspotCore
- View
- .sendSignInLink
- SpottedCheckInView
- ProfileEditorView
- ReferenceSearchView
- Airport
- Cross-platform Contract Rules
- AircraftType
- Check-in Verification Levels
- Wingspot Repository
- Wingspot
- CheckInKind
- options
- packages
- Supabase
- .body
- Code Sharing Strategy (Native Codebases, Shared Contracts)
- Wingspot
- ProfileDetailsView
- Badge System
- .fts
- check-strings.sh
- RealSnapshotTests
- project.yml

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
10. `SpottedDraft` - 18 edges

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

## Communities (51 total, 8 thin omitted)

### Community 0 - "base"
Cohesion: 0.12
Nodes (17): ASSETCATALOG_COMPILER_APPICON_NAME, ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME, CODE_SIGN_STYLE, CURRENT_PROJECT_VERSION, GENERATE_INFOPLIST_FILE, INFOPLIST_FILE, INFOPLIST_KEY_CFBundleDisplayName, INFOPLIST_KEY_UIApplicationSceneManifest_Generation (+9 more)

### Community 1 - "Decodable"
Cohesion: 0.06
Nodes (26): BCBP, CodingKeys, displayName, homeAirport, id, username, ProfileDetails, ProfileRow (+18 more)

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
Cohesion: 0.08
Nodes (11): AccountBackend, AccountStore, .needsProfileSetup, .profile, UnconfiguredAccountBackend, Profile, .hasChosenUsername, SupabaseAccountBackend (+3 more)

### Community 6 - "http.ts"
Cohesion: 0.28
Nodes (16): invalid(), isOptionalText(), register(), unregister(), validate(), apiKey(), authenticate(), Authenticated (+8 more)

### Community 7 - "Airport Visit Check-in"
Cohesion: 0.40
Nodes (5): Airport Visit Check-in, Batch Mode Spotting Session, Flown Check-in, Spotted Check-in, Spotting Locations

### Community 8 - "build"
Cohesion: 0.07
Nodes (16): _airport(), build(), _curated_keywords(), InputError, _load_airports(), _load_types(), main(), _rows() (+8 more)

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

### Community 16 - "AccountError"
Cohesion: 0.05
Nodes (41): AccountError, invalidEmail, invalidLink, invalidUsername, notConfigured, offline, tooManyRequests, unknown (+33 more)

### Community 18 - ".init"
Cohesion: 0.14
Nodes (6): FieldScanner, Substring, .trimmed, BoardingPass, Leg, BCBPTests

### Community 19 - "faa_aircraft_types.py"
Cohesion: 0.09
Nodes (13): choose_name(), _csv_rows(), generate(), InputError, _keyed(), main(), maker_name(), parse_order() (+5 more)

### Community 20 - "Foundation"
Cohesion: 0.07
Nodes (24): CoreLocation, Foundation, GRDB, TestVectors, Fixture, anExactAirportCodeComesFirst(), anExactTypeCodeComesFirst(), database() (+16 more)

### Community 21 - "ReferenceDatabase"
Cohesion: 0.08
Nodes (24): CryptoKit, ReferenceDatabase, ReferenceDataError, checksumMismatch, downloadFailed, insecureURL, sizeMismatch, unsupportedSchema (+16 more)

### Community 22 - "CheckInResultView"
Cohesion: 0.22
Nodes (5): CheckInResultView, .body, .detail, .headline, .isFirstTime

### Community 23 - "Sendable"
Cohesion: 0.10
Nodes (22): AircraftTypeChoice, CheckInStore, History, firstTime, seenBefore, Place, SpottedDraft, .hasAircraft (+14 more)

### Community 24 - "Build work"
Cohesion: 0.08
Nodes (24): Before each milestone, Decisions, Milestones, Phase 1 plan: iOS MVP to first TestFlight, Accounts and services, After Phase 1, Backend, Before real users sign up (+16 more)

### Community 25 - "String"
Cohesion: 0.22
Nodes (3): String, .droppingLeadingZeros, NationalityPrefix

### Community 26 - "WingspotCore"
Cohesion: 0.18
Nodes (8): Account, Observation, OSLog, Persistence, ReferenceData, SwiftData, SwiftUI, WingspotCore

### Community 27 - "View"
Cohesion: 0.14
Nodes (7): SignInLinkAlert, View, EmailSignInView, .body, .form, OnboardingView, .body

### Community 28 - ".sendSignInLink"
Cohesion: 0.18
Nodes (4): EmailAddress, Username, ProfileRulesTests, .normalizedUsername

### Community 29 - "SpottedCheckInView"
Cohesion: 0.19
Nodes (7): NearestKey, SpottedCheckInView, .body, .canSave, .hasInput, .registration, .status

### Community 30 - "ProfileEditorView"
Cohesion: 0.18
Nodes (7): State, loading, signedIn, signedOut, ProfileEditorView, .airportLabel, .body

### Community 31 - "ReferenceSearchView"
Cohesion: 0.19
Nodes (8): AirportSearchView, .body, ReferenceSearchView, .body, .placeholder, TypeSearchView, .body, .form

### Community 33 - "Cross-platform Contract Rules"
Cohesion: 0.22
Nodes (10): Live and Historic ADS-B Data, Shared Deep Link Scheme, devices Table, entitlements Table, Flight Lookup Provider, GET /v1/config, GET /v1/me/entitlements, Unified Push Notification Model (+2 more)

### Community 34 - "AircraftType"
Cohesion: 0.40
Nodes (3): AircraftType, .id, .name

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

### Community 50 - "project.yml"
Cohesion: 0.50
Nodes (3): name, settings, targets

## Ambiguous Edges - Review These
- `Shared Deep Link Scheme` → `GET /v1/config`  [AMBIGUOUS]
  docs/CONCEPT.md · relation: conceptually_related_to

## Knowledge Gaps
- **93 isolated node(s):** `PDFKit`, `invalidEmail`, `invalidUsername`, `usernameTaken`, `invalidLink` (+88 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 303 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **8 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `String` to `Decodable`, `AccountStore`, `AccountError`, `.init`, `Foundation`, `ReferenceDatabase`, `CheckInResultView`, `Sendable`, `View`, `.sendSignInLink`, `SpottedCheckInView`, `ProfileEditorView`, `Airport`, `AircraftType`, `CheckInKind`, `.body`, `ProfileDetailsView`, `.fts`, `RealSnapshotTests`?**
  _High betweenness centrality (0.150) - this node is a cross-community bridge._
- **Are the 13 inferred relationships involving `AccountStore` (e.g. with `.aBadLinkKeepsTheUserSignedOutAndReportsIt()` and `.aSignInLinkSignsInAndAsksForAUsername()`) actually correct?**
  _`AccountStore` has 13 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PDFKit`, `invalidEmail`, `invalidUsername` to the rest of the system?**
  _93 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `base` be split into smaller, more focused modules?**
  _Cohesion score 0.11764705882352941 - nodes in this community are weakly interconnected._
- **Why does `Foundation` connect `Foundation` to `Decodable`, `AccountStore`, `.fts`, `AccountError`, `.init`, `ReferenceDatabase`, `Sendable`, `WingspotCore`, `.sendSignInLink`?**
  _High betweenness centrality (0.025) - this node is a cross-community bridge._
- **Should `Decodable` be split into smaller, more focused modules?**
  _Cohesion score 0.06028368794326241 - nodes in this community are weakly interconnected._

### Low-confidence Hints
_AMBIGUOUS edges — the extractor was unsure. Verify before acting on these._

- **What is the exact relationship between `Shared Deep Link Scheme` and `GET /v1/config`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._