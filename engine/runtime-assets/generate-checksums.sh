#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST_PATH="${ROOT_DIR}/manifest.json"
OUTPUT_PATH="${ROOT_DIR}/checksums.json"
PLATFORM_ARCH="${1:-all}"

python3 - <<'PY' "${MANIFEST_PATH}" "${OUTPUT_PATH}" "${ROOT_DIR}" "${PLATFORM_ARCH}"
import datetime as dt
import hashlib
import json
import pathlib
import sys

manifest_path = pathlib.Path(sys.argv[1])
output_path = pathlib.Path(sys.argv[2])
root_dir = pathlib.Path(sys.argv[3])
platform_arch = sys.argv[4]

manifest = json.loads(manifest_path.read_text())
version = manifest["sing_box"]["version"]
assets = manifest["sing_box"]["assets"]

def sha256(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

if output_path.exists():
    output = json.loads(output_path.read_text())
else:
    output = {"schema_version": 1, "artifacts": {}}

output["schema_version"] = 1
output["generated_at_utc"] = dt.datetime.utcnow().replace(microsecond=0).isoformat() + "Z"
targets = list(assets.keys()) if platform_arch == "all" else [platform_arch]
for target in targets:
    if target not in assets:
        raise SystemExit(f"Unknown platform_arch: {target}")
    asset = assets[target]
    archive_rel = pathlib.Path(target) / asset["archive_name"]
    binary_rel = pathlib.Path(target) / asset["binary_relative_path"]
    archive_path = root_dir / archive_rel
    binary_path = root_dir / binary_rel
    if not archive_path.exists():
        raise SystemExit(f"Archive not found: {archive_path}")
    if not binary_path.exists():
        raise SystemExit(f"Binary not found: {binary_path}")
    output["artifacts"][target] = {
        "version": version,
        "archive": {
            "path": str(archive_rel),
            "sha256": sha256(archive_path),
        },
        "binary": {
            "path": str(binary_rel),
            "sha256": sha256(binary_path),
        },
    }
    print(f"[checksums] {target} version={version}")

output_path.write_text(json.dumps(output, indent=2) + "\n")
print(f"[checksums] updated {output_path}")
PY
