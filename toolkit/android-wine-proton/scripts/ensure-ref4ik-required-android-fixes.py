#!/usr/bin/env python3

from pathlib import Path
import re
import sys


def ensure_pulse_fix(source_dir: Path) -> str:
    path = source_dir / "dlls" / "winepulse.drv" / "pulse.c"
    text = path.read_text(encoding="utf-8")

    lines = text.splitlines()
    target_tokens = (
        "pthread_mutexattr_setprotocol",
        "pthread_mutexattr_setrobust",
    )

    for i, line in enumerate(lines):
        if not any(token in line for token in target_tokens):
            continue

        block_start = i
        while block_start > 0:
            prev = lines[block_start - 1]
            if any(token in prev for token in target_tokens):
                block_start -= 1
                continue
            break

        block_end = i
        while block_end + 1 < len(lines):
            nxt = lines[block_end + 1]
            if any(token in nxt for token in target_tokens):
                block_end += 1
                continue
            break

        prev_line = lines[block_start - 1].strip() if block_start > 0 else ""
        next_line = lines[block_end + 1].strip() if block_end + 1 < len(lines) else ""
        if prev_line == "#ifndef __ANDROID__" and next_line == "#endif":
            return "pulse: Android guard already covers mutex attribute block"

        indent = re.match(r"^[ \t]*", lines[block_start]).group(0)
        block_lines = lines[block_start : block_end + 1]
        replacement = [
            f"{indent}#ifndef __ANDROID__",
            *block_lines,
            f"{indent}#endif",
        ]
        lines[block_start : block_end + 1] = replacement
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        guarded = ", ".join(
            token.replace("pthread_mutexattr_", "")
            for token in target_tokens
            if any(token in block_line for block_line in block_lines)
        )
        return f"pulse: added Android guard around mutex attribute block ({guarded})"

    raise RuntimeError(f"pulse: supported mutex attribute call not found in {path}")


def ensure_locale_fix(source_dir: Path) -> str:
    path = source_dir / "dlls" / "ntdll" / "unix" / "env.c"
    text = path.read_text(encoding="utf-8")

    if '#ifdef __ANDROID__\n    const char *all = getenv( "LC_ALL" );' in text:
        return "locale: Android locale workaround already present"

    pattern = re.compile(
        r'(?P<indent>\s*)setlocale\( LC_ALL, "" \);\n'
        r'(?P=indent)if \(!unix_to_win_locale\( setlocale\( LC_CTYPE, NULL \), system_locale \)\) system_locale\[0\] = 0;\n'
        r'(?P=indent)if \(!unix_to_win_locale\( setlocale\( LC_MESSAGES, NULL \), user_locale \)\) user_locale\[0\] = 0;\n',
        re.MULTILINE,
    )
    match = pattern.search(text)
    if not match:
        raise RuntimeError(f"locale: expected locale init block not found in {path}")

    indent = match.group("indent")
    replacement = (
        f"{indent}#ifdef __ANDROID__\n"
        f'{indent}const char *all = getenv( "LC_ALL" );\n'
        f'{indent}if (!all) all = "C.UTF-8";\n'
        f"{indent}if (!unix_to_win_locale( all, system_locale )) system_locale[0] = 0;\n"
        f"{indent}if (!unix_to_win_locale( all, user_locale )) user_locale[0] = 0;\n"
        f"{indent}#else\n"
        f'{indent}setlocale( LC_ALL, "" );\n'
        f"{indent}if (!unix_to_win_locale( setlocale( LC_CTYPE, NULL ), system_locale )) system_locale[0] = 0;\n"
        f"{indent}if (!unix_to_win_locale( setlocale( LC_MESSAGES, NULL ), user_locale )) user_locale[0] = 0;\n"
        f"{indent}#endif\n"
    )
    text = text[: match.start()] + replacement + text[match.end() :]
    path.write_text(text, encoding="utf-8")
    return "locale: added Android locale workaround"


def ensure_winex11_glx_fix(source_dir: Path) -> str:
    path = source_dir / "dlls" / "winex11.drv" / "opengl.c"
    text = path.read_text(encoding="utf-8")

    if "WINE_X11FORCEGLX" not in text and "wine_x11forceglx" not in text:
        return "winex11: GLX env-var force block not present, nothing to reconcile"

    if "static int wine_x11forceglx = -1;" in text:
        return "winex11: GLX env-var declaration already present"

    init_opengl = re.search(
        r"static void init_opengl\(void\)\n\{\n(?P<body>.*?)(?=\n(?:static |BOOL |void |\w+\s+\*?\w+\())",
        text,
        re.DOTALL,
    )
    if not init_opengl:
        return "winex11: init_opengl() block not found, skipping GLX env-var reconciliation"

    body = init_opengl.group("body")
    declaration = "    static int wine_x11forceglx = -1;\n"
    anchors = (
        "    unsigned int i;\n",
        "    int error_base, event_base;\n",
        "    int event_base, error_base;\n",
    )

    for anchor in anchors:
        if anchor in body:
            body = body.replace(anchor, anchor + declaration, 1)
            text = text[: init_opengl.start("body")] + body + text[init_opengl.end("body") :]
            path.write_text(text, encoding="utf-8")
            return f"winex11: restored missing GLX env-var declaration after patch drift (anchor: {anchor.strip()})"

    body = declaration + body
    text = text[: init_opengl.start("body")] + body + text[init_opengl.end("body") :]
    path.write_text(text, encoding="utf-8")
    return "winex11: restored missing GLX env-var declaration at init_opengl() top after patch drift"


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: ensure-ref4ik-required-android-fixes.py <wine-source-dir>", file=sys.stderr)
        return 1

    source_dir = Path(sys.argv[1])
    if not (source_dir / ".git").exists():
        print(f"not a git checkout: {source_dir}", file=sys.stderr)
        return 1

    results = [
        ensure_pulse_fix(source_dir),
        ensure_locale_fix(source_dir),
        ensure_winex11_glx_fix(source_dir),
    ]
    for line in results:
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
