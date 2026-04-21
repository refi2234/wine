#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${1:-}"
MANIFEST_PATH="${SCRIPT_DIR%/scripts}/patches/extra-wine-patches.json"
MANIFEST_DIR="$(cd "$(dirname "$MANIFEST_PATH")" && pwd)"

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

echo "Applying optional extra Wine patch bundle from $MANIFEST_PATH"

git -C "$SOURCE_DIR" config user.name "extra-patch-bot" >/dev/null
git -C "$SOURCE_DIR" config user.email "extra-patch-bot@example.invalid" >/dev/null

python3 - "$MANIFEST_PATH" <<'PY' > "$TMP_DIR/patch-list.tsv"
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1]).resolve()
manifest_dir = manifest_path.parent
data = json.loads(manifest_path.read_text(encoding="utf-8"))
for item in data.get("patches", []):
    patch_path = item.get("path", "")
    if patch_path:
        patch_path = str((manifest_dir / patch_path).resolve())
    print(f"{item['id']}\t{item['description']}\t{patch_path}\t{item.get('url', '')}")
PY

applied=0
skipped=0
declare -a applied_ids=()
declare -a skipped_ids=()
while IFS=$'\t' read -r patch_id description local_path url; do
    [[ -n "$patch_id" ]] || continue
    patch_file="$TMP_DIR/${patch_id}.patch"
    if [[ -n "$local_path" && -f "$local_path" ]]; then
        echo "Using bundled extra patch: $description"
        cp "$local_path" "$patch_file"
    else
        echo "ERROR: bundled extra patch is missing from the repository: $patch_id" >&2
        git -C "$SOURCE_DIR" reset --hard HEAD >/dev/null 2>&1 || true
        git -C "$SOURCE_DIR" clean -fd >/dev/null 2>&1 || true
        skipped=$((skipped + 1))
        skipped_ids+=("$patch_id")
        continue
    fi
    if bash "$SCRIPT_DIR/apply_patch_series.sh" "$SOURCE_DIR" "$patch_file"; then
        if ! git -C "$SOURCE_DIR" diff --quiet --ignore-submodules -- || ! git -C "$SOURCE_DIR" diff --cached --quiet --ignore-submodules --; then
            git -C "$SOURCE_DIR" add -A
            git -C "$SOURCE_DIR" commit -qm "tmp: apply $patch_id" || true
        fi
        applied=$((applied + 1))
        applied_ids+=("$patch_id")
    else
        echo "WARNING: skipping extra patch that failed to apply cleanly: $patch_id"
        git -C "$SOURCE_DIR" reset --hard HEAD >/dev/null 2>&1 || true
        git -C "$SOURCE_DIR" clean -fd >/dev/null 2>&1 || true
        echo "Restored source tree checkpoint after failed extra patch: $patch_id"
        skipped=$((skipped + 1))
        skipped_ids+=("$patch_id")
    fi
done < "$TMP_DIR/patch-list.tsv"

echo "Extra Wine patch bundle summary: applied=$applied skipped=$skipped"
if (( applied > 0 )); then
    printf 'Applied extra patches: %s\n' "${applied_ids[*]}"
fi
if (( skipped > 0 )); then
    printf 'Skipped extra patches: %s\n' "${skipped_ids[*]}"
fi
