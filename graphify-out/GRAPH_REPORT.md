# Graph Report - wingspot  (2026-11-04)

## Corpus Check
- Corpus is ~12,105 words - fits in a single context window. You may not need a graph.

## Summary
- 251 nodes · 393 edges · 12 communities (9 shown, 3 thin omitted)
- Extraction: 92% EXTRACTED · 8% INFERRED · 0% AMBIGUOUS · INFERRED: 31 edges (avg confidence: 0.9)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- iOS Project Configuration
- BCBP Parser Internals
- App Shell and Navigation
- Product Features and Contracts
- Backend Data and Architecture
- Test Vectors and Decoding
- Registration Normalization
- Check-In Kind Model
- Great Circle Distance
- BCBP Parser Tests
- Check-In Modes
- Swift Package Manifests

## God Nodes (most connected - your core abstractions)
1. `base` - 15 edges
2. `Registration` - 12 edges
3. `DistanceVector` - 12 edges
4. `CheckInKind` - 11 edges
5. `BCBPError` - 10 edges
6. `GeoCoordinate` - 10 edges
7. `SpottedCheckInView` - 10 edges
8. `BoardingPass` - 9 edges
9. `BCBPVector` - 9 edges
10. `Leg` - 8 edges

## Surprising Connections (you probably didn't know these)
- `BCBP Swift Package` --implements--> `BCBP Parser`  [INFERRED]
  README.md → docs/CONCEPT.md
- `contracts/test-vectors` --implements--> `Shared Test Vectors`  [INFERRED]
  contracts/README.md → docs/CONCEPT.md
- `Wingspot Repository` --references--> `Supabase Backend Project`  [EXTRACTED]
  README.md → backend/README.md
- `Wingspot Repository` --implements--> `Monorepo Layout`  [INFERRED]
  README.md → docs/CONCEPT.md
- `Wingspot Repository` --references--> `Wingspot App Concept`  [EXTRACTED]
  README.md → docs/CONCEPT.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Offline Check-in Sync Flow** — docs_concept_outbox_sync, docs_concept_post_v1_checkins, docs_concept_checkins_table, docs_concept_badge_engine, docs_concept_client_badge_predictor [EXTRACTED 1.00]
- **Shared Contract Artifacts** — contracts_readme_contracts, docs_concept_openapi_spec, docs_concept_shared_test_vectors, docs_concept_design_tokens, docs_concept_on_device_database [EXTRACTED 1.00]
- **Cross-platform Pro Entitlement** — docs_concept_wingspot_pro, docs_concept_entitlements_table, docs_concept_get_v1_me_entitlements, docs_concept_cross_platform_contract_rules [EXTRACTED 1.00]

## Communities (12 total, 3 thin omitted)

### Community 0 - "iOS Project Configuration"
Cohesion: 0.05
Nodes (44): ASSETCATALOG_COMPILER_APPICON_NAME, ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME, CODE_SIGN_STYLE, CURRENT_PROJECT_VERSION, GENERATE_INFOPLIST_FILE, INFOPLIST_KEY_CFBundleDisplayName, INFOPLIST_KEY_UIApplicationSceneManifest_Generation, INFOPLIST_KEY_UILaunchScreen_Generation (+36 more)

### Community 1 - "BCBP Parser Internals"
Cohesion: 0.10
Nodes (16): Foundation, FieldScanner, String, .droppingLeadingZeros, Substring, .trimmed, BCBPError, .code (+8 more)

### Community 2 - "App Shell and Navigation"
Cohesion: 0.08
Nodes (21): AppTab, badges, checkIn, explore, feed, profile, RootView, .body (+13 more)

### Community 3 - "Product Features and Contracts"
Cohesion: 0.10
Nodes (28): Android App (Kotlin / Jetpack Compose), Contracts Folder, contracts/test-vectors, Android Project Structure, Badge System, badges Table, BCBP Parser, Boarding Pass Scan (+20 more)

### Community 4 - "Backend Data and Architecture"
Cohesion: 0.09
Nodes (27): refdata-pipeline, Supabase Backend Project, Live and Historic ADS-B Data, aircraft Table, airports Table, Anti-cheat Rules, checkins Table, CloudKit (Ruled Out) (+19 more)

### Community 5 - "Test Vectors and Decoding"
Cohesion: 0.14
Nodes (16): BCBP, BCBPVector, .testDescription, BCBPVectors, Expected, Leg, DistanceVector, .testDescription (+8 more)

### Community 6 - "Registration Normalization"
Cohesion: 0.16
Nodes (4): NationalityPrefix, Registration, .description, RegistrationTests

### Community 7 - "Check-In Kind Model"
Cohesion: 0.20
Nodes (8): CheckInKind, airport, flown, .id, spotted, .subtitle, .systemImage, .title

### Community 10 - "Check-In Modes"
Cohesion: 0.40
Nodes (5): Airport Visit Check-in, Batch Mode Spotting Session, Flown Check-in, Spotted Check-in, Spotting Locations

## Ambiguous Edges - Review These
- `Shared Deep Link Scheme` → `GET /v1/config`  [AMBIGUOUS]
  docs/CONCEPT.md · relation: conceptually_related_to

## Knowledge Gaps
- **39 isolated node(s):** `.trimmed`, `.droppingLeadingZeros`, `invalidFormatCode`, `invalidLegCount`, `truncated` (+34 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 84 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **3 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `BCBP Parser Internals` to `App Shell and Navigation`, `Test Vectors and Decoding`, `Registration Normalization`, `Check-In Kind Model`, `BCBP Parser Tests`?**
  _High betweenness centrality (0.162) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `Registration` (e.g. with `.exposesPrefix()` and `.normalizes()`) actually correct?**
  _`Registration` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `.trimmed`, `.droppingLeadingZeros`, `invalidFormatCode` to the rest of the system?**
  _39 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `iOS Project Configuration` be split into smaller, more focused modules?**
  _Cohesion score 0.046464646464646465 - nodes in this community are weakly interconnected._
- **Why does `Registration` connect `Registration Normalization` to `BCBP Parser Internals`, `App Shell and Navigation`, `Test Vectors and Decoding`?**
  _High betweenness centrality (0.049) - this node is a cross-community bridge._
- **Should `BCBP Parser Internals` be split into smaller, more focused modules?**
  _Cohesion score 0.09841269841269841 - nodes in this community are weakly interconnected._

### Low-confidence Hints
_AMBIGUOUS edges — the extractor was unsure. Verify before acting on these._

- **What is the exact relationship between `Shared Deep Link Scheme` and `GET /v1/config`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._

> Token note: semantic extraction used one subagent at 106,892 total tokens. The harness reports no input/output split, so the token fields above read 0.
