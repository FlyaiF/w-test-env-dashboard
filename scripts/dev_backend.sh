#!/bin/bash
set -euo pipefail

# Runs the Spring Boot backend on the local profile (H2 in Oracle mode + demo seed data).
#
# Usage:
#   scripts/dev_backend.sh [run]          # boot the backend (default)
#   scripts/dev_backend.sh test           # run the backend test suite
#
# Once running:
#   curl localhost:8080/api/environments
#   curl localhost:8080/actuator/health
#   curl -X POST localhost:8080/api/environments/1/refresh   # manual Version Collection (slice 05)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKEND_DIR="$PROJECT_DIR/backend"

# Flutter's proxy gotcha (AGENTS.md) also trips Maven/Testcontainers networking; clear it.
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy || true

cmd="${1:-run}"

case "$cmd" in
    run)
        exec mvn -f "$BACKEND_DIR/pom.xml" spring-boot:run \
            -Dspring-boot.run.profiles=local
        ;;
    test)
        exec mvn -f "$BACKEND_DIR/pom.xml" test
        ;;
    *)
        echo "Unknown command: $cmd (expected: run | test)" >&2
        exit 2
        ;;
esac
