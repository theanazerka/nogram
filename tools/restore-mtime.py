#!/usr/bin/env python3
"""Set every tracked file's mtime to the time of the last commit that touched it.

Fresh CI checkouts stamp all files with "now", which makes make rebuild everything
even when compiled objects come from cache. Run from inside the repository.
"""
import os
import subprocess

out = subprocess.check_output(
    ['git', '-c', 'core.quotepath=off', 'log', '--format=__T %ct', '--name-only', '--no-renames', 'HEAD'],
    text=True, errors='replace')

seen = set()
stamp = None
count = 0
for line in out.splitlines():
    if line.startswith('__T '):
        stamp = int(line[4:])
        continue
    if not line or line in seen:
        continue
    seen.add(line)
    if os.path.lexists(line) and not os.path.islink(line):
        os.utime(line, (stamp, stamp))
        count += 1
print('restore-mtime: %d files' % count)
