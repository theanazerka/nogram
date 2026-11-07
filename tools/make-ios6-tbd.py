#!/usr/bin/env python3
"""Generate .tbd link stubs from real iOS 6 dylibs.

Usage: make-ios6-tbd.py <dylib> <install name> <out.tbd>

The iOS 11.4 SDK stubs re-export libc++abi from libc++, which is not true on
iOS 6, so the linker records __cxa_* etc. against the wrong library and dyld
refuses to start the app. Linking against stubs made from the iOS 6 binaries
binds every symbol to the library that really provides it there.
"""
import re
import subprocess
import sys

dylib, install_name, out = sys.argv[1:4]
trie = subprocess.run(['llvm-objdump', '--macho', '--arch=armv7', '--exports-trie', dylib],
                      capture_output=True, text=True).stdout
symbols = sorted({m.group(1) for m in re.finditer(r'^\s*0x[0-9A-Fa-f]+\s+(\S+)', trie, re.M)})
if not symbols:
    sys.exit('no exports found in %s' % dylib)


def wrap(items):
    lines, line = [], ''
    for item in items:
        quoted = "'%s'" % item if any(c in item for c in ',[]{}:#') else item
        if len(line) + len(quoted) > 90:
            lines.append(line.rstrip(', '))
            line = ''
        line += quoted + ', '
    lines.append(line.rstrip(', '))
    return ('\n' + ' ' * 26).join(lines)


with open(out, 'w') as f:
    f.write('--- !tapi-tbd-v2\n')
    f.write('archs:           [ armv7, armv7s ]\n')
    f.write('platform:        ios\n')
    f.write('install-name:    %s\n' % install_name)
    f.write('current-version: 1\n')
    f.write('compatibility-version: 1\n')
    f.write('exports:\n')
    f.write('  - archs:           [ armv7, armv7s ]\n')
    f.write('    symbols:         [ %s ]\n' % wrap(symbols))
    f.write('...\n')
print('%s: %d symbols' % (out, len(symbols)))
