#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="$PROJECT_DIR/apps/zipr_tool"
STAMP="$APP_DIR/.dart_tool/codex_pub_get.stamp"

if [ ! -f "$APP_DIR/assets/fonts/SarasaGothicSC-Regular.ttf" ]; then
    "$SCRIPT_DIR/sync_assets.sh"
fi

mkdir -p "$APP_DIR/.dart_tool"

NEEDS_PUB_GET=0
if [ ! -f "$STAMP" ]; then
    NEEDS_PUB_GET=1
else
    for DEP_FILE in \
        "$APP_DIR/pubspec.yaml" \
        "$APP_DIR/pubspec.lock" \
        "$APP_DIR/pubspec_overrides.yaml" \
        "$PROJECT_DIR/packages/shared_ui/pubspec.yaml" \
        "$APP_DIR/rust_builder/pubspec.yaml"
    do
        if [ -f "$DEP_FILE" ] && [ "$DEP_FILE" -nt "$STAMP" ]; then
            NEEDS_PUB_GET=1
            break
        fi
    done
fi

cd "$APP_DIR"

if [ "$NEEDS_PUB_GET" -eq 1 ]; then
    echo "--- Dependencies changed; running flutter pub get ---"
    flutter pub get
    touch "$STAMP"
else
    echo "--- Dependencies unchanged; skipping pub get ---"
fi

flutter run --no-pub -d macos "$@"
