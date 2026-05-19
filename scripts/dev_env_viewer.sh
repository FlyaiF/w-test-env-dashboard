#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="$PROJECT_DIR/apps/env_viewer"
BUILD_DIR="$PROJECT_DIR/build/sidecar"
APP_SIDECAR_DIR="$APP_DIR/go_sidecar"
APP_JDBC_DIR="$APP_SIDECAR_DIR/jdbc"
STAMP="$APP_DIR/.dart_tool/codex_pub_get.stamp"

usage() {
    cat <<'EOF'
Usage:
  scripts/dev_env_viewer.sh [prepare]
  scripts/dev_env_viewer.sh run [flutter run args...]

Builds the Go sidecar and JDBC helper, copies them into apps/env_viewer/go_sidecar/,
syncs app assets, and runs flutter pub get when dependencies changed.

Environment:
  OCEANBASE_JDBC_JAR=/path/to/oceanbase-client.jar
    Optional override used by scripts/build_sidecar.sh when copying the JDBC driver.
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

host_binary_name() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) echo "go_sidecar.exe" ;;
        *) echo "go_sidecar" ;;
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

copy_sidecar_artifacts() {
    local binary_name
    binary_name="$(host_binary_name)"
    local source_binary=""

    for candidate in \
        "$BUILD_DIR/$binary_name" \
        "$BUILD_DIR/go_sidecar" \
        "$BUILD_DIR/go_sidecar.exe"
    do
        if [ -f "$candidate" ]; then
            source_binary="$candidate"
            break
        fi
    done

    if [ -z "$source_binary" ]; then
        echo "error: sidecar binary was not built under $BUILD_DIR" >&2
        exit 1
    fi

    mkdir -p "$APP_SIDECAR_DIR"
    cp "$source_binary" "$APP_SIDECAR_DIR/$binary_name"
    chmod +x "$APP_SIDECAR_DIR/$binary_name" 2>/dev/null || true
    echo "=== Copied sidecar: $APP_SIDECAR_DIR/$binary_name ==="

    if [ -d "$BUILD_DIR/jdbc" ]; then
        mkdir -p "$APP_JDBC_DIR"
        for jar_name in runtime-info-helper.jar oceanbase-client.jar; do
            if [ -f "$BUILD_DIR/jdbc/$jar_name" ]; then
                cp "$BUILD_DIR/jdbc/$jar_name" "$APP_JDBC_DIR/"
                echo "=== Copied JDBC helper: $APP_JDBC_DIR/$jar_name ==="
            else
                echo "warning: missing JDBC artifact: $BUILD_DIR/jdbc/$jar_name"
            fi
        done
    else
        echo "warning: JDBC helper directory not found: $BUILD_DIR/jdbc"
    fi
}

prepare() {
    echo "=== Syncing shared assets ==="
    "$SCRIPT_DIR/sync_assets.sh"

    "$SCRIPT_DIR/build_sidecar.sh"
    copy_sidecar_artifacts
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
