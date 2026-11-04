# Graph Report - wingspot  (2026-11-04)

## Corpus Check
- 55 files · ~24,558 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 11 file(s) not represented in the graph (top: (none) 3, .csv 3, .toml 1)

## Summary
- 483 nodes · 767 edges · 18 communities (14 shown, 4 thin omitted)
- Extraction: 96% EXTRACTED · 4% INFERRED · 0% AMBIGUOUS · INFERRED: 32 edges (avg confidence: 0.89)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `6a05244e`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- iOS Project Configuration
- Sendable
- App Shell and Navigation
- Wingspot Repository
- api.test.js
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
- BCBPError
- .mcp.json
- String

## God Nodes (most connected - your core abstractions)
1. `BuildRefdataTests` - 23 edges
2. `build()` - 20 edges
3. `base` - 16 edges
4. `write_batches()` - 15 edges
5. `Registration` - 12 edges
6. `DistanceVector` - 12 edges
7. `CheckInKind` - 11 edges
8. `PostgresImportTests` - 10 edges
9. `BCBPError` - 10 edges
10. `GeoCoordinate` - 10 edges

## Surprising Connections (you probably didn't know these)
- `BCBP Swift Package` --implements--> `BCBP Parser`  [INFERRED]
  README.md → docs/CONCEPT.md
- `contracts/test-vectors` --implements--> `Shared Test Vectors`  [INFERRED]
  contracts/README.md → docs/CONCEPT.md
- `Wingspot Repository` --implements--> `Monorepo Layout`  [INFERRED]
  README.md → docs/CONCEPT.md
- `WingspotCore Swift Package` --implements--> `WingspotCore Module`  [INFERRED]
  README.md → docs/CONCEPT.md
- `Wingspot Repository` --references--> `Wingspot App Concept`  [EXTRACTED]
  README.md → docs/CONCEPT.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Cross-platform Pro Entitlement** — docs_concept_wingspot_pro, docs_concept_entitlements_table, docs_concept_get_v1_me_entitlements, docs_concept_cross_platform_contract_rules [EXTRACTED 1.00]
- **Offline Check-in Sync Flow** — docs_concept_outbox_sync, docs_concept_post_v1_checkins, docs_concept_checkins_table, docs_concept_badge_engine, docs_concept_client_badge_predictor [EXTRACTED 1.00]
- **Shared Contract Artifacts** — contracts_readme_contracts, docs_concept_openapi_spec, docs_concept_shared_test_vectors, docs_concept_design_tokens, docs_concept_on_device_database [EXTRACTED 1.00]

## Communities (18 total, 4 thin omitted)

### Community 0 - "iOS Project Configuration"
Cohesion: 0.05
Nodes (45): ASSETCATALOG_COMPILER_APPICON_NAME, ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME, CODE_SIGN_STYLE, CURRENT_PROJECT_VERSION, GENERATE_INFOPLIST_FILE, INFOPLIST_FILE, INFOPLIST_KEY_CFBundleDisplayName, INFOPLIST_KEY_UIApplicationSceneManifest_Generation (+37 more)

### Community 1 - "Sendable"
Cohesion: 0.09
Nodes (19): BCBP, BCBPVector, .testDescription, BCBPVectors, Expected, Leg, GeoCoordinate, GreatCircle (+11 more)

### Community 2 - "App Shell and Navigation"
Cohesion: 0.05
Nodes (30): AppTab, badges, checkIn, explore, feed, profile, RootView, .body (+22 more)

### Community 3 - "Wingspot Repository"
Cohesion: 0.05
Nodes (55): Android App (Kotlin / Jetpack Compose), refdata-pipeline, Supabase Backend Project, Contracts Folder, contracts/test-vectors, Live and Historic ADS-B Data, aircraft Table, airports Table (+47 more)

### Community 4 - "api.test.js"
Cohesion: 0.09
Nodes (17): ajv, assertError(), assertMatches(), spec, status, devDependencies, ajv@8.17.1, ajv-formats@3.0.1 (+9 more)

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
Cohesion: 0.29
Nodes (6): Build, Data sources, Load into Postgres, Publish, Reference data pipeline, Test

### Community 16 - "BCBPError"
Cohesion: 0.09
Nodes (18): BCBPError, .code, invalidField, invalidFormatCode, invalidLegCount, truncated, APIClient, APIError (+10 more)

### Community 18 - "String"
Cohesion: 0.08
Nodes (14): Foundation, FieldScanner, String, .droppingLeadingZeros, Substring, .trimmed, BoardingPass, Leg (+6 more)

## Ambiguous Edges - Review These
- `Shared Deep Link Scheme` → `GET /v1/config`  [AMBIGUOUS]
  docs/CONCEPT.md · relation: conceptually_related_to

## Knowledge Gaps
- **43 isolated node(s):** `.trimmed`, `.droppingLeadingZeros`, `invalidFormatCode`, `invalidLegCount`, `truncated` (+38 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 170 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **4 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `String` to `BCBPError`, `Sendable`, `App Shell and Navigation`?**
  _High betweenness centrality (0.056) - this node is a cross-community bridge._
- **What connects `.trimmed`, `.droppingLeadingZeros`, `invalidFormatCode` to the rest of the system?**
  _43 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `iOS Project Configuration` be split into smaller, more focused modules?**
  _Cohesion score 0.04541062801932367 - nodes in this community are weakly interconnected._
- **Why does `Registration` connect `String` to `Sendable`, `App Shell and Navigation`?**
  _High betweenness centrality (0.016) - this node is a cross-community bridge._
- **Should `Sendable` be split into smaller, more focused modules?**
  _Cohesion score 0.09358974358974359 - nodes in this community are weakly interconnected._
- **Why does `CheckInKind` connect `App Shell and Navigation` to `String`?**
  _High betweenness centrality (0.014) - this node is a cross-community bridge._

### Low-confidence Hints
_AMBIGUOUS edges — the extractor was unsure. Verify before acting on these._

- **What is the exact relationship between `Shared Deep Link Scheme` and `GET /v1/config`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._