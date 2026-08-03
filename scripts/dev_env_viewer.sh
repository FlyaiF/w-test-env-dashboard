#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="$PROJECT_DIR/apps/env_viewer"
STAMP="$APP_DIR/.dart_tool/codex_pub_get.stamp"

usage() {
    cat <<'EOF'
Usage:
  scripts/dev_env_viewer.sh [prepare]
  scripts/dev_env_viewer.sh run [flutter run args...]

Syncs app assets and runs flutter pub get when dependencies changed. env_viewer is
a thin client: this script does not build or start the Spring backend. Run
scripts/dev_backend.sh in another terminal, or connect to an existing backend.

Environment:
  ENV_DASHBOARD_BACKEND_URL=http://host:port
    Optional backend override. Defaults to the saved setting, then localhost:8080.
EOF
}

default_device() {
    case "$(uname -s)" in
        Darwin*) echo "macos" ;;
        Linux*) echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *) echo "" ;;
    esac
}

run_pub_get_if_needed() {
    mkdir -p "$APP_DIR/.dart_tool"

    local needs_pub_get=0
    if [ ! -f "$STAMP" ]; then
        needs_pub_get=1
    else
        for dep_file in \
            "$APP_DIR/pubspec.yaml" \
            "$APP_DIR/pubspec.lock" \
            "$APP_DIR/pubspec_overrides.yaml" \
            "$PROJECT_DIR/packages/shared_ui/pubspec.yaml"
        do
            if [ -f "$dep_file" ] && [ "$dep_file" -nt "$STAMP" ]; then
                needs_pub_get=1
                break
            fi
        done
    fi

    if [ "$needs_pub_get" -eq 1 ]; then
        echo "=== Fetching env_viewer Flutter dependencies ==="
        (cd "$APP_DIR" && flutter pub get)
        touch "$STAMP"
    else
        echo "=== env_viewer Flutter dependencies unchanged ==="
    fi
}

prepare() {
    echo "=== Syncing shared assets ==="
    "$SCRIPT_DIR/sync_assets.sh"

    run_pub_get_if_needed
}

command="${1:-prepare}"
case "$command" in
    prepare)
        shift || true
        prepare
        ;;
    run)
        shift || true
        prepare
        cd "$APP_DIR"
        if [ "$#" -eq 0 ]; then
            device="$(default_device)"
            if [ -n "$device" ]; then
                exec flutter run --no-pub -d "$device"
            fi
            exec flutter run --no-pub
        fi
        exec flutter run --no-pub "$@"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        echo "error: unknown command: $command" >&2
        usage >&2
        exit 2
        ;;
esac
