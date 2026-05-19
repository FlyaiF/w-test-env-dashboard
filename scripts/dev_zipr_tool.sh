#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="$PROJECT_DIR/apps/zipr_tool"
STAMP="$APP_DIR/.dart_tool/codex_pub_get.stamp"

usage() {
    cat <<'EOF'
Usage:
  scripts/dev_zipr_tool.sh [prepare]
  scripts/dev_zipr_tool.sh run [flutter run args...]

Syncs app assets, verifies the zipr submodule, and runs flutter pub get when
dependencies changed. zipr_tool does not need a copied sidecar because the Rust
archive engine is linked into the Flutter app by cargokit.
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

ensure_zipr_submodule() {
    if [ -f "$PROJECT_DIR/zipr/Cargo.toml" ]; then
        return
    fi

    echo "=== Initializing zipr submodule ==="
    git -C "$PROJECT_DIR" submodule update --init zipr
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
            "$PROJECT_DIR/packages/shared_ui/pubspec.yaml" \
            "$APP_DIR/rust_builder/pubspec.yaml"
        do
            if [ -f "$dep_file" ] && [ "$dep_file" -nt "$STAMP" ]; then
                needs_pub_get=1
                break
            fi
        done
    fi

    if [ "$needs_pub_get" -eq 1 ]; then
        echo "=== Fetching zipr_tool Flutter dependencies ==="
        (cd "$APP_DIR" && flutter pub get)
        touch "$STAMP"
    else
        echo "=== zipr_tool Flutter dependencies unchanged ==="
    fi
}

prepare() {
    echo "=== Syncing shared assets ==="
    "$SCRIPT_DIR/sync_assets.sh"

    ensure_zipr_submodule

    if ! command -v cargo >/dev/null 2>&1; then
        echo "warning: cargo not found; flutter run/build will fail when cargokit compiles Rust"
    fi

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
