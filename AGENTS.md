# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Test environment dashboard — a Flutter desktop app with a Go HTTP sidecar that manages test environments stored in an Oracle database. The UI is in Chinese.

## Architecture

**Flutter app** (`flutter_app/`) spawns the **Go sidecar** (`go_sidecar/`) as a subprocess. They communicate via HTTP on localhost with a dynamically allocated port. The sidecar writes `PORT=<num>` to stdout on startup; Flutter's `SidecarManager` reads it and configures `SidecarClient`.

- **State management**: Provider pattern with `ChangeNotifier` (`EnvService`, `SidecarManager`)
- **Database**: Oracle via `go-ora/v2`, table `TENVINFO`, pooled connections
- **SSH log streaming**: `dartssh2` parses `E_WEBSERVERADDR` format `"server:port&username/password"` to `tail -f` remote logs
- **Config persistence**: JSON at `~/.test-env-dashboard/config.json`

**Go API endpoints**: `GET/POST /api/envs`, `GET/PUT/DELETE /api/envs/{id}`, `POST /api/db/test`, `GET /health`

## Common Commands

```bash
# Flutter
cd flutter_app && flutter pub get
cd flutter_app && flutter run -d macos
cd flutter_app && flutter analyze
cd flutter_app && flutter test

# Go sidecar
cd go_sidecar && go build -o ../build/sidecar/go_sidecar .

# Release builds
./scripts/build_release.sh macos    # also: windows, linux
./scripts/build_sidecar.sh          # current platform
./scripts/build_sidecar.sh all      # cross-compile all platforms
```

## Key Files

- `flutter_app/lib/sidecar/sidecar_manager.dart` — spawns Go process, port discovery, lifecycle
- `flutter_app/lib/sidecar/sidecar_client.dart` — HTTP client to sidecar API
- `flutter_app/lib/services/env_service.dart` — environment CRUD, pagination, search state
- `flutter_app/lib/widgets/app_scaffold.dart` — main layout with NavigationRail
- `go_sidecar/main.go` — server startup, IPC protocol, graceful shutdown
- `go_sidecar/db/oracle.go` — connection pool setup
- `go_sidecar/db/queries.go` — SQL for TENVINFO table
- `go_sidecar/handler/env.go` — REST endpoint handlers

## Gotchas

- **Proxy breaks Flutter tests**: If HTTP proxy env vars are set, `flutter test` fails with "Invalid WebSocket upgrade request". Unset them first:
  ```bash
  unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy
  ```
- **Oracle DATE timezone**: Oracle `DATE` columns have no timezone. `go-ora` reads them as Go local time, which gets serialized to UTC in JSON. Flutter must call `.toLocal()` before formatting with `DateFormat`, otherwise times will be off by the local UTC offset.

## Conventions

- Go model uses `*string` for nullable fields; Dart uses `String?`
- Platform binary resolution: `SidecarManager._resolveBinaryPath()` checks app bundle first, then `build/sidecar/` for dev
- CI builds universal macOS binary via `lipo` (arm64 + amd64)
