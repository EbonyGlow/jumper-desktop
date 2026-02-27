#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
EVIDENCE_ROOT="${1:-${ROOT_DIR}/release-evidence}"

required_artifacts=(
  "runtime-evidence-darwin-arm64"
  "runtime-evidence-linux-amd64"
  "runtime-evidence-windows-amd64"
)

echo "[m3-gate] evidence root: ${EVIDENCE_ROOT}"

for artifact in "${required_artifacts[@]}"; do
  artifact_dir="${EVIDENCE_ROOT}/${artifact}"
  if [[ ! -d "${artifact_dir}" ]]; then
    echo "[m3-gate] missing artifact directory: ${artifact_dir}"
    exit 1
  fi

  platform_arch="${artifact#runtime-evidence-}"
  runtime_log="${artifact_dir}/engine/runtime-assets/${platform_arch}/runtime.log"
  proxies_json="${artifact_dir}/engine/runtime-assets/${platform_arch}/proxies.json"
  checksums_json="${artifact_dir}/engine/runtime-assets/checksums.json"

  for required_file in "${runtime_log}" "${proxies_json}" "${checksums_json}"; do
    if [[ ! -f "${required_file}" ]]; then
      echo "[m3-gate] missing required file: ${required_file}"
      exit 1
    fi
  done

  if command -v rg >/dev/null 2>&1; then
    rg -q "sing-box started" "${runtime_log}" || {
      echo "[m3-gate] startup marker missing in ${runtime_log}"
      exit 1
    }
  else
    grep -q "sing-box started" "${runtime_log}" || {
      echo "[m3-gate] startup marker missing in ${runtime_log}"
      exit 1
    }
  fi

  proxy_count="$(python3 - <<'PY' "${proxies_json}"
import json,sys
try:
  data=json.load(open(sys.argv[1]))
  print(len((data.get("proxies") or {}).keys()))
except Exception:
  print(0)
PY
)"
  if [[ "${proxy_count}" -le 0 ]]; then
    echo "[m3-gate] invalid proxy count ${proxy_count} in ${proxies_json}"
    exit 1
  fi

  echo "[m3-gate] ${platform_arch} evidence ok (proxy_count=${proxy_count})"
done

echo "[m3-gate] all required evidence verified"
