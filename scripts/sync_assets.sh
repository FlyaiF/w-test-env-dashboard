#!/bin/bash
# Copy shared font assets from repo-root assets/ into each app's local
# assets/ directory. Flutter's bundler does not reliably resolve `..`
# paths in pubspec.yaml on Windows, so each app needs the assets sitting
# next to its own pubspec.
#
# Run this before `flutter build`, `flutter run`, or `flutter test` if
# you've just cloned the repo or pulled new font files. The build scripts
# and CI call it automatically.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

for APP in env_viewer zipr_tool; do
    DEST="$PROJECT_DIR/apps/$APP/assets/fonts"
    mkdir -p "$DEST"
    cp -R "$PROJECT_DIR/assets/fonts/." "$DEST/"
    echo "Synced fonts into apps/$APP/assets/fonts/"
done
