#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SIDECAR_DIR="$PROJECT_DIR/go_sidecar"
BUILD_DIR="$PROJECT_DIR/build/sidecar"

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

echo "=== Sidecar build complete ==="
