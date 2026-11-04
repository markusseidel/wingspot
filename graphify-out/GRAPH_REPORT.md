# Graph Report - wingspot  (2026-11-04)

## Corpus Check
- 57 files · ~26,323 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 13 file(s) not represented in the graph (top: .csv 5, (none) 3, .toml 1)

## Summary
- 528 nodes · 860 edges · 21 communities (16 shown, 5 thin omitted)
- Extraction: 96% EXTRACTED · 4% INFERRED · 0% AMBIGUOUS · INFERRED: 32 edges (avg confidence: 0.89)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `d9aadaee`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- iOS Project Configuration
- String
- App Shell and Navigation
- Wingspot Repository
- api.test.js
- build
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
- Foundation
- .mcp.json
- .init
- FaaAircraftTypesTests
- GeoCoordinate

## God Nodes (most connected - your core abstractions)
1. `BuildRefdataTests` - 23 edges
2. `build()` - 20 edges
3. `base` - 16 edges
4. `write_batches()` - 15 edges
5. `FaaAircraftTypesTests` - 15 edges
6. `generate()` - 13 edges
7. `Registration` - 12 edges
8. `DistanceVector` - 12 edges
9. `CheckInKind` - 11 edges
10. `PostgresImportTests` - 10 edges

## Surprising Connections (you probably didn't know these)
- `BCBP Swift Package` --implements--> `BCBP Parser`  [INFERRED]
  README.md → docs/CONCEPT.md
- `contracts/test-vectors` --implements--> `Shared Test Vectors`  [INFERRED]
  contracts/README.md → docs/CONCEPT.md
- `Android App (Kotlin / Jetpack Compose)` --conceptually_related_to--> `Android Project Structure`  [INFERRED]
  android/README.md → docs/CONCEPT.md
- `Contracts Folder` --references--> `Design Tokens (contracts/design-tokens.json)`  [EXTRACTED]
  contracts/README.md → docs/CONCEPT.md
- `Wingspot Repository` --implements--> `Monorepo Layout`  [INFERRED]
  README.md → docs/CONCEPT.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Cross-platform Pro Entitlement** — docs_concept_wingspot_pro, docs_concept_entitlements_table, docs_concept_get_v1_me_entitlements, docs_concept_cross_platform_contract_rules [EXTRACTED 1.00]
- **Offline Check-in Sync Flow** — docs_concept_outbox_sync, docs_concept_post_v1_checkins, docs_concept_checkins_table, docs_concept_badge_engine, docs_concept_client_badge_predictor [EXTRACTED 1.00]
- **Shared Contract Artifacts** — contracts_readme_contracts, docs_concept_openapi_spec, docs_concept_shared_test_vectors, docs_concept_design_tokens, docs_concept_on_device_database [EXTRACTED 1.00]

## Communities (21 total, 5 thin omitted)

### Community 0 - "iOS Project Configuration"
Cohesion: 0.05
Nodes (45): ASSETCATALOG_COMPILER_APPICON_NAME, ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME, CODE_SIGN_STYLE, CURRENT_PROJECT_VERSION, GENERATE_INFOPLIST_FILE, INFOPLIST_FILE, INFOPLIST_KEY_CFBundleDisplayName, INFOPLIST_KEY_UIApplicationSceneManifest_Generation (+37 more)

### Community 1 - "String"
Cohesion: 0.06
Nodes (34): BCBP, String, .droppingLeadingZeros, BCBPError, .code, invalidField, invalidFormatCode, invalidLegCount (+26 more)

### Community 2 - "App Shell and Navigation"
Cohesion: 0.05
Nodes (30): AppTab, badges, checkIn, explore, feed, profile, RootView, .body (+22 more)

### Community 3 - "Wingspot Repository"
Cohesion: 0.05
Nodes (55): Android App (Kotlin / Jetpack Compose), refdata-pipeline, Supabase Backend Project, Contracts Folder, contracts/test-vectors, Live and Historic ADS-B Data, aircraft Table, airports Table (+47 more)

### Community 4 - "api.test.js"
Cohesion: 0.09
Nodes (17): ajv, assertError(), assertMatches(), spec, status, devDependencies, ajv@8.17.1, ajv-formats@3.0.1 (+9 more)

### Community 5 - "build"
Cohesion: 0.13
Nodes (8): _airport(), build(), _curated_keywords(), InputError, _load_airports(), _load_types(), _rows(), InvalidInputTests

### Community 6 - "http.ts"
Cohesion: 0.28
Nodes (16): invalid(), isOptionalText(), register(), unregister(), validate(), apiKey(), authenticate(), Authenticated (+8 more)

### Community 7 - "Airport Visit Check-in"
Cohesion: 0.40
Nodes (5): Airport Visit Check-in, Batch Mode Spotting Session, Flown Check-in, Spotted Check-in, Spotting Locations

### Community 8 - "faa_aircraft_types.py"
Cohesion: 0.07
Nodes (20): main(), choose_name(), _csv_rows(), generate(), InputError, _keyed(), main(), maker_name() (+12 more)

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

### Community 16 - "Foundation"
Cohesion: 0.10
Nodes (11): Foundation, TestVectors, APIClient, APIError, unexpectedStatus, client(), configDecodesTheContractShape(), configIgnoresUnknownFields() (+3 more)

### Community 18 - ".init"
Cohesion: 0.23
Nodes (4): FieldScanner, Substring, .trimmed, Leg

### Community 20 - "GeoCoordinate"
Cohesion: 0.27
Nodes (3): GeoCoordinate, GreatCircle, GreatCircleTests

## Ambiguous Edges - Review These
- `Shared Deep Link Scheme` → `GET /v1/config`  [AMBIGUOUS]
  docs/CONCEPT.md · relation: conceptually_related_to

## Knowledge Gaps
- **44 isolated node(s):** `PDFKit`, `.trimmed`, `.droppingLeadingZeros`, `invalidFormatCode`, `invalidLegCount` (+39 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 182 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **5 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `String` to `Foundation`, `.init`, `App Shell and Navigation`?**
  _High betweenness centrality (0.048) - this node is a cross-community bridge._
- **What connects `PDFKit`, `.trimmed`, `.droppingLeadingZeros` to the rest of the system?**
  _44 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `iOS Project Configuration` be split into smaller, more focused modules?**
  _Cohesion score 0.04541062801932367 - nodes in this community are weakly interconnected._
- **Why does `BuildRefdataTests` connect `BuildRefdataTests` to `faa_aircraft_types.py`, `build`?**
  _High betweenness centrality (0.016) - this node is a cross-community bridge._
- **Should `String` be split into smaller, more focused modules?**
  _Cohesion score 0.06120218579234973 - nodes in this community are weakly interconnected._
- **Why does `Registration` connect `String` to `Foundation`, `App Shell and Navigation`, `GeoCoordinate`?**
  _High betweenness centrality (0.013) - this node is a cross-community bridge._

### Low-confidence Hints
_AMBIGUOUS edges — the extractor was unsure. Verify before acting on these._

- **What is the exact relationship between `Shared Deep Link Scheme` and `GET /v1/config`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._