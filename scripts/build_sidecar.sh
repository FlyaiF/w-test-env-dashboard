#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SIDECAR_DIR="$PROJECT_DIR/go_sidecar"
BUILD_DIR="$PROJECT_DIR/build/sidecar"
JDBC_HELPER_DIR="$SIDECAR_DIR/jdbc_helper"
JDBC_BUILD_DIR="$BUILD_DIR/jdbc"
OCEANBASE_DRIVER_SRC="${OCEANBASE_JDBC_JAR:-$HOME/.m2/repository/com/oceanbase/oceanbase-client/2.4.7.1/oceanbase-client-2.4.7.1.jar}"

echo "=== Building Go sidecar ==="
cd "$SIDECAR_DIR"

VERSION=$(git -C "$PROJECT_DIR" describe --tags --always 2>/dev/null || echo "dev")
COMMIT=$(git -C "$PROJECT_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
PKG="test-env-dashboard/go_sidecar/buildinfo"
LDFLAGS="-s -w -X $PKG.Version=$VERSION -X $PKG.Commit=$COMMIT -X $PKG.BuildTime=$BUILD_TIME"

# Build for current platform only by default
# Pass "all" as argument to cross-compile
if [ "$1" = "all" ]; then
    echo "Cross-compiling for all platforms..."

    GOOS=darwin GOARCH=amd64 go build -ldflags="$LDFLAGS" -o "$BUILD_DIR/darwin-amd64/go_sidecar" .
    echo "  darwin/amd64 done"

    GOOS=darwin GOARCH=arm64 go build -ldflags="$LDFLAGS" -o "$BUILD_DIR/darwin-arm64/go_sidecar" .
    echo "  darwin/arm64 done"

    GOOS=windows GOARCH=amd64 go build -ldflags="$LDFLAGS" -o "$BUILD_DIR/windows-amd64/go_sidecar.exe" .
    echo "  windows/amd64 done"

    GOOS=linux GOARCH=amd64 go build -ldflags="$LDFLAGS" -o "$BUILD_DIR/linux-amd64/go_sidecar" .
    echo "  linux/amd64 done"
else
    echo "Building for current platform..."
    go build -ldflags="$LDFLAGS" -o "$BUILD_DIR/go_sidecar" .

    # Also copy to go_sidecar/ for dev mode
    cp "$BUILD_DIR/go_sidecar" "$SIDECAR_DIR/go_sidecar"
    echo "  done: $BUILD_DIR/go_sidecar"
fi

echo ""
echo "=== Building JDBC helper ==="
mkdir -p "$JDBC_BUILD_DIR/classes"
if command -v javac >/dev/null 2>&1 && command -v jar >/dev/null 2>&1; then
    javac -source 8 -target 8 -d "$JDBC_BUILD_DIR/classes" "$JDBC_HELPER_DIR/RuntimeInfoHelper.java"
    jar cf "$JDBC_BUILD_DIR/runtime-info-helper.jar" -C "$JDBC_BUILD_DIR/classes" RuntimeInfoHelper.class
    if [ -f "$OCEANBASE_DRIVER_SRC" ]; then
        cp "$OCEANBASE_DRIVER_SRC" "$JDBC_BUILD_DIR/oceanbase-client.jar"
        echo "  copied OceanBase JDBC driver"
    else
        echo "  warning: OceanBase JDBC driver not found: $OCEANBASE_DRIVER_SRC"
        echo "  set OCEANBASE_JDBC_JAR=/path/to/oceanbase-client.jar to include it"
    fi
    echo "  done: $JDBC_BUILD_DIR/runtime-info-helper.jar"
else
    echo "  warning: javac/jar not found; OceanBase Oracle JDBC helper was not built"
fi

echo "=== Sidecar build complete ==="
