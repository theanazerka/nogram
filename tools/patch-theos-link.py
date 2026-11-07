#!/usr/bin/env python3
"""Make Theos link through an ld64 -filelist instead of passing every object on the command line.

~3000 object paths overflow the 128 KiB single-argument limit of `bash -c`, so the
list is written with make's $(file) function (no shell involved) and handed to ld.
The list goes into $(THEOS_OBJ_DIR), which exists by the time the link recipe runs.
"""
import sys

path = sys.argv[1]
s = open(path).read()
original = '\t$$(ECHO_LINKING)$$(ECHO_UNBUFFERED)$$(TARGET_LD) $$(ALL_LDFLAGS) -o "$$@" $$^$$(ECHO_END)'
old_patch = ('\t$$(file >$$@.filelist)$$(foreach o,$$^,$$(file >>$$@.filelist,$$o))\n'
             '\t$$(ECHO_LINKING)$$(ECHO_UNBUFFERED)$$(TARGET_LD) $$(ALL_LDFLAGS) -o "$$@" -filelist "$$@.filelist"$$(ECHO_END)')
filelist = '$$(THEOS_OBJ_DIR)/$$(notdir $$@).filelist'
new = ('\t$$(file >%s)$$(foreach o,$$^,$$(file >>%s,$$o))\n'
       '\t$$(ECHO_LINKING)$$(ECHO_UNBUFFERED)$$(TARGET_LD) $$(ALL_LDFLAGS) -o "$$@" -filelist "%s"$$(ECHO_END)') % (filelist, filelist, filelist)
if new in s:
    sys.exit(0)
if old_patch in s:
    s = s.replace(old_patch, new)
elif original in s:
    s = s.replace(original, new)
else:
    sys.exit('patch-theos-link: link rule not found in %s' % path)
open(path, 'w').write(s)
print('patch-theos-link: linking via -filelist')
