#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_ARCH="${1:-darwin-arm64}"
VERSION_INPUT="${2:-latest}"
BUNDLE_ID="${3:-com.example.sdkSmokeApp}"
RESOLVED_LOCK="${ROOT_DIR}/engine/runtime-assets/resolved-runtime-lock.json"

echo "[release-check] prepare runtime assets"
"${ROOT_DIR}/engine/runtime-assets/prepare-runtime-assets.sh" "${PLATFORM_ARCH}" "${VERSION_INPUT}"

RESOLVED_VERSION="$(python3 - <<'PY' "${RESOLVED_LOCK}"
import json
import pathlib
import sys
lock_path = pathlib.Path(sys.argv[1])
data = json.loads(lock_path.read_text())
print(data["resolved_version"])
PY
)"

echo "[release-check] verify checksums"
"${ROOT_DIR}/engine/runtime-assets/verify-checksums.sh" "${PLATFORM_ARCH}"

echo "[release-check] backup runtime"
"${ROOT_DIR}/engine/runtime-assets/backup-runtime-container.sh" "${BUNDLE_ID}"

echo "[release-check] rollback runtime (latest backup)"
"${ROOT_DIR}/engine/runtime-assets/rollback-runtime-container.sh" "${BUNDLE_ID}" latest

echo "[release-check] validate runtime chain"
"${ROOT_DIR}/engine/runtime-assets/validate-runtime-chain.sh" "${PLATFORM_ARCH}" "${RESOLVED_VERSION}"

echo "[release-check] all checks passed"
