#!/usr/bin/env python3
"""Generate .tbd link stubs from real iOS 6 dylibs.

Usage: make-ios6-tbd.py <dylib> <out.tbd>

The iOS 11.4 SDK stubs re-export libc++abi from libc++, which is not true on
iOS 6, so the linker records __cxa_* etc. against the wrong library and dyld
refuses to start the app. Linking against stubs made from the iOS 6 binaries
binds every symbol to the library that really provides it there.
Requires llvm-readtapi (LLVM 18+).
"""
import shutil
import subprocess
import sys

dylib, out = sys.argv[1:3]
tool = shutil.which('llvm-readtapi') or shutil.which('llvm-readtapi-18')
if tool is None:
    sys.exit('llvm-readtapi not found')
subprocess.check_call([tool, '-stubify', '--filetype=tbd-v3', dylib, '--o=' + out])
print('wrote', out)
