#!/bin/bash
# disable-unsupported-proton-dlls.sh
# Removes GE-added x64-only helper DLLs from the Android Proton build graph.

set -euo pipefail

SOURCE_DIR="${1:?usage: disable-unsupported-proton-dlls.sh <wine-source-dir>}"
CONFIGURE_AC="$SOURCE_DIR/configure.ac"

[[ -f "$CONFIGURE_AC" ]] || {
    echo "configure.ac not found: $CONFIGURE_AC" >&2
    exit 1
}

python3 - "$CONFIGURE_AC" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
lines = text.splitlines()

disabled = {
    "WINE_CONFIG_MAKEFILE(dlls/amd_ags_x64)",
    "WINE_CONFIG_MAKEFILE(dlls/amdxc64)",
    "WINE_CONFIG_MAKEFILE(dlls/atidxx64)",
}

updated = []
changed = False
for line in lines:
    stripped = line.strip()
    if stripped in disabled:
        updated.append(f"dnl {stripped}  dnl disabled for Android ARM64 Proton build")
        changed = True
    else:
        updated.append(line)

if changed:
    path.write_text("\n".join(updated) + "\n", encoding="utf-8")
    print("Disabled unsupported x64-only GE DLL makefiles in configure.ac")
else:
    print("No unsupported x64-only GE DLL makefiles found in configure.ac")
PY
