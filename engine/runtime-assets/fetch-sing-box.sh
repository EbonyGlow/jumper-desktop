#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_ARCH="${1:-darwin-arm64}"
VERSION="${2:-1.12.22}"

case "$PLATFORM_ARCH" in
  darwin-arm64|darwin-amd64|linux-amd64|linux-arm64|windows-amd64)
    ;;
  *)
    echo "Unsupported platform-arch: $PLATFORM_ARCH"
    echo "Supported: darwin-arm64 darwin-amd64 linux-amd64 linux-arm64 windows-amd64"
    exit 1
    ;;
esac

ARCHIVE_EXT="tar.gz"
if [[ "${PLATFORM_ARCH}" == windows-* ]]; then
  ARCHIVE_EXT="zip"
fi

ARCHIVE_NAME="sing-box-${VERSION}-${PLATFORM_ARCH}.${ARCHIVE_EXT}"
DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/${ARCHIVE_NAME}"
TARGET_DIR="${ROOT_DIR}/${PLATFORM_ARCH}"
ARCHIVE_PATH="${TARGET_DIR}/${ARCHIVE_NAME}"
BINARY_NAME="sing-box"
if [[ "${PLATFORM_ARCH}" == windows-* ]]; then
  BINARY_NAME="sing-box.exe"
fi
BINARY_PATH="${TARGET_DIR}/sing-box-${VERSION}-${PLATFORM_ARCH}/${BINARY_NAME}"

mkdir -p "${TARGET_DIR}"

if [[ -f "${BINARY_PATH}" ]]; then
  echo "[runtime-assets] Using existing binary: ${BINARY_PATH}"
  if [[ "${PLATFORM_ARCH}" != windows-* ]]; then
    chmod +x "${BINARY_PATH}"
  fi
  echo "[runtime-assets] Ready: ${BINARY_PATH}"
  echo "[runtime-assets] Run check:"
  echo "  \"${BINARY_PATH}\" version"
  exit 0
fi

if [[ -f "${ARCHIVE_PATH}" ]]; then
  echo "[runtime-assets] Reusing existing archive: ${ARCHIVE_PATH}"
else
  echo "[runtime-assets] Downloading ${DOWNLOAD_URL}"
  curl --retry 3 --retry-all-errors --retry-delay 2 -fL "${DOWNLOAD_URL}" -o "${ARCHIVE_PATH}"
fi

echo "[runtime-assets] Extracting ${ARCHIVE_NAME}"
if [[ "${ARCHIVE_EXT}" == "tar.gz" ]]; then
  tar -xzf "${ARCHIVE_PATH}" -C "${TARGET_DIR}"
else
  unzip -o "${ARCHIVE_PATH}" -d "${TARGET_DIR}" >/dev/null
fi

if [[ ! -f "${BINARY_PATH}" ]]; then
  echo "Binary not found after extraction: ${BINARY_PATH}"
  exit 1
fi
if [[ "${PLATFORM_ARCH}" != windows-* ]]; then
  chmod +x "${BINARY_PATH}"
fi

echo "[runtime-assets] Ready: ${BINARY_PATH}"
echo "[runtime-assets] Run check:"
echo "  \"${BINARY_PATH}\" version"
