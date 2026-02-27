#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_ARCH="${1:-darwin-arm64}"
VERSION="${2:-1.12.22}"
API_BASE="${3:-http://127.0.0.1:20123}"

BINARY_NAME="sing-box"
if [[ "${PLATFORM_ARCH}" == windows-* ]]; then
  BINARY_NAME="sing-box.exe"
fi

BINARY_PATH="${ROOT_DIR}/${PLATFORM_ARCH}/sing-box-${VERSION}-${PLATFORM_ARCH}/${BINARY_NAME}"
CONFIG_PATH="${ROOT_DIR}/${PLATFORM_ARCH}/minimal-config.json"
WORK_DIR="${ROOT_DIR}/${PLATFORM_ARCH}"
PROXIES_OUT="${ROOT_DIR}/${PLATFORM_ARCH}/proxies.json"
RUNTIME_LOG="${ROOT_DIR}/${PLATFORM_ARCH}/runtime.log"

has_startup_marker() {
  if command -v rg >/dev/null 2>&1; then
    rg -q "sing-box started" "${RUNTIME_LOG}"
    return
  fi
  grep -q "sing-box started" "${RUNTIME_LOG}"
}

if [[ ! -f "${BINARY_PATH}" ]]; then
  echo "Binary not found: ${BINARY_PATH}"
  exit 1
fi
if [[ ! -f "${CONFIG_PATH}" ]]; then
  echo "Config not found: ${CONFIG_PATH}"
  exit 1
fi

echo "[runtime-assets] Starting runtime for validation"
"${BINARY_PATH}" run --disable-color -c "${CONFIG_PATH}" -D "${WORK_DIR}" > "${RUNTIME_LOG}" 2>&1 &
PID=$!
cleanup() {
  if kill -0 "${PID}" >/dev/null 2>&1; then
    kill "${PID}" >/dev/null 2>&1 || true
    wait "${PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "[runtime-assets] Waiting for startup log marker"
for _ in $(seq 1 20); do
  if has_startup_marker; then
    break
  fi
  sleep 1
done
if ! has_startup_marker; then
  echo "Startup marker not found in ${RUNTIME_LOG}"
  exit 1
fi

echo "[runtime-assets] Querying proxies API"
for _ in $(seq 1 20); do
  if curl -fsS "${API_BASE}/proxies" -o "${PROXIES_OUT}"; then
    break
  fi
  sleep 1
done

if [[ ! -s "${PROXIES_OUT}" ]]; then
  echo "Empty proxies response: ${PROXIES_OUT}"
  exit 1
fi

PROXY_COUNT="$(python3 - <<'PY' "${PROXIES_OUT}"
import json,sys
try:
  data=json.load(open(sys.argv[1]))
  print(len((data.get("proxies") or {}).keys()))
except Exception:
  print(0)
PY
)"
if [[ "${PROXY_COUNT}" -le 0 ]]; then
  echo "Invalid proxy count: ${PROXY_COUNT}"
  exit 1
fi

echo "[runtime-assets] Stopping runtime"
kill "${PID}" >/dev/null 2>&1 || true
wait "${PID}" 2>/dev/null || true

echo "[runtime-assets] Validation succeeded"
echo "[runtime-assets] startup marker found in ${RUNTIME_LOG}"
echo "[runtime-assets] proxy count: ${PROXY_COUNT}"
echo "[runtime-assets] proxies saved to ${PROXIES_OUT}"
