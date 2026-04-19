#!/usr/bin/env python3
"""
Adjust dlls/wineandroid.drv/init.c for upstream callback signature drift.

Newer Wine trees changed the user-driver pWindowPosChanged callback signature,
while the Android driver can still carry the older implementation with one extra
BOOL parameter. We bridge this by inserting a small wrapper and pointing the
driver vtable to it.
"""
import os
import re
import sys


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: fix_wineandroid_init_c.py <wine-source-dir>")
        return 1

    wine_src = sys.argv[1]
    init_c = os.path.join(wine_src, "dlls", "wineandroid.drv", "init.c")

    if not os.path.exists(init_c):
        print(f"ERROR: {init_c} not found")
        return 1

    with open(init_c, encoding="utf-8", errors="replace") as f:
        src = f.read()

    if "ANDROID_WindowPosChanged_bridge" in src:
        print("wineandroid init.c: callback bridge already present")
        return 0

    signature_pattern = re.compile(
        r"void\s+ANDROID_WindowPosChanged\s*"
        r"\(\s*HWND\s+hwnd\s*,\s*HWND\s+insert_after\s*,\s*HWND\s+owner_hint\s*,\s*"
        r"UINT\s+swp_flags\s*,\s*BOOL\s+\w+\s*,\s*const\s+struct\s+window_rects\s+\*\s*\w+\s*,\s*"
        r"struct\s+window_surface\s+\*\s*\w+\s*\)"
    )
    if not signature_pattern.search(src):
        print("wineandroid init.c: no drifted ANDROID_WindowPosChanged signature found, skipping")
        return 0

    anchor = "static const struct user_driver_funcs"
    idx = src.find(anchor)
    if idx == -1:
        print("ERROR: could not find user_driver_funcs table in wineandroid init.c")
        return 1

    wrapper = (
        "static void ANDROID_WindowPosChanged_bridge( HWND hwnd, HWND insert_after, HWND owner_hint,\n"
        "                                              UINT swp_flags, const struct window_rects *new_rects,\n"
        "                                              struct window_surface *surface )\n"
        "{\n"
        "    ANDROID_WindowPosChanged( hwnd, insert_after, owner_hint, swp_flags, FALSE, new_rects, surface );\n"
        "}\n\n"
    )

    updated = src[:idx] + wrapper + src[idx:]
    if ".pWindowPosChanged = ANDROID_WindowPosChanged," not in updated:
        print("ERROR: could not find pWindowPosChanged assignment in wineandroid init.c")
        return 1
    updated = updated.replace(
        ".pWindowPosChanged = ANDROID_WindowPosChanged,",
        ".pWindowPosChanged = ANDROID_WindowPosChanged_bridge,",
        1,
    )

    with open(init_c, "w", encoding="utf-8", newline="\n") as f:
        f.write(updated)

    print("wineandroid init.c: inserted callback bridge for ANDROID_WindowPosChanged")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
