#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "[runtime-setup-test] Running runtime setup integration test"
cd "${ROOT_DIR}/flutter/apps/sdk_smoke_app"
fvm flutter test integration_test/runtime_setup_test.dart -d macos \
  --dart-define=JUMPER_WORKSPACE_BASE_PATH="${ROOT_DIR}" \
  --dart-define=JUMPER_RUNTIME_VERSION=1.12.22 \
  --dart-define=JUMPER_RUNTIME_PLATFORM_ARCH=darwin-arm64
