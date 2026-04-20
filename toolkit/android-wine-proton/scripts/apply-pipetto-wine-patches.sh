#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${1:-}"
MANIFEST_PATH="${SCRIPT_DIR%/scripts}/patches/pipetto-wine-patches.json"

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

echo "Applying local Pipetto Wine patch bundle from $MANIFEST_PATH"

git -C "$SOURCE_DIR" config user.name "pipetto-patch-bot" >/dev/null
git -C "$SOURCE_DIR" config user.email "pipetto-patch-bot@example.invalid" >/dev/null

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

applied=0
skipped=0
declare -a applied_ids=()
declare -a skipped_ids=()
while IFS=$'\t' read -r patch_id description patch_path; do
    [[ -n "$patch_id" ]] || continue
    echo "Applying Pipetto patch: $description"
    if bash "$SCRIPT_DIR/apply_patch_series.sh" "$SOURCE_DIR" "$patch_path"; then
        if ! git -C "$SOURCE_DIR" diff --quiet --ignore-submodules -- || ! git -C "$SOURCE_DIR" diff --cached --quiet --ignore-submodules --; then
            git -C "$SOURCE_DIR" add -A
            git -C "$SOURCE_DIR" commit -qm "tmp: apply $patch_id" || true
        fi
        applied=$((applied + 1))
        applied_ids+=("$patch_id")
    else
        echo "WARNING: skipping Pipetto patch that failed to apply cleanly: $patch_id"
        git -C "$SOURCE_DIR" reset --hard HEAD >/dev/null 2>&1 || true
        git -C "$SOURCE_DIR" clean -fd >/dev/null 2>&1 || true
        skipped=$((skipped + 1))
        skipped_ids+=("$patch_id")
    fi
done < "$TMP_DIR/patch-list.tsv"

echo "Pipetto Wine patch bundle summary: applied=$applied skipped=$skipped"
if (( applied > 0 )); then
    printf 'Applied Pipetto patches: %s\n' "${applied_ids[*]}"
fi
if (( skipped > 0 )); then
    printf 'Skipped Pipetto patches: %s\n' "${skipped_ids[*]}"
fi
