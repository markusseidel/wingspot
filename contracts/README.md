# Contracts

Single source of truth shared by the iOS app, the Android app and the backend (see `docs/CONCEPT.md` §11.1a and §11.5).

| Folder | Content |
|---|---|
| `openapi.yaml` | API contract (`/v1`), written before the endpoints are implemented. Covers config, devices, entitlements and the reference data manifest so far. |
| `refdata/` | Schema of the on-device reference database. |
| `test-vectors/` | Input → expected output files. Every client implementation of the same logic must pass them. |

Planned: `badge-rules/`, `i18n/`, `design-tokens.json`, `badge-art/`, `analytics-events.yaml`.
