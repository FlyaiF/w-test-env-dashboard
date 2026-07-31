# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A monorepo with two Flutter desktop apps, a central backend for the environment dashboard, and a
shared UI package. The UI of both apps is in Chinese.

- **env_viewer** (`apps/env_viewer/`) — thin desktop client for browsing and curating test
  environments, collecting live versions, and launching the user's SSH/DB tools with credentials
  brokered on demand.
- **backend** (`backend/`) — Spring Boot/Java service that owns the normalized catalog, resource
  inventory, encrypted secrets, version collection, and the HTTP API consumed by `env_viewer`.
- **zipr_tool** (`apps/zipr_tool/`) — archive viewer/patcher (zip/jar/war/ear) backed by a Rust library
  through flutter_rust_bridge FFI.
- **shared_ui** (`packages/shared_ui/`) — generic AppScaffold, theme, About primitives, and
  FilterHistoryTextField.
- **go_sidecar** (`go_sidecar/`) — retained legacy, pre-redesign implementation and migration
  reference. It is not part of the active `env_viewer` runtime, development script, CI build, or
  release package.

## Architecture

`env_viewer` is a thin HTTP client. `BackendClient` talks to one separately deployed Spring backend;
the URL defaults to `http://localhost:8080` and can be changed in Settings or locked with
`ENV_DASHBOARD_BACKEND_URL`. The app does not spawn a local backend and ships no database drivers.

- **Client state**: Provider + `ChangeNotifier` (`EnvironmentStore`, `InventoryStore`, `ConfigStore`). Backend data is
  canonical; the client keeps only presentation state and DTO/view mappings.
- **Backend domains**: Environment Catalog, Resource Inventory (`Server`/`Database`), Version
  Collection, and Access Brokering. Components reference shared resources by ID.
- **Backend database**: H2 in Oracle compatibility mode for the `local` profile; Oracle 11g for
  `prod`. Oracle, Dameng, and OceanBase JDBC drivers are included in release jars via the Maven
  `probe-drivers` profile.
- **Version collection**: scheduled/manual backend probes update component version,
  `versionUpdatedAt`, `lastCollectedAt`, and per-component status.
- **Credentials**: encrypted and stored by the backend, returned only by explicit broker calls. The
  desktop passes them to a user-selected SSH/DB tool and must not persist brokered secrets.
- **Client config**: JSON at `~/.test-env-dashboard/config.json`, limited to backend URL and local
  tool preferences. UI preferences (theme mode, sidebar expanded state) persist separately in
  `~/.test-env-dashboard/ui.json` via `AppThemeController`.
- **Archive operations**: in-process Rust via flutter_rust_bridge (the `zipr` crate at repo root);
  `zipr_tool` uses no subprocess.

Principal HTTP routes are `/api/environments`, `/api/servers`, `/api/databases`,
`PUT /api/components/{id}/links`, `POST /api/environments/{id}/refresh`, and the on-demand
`/credentials` plus `/secret` routes under Servers/Databases. Health is at `/actuator/health`.

## Common Commands

```bash
# One-time per checkout / after pulling new font files
./scripts/sync_assets.sh

# backend — Java 21 + Maven; local profile is H2 with seed data
./scripts/dev_backend.sh run
mvn -f backend/pom.xml verify
mvn -f backend/pom.xml -Pprobe-drivers verify  # release-shaped jar, all probe drivers
mvn -f backend/pom.xml test -Dgroups=oracle-it -DexcludedGroups=  # optional Oracle 11g check

# env_viewer — start the backend separately first, or set ENV_DASHBOARD_BACKEND_URL
./scripts/dev_env_viewer.sh
./scripts/dev_env_viewer.sh run
cd apps/env_viewer && flutter analyze
cd apps/env_viewer && flutter test

# zipr_tool (requires the public zipr submodule)
git submodule update --init --recursive
./scripts/dev_zipr_tool.sh run
cd apps/zipr_tool && flutter analyze
cd apps/zipr_tool && flutter test

# One-time legacy TENVINFO -> new-schema import (slice 07; ADR-0004, PRD §8).
# Dry run by default; --apply writes. Source = old Oracle; target = backend datasource.
LEGACY_JDBC_URL=jdbc:oracle:thin:@oldhost:1521/ORCL LEGACY_DB_USERNAME=app LEGACY_DB_PASSWORD=secret \
  scripts/import_tenvinfo.sh
LEGACY_JDBC_URL=... LEGACY_DB_USERNAME=... LEGACY_DB_PASSWORD=... scripts/import_tenvinfo.sh --apply

# Release-shaped local build: verifies/package backend with probe drivers, then builds both apps.
# The backend jar is deployed separately; it is not embedded in env_viewer.
./scripts/build_release.sh macos    # also: windows, linux
```

## Key Files

- `apps/env_viewer/lib/api/backend_client.dart` — the thin client's HTTP boundary
- `apps/env_viewer/lib/catalog/environment_store.dart` — catalog/read-model state and refresh flows
- `apps/env_viewer/lib/inventory/inventory_store.dart` — canonical Server/Database presentation state
- `apps/env_viewer/lib/catalog/catalog_acl.dart` — DTO-to-view anti-corruption mapping
- `apps/env_viewer/lib/config/config_store.dart` — backend URL and local tool preferences
- `apps/env_viewer/lib/services/access/access_launcher.dart` — brokers credentials and launches tools
- `apps/env_viewer/lib/services/remote_file/remote_file_session.dart` — in-app SSH tail/SFTP view of remote logs/files (docs/remote-file-viewer.md)
- `apps/env_viewer/lib/remote_files/remote_file_store.dart` — 日志文件 tab state and brokered open flow
- `apps/env_viewer/lib/pages/catalog/catalog_page.dart` — main environment catalog UI
- `apps/env_viewer/lib/pages/inventory/inventory_page.dart` — shared resource management and reverse references
- `backend/src/main/java/com/flyaif/envdashboard/catalog/` — Environment/Component domain and API
- `backend/src/main/java/com/flyaif/envdashboard/inventory/` — shared Server/Database inventory
- `backend/src/main/java/com/flyaif/envdashboard/collection/` — scheduler, probes, machine access
- `backend/src/main/java/com/flyaif/envdashboard/access/` — encrypted secrets and credential broker
- `backend/src/main/java/com/flyaif/envdashboard/legacyimport/` — one-time `TENVINFO` importer
- `backend/src/main/resources/db/migration/` — normalized schema migrations
- `apps/zipr_tool/lib/services/zipr_service.dart` — Rust FFI wrapper for archive operations
- `apps/zipr_tool/rust/Cargo.toml` — FFI crate; depends on the repo-root `zipr` submodule
- `packages/shared_ui/lib/src/app_scaffold.dart` — generic NavGroup/NavItem-driven scaffold
- `zipr/src/lib.rs` — core archive diff and patching logic
- `go_sidecar/` and `scripts/build_sidecar.sh` — legacy-only implementation/reference tooling; do not
  reintroduce them into the active client delivery path

## Gotchas

- **Proxy breaks Flutter tests**: if HTTP proxy env vars are set, `flutter test` fails with “Invalid
  WebSocket upgrade request”. Unset them first:
  ```bash
  unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy
  ```
- **The backend is a separate process**: `scripts/dev_env_viewer.sh` only prepares/runs Flutter. Start
  `scripts/dev_backend.sh run` in another terminal or set `ENV_DASHBOARD_BACKEND_URL`. A Settings URL
  change takes effect after restart.
- **Production backend secrets/config**: the `prod` profile needs `ORACLE_JDBC_URL`,
  `ORACLE_USERNAME`, `ORACLE_PASSWORD`, and a high-entropy `ACCESS_SECRET_KEY`.
- **Oracle DATE timezone**: Oracle `DATE` has no timezone. The backend reads version update time in the
  backend JVM's zone and serializes an instant; Flutter must call `.toLocal()` before display.
- **Per-app `assets/` is gitignored but required at build time**: fonts live once at root
  `assets/fonts/`. Run `scripts/sync_assets.sh`; build scripts and CI do this automatically.
- **Only zipr_tool needs the submodule**: `env_viewer` and backend CI checkouts deliberately skip it.
  Initialize `zipr/` before building `zipr_tool` locally.

## Conventions

- Java entities/API DTOs use normalized fields (`versionUpdatedAt`, never the obsolete
  `deployTime`); Dart DTOs mirror the API and the catalog ACL maps them to display models.
- Java uses nullable references where the domain permits missing data; Dart uses nullable types.
- Backend URL precedence is `ENV_DASHBOARD_BACKEND_URL` → persisted Settings value →
  `http://localhost:8080`.
- Release backend jars must activate `-Pprobe-drivers`; desktop packages contain no sidecar/JDBC
  helper artifacts.
- CI checks out the public `zipr` submodule only for `zipr_tool` jobs.
- Fonts live once at root `assets/fonts/`; `scripts/sync_assets.sh` populates each app's gitignored
  `assets/fonts/` directory for reliable Flutter bundling on every platform.
