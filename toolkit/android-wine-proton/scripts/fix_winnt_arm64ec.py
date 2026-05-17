#!/usr/bin/env python3
"""Keep winnt.h ARM64EC-friendly when upstream chooses x86 inline asm."""

import sys
from pathlib import Path


def replace_once(text, old, new, label):
    if new in text:
        print(f"  [{label}] already applied")
        return text, 0
    if old not in text:
        print(f"  [{label}] pattern not found")
        return text, 0
    print(f"  [{label}] applied")
    return text.replace(old, new, 1), 1


def main():
    if len(sys.argv) != 2:
        print("Usage: fix_winnt_arm64ec.py <wine-source-dir>")
        return 1

    path = Path(sys.argv[1]) / "include" / "winnt.h"
    if not path.exists():
        print(f"ERROR: missing file {path}")
        return 2

    text = path.read_text(encoding="utf-8", errors="replace")
    total = 0

    text, n = replace_once(
        text,
        "#if defined(__x86_64__) || defined(__i386__)\n"
        '    for (;;) __asm__ __volatile__( "int $0x29" :: "c" ((ULONG_PTR)code) : "memory" );\n'
        "#elif defined(__aarch64__)\n",
        "#if (defined(__x86_64__) || defined(__i386__)) && !defined(__arm64ec__)\n"
        '    for (;;) __asm__ __volatile__( "int $0x29" :: "c" ((ULONG_PTR)code) : "memory" );\n'
        "#elif defined(__aarch64__) || defined(__arm64ec__)\n",
        "arm64ec fastfail asm",
    )
    total += n

    # InterlockedExchange: exclude arm64ec from x86 inline asm path
    text, n = replace_once(
        text,
        "#elif defined(__i386__) || defined(__x86_64__)\n"
        '    __asm__ __volatile__( "lock; xchgl %0,(%1)"\n'
        '                          : "=r" (ret) :"r" (dest), "0" (val) : "memory" );\n'
        "#else\n"
        "    do ret = *dest; while (!__sync_bool_compare_and_swap( dest, ret, val ));\n",
        "#elif (defined(__i386__) || defined(__x86_64__)) && !defined(__arm64ec__)\n"
        '    __asm__ __volatile__( "lock; xchgl %0,(%1)"\n'
        '                          : "=r" (ret) :"r" (dest), "0" (val) : "memory" );\n'
        "#else\n"
        "    do ret = *dest; while (!__sync_bool_compare_and_swap( dest, ret, val ));\n",
        "arm64ec InterlockedExchange asm",
    )
    total += n

    # InterlockedExchangePointer: exclude arm64ec from x86_64 inline asm path
    text, n = replace_once(
        text,
        "#elif defined(__x86_64__)\n"
        '    __asm__ __volatile__( "lock; xchgq %0,(%1)" : "=r" (ret) :"r" (dest), "0" (val) : "memory" );\n'
        "#elif defined(__i386__)\n"
        '    __asm__ __volatile__( "lock; xchgl %0,(%1)" : "=r" (ret) :"r" (dest), "0" (val) : "memory" );\n',
        "#elif defined(__x86_64__) && !defined(__arm64ec__)\n"
        '    __asm__ __volatile__( "lock; xchgq %0,(%1)" : "=r" (ret) :"r" (dest), "0" (val) : "memory" );\n'
        "#elif defined(__i386__)\n"
        '    __asm__ __volatile__( "lock; xchgl %0,(%1)" : "=r" (ret) :"r" (dest), "0" (val) : "memory" );\n',
        "arm64ec InterlockedExchangePointer asm",
    )
    total += n

    # __WINE_ATOMIC_LOAD/STORE: use proper __atomic builtins for arm64ec
    text, n = replace_once(
        text,
        "#if defined(__x86_64__) || defined(__i386__)\n"
        "/* On x86, Support old GCC",
        "#if (defined(__x86_64__) || defined(__i386__)) && !defined(__arm64ec__)\n"
        "/* On x86, Support old GCC",
        "arm64ec atomic load/store macros",
    )
    total += n

    path.write_text(text, encoding="utf-8")
    print(f"\nDone. Applied {total} fix(es) to winnt.h")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
