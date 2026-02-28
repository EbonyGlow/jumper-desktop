#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_ARCH="${1:-darwin-arm64}"
VERSION_INPUT="${2:-latest}"
LOCKFILE_PATH="${ROOT_DIR}/resolved-runtime-lock.json"
MANIFEST_PATH="${ROOT_DIR}/manifest.json"

case "${PLATFORM_ARCH}" in
  darwin-arm64|darwin-amd64|linux-amd64|linux-arm64|windows-amd64)
    ;;
  *)
    echo "Unsupported platform-arch: ${PLATFORM_ARCH}"
    echo "Supported: darwin-arm64 darwin-amd64 linux-amd64 linux-arm64 windows-amd64"
    exit 1
    ;;
esac

resolve_latest_version() {
  python3 - <<'PY' "${GITHUB_TOKEN:-}"
import json
import sys
import urllib.request

token = sys.argv[1]
request = urllib.request.Request(
    "https://api.github.com/repos/SagerNet/sing-box/releases/latest",
    headers={
        "Accept": "application/vnd.github+json",
        **({"Authorization": f"Bearer {token}"} if token else {}),
    },
)
with urllib.request.urlopen(request, timeout=20) as response:
    payload = json.load(response)
tag = payload.get("tag_name")
if not isinstance(tag, str) or not tag.strip():
    raise SystemExit("missing tag_name from GitHub latest release API")
print(tag.removeprefix("v"))
PY
}

VERSION="${VERSION_INPUT}"
if [[ "${VERSION_INPUT}" == "latest" ]]; then
  echo "[runtime-assets] Resolving latest sing-box version"
  VERSION="$(resolve_latest_version)"
fi

echo "[runtime-assets] Preparing ${PLATFORM_ARCH} version ${VERSION}"

"${ROOT_DIR}/fetch-sing-box.sh" "${PLATFORM_ARCH}" "${VERSION}"

python3 - <<'PY' "${MANIFEST_PATH}" "${VERSION}"
import json
import pathlib
import sys

manifest_path = pathlib.Path(sys.argv[1])
version = sys.argv[2]
manifest = json.loads(manifest_path.read_text())
platforms = [
    "darwin-arm64",
    "darwin-amd64",
    "linux-amd64",
    "linux-arm64",
    "windows-amd64",
]
assets = {}
for platform in platforms:
    ext = "zip" if platform.startswith("windows-") else "tar.gz"
    binary = "sing-box.exe" if platform.startswith("windows-") else "sing-box"
    archive_name = f"sing-box-{version}-{platform}.{ext}"
    assets[platform] = {
        "archive_name": archive_name,
        "archive_url": f"https://github.com/SagerNet/sing-box/releases/download/v{version}/{archive_name}",
        "binary_relative_path": f"sing-box-{version}-{platform}/{binary}",
    }

manifest["sing_box"] = {
    "version": version,
    "assets": assets,
}
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
print(f"[runtime-assets] Updated manifest: {manifest_path}")
PY

"${ROOT_DIR}/generate-checksums.sh" "${PLATFORM_ARCH}"
"${ROOT_DIR}/verify-checksums.sh" "${PLATFORM_ARCH}"

python3 - <<'PY' "${LOCKFILE_PATH}" "${PLATFORM_ARCH}" "${VERSION}" "${ROOT_DIR}"
import datetime as dt
import hashlib
import json
import pathlib
import sys

lock_path = pathlib.Path(sys.argv[1])
platform_arch = sys.argv[2]
version = sys.argv[3]
root_dir = pathlib.Path(sys.argv[4])

ext = "zip" if platform_arch.startswith("windows-") else "tar.gz"
binary_name = "sing-box.exe" if platform_arch.startswith("windows-") else "sing-box"
archive = root_dir / platform_arch / f"sing-box-{version}-{platform_arch}.{ext}"
binary = root_dir / platform_arch / f"sing-box-{version}-{platform_arch}" / binary_name

def sha256(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

record = {
    "schema_version": 1,
    "generated_at_utc": dt.datetime.utcnow().replace(microsecond=0).isoformat() + "Z",
    "source": "prepare-runtime-assets.sh",
    "platform_arch": platform_arch,
    "resolved_version": version,
    "artifacts": {
        "archive": {
            "path": str(archive.relative_to(root_dir)),
            "sha256": sha256(archive),
        },
        "binary": {
            "path": str(binary.relative_to(root_dir)),
            "sha256": sha256(binary),
        },
    },
}
lock_path.write_text(json.dumps(record, indent=2) + "\n")
print(f"[runtime-assets] Wrote lockfile: {lock_path}")
PY

echo "[runtime-assets] Prepared ${PLATFORM_ARCH} version ${VERSION}"
