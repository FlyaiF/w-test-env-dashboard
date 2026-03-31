#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
PLATFORM=${1:-macos}

echo "=== Release build for $PLATFORM ==="

# Step 1a: Build Go sidecar
echo ""
echo "--- Step 1a: Building Go sidecar ---"
"$SCRIPT_DIR/build_sidecar.sh"

# Step 1b: Build zipr CLI
echo ""
echo "--- Step 1b: Building zipr CLI ---"
"$SCRIPT_DIR/build_zipr.sh"

# Step 2: Bundle binaries into Flutter app
echo ""
echo "--- Step 2: Building Flutter app ---"
cd "$PROJECT_DIR/flutter_app"

case "$PLATFORM" in
    macos)
        flutter build macos --release

        # Copy sidecar into .app bundle
        APP_BUNDLE="$PROJECT_DIR/flutter_app/build/macos/Build/Products/Release/test_env_dashboard.app"
        cp "$BUILD_DIR/sidecar/go_sidecar" "$APP_BUNDLE/Contents/Resources/go_sidecar"
        chmod +x "$APP_BUNDLE/Contents/Resources/go_sidecar"
        cp "$BUILD_DIR/zipr/zipr" "$APP_BUNDLE/Contents/Resources/zipr"
        chmod +x "$APP_BUNDLE/Contents/Resources/zipr"
        echo "Bundled sidecar + zipr into $APP_BUNDLE"
        ;;
    windows)
        flutter build windows --release

        WINDOWS_DIR="$PROJECT_DIR/flutter_app/build/windows/x64/runner/Release"
        mkdir -p "$WINDOWS_DIR/data"
        cp "$BUILD_DIR/sidecar/go_sidecar" "$WINDOWS_DIR/data/go_sidecar.exe"
        cp "$BUILD_DIR/zipr/zipr" "$WINDOWS_DIR/data/zipr.exe"
        echo "Bundled sidecar + zipr into $WINDOWS_DIR/data/"
        ;;
    linux)
        flutter build linux --release

        LINUX_DIR="$PROJECT_DIR/flutter_app/build/linux/x64/release/bundle"
        mkdir -p "$LINUX_DIR/data"
        cp "$BUILD_DIR/sidecar/go_sidecar" "$LINUX_DIR/data/go_sidecar"
        chmod +x "$LINUX_DIR/data/go_sidecar"
        cp "$BUILD_DIR/zipr/zipr" "$LINUX_DIR/data/zipr"
        chmod +x "$LINUX_DIR/data/zipr"
        echo "Bundled sidecar + zipr into $LINUX_DIR/data/"
        ;;
    *)
        echo "Unknown platform: $PLATFORM"
        echo "Usage: $0 [macos|windows|linux]"
        exit 1
        ;;
esac

echo ""
echo "=== Release build complete ==="
