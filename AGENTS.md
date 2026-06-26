# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A monorepo with two separate Flutter desktop apps that share a small UI package. The UI of both apps is in Chinese.

- **env_viewer** (`apps/env_viewer/`) — test environment dashboard, backed by Oracle via a Go HTTP sidecar. Lists/searches/manages test environments and streams remote logs over SSH.
- **zipr_tool** (`apps/zipr_tool/`) — archive viewer/patcher (zip/jar/war/ear) backed by a Rust library via flutter_rust_bridge FFI.
- **shared_ui** (`packages/shared_ui/`) — generic AppScaffold, theme, About primitives, FilterHistoryTextField.

## Architecture

**env_viewer** spawns the **Go sidecar** (`go_sidecar/`) as a subprocess. They communicate via HTTP on localhost with a dynamically allocated port. The sidecar writes `PORT=<num>` to stdout on startup; Flutter's `SidecarManager` reads it and configures `SidecarClient`.

- **State management**: Provider pattern with `ChangeNotifier` (`EnvService`, `SidecarManager`, `ZiprService`)
- **Database**: Oracle via `go-ora/v2`, table `TENVINFO`, pooled connections
- **SSH log streaming**: `dartssh2` parses `E_WEBSERVERADDR` format `"server:port&username/password"` to `tail -f` remote logs
- **Archive ops**: in-process Rust via `flutter_rust_bridge` (the `zipr` crate at repo root). No subprocess.
- **Config persistence**: env_viewer only — JSON at `~/.test-env-dashboard/config.json`

**Go API endpoints**: `GET/POST /api/envs`, `GET/PUT/DELETE /api/envs/{id}`, `POST /api/db/test`, `GET /health`

## Common Commands

```bash
# One-time per checkout / after pulling new font files
./scripts/sync_assets.sh

# env_viewer
cd apps/env_viewer && flutter pub get
cd apps/env_viewer && flutter run -d macos
cd apps/env_viewer && flutter analyze
cd apps/env_viewer && flutter test

# zipr_tool
cd apps/zipr_tool && flutter pub get
cd apps/zipr_tool && flutter run -d macos
cd apps/zipr_tool && flutter analyze
cd apps/zipr_tool && flutter test

# Go sidecar (used only by env_viewer)
cd go_sidecar && go build -o ../build/sidecar/go_sidecar .

# backend — new Spring Boot service for the redesign (see docs/PRD-redesign.md).
# Java 21 + Maven. Local dev uses H2 (Oracle compatibility mode) with seed data.
scripts/dev_backend.sh run                 # boot on localhost:8080 (local profile)
mvn -f backend/pom.xml verify              # full test suite (H2; Oracle IT excluded)
mvn -f backend/pom.xml test -Dgroups=oracle-it -DexcludedGroups=   # optional Oracle 11g Testcontainers check

# One-time legacy TENVINFO -> new-schema import (slice 07; ADR-0004, PRD §8). Dry run by default;
# --apply to write. Reads the old Oracle, writes into the backend's own datasource (APP_PROFILES).
LEGACY_JDBC_URL=jdbc:oracle:thin:@oldhost:1521/ORCL LEGACY_DB_USERNAME=app LEGACY_DB_PASSWORD=secret \
  scripts/import_tenvinfo.sh                # preview report, no writes
LEGACY_JDBC_URL=... LEGACY_DB_USERNAME=... LEGACY_DB_PASSWORD=... scripts/import_tenvinfo.sh --apply

# Release builds — builds both apps, embeds go_sidecar in env_viewer only
./scripts/build_release.sh macos    # also: windows, linux
./scripts/build_sidecar.sh          # current platform
./scripts/build_sidecar.sh all      # cross-compile all platforms
```

## Key Files

- `apps/env_viewer/lib/sidecar/sidecar_manager.dart` — spawns Go process, port discovery, lifecycle
- `apps/env_viewer/lib/sidecar/sidecar_client.dart` — HTTP client to sidecar API
- `apps/env_viewer/lib/services/env_service.dart` — environment CRUD, pagination, search state
- `apps/env_viewer/lib/widgets/app_scaffold.dart` — env_viewer's nav definition (groups/items), delegates to shared_ui scaffold
- `apps/zipr_tool/lib/services/zipr_service.dart` — Rust FFI wrapper for archive operations
- `apps/zipr_tool/rust/Cargo.toml` — Rust crate compiled into the app; depends on the repo-root `zipr` crate
- `packages/shared_ui/lib/src/app_scaffold.dart` — generic NavGroup/NavItem-driven scaffold
- `go_sidecar/main.go` — server startup, IPC protocol, graceful shutdown
- `go_sidecar/db/oracle.go` — connection pool setup
- `go_sidecar/db/queries.go` — SQL for TENVINFO table
- `go_sidecar/handler/env.go` — REST endpoint handlers
- `zipr/src/lib.rs` — core archive diff and patching logic (consumed by zipr_tool via FFI)

## Gotchas

- **Proxy breaks Flutter tests**: If HTTP proxy env vars are set, `flutter test` fails with "Invalid WebSocket upgrade request". Unset them first:
  ```bash
  unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy
  ```
- **Oracle DATE timezone**: Oracle `DATE` columns have no timezone. `go-ora` reads them as Go local time, which gets serialized to UTC in JSON. Flutter must call `.toLocal()` before formatting with `DateFormat`, otherwise times will be off by the local UTC offset.
- **Per-app `assets/` is gitignored, but required at build time**: Each app's `pubspec.yaml` references fonts via the local path `assets/fonts/...`. Flutter's bundler does not reliably resolve `..` paths on Windows, so we keep a single canonical copy of the fonts at repo-root `assets/fonts/` and use `scripts/sync_assets.sh` to populate each app's local `assets/fonts/` before any build. Run the script after a fresh clone or when font files change. Build scripts and CI call it automatically.

## Conventions

- Go model uses `*string` for nullable fields; Dart uses `String?`
- Platform binary resolution: `SidecarManager._resolveBinaryPath()` checks app bundle first, then `build/sidecar/` for dev
- CI builds universal macOS binary via `lipo` (arm64 + amd64)
- Fonts live once at repo root `assets/fonts/`; `scripts/sync_assets.sh` copies them into each app's local `assets/fonts/` (gitignored) so Flutter's bundler picks them up reliably on all platforms
