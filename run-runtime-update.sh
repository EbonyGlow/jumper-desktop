#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
ASSETS_DIR="${ROOT_DIR}/engine/runtime-assets"

PLATFORM_ARCH="${1:-darwin-arm64}"
VERSION="${2:-1.12.22}"
BUNDLE_ID="${3:-com.example.sdkSmokeApp}"
API_BASE="${4:-http://127.0.0.1:20123}"
RUNTIME_ROOT_OVERRIDE="${5:-}"

RUNTIME_ROOT=""
BACKUP_ROOT=""
LOCAL_BACKUP_DIR=""
ROLLBACK_ENABLED=0
ROLLBACK_ATTEMPTED=0
FIRST_INSTALL=0

resolve_paths() {
  if [[ -n "${RUNTIME_ROOT_OVERRIDE}" ]]; then
    RUNTIME_ROOT="${RUNTIME_ROOT_OVERRIDE}"
    BACKUP_ROOT="${RUNTIME_ROOT_OVERRIDE}-backups"
    return
  fi

  local container_runtime="${HOME}/Library/Containers/${BUNDLE_ID}/Data/Library/Application Support/jumper-runtime"
  local container_backup="${HOME}/Library/Containers/${BUNDLE_ID}/Data/Library/Application Support/jumper-runtime-backups"
  local fallback_runtime="${HOME}/Library/Application Support/jumper-runtime"
  local fallback_backup="${HOME}/Library/Application Support/jumper-runtime-backups"

  if [[ -d "${container_runtime}" || -d "${container_backup}" ]]; then
    RUNTIME_ROOT="${container_runtime}"
    BACKUP_ROOT="${container_backup}"
    return
  fi
  RUNTIME_ROOT="${fallback_runtime}"
  BACKUP_ROOT="${fallback_backup}"
}

rollback_on_failure() {
  local message="$1"
  trap - ERR
  if [[ "${ROLLBACK_ATTEMPTED}" -eq 1 ]]; then
    echo "[runtime-update] rollback already attempted, aborting: ${message}"
    exit 1
  fi
  ROLLBACK_ATTEMPTED=1
  echo "[runtime-update] ERROR: ${message}"
  if [[ "${ROLLBACK_ENABLED}" -ne 1 ]]; then
    if [[ "${FIRST_INSTALL}" -eq 1 ]]; then
      echo "[runtime-update] no backup available (first install), cleaning runtime root"
      clear_directory_contents "${RUNTIME_ROOT}" || true
      echo "[runtime-update] first-install cleanup completed"
    else
      echo "[runtime-update] rollback skipped (no backup created)"
    fi
    exit 1
  fi

  echo "[runtime-update] rolling back"
  if [[ -n "${RUNTIME_ROOT_OVERRIDE}" ]]; then
    mkdir -p "${RUNTIME_ROOT}"
    clear_directory_contents "${RUNTIME_ROOT}"
    cp -R "${LOCAL_BACKUP_DIR}/." "${RUNTIME_ROOT}/"
  else
    "${ASSETS_DIR}/rollback-runtime-container.sh" "${BUNDLE_ID}" latest
  fi
  echo "[runtime-update] rollback completed"
  exit 1
}

on_error() {
  local line_no="$1"
  rollback_on_failure "command failed at line ${line_no}"
}

clear_directory_contents() {
  local target_dir="$1"
  python3 - <<'PY' "${target_dir}"
import pathlib
import shutil
import sys

target = pathlib.Path(sys.argv[1])
target.mkdir(parents=True, exist_ok=True)
for child in target.iterdir():
    if child.is_dir():
        shutil.rmtree(child)
    else:
        child.unlink()
PY
}

trap 'on_error ${LINENO}' ERR

echo "[runtime-update] resolving paths"
resolve_paths

echo "[runtime-update] fetch runtime asset"
"${ASSETS_DIR}/fetch-sing-box.sh" "${PLATFORM_ARCH}" "${VERSION}"

echo "[runtime-update] verify artifact checksum"
"${ASSETS_DIR}/verify-checksums.sh" "${PLATFORM_ARCH}"

SOURCE_BINARY="${ASSETS_DIR}/${PLATFORM_ARCH}/sing-box-${VERSION}-${PLATFORM_ARCH}/sing-box"
if [[ "${PLATFORM_ARCH}" == windows-* ]]; then
  SOURCE_BINARY="${ASSETS_DIR}/${PLATFORM_ARCH}/sing-box-${VERSION}-${PLATFORM_ARCH}/sing-box.exe"
fi
SOURCE_CONFIG="${ASSETS_DIR}/${PLATFORM_ARCH}/minimal-config.json"

if [[ ! -f "${SOURCE_BINARY}" ]]; then
  rollback_on_failure "source binary not found: ${SOURCE_BINARY}"
fi
if [[ ! -f "${SOURCE_CONFIG}" ]]; then
  rollback_on_failure "source config not found: ${SOURCE_CONFIG}"
fi

echo "[runtime-update] backup current runtime"
if [[ -n "${RUNTIME_ROOT_OVERRIDE}" ]]; then
  if [[ -d "${RUNTIME_ROOT}" ]]; then
    TS="$(date +%Y%m%d-%H%M%S)"
    LOCAL_BACKUP_DIR="${BACKUP_ROOT}/${TS}"
    mkdir -p "${LOCAL_BACKUP_DIR}"
    cp -R "${RUNTIME_ROOT}/." "${LOCAL_BACKUP_DIR}/"
    ROLLBACK_ENABLED=1
    echo "[runtime-update] local backup created: ${LOCAL_BACKUP_DIR}"
  else
    FIRST_INSTALL=1
    mkdir -p "${RUNTIME_ROOT}"
    echo "[runtime-update] first install mode (no existing runtime root): ${RUNTIME_ROOT}"
  fi
else
  if [[ -d "${RUNTIME_ROOT}" ]]; then
    "${ASSETS_DIR}/backup-runtime-container.sh" "${BUNDLE_ID}"
    ROLLBACK_ENABLED=1
  else
    FIRST_INSTALL=1
    mkdir -p "${RUNTIME_ROOT}"
    echo "[runtime-update] first install mode (no existing runtime root): ${RUNTIME_ROOT}"
  fi
fi

STAGING_DIR="${RUNTIME_ROOT}.update-staging-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${STAGING_DIR}"
cleanup_staging() {
  rm -rf "${STAGING_DIR}"
}
trap cleanup_staging EXIT

TARGET_BINARY_NAME="sing-box"
if [[ "${PLATFORM_ARCH}" == windows-* ]]; then
  TARGET_BINARY_NAME="sing-box.exe"
fi

echo "[runtime-update] prepare staging files"
cp "${SOURCE_BINARY}" "${STAGING_DIR}/${TARGET_BINARY_NAME}"
cp "${SOURCE_CONFIG}" "${STAGING_DIR}/config.json"
if [[ "${PLATFORM_ARCH}" != windows-* ]]; then
  chmod +x "${STAGING_DIR}/${TARGET_BINARY_NAME}"
fi
printf '%s\n' "${VERSION}" > "${STAGING_DIR}/VERSION"

echo "[runtime-update] apply staged runtime"
mkdir -p "${RUNTIME_ROOT}"
clear_directory_contents "${RUNTIME_ROOT}"
cp -R "${STAGING_DIR}/." "${RUNTIME_ROOT}/"

echo "[runtime-update] validate updated runtime"
"${ASSETS_DIR}/validate-runtime-install.sh" "${RUNTIME_ROOT}" "${API_BASE}"

echo "[runtime-update] update succeeded"
echo "[runtime-update] runtime root: ${RUNTIME_ROOT}"
