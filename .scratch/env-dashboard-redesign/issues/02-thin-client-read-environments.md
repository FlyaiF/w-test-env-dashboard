# 02 — Thin client reads Environments from the backend

Status: ready-for-agent

## Parent

[docs/PRD-redesign.md](../../../docs/PRD-redesign.md) — Test Environment Dashboard Redesign.

## What to build

Slim the `env_viewer` Flutter app down to a thin client (ADR-0001, ADR-0005) that reads its data from
the new backend instead of owning it. Shed the local-tool machinery: Go sidecar spawning and IPC, the
local JSON canonical store at `~/.test-env-dashboard/config.json`, sync/merge, and **all** direct
Oracle/DB access (no DB drivers ship to the desktop).

In their place, add a backend HTTP client and an **anti-corruption layer** that translates backend API
DTOs into the client's view models, so backend shapes never leak into the UI. Render the Environment
list and Environment detail (its Components) read-only against the live backend from slice 01.

The tool registry (launching the user's SSH/DB tools) stays in the app but is not wired to data yet
— that is slice 06.

## Acceptance criteria

- [ ] Sidecar spawning/IPC, the local JSON store, sync/merge, and all DB access are removed from `env_viewer`
- [ ] A backend API client fetches Environments from slice 01's endpoints
- [ ] An anti-corruption layer maps API DTOs to view models; UI code does not reference raw DTOs
- [ ] Environment list and Environment detail (Components) render read-only against a running backend
- [ ] `flutter analyze` is clean and `flutter test` passes (proxy env vars unset per AGENTS.md)
- [ ] UI strings remain Chinese; domain terms map to the glossary (no "web server"/"TENVINFO" leakage)

## Blocked by

- 01 — Walking skeleton: read Environments (backend)

## Implementation notes — scope landed & deferrals

The `env_viewer` app is slimmed to a thin client. Shed: the `sidecar/` (spawning + IPC), the local
JSON canonical store (`LocalStore`) + `SyncService` (sync/merge), `EnvService` (the 260-line god
object), the in-app SSH log path (`ssh_service`, `log_file_store`, log-viewer page — also a PRD §7
non-goal), the management/settings pages, the legacy models (`EnvInfo`/`Environment`/`Server`/…) and
`addr_parser`. No DB drivers were ever in the client; the now-dead `dartssh2`/`data_table_2`/
`file_picker`/`path_provider` deps are dropped from `pubspec.yaml`.

Added a clean read path: `lib/api` (`BackendClient` over `GET /api/environments` + `/{id}`, plus DTOs
mirroring the backend contract), `lib/catalog` (an `EnvironmentView`/`ComponentView` view model, a
`CatalogAcl` anti-corruption layer that maps DTO enum strings → glossary labels, and an
`EnvironmentStore` `ChangeNotifier`), and a read-only `CatalogPage` (Environment list + Component
detail). UI stays Chinese; roles/probe/status map to the ubiquitous language (网关/界面/主服务,
版本探测, 采集) with no `web server`/`TENVINFO`/`YWDB` leakage. ACL + client + store are unit-tested;
the page has a widget test.

Intentional carry-overs (not scope creep):

- **Tool registry stays unwired** (per the issue) — `services/ssh_tools/` and `ConfigService` (now
  persisting only `ssh`/`ssh_tools` prefs, no Oracle/DB config) are retained as the seam slice 06
  wires for credential-brokered launching. Nothing imports them at runtime yet.
- **`flutter analyze` / `flutter test` not executed here** — this dev machine has no Dart/Flutter SDK
  (only the Java backend is locally buildable). Code was written to `flutter_lints` by inspection and
  reviewed on both Standards and Spec axes; the maintainer must run analyze/test (unset proxy vars per
  AGENTS.md gotcha) before cutover.
