#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${1:-}"
MANIFEST_PATH="${SCRIPT_DIR%/scripts}/patches/extra-wine-patches.json"

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

python3 - "$MANIFEST_PATH" <<'PY' > "$TMP_DIR/patch-list.tsv"
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for item in data.get("patches", []):
    print(f"{item['id']}\t{item['description']}\t{item['url']}")
PY

applied=0
skipped=0
declare -a applied_ids=()
declare -a skipped_ids=()
while IFS=$'\t' read -r patch_id description url; do
    [[ -n "$patch_id" ]] || continue
    patch_file="$TMP_DIR/${patch_id}.patch"
    echo "Downloading extra patch: $description"
    curl -LfsS "$url" -o "$patch_file"
    if bash "$SCRIPT_DIR/apply_patch_series.sh" "$SOURCE_DIR" "$patch_file"; then
        applied=$((applied + 1))
        applied_ids+=("$patch_id")
    else
        echo "WARNING: skipping extra patch that failed to apply cleanly: $patch_id"
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
