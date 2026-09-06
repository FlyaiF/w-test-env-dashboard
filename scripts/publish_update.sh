#!/bin/bash
# Publish an env_viewer release to the backend's client-updates directory
# (docs/guides/client-update.md). Run after the tagged CI build has finished:
#
#   UPDATE_SSH_TARGET=user@backend-host \
#   UPDATE_REMOTE_DIR=/opt/env-dashboard/client-updates \
#   scripts/publish_update.sh v1.2.0
#
# Optional: BACKEND_URL=http://backend-host:8080 to verify what clients will
# be offered after the copy. Requires the GitHub CLI (`gh`) authenticated for
# this repository.
set -euo pipefail

TAG=${1:-}
if [[ -z "$TAG" ]]; then
    echo "Usage: $0 <tag>   e.g. $0 v1.2.0" >&2
    exit 64
fi
: "${UPDATE_SSH_TARGET:?set UPDATE_SSH_TARGET, e.g. user@backend-host}"
: "${UPDATE_REMOTE_DIR:?set UPDATE_REMOTE_DIR, e.g. /opt/env-dashboard/client-updates}"

VERSION="${TAG#v}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "--- Downloading release assets for $TAG ---"
gh release download "$TAG" --dir "$WORK_DIR" --pattern "env_viewer-$VERSION-*.zip"
# Notes are optional; tolerate their absence.
gh release download "$TAG" --dir "$WORK_DIR" --pattern "env_viewer-$VERSION.notes.md" || true

for platform in macos windows; do
    if [[ ! -f "$WORK_DIR/env_viewer-$VERSION-$platform.zip" ]]; then
        echo "ERROR: release $TAG has no env_viewer-$VERSION-$platform.zip — refusing a half release" >&2
        exit 1
    fi
done
if [[ ! -f "$WORK_DIR/env_viewer-$VERSION.notes.md" ]]; then
    echo "NOTE: no release notes attached; the update popup will show only the version."
fi

echo "--- Copying to $UPDATE_SSH_TARGET:$UPDATE_REMOTE_DIR ---"
scp "$WORK_DIR"/env_viewer-* "$UPDATE_SSH_TARGET:$UPDATE_REMOTE_DIR/"

if [[ -n "${BACKEND_URL:-}" ]]; then
    echo "--- Verifying what clients will be offered ---"
    for platform in macos windows; do
        echo "$platform:"
        curl -fsS "${BACKEND_URL%/}/api/client-updates/env_viewer/latest?platform=$platform" \
            | python3 -m json.tool || echo "  (no update offered — check envdashboard.client-updates.dir on the backend)"
    done
fi

echo "--- Published env_viewer $VERSION ---"
