#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_ARCH="${1:-darwin-arm64}"
VERSION="${2:-1.12.22}"
BUNDLE_ID="${3:-com.example.sdkSmokeApp}"

echo "[release-check] verify checksums"
"${ROOT_DIR}/engine/runtime-assets/verify-checksums.sh" "${PLATFORM_ARCH}"

echo "[release-check] backup runtime"
"${ROOT_DIR}/engine/runtime-assets/backup-runtime-container.sh" "${BUNDLE_ID}"

echo "[release-check] rollback runtime (latest backup)"
"${ROOT_DIR}/engine/runtime-assets/rollback-runtime-container.sh" "${BUNDLE_ID}" latest

echo "[release-check] validate runtime chain"
"${ROOT_DIR}/engine/runtime-assets/validate-runtime-chain.sh" "${PLATFORM_ARCH}" "${VERSION}"

echo "[release-check] all checks passed"
