# env_viewer

测试环境速查工具 — a thin Flutter desktop client for the central Test Environment Dashboard
backend. It browses and curates Environments/Components, triggers live version collection, and
launches the user's SSH/DB tools for linked resources with credentials brokered on demand.

The client talks only to the Spring Boot HTTP API. It does not connect to Oracle directly, spawn a
Go sidecar, or ship JDBC drivers.

All paths below are relative to the repository root unless otherwise noted.

## Prerequisites

- **Flutter** 3.41.6 (`stable`) — match `.github/workflows/build.yml`.
- A running **env-dashboard backend** reachable over HTTP. For local development, also install Java
  21 and Maven; `scripts/dev_backend.sh` starts an H2-backed instance with demo data.
- The platform toolchain for the desktop target:
  - macOS: Xcode + CocoaPods.
  - Windows: Visual Studio 2022 with the “Desktop development with C++” workload.
  - Linux: `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`, `liblzma-dev`.
- Optional: supported SSH/DB desktop tools you want the app to launch. Their paths/defaults are set
  under 设置.

## First-time setup

```bash
# Sync fonts and fetch Dart dependencies. This does not start the backend.
./scripts/dev_env_viewer.sh
```

## Run locally

Start the backend in one terminal:

```bash
./scripts/dev_backend.sh run

# Optional smoke checks once it is ready:
curl http://localhost:8080/actuator/health
curl http://localhost:8080/api/environments
```

Then start the client in another terminal:

```bash
./scripts/dev_env_viewer.sh run

# Or pass Flutter arguments explicitly:
./scripts/dev_env_viewer.sh run -d macos
```

The client uses `http://localhost:8080` by default. To point it at another deployment, either set the
address under 设置 → 后端服务 and restart, or lock it for the process:

```bash
ENV_DASHBOARD_BACKEND_URL=http://backend.example.test:8080 \
  ./scripts/dev_env_viewer.sh run
```

On a healthy launch, the window is titled 测试环境速查工具, the navigation contains 环境目录 / 资源清单 /
设置 / 关于, the cloud indicator is green, and the local profile's seeded environments appear in 环境目录.
资源清单 manages shared Servers/Databases, shows their reverse Environment references, and links them
from Components without exposing stored secrets. A
red cloud means the configured backend could not be reached. Catalog data is canonical on the
backend; the desktop persists only its backend URL and local tool preferences.

## Run checks

```bash
# Avoid Flutter's WebSocket/proxy failure in environments with proxy variables.
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy

cd apps/env_viewer
flutter pub get
flutter analyze
flutter test
```

CI runs both `flutter analyze` and `flutter test` in the `env-viewer-checks` job before a tagged
release can be published.

## Build and release

To build only this desktop client:

```bash
./scripts/sync_assets.sh
cd apps/env_viewer
flutter pub get
flutter build macos --release       # or: windows / linux
```

For a release-shaped build of the whole repository:

```bash
# Verifies and packages the Spring backend with -Pprobe-drivers, then builds both desktop apps.
./scripts/build_release.sh macos     # or: windows / linux
```

The backend jar is written under `backend/target/`; the macOS client is under
`apps/env_viewer/build/macos/Build/Products/Release/env_viewer.app`. They are separate deployables:
the jar is never embedded in the app. Tagged GitHub releases contain the executable backend jar and
the macOS/Windows client archives.

Production backend startup requires the Oracle datasource and encryption-key environment variables
documented in `backend/src/main/resources/application-prod.yml`, for example:

```bash
ORACLE_JDBC_URL=... ORACLE_USERNAME=... ORACLE_PASSWORD=... ACCESS_SECRET_KEY=... \
  java -jar backend/target/env-dashboard-backend-*.jar --spring.profiles.active=prod
```

## Troubleshooting

- **Cloud indicator stays red / catalog is empty**: confirm the backend is running, check
  `http://HOST:PORT/actuator/health`, and verify 设置 → 后端服务. A changed saved URL takes effect
  after restart; `ENV_DASHBOARD_BACKEND_URL` overrides and locks the field.
- **`flutter test` hangs or reports an invalid WebSocket upgrade**: unset all HTTP proxy variables
  shown above.
- **macOS build fails on a fresh checkout with CocoaPods errors**: run
  `cd apps/env_viewer/macos && pod install`.
- **Chinese text renders as boxes**: run `scripts/sync_assets.sh`, then rebuild.
- **A launched SSH/DB tool is missing or incorrect**: configure its executable path/default under
  设置. Resource credentials come from the backend only when an action requests them; they are not
  loaded with the catalog.

## Legacy note

`go_sidecar/` and `scripts/build_sidecar.sh` remain in the repository only as the pre-redesign
implementation and migration reference. Current `env_viewer` development, CI, and release paths do
not build, copy, or package the sidecar or its former JDBC helper.
