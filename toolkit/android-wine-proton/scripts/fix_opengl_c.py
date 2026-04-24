#!/usr/bin/env python3
"""
Apply the Android-specific opengl.c changes directly when the original
GameNative patch drifts against newer Proton/Wine sources.
"""
import os
import re
import sys


def apply(src, description, old, new):
    if new in src:
        print(f"  [{description}] already applied, skipping")
        return src, 0
    if old not in src:
        print(f"  [{description}] pattern not found, skipping")
        return src, 0
    print(f"  [{description}] applied")
    return src.replace(old, new, 1), 1


def has_forceglx_declaration(src):
    return re.search(r"\b(?:static\s+)?int\s+wine_x11forceglx\b", src) is not None


def ensure_forceglx_file_fallback(src):
    marker = "/* Android fallback for patched WINE_X11FORCEGLX handling. */"
    if marker in src:
        return src, 0
    fallback = (
        "\n#ifdef __ANDROID__\n"
        f"{marker}\n"
        "static int wine_x11forceglx;\n"
        "#endif\n"
    )
    include_match = list(re.finditer(r'^\s*#include\s+[<"].*[>"]\s*$', src, re.MULTILINE))
    if include_match:
        pos = include_match[-1].end()
        return src[:pos] + fallback + src[pos:], 1
    return fallback + "\n" + src, 1


def main():
    if len(sys.argv) < 2:
        print("Usage: fix_opengl_c.py <wine-source-dir>")
        return 1

    path = os.path.join(sys.argv[1], "dlls", "winex11.drv", "opengl.c")
    if not os.path.exists(path):
        print(f"ERROR: missing file {path}")
        return 2

    with open(path, errors="replace") as f:
        src = f.read()

    total = 0

    src, n = apply(
        src,
        "android wine_x11forceglx variable",
        "UINT X11DRV_OpenGLInit( UINT version, const struct opengl_funcs *opengl_funcs, const struct opengl_driver_funcs **driver_funcs )\n{\n    int error_base, event_base;\n",
        "UINT X11DRV_OpenGLInit( UINT version, const struct opengl_funcs *opengl_funcs, const struct opengl_driver_funcs **driver_funcs )\n{\n    int error_base, event_base;\n#ifdef __ANDROID__\n    int wine_x11forceglx = 0;\n#endif\n",
    )
    total += n

    src, n = apply(
        src,
        "android WINE_X11FORCEGLX handling",
        '    if(!X11DRV_WineGL_InitOpenglInfo()) goto failed;\n\n    if (XQueryExtension( gdi_display, "GLX", &glx_opcode, &event_base, &error_base ))\n',
        '    if(!X11DRV_WineGL_InitOpenglInfo()) goto failed;\n\n#ifdef __ANDROID__\n    if (getenv("WINE_X11FORCEGLX"))\n        wine_x11forceglx = atoi(getenv("WINE_X11FORCEGLX"));\n\n    if (XQueryExtension( gdi_display, "GLX", &glx_opcode, &event_base, &error_base ) || wine_x11forceglx)\n#else\n    if (XQueryExtension( gdi_display, "GLX", &glx_opcode, &event_base, &error_base ))\n#endif\n',
    )
    total += n

    if not has_forceglx_declaration(src):
        pattern = re.compile(
            r"(UINT\s+X11DRV_OpenGLInit\s*\([^)]*\)\s*\n\{\n(?:[ \t].*\n)*?[ \t]*int\s+error_base,\s*event_base;\n)",
            re.MULTILINE,
        )
        match = pattern.search(src)
        if match:
            src = src[: match.end()] + "#ifdef __ANDROID__\n    int wine_x11forceglx = 0;\n#endif\n" + src[match.end() :]
            print("  [regex android wine_x11forceglx variable] applied")
            total += 1

    if "wine_x11forceglx" in src and not has_forceglx_declaration(src):
        pattern = re.compile(r"(UINT\s+X11DRV_OpenGLInit\s*\([^)]*\)\s*\n\{\n)", re.MULTILINE)
        match = pattern.search(src)
        if match:
            src = src[: match.end()] + "#ifdef __ANDROID__\n    int wine_x11forceglx = 0;\n#endif\n" + src[match.end() :]
            print("  [fallback android wine_x11forceglx variable] applied")
            total += 1

    if "|| wine_x11forceglx" not in src:
        pattern = re.compile(
            r'([ \t]*if\s*\(\s*XQueryExtension\(\s*gdi_display,\s*"GLX",\s*&glx_opcode,\s*&event_base,\s*&error_base\s*\)\s*\)\s*\n)',
            re.MULTILINE,
        )
        match = pattern.search(src)
        if match:
            replacement = (
                '#ifdef __ANDROID__\n'
                '    if (getenv("WINE_X11FORCEGLX"))\n'
                '        wine_x11forceglx = atoi(getenv("WINE_X11FORCEGLX"));\n'
                '\n'
                '    if (XQueryExtension( gdi_display, "GLX", &glx_opcode, &event_base, &error_base ) || wine_x11forceglx)\n'
                '#else\n'
                '    if (XQueryExtension( gdi_display, "GLX", &glx_opcode, &event_base, &error_base ))\n'
                '#endif\n'
            )
            src = src[: match.start()] + replacement + src[match.end() :]
            print("  [regex android WINE_X11FORCEGLX handling] applied")
            total += 1

    if "wine_x11forceglx" in src and not has_forceglx_declaration(src):
        pattern = re.compile(r"(UINT\s+X11DRV_OpenGLInit\s*\([^)]*\)\s*\n\{\n)", re.MULTILINE)
        match = pattern.search(src)
        if match:
            src = src[: match.end()] + "#ifdef __ANDROID__\n    int wine_x11forceglx = 0;\n#endif\n" + src[match.end() :]
            print("  [final fallback android wine_x11forceglx variable] applied")
            total += 1

    if "wine_x11forceglx" in src:
        src, n = ensure_forceglx_file_fallback(src)
        if n:
            print("  [file-scope android wine_x11forceglx fallback] applied")
            total += n

    with open(path, "w", encoding="utf-8") as f:
        f.write(src)

    print(f"\nDone. Applied {total} fix(es) to opengl.c")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
