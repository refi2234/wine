#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${1:-}"
PATCH_DIR="${SCRIPT_DIR%/scripts}/patches/ref4ik-wine-bionic-2026-03-04"

if [[ -z "$SOURCE_DIR" || ! -d "$SOURCE_DIR/.git" ]]; then
    echo "Usage: $0 <wine-source-dir>" >&2
    exit 1
fi

REQUIRED_PATCHES=(
    "$PATCH_DIR/0001-pulse-disable-pthread_mutex_setprotocolattr-on-android.patch"
    "$PATCH_DIR/0004-ntdll-workaround-for-locales-on-android.patch"
)

OPTIONAL_PATCHES=(
    "$PATCH_DIR/0002-winex11-force-glx-extension-through-env-var.patch"
    "$PATCH_DIR/0005-winevulkan-fixup-compilation-when-os-is-used.patch"
)

OPTIONAL_ESYNC_PATCH="$PATCH_DIR/0003-add-pipetto-crypto-esync-patches.patch"

echo "Applying local REF4IK March 4, 2026 patchset from $PATCH_DIR"
applied=0
skipped=0
required_failed=0

for patch_path in "${REQUIRED_PATCHES[@]}"; do
    if bash "$SCRIPT_DIR/apply_patch_series.sh" "$SOURCE_DIR" "$patch_path"; then
        applied=$((applied + 1))
    else
        echo "WARNING: required REF4IK patch drifted and will be reconciled by source fixer: $(basename "$patch_path")"
        skipped=$((skipped + 1))
        required_failed=$((required_failed + 1))
    fi
done

python3 "$SCRIPT_DIR/ensure-ref4ik-required-android-fixes.py" "$SOURCE_DIR"

supports_ref4ik_esync_patch() {
    [[ -f "$SOURCE_DIR/server/Makefile.in" ]] || return 1
    [[ -f "$SOURCE_DIR/server/protocol.def" ]] || return 1
    [[ -f "$SOURCE_DIR/server/request.h" ]] || return 1
    [[ -f "$SOURCE_DIR/dlls/ntdll/unix/server.c" ]] || return 1
    [[ -f "$SOURCE_DIR/dlls/ntdll/unix/sync.c" ]] || return 1
    [[ -f "$SOURCE_DIR/dlls/ntdll/unix/unix_private.h" ]] || return 1
    return 0
}

if supports_ref4ik_esync_patch; then
    if bash "$SCRIPT_DIR/apply_patch_series.sh" "$SOURCE_DIR" "$OPTIONAL_ESYNC_PATCH"; then
        applied=$((applied + 1))
        if [[ ! -f "$SOURCE_DIR/dlls/ntdll/unix/esync.c" || ! -f "$SOURCE_DIR/server/esync.c" ]]; then
            echo "WARNING: REF4IK legacy esync bundle left source tree in an incomplete state; rolling it back"
            git -C "$SOURCE_DIR" reset --hard HEAD >/dev/null 2>&1 || true
            git -C "$SOURCE_DIR" clean -fd >/dev/null 2>&1 || true
            applied=$((applied - 1))
            skipped=$((skipped + 1))
        fi
    else
        echo "WARNING: skipping optional REF4IK legacy esync bundle because it no longer applies cleanly: $(basename "$OPTIONAL_ESYNC_PATCH")"
        skipped=$((skipped + 1))
    fi
else
    echo "WARNING: skipping optional REF4IK legacy esync bundle because this Wine source lacks the older server/ntdll sync files it needs"
    skipped=$((skipped + 1))
fi

for patch_path in "${OPTIONAL_PATCHES[@]}"; do
    if bash "$SCRIPT_DIR/apply_patch_series.sh" "$SOURCE_DIR" "$patch_path"; then
        applied=$((applied + 1))
    else
        echo "WARNING: skipping optional REF4IK patch that no longer applies cleanly: $(basename "$patch_path")"
        skipped=$((skipped + 1))
    fi
done

python3 "$SCRIPT_DIR/ensure-ref4ik-required-android-fixes.py" "$SOURCE_DIR"

echo "REF4IK bionic patch summary: applied=$applied skipped=$skipped required_drifted=$required_failed total=$(( ${#REQUIRED_PATCHES[@]} + ${#OPTIONAL_PATCHES[@]} ))"
