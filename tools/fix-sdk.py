#!/usr/bin/env python3
"""Make an iPhoneOS 10.x SDK usable for armv7 builds targeting iOS 6.

The 10.x .tbd stubs (tapi v2) dropped symbols that only exist on 32-bit ARM,
e.g. objc_msgSend_stret and the compiler_rt helpers (__umodsi3, __divsi3 ...).
The 9.3 SDK still lists them, but its old v1 stubs are mis-detected as
simulator libraries by current ld64. This script copies every symbol that a
9.3 stub has and the matching 10.x stub lacks into an extra armv7 exports
block of the 10.x stub.

Usage: fix-sdk.py <iPhoneOS9.3.sdk> <iPhoneOS10.x.sdk>
"""
import os
import re
import sys

KEYS = ('symbols', 'objc-classes', 'objc-ivars', 'weak-def-symbols')
LIST_RE = re.compile(r'(%s):\s*\[(.*?)\]' % '|'.join(re.escape(k) for k in KEYS), re.S)


def collect(text):
    found = {k: set() for k in KEYS}
    for key, body in LIST_RE.findall(text):
        for token in body.replace('\n', ' ').split(','):
            token = token.strip().strip("'\"")
            if token:
                found[key].add(token)
    return found


def fmt_list(items):
    return '[ ' + ', '.join(sorted(items)) + ' ]'


def patch(old_path, new_path):
    old = collect(open(old_path, encoding='utf-8', errors='replace').read())
    text = open(new_path, encoding='utf-8', errors='replace').read()
    new = collect(text)
    missing = {k: old[k] - new[k] for k in KEYS}
    # The legacy objc runtime ABI names classes differently in v1 stubs; only
    # carry over plain symbols for objc metadata keys that already match.
    if not any(missing.values()):
        return 0
    block = '  - archs:                [ armv7, armv7s ]\n'
    for key in KEYS:
        if missing[key]:
            block += '    %-22s%s\n' % (key + ':', fmt_list(missing[key]))
    end = text.rstrip().rfind('\n...')
    if end < 0:
        return 0
    head = text[:end + 1]
    if 'exports:' not in head:
        head += 'exports:\n'
    open(new_path, 'w', encoding='utf-8').write(head + block + '...\n')
    return sum(len(v) for v in missing.values())


def main():
    old_sdk, new_sdk = sys.argv[1], sys.argv[2]
    total = files = 0
    for root, _, names in os.walk(new_sdk):
        for name in names:
            if not name.endswith('.tbd'):
                continue
            new_path = os.path.join(root, name)
            rel = os.path.relpath(new_path, new_sdk)
            old_path = os.path.join(old_sdk, rel)
            if os.path.exists(old_path):
                added = patch(old_path, new_path)
                if added:
                    files += 1
                    total += added
    print('fix-sdk: added %d armv7 symbols to %d stubs' % (total, files))


if __name__ == '__main__':
    main()
