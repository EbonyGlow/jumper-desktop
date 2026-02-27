#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIME_DIR="${ROOT_DIR}/engine/runtime-assets/darwin-arm64"
VERSION="${1:-1.12.22}"
BINARY_PATH="${RUNTIME_DIR}/sing-box-${VERSION}-darwin-arm64/sing-box"
CONFIG_PATH="${RUNTIME_DIR}/minimal-config.json"
CONTAINER_BUNDLE_ID="${2:-com.example.sdkSmokeApp}"
CONTAINER_STAGE_DIR="${HOME}/Library/Containers/${CONTAINER_BUNDLE_ID}/Data/tmp/jumper-runtime"
STAGED_BINARY_PATH="${CONTAINER_STAGE_DIR}/sing-box"
STAGED_CONFIG_PATH="${CONTAINER_STAGE_DIR}/config.json"

if [[ ! -f "${BINARY_PATH}" ]]; then
  echo "[smoke-e2e-drive-direct] Runtime binary not found, fetching..."
  "${ROOT_DIR}/engine/runtime-assets/fetch-sing-box.sh" darwin-arm64 "${VERSION}"
fi

if [[ ! -f "${CONFIG_PATH}" ]]; then
  echo "[smoke-e2e-drive-direct] Missing minimal config: ${CONFIG_PATH}"
  exit 1
fi

echo "[smoke-e2e-drive-direct] Staging runtime into app container: ${CONTAINER_STAGE_DIR}"
mkdir -p "${CONTAINER_STAGE_DIR}"
cp -f "${BINARY_PATH}" "${STAGED_BINARY_PATH}"
cp -f "${CONFIG_PATH}" "${STAGED_CONFIG_PATH}"
chmod +x "${STAGED_BINARY_PATH}"

echo "[smoke-e2e-drive-direct] Running integration test with SDK-managed startup"
cd "${ROOT_DIR}/flutter/apps/sdk_smoke_app"
fvm flutter test integration_test/sdk_runtime_chain_test.dart -d macos \
  --dart-define=JUMPER_CORE_BIN="${STAGED_BINARY_PATH}" \
  --dart-define=JUMPER_CORE_ARGS="run --disable-color -c ${STAGED_CONFIG_PATH} -D ${CONTAINER_STAGE_DIR}" \
  --dart-define=JUMPER_CORE_CONFIG_PATH="${STAGED_CONFIG_PATH}" \
  --dart-define=JUMPER_CORE_WORKDIR="${CONTAINER_STAGE_DIR}" \
  --dart-define=JUMPER_CORE_API_BASE=http://127.0.0.1:20123 \
  --dart-define=JUMPER_ASSUME_BIN_ACCESSIBLE=true \
  --dart-define=JUMPER_SKIP_START=false
