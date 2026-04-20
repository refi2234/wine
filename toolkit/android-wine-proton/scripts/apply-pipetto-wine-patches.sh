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

lookup_patch_path() {
    local needle="$1"
    awk -F '\t' -v id="$needle" '$1 == id { print $3; exit }' "$TMP_DIR/patch-list.tsv"
}

commit_checkpoint() {
    local message="$1"
    if ! git -C "$SOURCE_DIR" diff --quiet --ignore-submodules -- || ! git -C "$SOURCE_DIR" diff --cached --quiet --ignore-submodules --; then
        git -C "$SOURCE_DIR" add -A
        git -C "$SOURCE_DIR" commit -qm "$message" || true
    fi
}

apply_patch_with_tracking() {
    local patch_id="$1"
    local description="$2"
    local patch_path="$3"

    echo "Applying Pipetto patch: $description"
    if bash "$SCRIPT_DIR/apply_patch_series.sh" "$SOURCE_DIR" "$patch_path"; then
        commit_checkpoint "tmp: apply $patch_id"
        applied=$((applied + 1))
        applied_ids+=("$patch_id")
        return 0
    fi

    echo "WARNING: skipping Pipetto patch that failed to apply cleanly: $patch_id"
    git -C "$SOURCE_DIR" reset --hard HEAD >/dev/null 2>&1 || true
    git -C "$SOURCE_DIR" clean -fd >/dev/null 2>&1 || true
    skipped=$((skipped + 1))
    skipped_ids+=("$patch_id")
    return 1
}

source_supports_pipetto_sync() {
    [[ -f "$SOURCE_DIR/server/esync.c" ]] || return 1
    [[ -f "$SOURCE_DIR/server/fsync.c" ]] || return 1
    [[ -f "$SOURCE_DIR/dlls/ntdll/unix/esync.c" ]] || return 1
    [[ -f "$SOURCE_DIR/dlls/ntdll/unix/fsync.c" ]] || return 1
    if ! grep -q 'WINE_DEFAULT_DEBUG_CHANNEL(esync);' "$SOURCE_DIR/dlls/ntdll/unix/esync.c"; then
        return 1
    fi
    return 0
}

apply_sync_group() {
    local server_patch ntdll_patch base_commit head_commit
    server_patch="$(lookup_patch_path pipetto-server)"
    ntdll_patch="$(lookup_patch_path pipetto-ntdll-unix)"

    if [[ -z "$server_patch" || -z "$ntdll_patch" ]]; then
        echo "WARNING: Pipetto sync group is incomplete in manifest; skipping"
        skipped=$((skipped + 2))
        skipped_ids+=("pipetto-server" "pipetto-ntdll-unix")
        return 0
    fi

    if ! source_supports_pipetto_sync; then
        echo "WARNING: source tree is too old or incompatible for Pipetto sync group; skipping"
        skipped=$((skipped + 2))
        skipped_ids+=("pipetto-server" "pipetto-ntdll-unix")
        return 0
    fi

    base_commit="$(git -C "$SOURCE_DIR" rev-parse HEAD)"
    head_commit="$base_commit"

    if apply_patch_with_tracking "pipetto-server" "Pipetto server sync/perf changes" "$server_patch"; then
        head_commit="$(git -C "$SOURCE_DIR" rev-parse HEAD)"
    else
        return 0
    fi

    if apply_patch_with_tracking "pipetto-ntdll-unix" "Pipetto ntdll unix sync/runtime changes" "$ntdll_patch"; then
        return 0
    fi

    echo "WARNING: rolling back Pipetto sync group because only part of it applied"
    git -C "$SOURCE_DIR" reset --hard "$base_commit" >/dev/null 2>&1 || true
    git -C "$SOURCE_DIR" clean -fd >/dev/null 2>&1 || true

    if [[ "$head_commit" != "$base_commit" ]]; then
        applied=$((applied - 1))
        skipped=$((skipped + 1))
        applied_ids=("${applied_ids[@]/pipetto-server}")
        skipped_ids+=("pipetto-server")
    fi
}

applied=0
skipped=0
declare -a applied_ids=()
declare -a skipped_ids=()
while IFS=$'\t' read -r patch_id description patch_path; do
    [[ -n "$patch_id" ]] || continue
    case "$patch_id" in
        pipetto-server|pipetto-ntdll-unix)
            continue
            ;;
        *)
            apply_patch_with_tracking "$patch_id" "$description" "$patch_path" || true
            ;;
    esac
done < "$TMP_DIR/patch-list.tsv"

apply_sync_group

echo "Pipetto Wine patch bundle summary: applied=$applied skipped=$skipped"
if (( applied > 0 )); then
    printf 'Applied Pipetto patches: %s\n' "${applied_ids[*]}"
fi
if (( skipped > 0 )); then
    printf 'Skipped Pipetto patches: %s\n' "${skipped_ids[*]}"
fi
