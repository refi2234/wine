#!/usr/bin/env python3
"""Keep Wine source ARM64EC-friendly when upstream chooses x86 inline asm."""

import re
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

    # YieldProcessor: exclude arm64ec from x86 "rep; nop" path
    # Wine 9.20 checks x86 first; ARM64EC defines __x86_64__ so it hits
    # the "rep; nop" path instead of the correct "dmb ishst; yield" path.
    # Reorder branches to match upstream master (arm/aarch64/arm64ec first).
    text, n = replace_once(
        text,
        "#if defined(__i386__) || defined(__x86_64__)\n"
        '    __asm__ __volatile__( "rep; nop" : : : "memory" );\n'
        "#elif defined(__arm__) || defined(__aarch64__)\n"
        '    __asm__ __volatile__( "dmb ishst\\n\\tyield" : : : "memory" );\n'
        "#else\n"
        '    __asm__ __volatile__( "" : : : "memory" );\n'
        "#endif\n",
        "#if defined(__arm__) || defined(__aarch64__) || defined(__arm64ec__)\n"
        '    __asm__ __volatile__( "dmb ishst\\n\\tyield" : : : "memory" );\n'
        "#elif defined(__i386__) || defined(__x86_64__)\n"
        '    __asm__ __volatile__( "rep; nop" : : : "memory" );\n'
        "#else\n"
        '    __asm__ __volatile__( "" : : : "memory" );\n'
        "#endif\n",
        "arm64ec YieldProcessor rep;nop",
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

    # ---- General scan: guard all x86-asm #if blocks across dlls/ ----
    source_dir = Path(sys.argv[1])
    scan_total = guard_x86_asm_blocks(source_dir)
    print(f"General scan: guarded {scan_total} x86-asm #if block(s) across source tree")

    return 0


# Pattern: full #if/#elif line that mentions an x86 arch macro.
_X86_IF_RE = re.compile(
    r'^(#\s*(?:if|elif)\b.+)$',
    re.MULTILINE,
)


def guard_x86_asm_blocks(source_dir: Path) -> int:
    """Add !defined(__arm64ec__) to #if blocks with x86 inline asm."""
    total = 0
    globs = list(source_dir.glob("dlls/**/*.[ch]"))
    for fpath in globs:
        try:
            text = fpath.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue

        new_text = text
        for m in reversed(list(_X86_IF_RE.finditer(text))):
            line = m.group(1)
            # Must reference an x86 arch macro
            if "defined(__i386__)" not in line and "defined(__x86_64__)" not in line:
                continue
            # Skip if already guarded for arm64ec
            if "__arm64ec__" in line:
                continue
            # Check if the block (up to next #else/#elif/#endif) contains inline asm
            block_start = m.end()
            block_end = text.find("\n#e", block_start)
            if block_end == -1:
                block_end = min(block_start + 2000, len(text))
            block = text[block_start:block_end]
            if "__asm__" not in block:
                continue
            # Append the guard at the very end of the line
            new_line = line + " && !defined(__arm64ec__)"
            new_text = new_text[:m.start()] + new_line + new_text[m.end():]
            rel = fpath.relative_to(source_dir)
            print(f"  [general scan] {rel}:{text[:m.start()].count(chr(10))+1}: added arm64ec guard")
            total += 1

        if new_text != text:
            fpath.write_text(new_text, encoding="utf-8")

    return total


if __name__ == "__main__":
    raise SystemExit(main())
