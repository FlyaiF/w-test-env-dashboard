#!/bin/bash
set -euo pipefail

# One-time legacy TENVINFO -> new normalized schema import (slice 07; ADR-0004, PRD §8).
# Reads the old Oracle's TENVINFO, parses the composite strings / fixed DB slots, and writes
# Environment / Component / Server / Database rows into the backend's own (new-schema) datasource.
# Emits a report of every blanked field and dropped row, with reasons, for human follow-up.
#
# DRY RUN BY DEFAULT — it parses and reports but writes nothing. Pass --apply to actually write.
#
# Legacy database coordinates (required):
#   LEGACY_JDBC_URL        e.g. jdbc:oracle:thin:@oldhost:1521/ORCL
#   LEGACY_DB_USERNAME
#   LEGACY_DB_PASSWORD
#   LEGACY_TABLE           optional, defaults to TENVINFO
#   LEGACY_TIMEZONE        optional, defaults to Asia/Shanghai (Oracle DATE has no timezone)
#
# Target schema = the backend's own datasource, selected by the Spring profile in APP_PROFILES
# (default: prod, which reads ORACLE_JDBC_URL / ORACLE_USERNAME / ORACLE_PASSWORD per
# application-prod.yml). Use APP_PROFILES=local to trial the import against an ephemeral H2.
#
# Usage:
#   LEGACY_JDBC_URL=... LEGACY_DB_USERNAME=... LEGACY_DB_PASSWORD=... \
#   ORACLE_JDBC_URL=... ORACLE_USERNAME=... ORACLE_PASSWORD=... \
#   scripts/import_tenvinfo.sh            # dry run (preview report, no writes)
#
#   ... scripts/import_tenvinfo.sh --apply    # write into the target schema

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKEND_DIR="$PROJECT_DIR/backend"

# Flutter's proxy gotcha (AGENTS.md) also trips Maven networking; clear it.
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy || true

: "${LEGACY_JDBC_URL:?Set LEGACY_JDBC_URL to the legacy database JDBC URL}"

dry_run="true"
case "${1:-}" in
    "")        dry_run="true" ;;
    --apply)   dry_run="false" ;;
    *)         echo "Unknown argument: $1 (expected nothing for dry run, or --apply to write)" >&2
               exit 2 ;;
esac

profiles="${APP_PROFILES:-prod},import"
table="${LEGACY_TABLE:-TENVINFO}"
legacy_timezone="${LEGACY_TIMEZONE:-Asia/Shanghai}"

# Oracle DATE carries no timezone. Pin the importer JVM's local zone so the same
# legacy value becomes the same Instant regardless of which workstation runs it.
export TZ="$legacy_timezone"

# Bind legacy coordinates through Spring's environment-variable mapping instead
# of Maven command-line arguments. In particular, keep the plaintext password out
# of `ps` / process command lines during the one-time migration.
export ENVDASHBOARD_IMPORT_LEGACY_URL="$LEGACY_JDBC_URL"
export ENVDASHBOARD_IMPORT_LEGACY_USERNAME="${LEGACY_DB_USERNAME:-}"
export ENVDASHBOARD_IMPORT_LEGACY_PASSWORD="${LEGACY_DB_PASSWORD:-}"
export ENVDASHBOARD_IMPORT_TABLE="$table"
export ENVDASHBOARD_IMPORT_DRY_RUN="$dry_run"
# Defense in depth for a run-once migration: do not start the HTTP server or
# background collector while the target catalog is only partially populated.
export SPRING_MAIN_WEB_APPLICATION_TYPE="none"
export ENVDASHBOARD_COLLECTION_SCHEDULER_ENABLED="false"

echo "TENVINFO import — profiles=${profiles}, dryRun=${dry_run}, table=${table}, timezone=${legacy_timezone}"

exec mvn -f "$BACKEND_DIR/pom.xml" spring-boot:run \
    -Dspring-boot.run.profiles="${profiles}"
