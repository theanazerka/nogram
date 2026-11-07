#!/usr/bin/env python3
"""Fail if a Mach-O strongly imports symbols that iOS 6 system libraries do not export.

dyld refuses to launch such an app ("Symbol not found") before main() runs.
usage: check-ios6-imports.py <binary> <iOS 6 sdk root with real dylibs>"""
import os, re, subprocess, sys, functools

BIN, SDK = sys.argv[1], sys.argv[2]

def run(*a):
    return subprocess.run(a, capture_output=True, text=True, errors='replace').stdout

@functools.lru_cache(None)
def exports(path):
    real = os.path.join(SDK, path.lstrip('/'))
    if not os.path.exists(real):
        return None
    out = run('llvm-objdump', '--macho', '--arch=armv7', '--exports-trie', real)
    syms = set()
    for line in out.splitlines():
        m = re.match(r'\s*0x[0-9A-Fa-f]+\s+(\S+)', line)
        if m:
            syms.add(m.group(1))
        m = re.match(r'\s*\[re-export\]\s+(\S+)', line)
    if not syms:
        for line in run('llvm-nm', '--arch=armv7', '-gU', real).splitlines():
            parts = line.split()
            if parts:
                syms.add(parts[-1])
    # re-exported libraries
    lc = run('llvm-objdump', '--macho', '--arch=armv7', '--private-headers', real)
    for m in re.finditer(r'cmd LC_REEXPORT_DYLIB\n\s+cmdsize \d+\n\s+name (\S+) \(offset', lc):
        sub = exports(m.group(1))
        if sub:
            syms |= sub
    return frozenset(syms)

binds = run('llvm-objdump', '--macho', '--bind', '--lazy-bind', BIN)
missing = {}
weak_skipped = 0
for line in binds.splitlines():
    if 'weak_import' in line:
        weak_skipped += 1
        continue
    parts = line.split()
    if len(parts) < 3 or not parts[-1].startswith('_') and not parts[-1].startswith('.'):
        continue
    sym = parts[-1]
    lib = parts[-2]
    if lib in ('flat-namespace', 'main-executable', 'this-image'):
        continue
    missing.setdefault(lib, set()).add(sym)

libs = {}
for line in run('llvm-objdump', '--macho', '--dylibs-used', BIN).splitlines()[1:]:
    p = line.strip().split(' (')[0]
    libs[os.path.basename(p).split('.')[0]] = p

total = 0
for lib, syms in sorted(missing.items()):
    path = libs.get(lib) or libs.get(lib.split('.')[0])
    if path is None:
        cand = [p for k, p in libs.items() if lib.startswith(k)]
        path = cand[0] if cand else None
    ex = exports(path) if path else None
    if ex is None:
        print('LIBRARY NOT IN iOS 6 SDK (strong!):', lib, path, len(syms))
        total += len(syms)
        continue
    bad = sorted(s for s in syms if s not in ex)
    if bad:
        total += len(bad)
        print('== %s (%s): %d missing' % (lib, path, len(bad)))
        for s in bad[:200]:
            print('   ', s)
print('weak binds skipped:', weak_skipped, 'missing total:', total)
sys.exit(1 if total else 0)
