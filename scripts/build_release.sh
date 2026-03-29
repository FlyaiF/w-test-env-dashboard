#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
PLATFORM=${1:-macos}

echo "=== Release build for $PLATFORM ==="

# Step 1: Build Go sidecar
echo ""
echo "--- Step 1: Building Go sidecar ---"
"$SCRIPT_DIR/build_sidecar.sh"

# Step 2: Bundle sidecar into Flutter app
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
        echo "Bundled sidecar into $APP_BUNDLE"
        ;;
    windows)
        flutter build windows --release

        WINDOWS_DIR="$PROJECT_DIR/flutter_app/build/windows/x64/runner/Release"
        mkdir -p "$WINDOWS_DIR/data"
        cp "$BUILD_DIR/sidecar/go_sidecar" "$WINDOWS_DIR/data/go_sidecar.exe"
        echo "Bundled sidecar into $WINDOWS_DIR/data/"
        ;;
    linux)
        flutter build linux --release

        LINUX_DIR="$PROJECT_DIR/flutter_app/build/linux/x64/release/bundle"
        mkdir -p "$LINUX_DIR/data"
        cp "$BUILD_DIR/sidecar/go_sidecar" "$LINUX_DIR/data/go_sidecar"
        chmod +x "$LINUX_DIR/data/go_sidecar"
        echo "Bundled sidecar into $LINUX_DIR/data/"
        ;;
    *)
        echo "Unknown platform: $PLATFORM"
        echo "Usage: $0 [macos|windows|linux]"
        exit 1
        ;;
esac

echo ""
echo "=== Release build complete ==="
