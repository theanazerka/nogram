#!/usr/bin/env python3
"""Rename upstream `+ (void)load` methods to `+ (void)tg_deferredLoad`.

They are then run by telegram/compat/TGDeferredLoads.m under the launch tracer, so a
crashing +load can be identified and skipped on iOS 6 (see AGENTS.md, debugging).
Idempotent. Run from the repository root after importing new upstream sources:
    python3 tools/defer-loads.py
"""
import os
import re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'telegram')
SKIP_DIRS = ('compat',)
PATTERN = re.compile(r'^\+ ?\(void\) ?load\b', re.M)

sources = []
with open(os.path.join(ROOT, 'sources.mk')) as f:
    for line in f:
        if line.startswith('\t'):
            sources.append(line.strip().rstrip('\\').strip())

changed = 0
for rel in sources:
    if rel.split('/')[0] in SKIP_DIRS:
        continue
    path = os.path.join(ROOT, rel)
    text = open(path, encoding='utf-8', errors='surrogateescape').read()
    new = PATTERN.sub('+ (void)tg_deferredLoad', text)
    if new != text:
        open(path, 'w', encoding='utf-8', errors='surrogateescape').write(new)
        changed += 1
print('defer-loads: %d files changed' % changed)
