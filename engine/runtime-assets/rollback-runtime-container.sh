#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ID="${1:-com.example.sdkSmokeApp}"
BACKUP_NAME="${2:-latest}"
RUNTIME_DIR="${HOME}/Library/Containers/${BUNDLE_ID}/Data/Library/Application Support/jumper-runtime"
BACKUP_ROOT="${HOME}/Library/Containers/${BUNDLE_ID}/Data/Library/Application Support/jumper-runtime-backups"

if [[ ! -d "${BACKUP_ROOT}" ]]; then
  FALLBACK_RUNTIME_DIR="${HOME}/Library/Application Support/jumper-runtime"
  FALLBACK_BACKUP_ROOT="${HOME}/Library/Application Support/jumper-runtime-backups"
  if [[ -d "${FALLBACK_BACKUP_ROOT}" ]]; then
    RUNTIME_DIR="${FALLBACK_RUNTIME_DIR}"
    BACKUP_ROOT="${FALLBACK_BACKUP_ROOT}"
  else
    echo "[rollback] backup root not found: ${BACKUP_ROOT}"
    exit 1
  fi
fi

if [[ "${BACKUP_NAME}" == "latest" ]]; then
  BACKUP_DIR="$(ls -1 "${BACKUP_ROOT}" | sort | tail -n 1)"
  if [[ -z "${BACKUP_DIR}" ]]; then
    echo "[rollback] no backups found in ${BACKUP_ROOT}"
    exit 1
  fi
  BACKUP_DIR="${BACKUP_ROOT}/${BACKUP_DIR}"
else
  BACKUP_DIR="${BACKUP_ROOT}/${BACKUP_NAME}"
fi

if [[ ! -d "${BACKUP_DIR}" ]]; then
  echo "[rollback] backup not found: ${BACKUP_DIR}"
  exit 1
fi

mkdir -p "${RUNTIME_DIR}"
rm -rf "${RUNTIME_DIR:?}/"*
cp -R "${BACKUP_DIR}/." "${RUNTIME_DIR}/"

echo "[rollback] restored from ${BACKUP_DIR}"
