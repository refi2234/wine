#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${1:-}"
PATCH_DIR="${SCRIPT_DIR%/scripts}/patches/ref4ik-wine-bionic-2026-03-04"

if [[ -z "$SOURCE_DIR" || ! -d "$SOURCE_DIR/.git" ]]; then
    echo "Usage: $0 <wine-source-dir>" >&2
    exit 1
fi

PATCHES=(
    "$PATCH_DIR/0001-pulse-disable-pthread_mutex_setprotocolattr-on-android.patch"
    "$PATCH_DIR/0002-winex11-force-glx-extension-through-env-var.patch"
    "$PATCH_DIR/0003-add-pipetto-crypto-esync-patches.patch"
    "$PATCH_DIR/0004-ntdll-workaround-for-locales-on-android.patch"
    "$PATCH_DIR/0005-winevulkan-fixup-compilation-when-os-is-used.patch"
)

echo "Applying local REF4IK March 4, 2026 patchset from $PATCH_DIR"
applied=0
skipped=0

for patch_path in "${PATCHES[@]}"; do
    if bash "$SCRIPT_DIR/apply_patch_series.sh" "$SOURCE_DIR" "$patch_path"; then
        applied=$((applied + 1))
    else
        echo "WARNING: skipping REF4IK patch that no longer applies cleanly: $(basename "$patch_path")"
        skipped=$((skipped + 1))
    fi
done

echo "REF4IK bionic patch summary: applied=$applied skipped=$skipped total=${#PATCHES[@]}"
