#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${1:-}"
PATCH_URL="https://github.com/Pipetto-crypto/wine/commit/5dff573c2bf7db9bf5bc986e6d99e6caff20b72a.patch"

if [[ -z "$SOURCE_DIR" || ! -d "$SOURCE_DIR/.git" ]]; then
    echo "Usage: $0 <wine-source-dir>" >&2
    exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PATCH_PATH="$TMP_DIR/pipetto-extreme-esync.patch"

echo "Downloading experimental extreme esync commit patch from $PATCH_URL"
curl -L --fail --retry 3 --retry-delay 2 "$PATCH_URL" -o "$PATCH_PATH"

echo "Applying experimental extreme esync commit patch"
bash "$SCRIPT_DIR/apply_patch_series.sh" "$SOURCE_DIR" "$PATCH_PATH"

echo "Extreme esync patch applied successfully"
