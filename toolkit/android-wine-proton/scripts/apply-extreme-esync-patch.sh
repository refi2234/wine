#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${1:-}"
PATCH_PATH="${SCRIPT_DIR%/scripts}/patches/extreme-esync/pipetto-extreme-esync.patch"

if [[ -z "$SOURCE_DIR" || ! -d "$SOURCE_DIR/.git" ]]; then
    echo "Usage: $0 <wine-source-dir>" >&2
    exit 1
fi

if [[ ! -f "$PATCH_PATH" ]]; then
    echo "ERROR: bundled extreme esync patch is missing: $PATCH_PATH" >&2
    exit 1
fi

echo "Applying bundled experimental extreme esync patch from $PATCH_PATH"
bash "$SCRIPT_DIR/apply_patch_series.sh" "$SOURCE_DIR" "$PATCH_PATH"

echo "Extreme esync patch applied successfully"
