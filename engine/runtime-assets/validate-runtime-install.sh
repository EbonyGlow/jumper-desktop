#!/usr/bin/env bash
set -euo pipefail

RUNTIME_DIR="${1:-}"
API_BASE="${2:-http://127.0.0.1:20123}"

if [[ -z "${RUNTIME_DIR}" ]]; then
  echo "Usage: $0 <runtime_dir> [api_base]"
  exit 1
fi

if [[ -f "${RUNTIME_DIR}/sing-box" ]]; then
  BINARY_PATH="${RUNTIME_DIR}/sing-box"
elif [[ -f "${RUNTIME_DIR}/sing-box.exe" ]]; then
  BINARY_PATH="${RUNTIME_DIR}/sing-box.exe"
else
  echo "[validate-install] runtime binary not found in ${RUNTIME_DIR}"
  exit 1
fi

CONFIG_PATH="${RUNTIME_DIR}/config.json"
if [[ ! -f "${CONFIG_PATH}" ]]; then
  echo "[validate-install] config not found: ${CONFIG_PATH}"
  exit 1
fi

RUNTIME_LOG="${RUNTIME_DIR}/runtime-update-validate.log"
PROXIES_OUT="${RUNTIME_DIR}/runtime-update-proxies.json"

has_startup_marker() {
  if command -v rg >/dev/null 2>&1; then
    rg -q "sing-box started" "${RUNTIME_LOG}"
    return
  fi
  grep -q "sing-box started" "${RUNTIME_LOG}"
}

echo "[validate-install] starting runtime from ${RUNTIME_DIR}"
"${BINARY_PATH}" run --disable-color -c "${CONFIG_PATH}" -D "${RUNTIME_DIR}" > "${RUNTIME_LOG}" 2>&1 &
PID=$!

cleanup() {
  if kill -0 "${PID}" >/dev/null 2>&1; then
    kill "${PID}" >/dev/null 2>&1 || true
    wait "${PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

for _ in $(seq 1 20); do
  if has_startup_marker; then
    break
  fi
  sleep 1
done
if ! has_startup_marker; then
  echo "[validate-install] startup marker not found in ${RUNTIME_LOG}"
  exit 1
fi

for _ in $(seq 1 20); do
  if curl -fsS "${API_BASE}/proxies" -o "${PROXIES_OUT}"; then
    break
  fi
  sleep 1
done
if [[ ! -s "${PROXIES_OUT}" ]]; then
  echo "[validate-install] proxies response empty: ${PROXIES_OUT}"
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
  echo "[validate-install] invalid proxy count: ${PROXY_COUNT}"
  exit 1
fi

echo "[validate-install] success"
echo "[validate-install] proxy count: ${PROXY_COUNT}"
