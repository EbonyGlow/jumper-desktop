#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_ARCH="${1:-darwin-arm64}"
VERSION="${2:-1.12.22}"
DURATION_SECONDS="${3:-1800}"
INTERVAL_SECONDS="${4:-5}"
API_BASE="${5:-http://127.0.0.1:20123}"

RUNTIME_DIR="${ROOT_DIR}/engine/runtime-assets/${PLATFORM_ARCH}"
BINARY_NAME="sing-box"
if [[ "${PLATFORM_ARCH}" == windows-* ]]; then
  BINARY_NAME="sing-box.exe"
fi
BINARY_PATH="${RUNTIME_DIR}/sing-box-${VERSION}-${PLATFORM_ARCH}/${BINARY_NAME}"
CONFIG_PATH="${RUNTIME_DIR}/minimal-config.json"
OUTPUT_DIR="${RUNTIME_DIR}/stability"
TS="$(date +%Y%m%d-%H%M%S)"
JSONL_PATH="${OUTPUT_DIR}/stability-${TS}.jsonl"
SUMMARY_PATH="${OUTPUT_DIR}/stability-${TS}.summary.txt"
RUNTIME_LOG_PATH="${OUTPUT_DIR}/stability-${TS}.runtime.log"

mkdir -p "${OUTPUT_DIR}"

if [[ ! -f "${BINARY_PATH}" ]]; then
  echo "[stability] runtime binary missing: ${BINARY_PATH}"
  exit 1
fi
if [[ ! -f "${CONFIG_PATH}" ]]; then
  echo "[stability] config missing: ${CONFIG_PATH}"
  exit 1
fi

echo "[stability] starting runtime"
"${BINARY_PATH}" run --disable-color -c "${CONFIG_PATH}" -D "${RUNTIME_DIR}" > "${RUNTIME_LOG_PATH}" 2>&1 &
CORE_PID=$!
cleanup() {
  if kill -0 "${CORE_PID}" >/dev/null 2>&1; then
    kill "${CORE_PID}" >/dev/null 2>&1 || true
    wait "${CORE_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

sleep 2

start_epoch="$(date +%s)"
end_epoch="$((start_epoch + DURATION_SECONDS))"
success_count=0
failure_count=0
max_latency_ms=0
sum_latency_ms=0
iterations=0
consecutive_failures=0
max_consecutive_failures=3

echo "[stability] running for ${DURATION_SECONDS}s (interval=${INTERVAL_SECONDS}s)"

while [[ "$(date +%s)" -lt "${end_epoch}" ]]; do
  iter_start_ms="$(python3 -c 'import time; print(int(time.time()*1000))')"
  http_code="$(curl -sS --connect-timeout 2 --max-time 4 -o "${OUTPUT_DIR}/.proxies.tmp.json" -w '%{http_code}' "${API_BASE}/proxies" || true)"
  iter_end_ms="$(python3 -c 'import time; print(int(time.time()*1000))')"
  latency_ms="$((iter_end_ms - iter_start_ms))"

  iterations="$((iterations + 1))"
  if [[ "${latency_ms}" -gt "${max_latency_ms}" ]]; then
    max_latency_ms="${latency_ms}"
  fi
  sum_latency_ms="$((sum_latency_ms + latency_ms))"

  if [[ "${http_code}" == "200" ]]; then
    proxy_count="$(python3 - <<'PY' "${OUTPUT_DIR}/.proxies.tmp.json"
import json,sys
try:
  d=json.load(open(sys.argv[1]))
  print(len((d.get("proxies") or {}).keys()))
except Exception:
  print(0)
PY
)"
    if [[ "${proxy_count}" -gt 0 ]]; then
      success_count="$((success_count + 1))"
      consecutive_failures=0
      printf '{"ts":"%s","ok":true,"http":%s,"latency_ms":%s,"proxy_count":%s}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${http_code}" "${latency_ms}" "${proxy_count}" >> "${JSONL_PATH}"
    else
      failure_count="$((failure_count + 1))"
      consecutive_failures="$((consecutive_failures + 1))"
      printf '{"ts":"%s","ok":false,"reason":"empty_proxies","http":%s,"latency_ms":%s}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${http_code}" "${latency_ms}" >> "${JSONL_PATH}"
    fi
  else
    failure_count="$((failure_count + 1))"
    consecutive_failures="$((consecutive_failures + 1))"
    printf '{"ts":"%s","ok":false,"reason":"http_error","http":"%s","latency_ms":%s}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${http_code}" "${latency_ms}" >> "${JSONL_PATH}"
  fi

  if [[ "${consecutive_failures}" -ge "${max_consecutive_failures}" ]]; then
    echo "[stability] abort: consecutive failures >= ${max_consecutive_failures}"
    break
  fi

  sleep "${INTERVAL_SECONDS}"
done

avg_latency_ms=0
if [[ "${iterations}" -gt 0 ]]; then
  avg_latency_ms="$((sum_latency_ms / iterations))"
fi

{
  echo "platform_arch=${PLATFORM_ARCH}"
  echo "version=${VERSION}"
  echo "duration_seconds=${DURATION_SECONDS}"
  echo "interval_seconds=${INTERVAL_SECONDS}"
  echo "iterations=${iterations}"
  echo "success_count=${success_count}"
  echo "failure_count=${failure_count}"
  echo "avg_latency_ms=${avg_latency_ms}"
  echo "max_latency_ms=${max_latency_ms}"
  echo "jsonl_path=${JSONL_PATH}"
  echo "runtime_log_path=${RUNTIME_LOG_PATH}"
} > "${SUMMARY_PATH}"

echo "[stability] summary:"
cat "${SUMMARY_PATH}"

if [[ "${failure_count}" -gt 0 ]]; then
  echo "[stability] failed due to non-zero failures"
  exit 1
fi

echo "[stability] passed"
