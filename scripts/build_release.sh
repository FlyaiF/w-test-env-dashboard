#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
PLATFORM=${1:-macos}

echo "=== Release build for $PLATFORM ==="

# Step 1: Build Go sidecar (env_viewer's backend)
echo ""
echo "--- Step 1: Building Go sidecar ---"
"$SCRIPT_DIR/build_sidecar.sh"

# Step 2: Build env_viewer
echo ""
echo "--- Step 2: Building env_viewer ---"
cd "$PROJECT_DIR/apps/env_viewer"
flutter pub get

case "$PLATFORM" in
    macos)
        flutter build macos --release
        APP="$PROJECT_DIR/apps/env_viewer/build/macos/Build/Products/Release/env_viewer.app"
        cp "$BUILD_DIR/sidecar/go_sidecar" "$APP/Contents/Resources/go_sidecar"
        chmod +x "$APP/Contents/Resources/go_sidecar"
        echo "  Created $APP"
        ;;
    windows)
        flutter build windows --release
        RUNNER_DIR="$PROJECT_DIR/apps/env_viewer/build/windows/x64/runner/Release"
        mkdir -p "$RUNNER_DIR/data"
        cp "$BUILD_DIR/sidecar/go_sidecar" "$RUNNER_DIR/data/go_sidecar.exe"
        echo "  Created $RUNNER_DIR/env_viewer.exe"
        ;;
    linux)
        flutter build linux --release
        BUNDLE_DIR="$PROJECT_DIR/apps/env_viewer/build/linux/x64/release/bundle"
        mkdir -p "$BUNDLE_DIR/data"
        cp "$BUILD_DIR/sidecar/go_sidecar" "$BUNDLE_DIR/data/go_sidecar"
        chmod +x "$BUNDLE_DIR/data/go_sidecar"
        echo "  Created $BUNDLE_DIR/env_viewer"
        ;;
    *)
        echo "Unknown platform: $PLATFORM"
        echo "Usage: $0 [macos|windows|linux]"
        exit 1
        ;;
esac

# Step 3: Build zipr_tool (Rust comes in via FFI, no separate binary)
echo ""
echo "--- Step 3: Building zipr_tool ---"
cd "$PROJECT_DIR/apps/zipr_tool"
flutter pub get
flutter build "$PLATFORM" --release

case "$PLATFORM" in
    macos)
        echo "  Created $PROJECT_DIR/apps/zipr_tool/build/macos/Build/Products/Release/zipr_tool.app"
        ;;
    windows)
        echo "  Created $PROJECT_DIR/apps/zipr_tool/build/windows/x64/runner/Release/zipr_tool.exe"
        ;;
    linux)
        echo "  Created $PROJECT_DIR/apps/zipr_tool/build/linux/x64/release/bundle/zipr_tool"
        ;;
esac

echo ""
echo "=== Release build complete ==="
