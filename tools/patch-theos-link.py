#!/usr/bin/env python3
"""Make Theos link through an ld64 -filelist instead of passing every object on the command line.

~3000 object paths overflow the 128 KiB single-argument limit of `bash -c`, so the
list is written with make's $(file) function (no shell involved) and handed to ld.
"""
import sys

path = sys.argv[1]
s = open(path).read()
old = '\t$$(ECHO_LINKING)$$(ECHO_UNBUFFERED)$$(TARGET_LD) $$(ALL_LDFLAGS) -o "$$@" $$^$$(ECHO_END)'
new = ('\t$$(file >$$@.filelist)$$(foreach o,$$^,$$(file >>$$@.filelist,$$o))\n'
       '\t$$(ECHO_LINKING)$$(ECHO_UNBUFFERED)$$(TARGET_LD) $$(ALL_LDFLAGS) -o "$$@" -filelist "$$@.filelist"$$(ECHO_END)')
if new in s:
    sys.exit(0)
if old not in s:
    sys.exit('patch-theos-link: link rule not found in %s' % path)
open(path, 'w').write(s.replace(old, new))
print('patch-theos-link: linking via -filelist')
