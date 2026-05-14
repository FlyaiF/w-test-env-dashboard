# env_viewer

测试环境速查工具 — a Flutter desktop app for browsing, managing, and tailing logs of test environments stored in an Oracle database. Communicates with an Oracle DB through a Go HTTP sidecar (`go_sidecar/`) that this app spawns as a subprocess on launch.

All paths below are relative to the repository root unless otherwise noted.

## Prerequisites

- **Flutter** 3.41.6 (channel `stable`) — match the version pinned by CI in `.github/workflows/build.yml`.
- **Go** 1.22+ — to build the sidecar.
- Platform toolchain for the target you want to run on:
  - macOS: Xcode + CocoaPods (`sudo gem install cocoapods`).
  - Windows: Visual Studio 2022 with the "Desktop development with C++" workload.
  - Linux: `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`, `liblzma-dev`.
- A reachable Oracle database (any version that speaks the standard listener protocol) with a user that can read the `TENVINFO` table — required to see any data; the app will launch without it but the dashboard will be empty.

## First-time setup

```bash
# 1. Sync shared font assets into the app's local assets/ directory.
#    Required because Flutter's bundler doesn't follow `..` paths on
#    Windows. Re-run after pulling new fonts.
./scripts/sync_assets.sh

# 2. Build the Go sidecar into build/sidecar/.
#    env_viewer looks for the binary here when run from `flutter run`.
./scripts/build_sidecar.sh

# 3. Fetch Dart dependencies.
cd apps/env_viewer && flutter pub get
```

## Run in dev mode

```bash
cd apps/env_viewer
flutter run -d macos          # or: windows / linux
```

What you should see on a healthy launch:
- The Chinese-titled window 测试环境速查工具 appears at 1280×800.
- The left-side nav lists 总览 / 日志 / 管理 plus a footer with 设置 / 关于.
- The header has a cloud icon: **red** = sidecar not running, **green** = sidecar connected. On first launch, before you configure Oracle, it's red and the app lands you on the 设置 page automatically.
- Fill out the Oracle DSN in 设置 (host, port, service name, username, password), click **测试连接**, then **保存并重新连接**. The header indicator should turn green, and 总览 will populate.

The Go sidecar is started as a child process at runtime; it writes `PORT=<num>` to stdout, which `SidecarManager` reads to configure the HTTP client. If startup fails, check that `build/sidecar/go_sidecar` exists and is executable — that's where `_devBinaryPath()` looks for it (`lib/sidecar/sidecar_manager.dart:147`).

## Run tests

```bash
# Unset proxy vars first — flutter test fails with "Invalid WebSocket
# upgrade request" if HTTP_PROXY/HTTPS_PROXY are set in the shell.
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy

cd apps/env_viewer
flutter test                  # ~29 unit tests
flutter analyze               # must be clean before pushing
```

## Build a release locally

```bash
# From repo root. Embeds go_sidecar in env_viewer.app/exe/bundle.
./scripts/build_release.sh macos      # or: windows / linux
```

Output for macOS: `apps/env_viewer/build/macos/Build/Products/Release/env_viewer.app` with `Contents/Resources/go_sidecar` inside.

## Troubleshooting

- **Header indicator stays red after entering Oracle credentials**: check Settings → 测试连接 for the underlying error. If it says the sidecar isn't running, the Go binary couldn't be located — re-run `./scripts/build_sidecar.sh` from the repo root.
- **`flutter test` hangs or fails with WebSocket error**: unset all proxy env vars first (see above).
- **macOS build fails on a fresh checkout with CocoaPods errors**: `cd apps/env_viewer/macos && pod install`.
- **Window opens but fonts look wrong (square boxes for Chinese characters)**: you skipped `scripts/sync_assets.sh`. Run it, then `flutter clean && flutter run`.
- **Oracle `DATE` columns display the wrong time**: known quirk — Oracle `DATE` has no timezone; `go-ora` reads them as Go local time which then becomes UTC in JSON. The Dart side calls `.toLocal()` before formatting. If you see drift, check that the sidecar host and the dashboard host are in the same timezone.
