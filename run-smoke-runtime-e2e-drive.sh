#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIME_DIR="${ROOT_DIR}/engine/runtime-assets/darwin-arm64"
VERSION="${1:-1.12.22}"
BINARY_PATH="${RUNTIME_DIR}/sing-box-${VERSION}-darwin-arm64/sing-box"
CONFIG_PATH="${RUNTIME_DIR}/minimal-config.json"

if [[ ! -f "${BINARY_PATH}" ]]; then
  echo "[smoke-e2e-drive] Runtime binary not found, fetching..."
  "${ROOT_DIR}/engine/runtime-assets/fetch-sing-box.sh" darwin-arm64 "${VERSION}"
fi

if [[ ! -f "${CONFIG_PATH}" ]]; then
  echo "[smoke-e2e-drive] Missing minimal config: ${CONFIG_PATH}"
  exit 1
fi

echo "[smoke-e2e-drive] Starting runtime externally"
"${BINARY_PATH}" run --disable-color -c "${CONFIG_PATH}" -D "${RUNTIME_DIR}" > "${RUNTIME_DIR}/integration-drive-runtime.log" 2>&1 &
CORE_PID=$!
cleanup() {
  if kill -0 "${CORE_PID}" >/dev/null 2>&1; then
    kill "${CORE_PID}" >/dev/null 2>&1 || true
    wait "${CORE_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT
sleep 2

echo "[smoke-e2e-drive] Running integration test"
cd "${ROOT_DIR}/flutter/apps/sdk_smoke_app"
fvm flutter test integration_test/sdk_runtime_chain_test.dart -d macos \
  --dart-define=JUMPER_CORE_BIN="${BINARY_PATH}" \
  --dart-define=JUMPER_CORE_ARGS="run --disable-color -c ${CONFIG_PATH} -D ${RUNTIME_DIR}" \
  --dart-define=JUMPER_CORE_WORKDIR="${RUNTIME_DIR}" \
  --dart-define=JUMPER_CORE_API_BASE=http://127.0.0.1:20123 \
  --dart-define=JUMPER_SKIP_START=true
