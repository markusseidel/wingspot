# Graph Report - wingspot  (2026-11-04)

## Corpus Check
- 49 files · ~22,807 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 8 file(s) not represented in the graph (top: (none) 2, .csv 2, .toml 1)

## Summary
- 422 nodes · 645 edges · 16 communities (13 shown, 3 thin omitted)
- Extraction: 95% EXTRACTED · 5% INFERRED · 0% AMBIGUOUS · INFERRED: 31 edges (avg confidence: 0.9)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `8792b0ca`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- iOS Project Configuration
- BCBP Parser Internals
- App Shell and Navigation
- Product Features and Contracts
- api.test.js
- Test Vectors and Decoding
- http.ts
- Airport Visit Check-in
- build_refdata.py
- ios.yml
- BuildRefdataTests
- Swift Package Manifests
- backend.yml
- contracts.yml
- Reference data pipeline
- CLAUDE.md

## God Nodes (most connected - your core abstractions)
1. `BuildRefdataTests` - 21 edges
2. `build()` - 16 edges
3. `base` - 15 edges
4. `Registration` - 12 edges
5. `DistanceVector` - 12 edges
6. `CheckInKind` - 11 edges
7. `BCBPError` - 10 edges
8. `GeoCoordinate` - 10 edges
9. `SpottedCheckInView` - 10 edges
10. `error()` - 9 edges

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

## Communities (16 total, 3 thin omitted)

### Community 0 - "iOS Project Configuration"
Cohesion: 0.05
Nodes (44): ASSETCATALOG_COMPILER_APPICON_NAME, ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME, CODE_SIGN_STYLE, CURRENT_PROJECT_VERSION, GENERATE_INFOPLIST_FILE, INFOPLIST_KEY_CFBundleDisplayName, INFOPLIST_KEY_UIApplicationSceneManifest_Generation, INFOPLIST_KEY_UILaunchScreen_Generation (+36 more)

### Community 1 - "BCBP Parser Internals"
Cohesion: 0.07
Nodes (18): Foundation, FieldScanner, String, .droppingLeadingZeros, Substring, .trimmed, BCBPError, .code (+10 more)

### Community 2 - "App Shell and Navigation"
Cohesion: 0.06
Nodes (28): AppTab, badges, checkIn, explore, feed, profile, RootView, .body (+20 more)

### Community 3 - "Product Features and Contracts"
Cohesion: 0.05
Nodes (55): Android App (Kotlin / Jetpack Compose), refdata-pipeline, Supabase Backend Project, Contracts Folder, contracts/test-vectors, Live and Historic ADS-B Data, aircraft Table, airports Table (+47 more)

### Community 4 - "api.test.js"
Cohesion: 0.09
Nodes (17): ajv, assertError(), assertMatches(), spec, status, devDependencies, ajv@8.17.1, ajv-formats@3.0.1 (+9 more)

### Community 5 - "Test Vectors and Decoding"
Cohesion: 0.09
Nodes (22): BCBP, BCBPVector, .testDescription, BCBPVectors, Expected, Leg, GeoCoordinate, GreatCircle (+14 more)

### Community 6 - "http.ts"
Cohesion: 0.30
Nodes (15): invalid(), isOptionalText(), register(), unregister(), validate(), authenticate(), Authenticated, client() (+7 more)

### Community 7 - "Airport Visit Check-in"
Cohesion: 0.40
Nodes (5): Airport Visit Check-in, Batch Mode Spotting Session, Flown Check-in, Spotted Check-in, Spotting Locations

### Community 8 - "build_refdata.py"
Cohesion: 0.12
Nodes (8): _airport(), build(), InputError, _load_airports(), _load_types(), main(), _rows(), InvalidInputTests

### Community 9 - "ios.yml"
Cohesion: 0.09
Nodes (23): runs-on, steps, jobs, app, packages, package, name, on (+15 more)

### Community 12 - "backend.yml"
Cohesion: 0.09
Nodes (23): jobs, refdata-pipeline, supabase, name, on, pull_request, push, permissions (+15 more)

### Community 13 - "contracts.yml"
Cohesion: 0.12
Nodes (15): jobs, openapi, name, on, pull_request, push, runs-on, steps (+7 more)

### Community 14 - "Reference data pipeline"
Cohesion: 0.40
Nodes (4): Build, Data sources, Reference data pipeline, Test

## Ambiguous Edges - Review These
- `Shared Deep Link Scheme` → `GET /v1/config`  [AMBIGUOUS]
  docs/CONCEPT.md · relation: conceptually_related_to

## Knowledge Gaps
- **39 isolated node(s):** `.trimmed`, `.droppingLeadingZeros`, `invalidFormatCode`, `invalidLegCount`, `truncated` (+34 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 152 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **3 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `BCBP Parser Internals` to `App Shell and Navigation`, `Test Vectors and Decoding`?**
  _High betweenness centrality (0.057) - this node is a cross-community bridge._
- **What connects `.trimmed`, `.droppingLeadingZeros`, `invalidFormatCode` to the rest of the system?**
  _39 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `iOS Project Configuration` be split into smaller, more focused modules?**
  _Cohesion score 0.046464646464646465 - nodes in this community are weakly interconnected._
- **Why does `Registration` connect `Test Vectors and Decoding` to `BCBP Parser Internals`, `App Shell and Navigation`?**
  _High betweenness centrality (0.017) - this node is a cross-community bridge._
- **Should `BCBP Parser Internals` be split into smaller, more focused modules?**
  _Cohesion score 0.06693877551020408 - nodes in this community are weakly interconnected._
- **Why does `CheckInKind` connect `App Shell and Navigation` to `BCBP Parser Internals`?**
  _High betweenness centrality (0.016) - this node is a cross-community bridge._

### Low-confidence Hints
_AMBIGUOUS edges — the extractor was unsure. Verify before acting on these._

- **What is the exact relationship between `Shared Deep Link Scheme` and `GET /v1/config`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._