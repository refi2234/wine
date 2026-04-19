#!/usr/bin/env python3

from pathlib import Path
import sys


def ensure_pulse_fix(source_dir: Path) -> str:
    path = source_dir / "dlls" / "winepulse.drv" / "pulse.c"
    text = path.read_text(encoding="utf-8")

    if "#ifndef __ANDROID__" in text and "pthread_mutexattr_setprotocol(&attr, PTHREAD_PRIO_INHERIT);" in text:
        return "pulse: already guarded for Android"

    original = """    pthread_mutexattr_init(&attr);
    pthread_mutexattr_setprotocol(&attr, PTHREAD_PRIO_INHERIT);
    if (pthread_mutex_init(&pulse_mutex, &attr) != 0)
"""
    replacement = """    pthread_mutexattr_init(&attr);
#ifndef __ANDROID__
    pthread_mutexattr_setprotocol(&attr, PTHREAD_PRIO_INHERIT);
#endif
    if (pthread_mutex_init(&pulse_mutex, &attr) != 0)
"""
    if original not in text:
        raise RuntimeError(f"pulse: expected block not found in {path}")

    path.write_text(text.replace(original, replacement, 1), encoding="utf-8")
    return "pulse: added Android guard around pthread_mutexattr_setprotocol"


def ensure_locale_fix(source_dir: Path) -> str:
    path = source_dir / "dlls" / "ntdll" / "unix" / "env.c"
    text = path.read_text(encoding="utf-8")

    if '#ifdef __ANDROID__\n    const char *all = getenv( "LC_ALL" );' in text:
        return "locale: Android locale workaround already present"

    original = """    setlocale( LC_ALL, "" );
    if (!unix_to_win_locale( setlocale( LC_CTYPE, NULL ), system_locale )) system_locale[0] = 0;
    if (!unix_to_win_locale( setlocale( LC_MESSAGES, NULL ), user_locale )) user_locale[0] = 0;
"""
    replacement = """#ifdef __ANDROID__
    const char *all = getenv( "LC_ALL" );
    if (!all) all = "C.UTF-8";
    if (!unix_to_win_locale( all, system_locale )) system_locale[0] = 0;
    if (!unix_to_win_locale( all, user_locale )) user_locale[0] = 0;
#else
    setlocale( LC_ALL, "" );
    if (!unix_to_win_locale( setlocale( LC_CTYPE, NULL ), system_locale )) system_locale[0] = 0;
    if (!unix_to_win_locale( setlocale( LC_MESSAGES, NULL ), user_locale )) user_locale[0] = 0;
#endif
"""
    if original not in text:
        raise RuntimeError(f"locale: expected block not found in {path}")

    path.write_text(text.replace(original, replacement, 1), encoding="utf-8")
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
