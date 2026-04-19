#!/usr/bin/env python3

from pathlib import Path
import re
import sys


def ensure_pulse_fix(source_dir: Path) -> str:
    path = source_dir / "dlls" / "winepulse.drv" / "pulse.c"
    text = path.read_text(encoding="utf-8")

    guarded_protocol = (
        "#ifndef __ANDROID__" in text
        and "pthread_mutexattr_setprotocol(&attr, PTHREAD_PRIO_INHERIT);" in text
    )
    guarded_robust = (
        "#ifndef __ANDROID__" in text
        and "pthread_mutexattr_setrobust(&attr, PTHREAD_MUTEX_ROBUST);" in text
    )
    if guarded_protocol or guarded_robust:
        return "pulse: already guarded for Android"

    protocol_pattern = re.compile(
        r'(?P<indent>\s*)pthread_mutexattr_setprotocol\(&attr,\s*PTHREAD_PRIO_INHERIT\);\n',
        re.MULTILINE,
    )
    robust_pattern = re.compile(
        r'(?P<indent>\s*)pthread_mutexattr_setrobust\(&attr,\s*PTHREAD_MUTEX_ROBUST\);\n',
        re.MULTILINE,
    )

    match = protocol_pattern.search(text)
    replacement_line = "pthread_mutexattr_setprotocol(&attr, PTHREAD_PRIO_INHERIT);"
    if not match:
        match = robust_pattern.search(text)
        replacement_line = "pthread_mutexattr_setrobust(&attr, PTHREAD_MUTEX_ROBUST);"

    if not match:
        raise RuntimeError(
            f"pulse: supported mutex attribute call not found in {path}"
        )

    indent = match.group("indent")
    replacement = (
        f"{indent}#ifndef __ANDROID__\n"
        f"{indent}{replacement_line}\n"
        f"{indent}#endif\n"
    )
    text = text[: match.start()] + replacement + text[match.end() :]
    path.write_text(text, encoding="utf-8")
    return f"pulse: added Android guard around {replacement_line}"


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
    ]
    for line in results:
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
