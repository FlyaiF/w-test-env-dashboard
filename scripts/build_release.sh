#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PLATFORM=${1:-macos}

case "$PLATFORM" in
    macos|windows|linux) ;;
    *)
        echo "Unknown platform: $PLATFORM"
        echo "Usage: $0 [macos|windows|linux]"
        exit 1
        ;;
esac

echo "=== Release build for $PLATFORM ==="

# Step 0: Sync shared assets (fonts) into each app's local assets/
echo ""
echo "--- Step 0: Syncing shared assets ---"
"$SCRIPT_DIR/sync_assets.sh"

# Step 1: Build and test the deployable Spring backend with all probe drivers.
echo ""
echo "--- Step 1: Building Spring backend ---"
mvn -B -f "$PROJECT_DIR/backend/pom.xml" -Pprobe-drivers clean verify

BACKEND_JAR="$(find "$PROJECT_DIR/backend/target" -maxdepth 1 -type f \
    -name 'env-dashboard-backend-*.jar' ! -name '*.original' -print -quit)"
if [[ -z "$BACKEND_JAR" ]]; then
    echo "ERROR: backend build did not produce an executable jar" >&2
    exit 1
fi

for entry in \
    'BOOT-INF/lib/DmJdbcDriver18-8.1.3.140.jar' \
    'BOOT-INF/lib/oceanbase-client-2.4.7.1.jar'; do
    if ! jar tf "$BACKEND_JAR" | grep -Fx "$entry"; then
        echo "ERROR: backend jar is missing required probe driver: $entry" >&2
        exit 1
    fi
done
echo "  Created $BACKEND_JAR"

# Step 2: Build the thin env_viewer client. The backend is deployed separately.
echo ""
echo "--- Step 2: Building env_viewer ---"
cd "$PROJECT_DIR/apps/env_viewer"
# Release packaging must start from a clean client output. Incremental platform
# builds can retain unowned plugin bundles or sidecar resources from older builds.
flutter clean
flutter pub get

# Self-update swap/rollback helper (docs/guides/client-update.md): a standalone Dart
# binary bundled with the app, because a running app cannot replace itself.
build_updater() {
    local out="$1"
    (cd "$PROJECT_DIR/apps/env_viewer/updater" \
        && dart pub get \
        && dart compile exe bin/env_viewer_updater.dart -o "$out")
}

case "$PLATFORM" in
    macos)
        flutter build macos --release
        APP="$PROJECT_DIR/apps/env_viewer/build/macos/Build/Products/Release/env_viewer.app"
        # Incremental Xcode builds do not remove unowned resources copied by an older release script.
        # Purge and guard the retired sidecar/JDBC payload before handing the app to a user.
        rm -f "$APP/Contents/Resources/go_sidecar"
        rm -rf "$APP/Contents/Resources/jdbc"
        test ! -e "$APP/Contents/Resources/go_sidecar"
        test ! -e "$APP/Contents/Resources/jdbc"
        build_updater "$APP/Contents/Resources/env_viewer_updater"
        test -x "$APP/Contents/Resources/env_viewer_updater"
        echo "  Created $APP"
        ;;
    windows)
        flutter build windows --release
        RUNNER_DIR="$PROJECT_DIR/apps/env_viewer/build/windows/x64/runner/Release"
        rm -f "$RUNNER_DIR/data/go_sidecar.exe"
        rm -rf "$RUNNER_DIR/data/jdbc"
        test ! -e "$RUNNER_DIR/data/go_sidecar.exe"
        test ! -e "$RUNNER_DIR/data/jdbc"
        build_updater "$RUNNER_DIR/env_viewer_updater.exe"
        test -e "$RUNNER_DIR/env_viewer_updater.exe"
        echo "  Created $RUNNER_DIR/env_viewer.exe"
        ;;
    linux)
        flutter build linux --release
        BUNDLE_DIR="$PROJECT_DIR/apps/env_viewer/build/linux/x64/release/bundle"
        rm -f "$BUNDLE_DIR/data/go_sidecar"
        rm -rf "$BUNDLE_DIR/data/jdbc"
        test ! -e "$BUNDLE_DIR/data/go_sidecar"
        test ! -e "$BUNDLE_DIR/data/jdbc"
        echo "  Created $BUNDLE_DIR/env_viewer"
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
