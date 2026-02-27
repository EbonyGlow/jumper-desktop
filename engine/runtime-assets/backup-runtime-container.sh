#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ID="${1:-com.example.sdkSmokeApp}"
RUNTIME_DIR="${HOME}/Library/Containers/${BUNDLE_ID}/Data/Library/Application Support/jumper-runtime"
BACKUP_ROOT="${HOME}/Library/Containers/${BUNDLE_ID}/Data/Library/Application Support/jumper-runtime-backups"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${BACKUP_ROOT}/${TS}"

if [[ ! -d "${RUNTIME_DIR}" ]]; then
  FALLBACK_RUNTIME_DIR="${HOME}/Library/Application Support/jumper-runtime"
  FALLBACK_BACKUP_ROOT="${HOME}/Library/Application Support/jumper-runtime-backups"
  if [[ -d "${FALLBACK_RUNTIME_DIR}" ]]; then
    RUNTIME_DIR="${FALLBACK_RUNTIME_DIR}"
    BACKUP_ROOT="${FALLBACK_BACKUP_ROOT}"
    BACKUP_DIR="${BACKUP_ROOT}/${TS}"
  else
    echo "[backup] runtime directory not found: ${RUNTIME_DIR}"
    exit 1
  fi
fi

mkdir -p "${BACKUP_DIR}"
cp -R "${RUNTIME_DIR}/." "${BACKUP_DIR}/"

echo "[backup] created ${BACKUP_DIR}"
