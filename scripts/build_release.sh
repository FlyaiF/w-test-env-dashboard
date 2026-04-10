#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
PLATFORM=${1:-macos}
PROFILES=("env_viewer" "zipr_tool")

echo "=== Release build for $PLATFORM ==="

# Step 1a: Build Go sidecar
echo ""
echo "--- Step 1a: Building Go sidecar ---"
"$SCRIPT_DIR/build_sidecar.sh"

# Step 1b: Build zipr CLI
echo ""
echo "--- Step 1b: Building zipr CLI ---"
"$SCRIPT_DIR/build_zipr.sh"

# Step 2: Build Flutter app
echo ""
echo "--- Step 2: Building Flutter app ---"
cd "$PROJECT_DIR/flutter_app"

case "$PLATFORM" in
    macos)
        flutter build macos --release

        SRC_APP="$PROJECT_DIR/flutter_app/build/macos/Build/Products/Release/test_env_dashboard.app"
        for PROFILE in "${PROFILES[@]}"; do
            echo "--- Packaging profile: $PROFILE ---"
            DEST_APP="$PROJECT_DIR/flutter_app/build/macos/Build/Products/Release/${PROFILE}.app"
            rm -rf "$DEST_APP"
            cp -R "$SRC_APP" "$DEST_APP"
            cp "$BUILD_DIR/sidecar/go_sidecar" "$DEST_APP/Contents/Resources/go_sidecar"
            chmod +x "$DEST_APP/Contents/Resources/go_sidecar"
            cp "$BUILD_DIR/zipr/zipr" "$DEST_APP/Contents/Resources/zipr"
            chmod +x "$DEST_APP/Contents/Resources/zipr"
            echo "  Created $DEST_APP"
        done
        ;;
    windows)
        flutter build windows --release

        WINDOWS_DIR="$PROJECT_DIR/flutter_app/build/windows/x64/runner/Release"
        mkdir -p "$WINDOWS_DIR/data"
        cp "$BUILD_DIR/sidecar/go_sidecar" "$WINDOWS_DIR/data/go_sidecar.exe"
        cp "$BUILD_DIR/zipr/zipr" "$WINDOWS_DIR/data/zipr.exe"

        for PROFILE in "${PROFILES[@]}"; do
            echo "--- Packaging profile: $PROFILE ---"
            cp "$WINDOWS_DIR/test_env_dashboard.exe" "$WINDOWS_DIR/${PROFILE}.exe"
            echo "  Created $WINDOWS_DIR/${PROFILE}.exe"
        done
        ;;
    linux)
        flutter build linux --release

        LINUX_DIR="$PROJECT_DIR/flutter_app/build/linux/x64/release/bundle"
        mkdir -p "$LINUX_DIR/data"
        cp "$BUILD_DIR/sidecar/go_sidecar" "$LINUX_DIR/data/go_sidecar"
        chmod +x "$LINUX_DIR/data/go_sidecar"
        cp "$BUILD_DIR/zipr/zipr" "$LINUX_DIR/data/zipr"
        chmod +x "$LINUX_DIR/data/zipr"

        for PROFILE in "${PROFILES[@]}"; do
            echo "--- Packaging profile: $PROFILE ---"
            cp "$LINUX_DIR/test_env_dashboard" "$LINUX_DIR/${PROFILE}"
            chmod +x "$LINUX_DIR/${PROFILE}"
            echo "  Created $LINUX_DIR/${PROFILE}"
        done
        ;;
    *)
        echo "Unknown platform: $PLATFORM"
        echo "Usage: $0 [macos|windows|linux]"
        exit 1
        ;;
esac

echo ""
echo "=== Release build complete ==="
echo "Profiles built: ${PROFILES[*]}"
