# zipr_tool

> Status: current
> Scope: zipr_tool desktop archive application

归档差异与补丁工具 — a Flutter desktop app for inspecting, diffing, and patching zip / jar / war / ear archives. The archive engine is the Rust crate at `zipr/`, statically linked into the app via [flutter_rust_bridge](https://pub.dev/packages/flutter_rust_bridge). No subprocess, no separate CLI binary.

All paths below are relative to the repository root unless otherwise noted.

## Prerequisites

- **Flutter** 3.41.6 (channel `stable`) — match the version pinned by CI in `.github/workflows/build.yml`.
- **Rust** stable (via `rustup`) — needed by cargokit, which compiles the Rust library during `flutter build`. macOS release builds expect both `aarch64-apple-darwin` and `x86_64-apple-darwin` targets installed.
- **`flutter_rust_bridge_codegen`** 2.12.0 — only required when you change Rust API signatures (`apps/zipr_tool/rust/src/api/zipr_api.rs`) and need to regenerate the Dart bindings:
  ```bash
  cargo install flutter_rust_bridge_codegen --version 2.12.0
  ```
- Platform toolchain for the target you want to run on:
  - macOS: Xcode + CocoaPods (`sudo gem install cocoapods`).
  - Windows: Visual Studio 2022 with the "Desktop development with C++" workload.
  - Linux: `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`, `liblzma-dev`.
- The `zipr/` submodule must be present — clone with `git clone --recurse-submodules` or run `git submodule update --init` after a plain clone. The Rust crate at `apps/zipr_tool/rust/` depends on it via path.

## First-time setup

```bash
# Sync assets, verify the zipr submodule, and fetch Dart dependencies.
./scripts/dev_zipr_tool.sh
```

## Run in dev mode

```bash
./scripts/dev_zipr_tool.sh run
# or pass Flutter args explicitly:
./scripts/dev_zipr_tool.sh run -d macos
```

The first launch is slow because cargokit compiles the Rust library (typically 1–3 minutes on a fresh checkout, instant after that thanks to Cargo's incremental cache).

What you should see on a healthy launch:
- The Chinese-titled window 归档差异与补丁工具 appears at 1280×800.
- The left-side nav has one item: 工具 → 归档, plus a 关于 footer entry.
- The 归档 page is empty — drag a `.zip`/`.jar`/`.war`/`.ear` onto the window, or click 选择文件, to load an archive.
- 关于 → 归档引擎 (Rust) shows the linked zipr crate version + git rev (e.g. `zipr 版本: 0.1.0`, `zipr Commit: d04248024621`). These come from `apps/zipr_tool/rust/build.rs`, which reads `zipr/Cargo.toml` and runs `git rev-parse` against the submodule at compile time.

## Run tests

```bash
# Unset proxy vars first — flutter test fails with "Invalid WebSocket
# upgrade request" if HTTP_PROXY/HTTPS_PROXY are set in the shell.
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy

cd apps/zipr_tool
flutter test                  # ~36 widget + service tests, FFI-mocked
flutter analyze               # must be clean before pushing
```

`zipr_service_test.dart` uses a mock `ZiprBridgeInterface` so tests don't depend on the Rust toolchain.

## Regenerating Rust→Dart bindings

If you add or change a function in `apps/zipr_tool/rust/src/api/zipr_api.rs`:

```bash
cd apps/zipr_tool
flutter_rust_bridge_codegen generate
```

This rewrites `lib/src/rust/` to match the new Rust API. Commit the regenerated Dart files together with the Rust change.

## Build a release locally

```bash
# From repo root. zipr_tool needs no extra backend binary — the Rust
# library is statically linked into the Flutter framework.
./scripts/build_release.sh macos      # or: windows / linux
```

Output for macOS: `apps/zipr_tool/build/macos/Build/Products/Release/zipr_tool.app` (~50 MB compressed once zipped).

## Troubleshooting

- **`flutter build` fails with `failed to read .../zipr/Cargo.toml`**: the zipr submodule isn't checked out. Run `git submodule update --init`.
- **First build is extremely slow / hangs at "Building rust_lib_test_env_dashboard"**: this is cargokit compiling Rust. On macOS the universal binary build (arm64 + x86_64) takes 1–3 minutes the first time; subsequent builds use Cargo's incremental cache. Check `apps/zipr_tool/rust/target/` is being populated.
- **`flutter test` hangs or fails with WebSocket error**: unset all proxy env vars first (see above).
- **macOS release build fails with "can't find target aarch64-apple-darwin"**: install both targets with `rustup target add aarch64-apple-darwin x86_64-apple-darwin`.
- **Window opens but fonts look wrong (square boxes for Chinese characters)**: you skipped `scripts/sync_assets.sh`. Run it, then `flutter clean && flutter run`.
- **About page shows zipr Commit: `unknown`**: the build.rs couldn't run `git` from the submodule directory. Make sure `git` is in `PATH` during build, or set `ZIPR_GIT_REV=<sha>` as an env var before `flutter build` to override.
