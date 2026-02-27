#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
FAILURES=0

has_pattern() {
  local pattern="$1"
  local file="$2"
  if command -v rg >/dev/null 2>&1; then
    rg -q "$pattern" "$file"
    return
  fi
  grep -Eq "$pattern" "$file"
}

require_pattern() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  if ! has_pattern "$pattern" "$file"; then
    echo "[audit-guard] FAIL: ${message}"
    FAILURES=$((FAILURES + 1))
  else
    echo "[audit-guard] OK: ${message}"
  fi
}

forbid_pattern() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  if has_pattern "$pattern" "$file"; then
    echo "[audit-guard] FAIL: ${message}"
    FAILURES=$((FAILURES + 1))
  else
    echo "[audit-guard] OK: ${message}"
  fi
}

RELEASE_CHECK="${ROOT_DIR}/run-runtime-release-check.sh"
UPDATE_SCRIPT="${ROOT_DIR}/run-runtime-update.sh"
VALIDATE_INSTALL="${ROOT_DIR}/engine/runtime-assets/validate-runtime-install.sh"
WORKFLOW_FILE="${ROOT_DIR}/.github/workflows/m3-gate-runtime-evidence.yml"
MACOS_PLUGIN="${ROOT_DIR}/flutter/packages/jumper_sdk_platform/macos/Classes/JumperSdkPlatformPlugin.swift"
STABILITY_SCRIPT="${ROOT_DIR}/run-runtime-stability-check.sh"

forbid_pattern "generate-checksums\\.sh" "${RELEASE_CHECK}" \
  "release-check must not regenerate checksums"
forbid_pattern "generate-checksums\\.sh" "${UPDATE_SCRIPT}" \
  "runtime-update must not regenerate checksums"
forbid_pattern "Generate checksums for platform" "${WORKFLOW_FILE}" \
  "m3 gate workflow must not include generate-checksums step"
forbid_pattern "\\bjq\\b" "${VALIDATE_INSTALL}" \
  "validate-runtime-install must not depend on jq"

require_pattern "saveCurrentProxySnapshot\\(services:" "${MACOS_PLUGIN}" \
  "system proxy enable path must persist snapshot"
require_pattern "loadProxySnapshot\\(\\)" "${MACOS_PLUGIN}" \
  "system proxy disable path must load snapshot"
require_pattern "restoreProxySnapshot\\(" "${MACOS_PLUGIN}" \
  "system proxy disable path must restore snapshot"
require_pattern "if try loadProxySnapshot\\(\\) == nil" "${MACOS_PLUGIN}" \
  "system proxy enable path must not overwrite existing snapshot"
require_pattern "expectedVersion: request\\.version" "${MACOS_PLUGIN}" \
  "runtime setup/inspect must enforce request version against manifest"
require_pattern "Source config not found:" "${MACOS_PLUGIN}" \
  "runtime setup must fail if source config is missing"
forbid_pattern "runtimeVersion == nil \\|\\|" "${MACOS_PLUGIN}" \
  "runtime inspect must not treat missing VERSION as matched"
require_pattern "let versionMatches = runtimeVersion == request\\.version" "${MACOS_PLUGIN}" \
  "runtime inspect must require exact VERSION match"
require_pattern "windows-\\*" "${STABILITY_SCRIPT}" \
  "stability script must handle windows binary naming"
require_pattern "trap 'on_error \\$\\{LINENO\\}' ERR" "${UPDATE_SCRIPT}" \
  "runtime-update must keep ERR trap rollback guard"
require_pattern "on_error\\(\\)" "${UPDATE_SCRIPT}" \
  "runtime-update must keep on_error handler"
require_pattern "rollback_on_failure \"command failed at line" "${UPDATE_SCRIPT}" \
  "runtime-update on_error must route to rollback_on_failure"
require_pattern "clear_directory_contents\\(\\)" "${UPDATE_SCRIPT}" \
  "runtime-update must use robust cleanup helper for hidden files"

if [[ "${FAILURES}" -gt 0 ]]; then
  echo "[audit-guard] baseline guard failed (${FAILURES} issues)"
  exit 1
fi

echo "[audit-guard] baseline guard passed"
