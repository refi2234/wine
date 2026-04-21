#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${1:-}"
MANIFEST_PATH="${SCRIPT_DIR%/scripts}/patches/arm64ec-support-patches.json"

if [[ -z "$SOURCE_DIR" || ! -d "$SOURCE_DIR/.git" ]]; then
    echo "Usage: $0 <wine-source-dir>" >&2
    exit 1
fi

if [[ ! -f "$MANIFEST_PATH" ]]; then
    echo "ERROR: manifest not found: $MANIFEST_PATH" >&2
    exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Applying local ARM64EC support patch bundle from $MANIFEST_PATH"

python3 - "$MANIFEST_PATH" <<'PY' > "$TMP_DIR/patch-list.tsv"
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1]).resolve()
manifest_dir = manifest_path.parent
data = json.loads(manifest_path.read_text(encoding="utf-8"))
for item in data.get("patches", []):
    patch_path = str((manifest_dir / item["path"]).resolve())
    print(f"{item['id']}\t{item['description']}\t{patch_path}")
PY

while IFS=$'\t' read -r patch_id description patch_path; do
    [[ -n "$patch_id" ]] || continue
    if [[ ! -f "$patch_path" ]]; then
        echo "ERROR: missing bundled ARM64EC support patch: $patch_path" >&2
        exit 1
    fi
    echo "Applying ARM64EC support patch: $description"
    bash "$SCRIPT_DIR/apply_patch_series.sh" "$SOURCE_DIR" "$patch_path"
done < "$TMP_DIR/patch-list.tsv"

echo "ARM64EC support patch bundle applied successfully"
