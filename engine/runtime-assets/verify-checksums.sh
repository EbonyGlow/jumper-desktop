#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECKSUMS_PATH="${ROOT_DIR}/checksums.json"
PLATFORM_ARCH="${1:-all}"

python3 - <<'PY' "${CHECKSUMS_PATH}" "${ROOT_DIR}" "${PLATFORM_ARCH}"
import hashlib
import json
import pathlib
import sys

checksums_path = pathlib.Path(sys.argv[1])
root_dir = pathlib.Path(sys.argv[2])
platform_arch = sys.argv[3]

if not checksums_path.exists():
    raise SystemExit(f"checksums.json not found: {checksums_path}")

checksums = json.loads(checksums_path.read_text())
artifacts = checksums.get("artifacts", {})
targets = list(artifacts.keys()) if platform_arch == "all" else [platform_arch]
if not targets:
    raise SystemExit("No checksum artifacts found")

def sha256(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

for target in targets:
    artifact = artifacts.get(target)
    if not artifact:
        raise SystemExit(f"No checksum entry for {target}")
    for key in ("archive", "binary"):
        entry = artifact[key]
        path = root_dir / entry["path"]
        if not path.exists():
            raise SystemExit(f"[verify] missing {target} {key} file: {path}")
        actual = sha256(path)
        expected = entry["sha256"]
        if actual != expected:
            raise SystemExit(
                f"[verify] checksum mismatch for {target} {key}: expected={expected} actual={actual}"
            )
        print(f"[verify] {target} {key} ok: {path}")
    print(f"[verify] success for {target}")
PY
