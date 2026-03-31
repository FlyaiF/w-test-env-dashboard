#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ZIPR_DIR="$PROJECT_DIR/zipr"
BUILD_DIR="$PROJECT_DIR/build/zipr"

echo "=== Building zipr CLI ==="
cd "$ZIPR_DIR"

if [ "$1" = "all" ]; then
    echo "Cross-compiling for all platforms..."

    cargo build --release --target x86_64-apple-darwin
    mkdir -p "$BUILD_DIR/darwin-amd64"
    cp target/x86_64-apple-darwin/release/zipr "$BUILD_DIR/darwin-amd64/zipr"
    echo "  darwin/amd64 done"

    cargo build --release --target aarch64-apple-darwin
    mkdir -p "$BUILD_DIR/darwin-arm64"
    cp target/aarch64-apple-darwin/release/zipr "$BUILD_DIR/darwin-arm64/zipr"
    echo "  darwin/arm64 done"
else
    echo "Building for current platform..."
    cargo build --release
    mkdir -p "$BUILD_DIR"
    cp target/release/zipr "$BUILD_DIR/zipr"
    echo "  done: $BUILD_DIR/zipr"
fi

echo "=== zipr build complete ==="
