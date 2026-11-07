#!/usr/bin/env python3
"""Compile a Telegram API .tl schema into the compact JSON used at runtime.

Usage: tl2json.py <telegram_api.tl> <layer> <out.json>

Output format:
  {"layer": N,
   "c": [[id, "predicate", "Type", [["name", "type"], ...]], ...],   # constructors
   "m": [[id, "method.name", "ReturnType", [["name", "type"], ...]], ...]}  # functions

Type strings are kept in TL notation ("flags.3?string", "Vector<long>", "!X", "#"),
the runtime coder in Sources/TLCoder.m interprets them.
"""
import json
import re
import sys

LINE = re.compile(r'^([A-Za-z0-9_.]+)#([0-9a-fA-F]{1,8})\s*(.*?)=\s*([^;]+);\s*$')


def parse(path):
    constructors, methods = [], []
    section = 'types'
    buf = ''
    for raw in open(path, encoding='utf-8'):
        line = raw.split('//', 1)[0].strip()
        if not line:
            continue
        if line == '---functions---':
            section = 'functions'
            continue
        if line == '---types---':
            section = 'types'
            continue
        buf = (buf + ' ' + line).strip()
        if not buf.endswith(';'):
            continue
        entry, buf = buf, ''
        m = LINE.match(entry)
        if not m:
            continue  # builtins without ids (int ? = Int; etc.)
        name, cid, args, result = m.groups()
        cid = int(cid, 16)
        if cid >= 0x80000000:
            cid -= 0x100000000
        params = []
        for tok in args.split():
            if tok.startswith('{') or tok == '#' or tok.startswith('['):
                continue
            if ':' not in tok:
                continue
            pname, ptype = tok.split(':', 1)
            params.append([pname, ptype])
        item = [cid, name, result.strip(), params]
        (constructors if section == 'types' else methods).append(item)
    return constructors, methods


def main():
    src, layer, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    c, m = parse(src)
    with open(out, 'w', encoding='utf-8') as f:
        json.dump({'layer': layer, 'c': c, 'm': m}, f, separators=(',', ':'), ensure_ascii=False)
    print('tl2json: layer %d, %d constructors, %d methods -> %s' % (layer, len(c), len(m), out))


if __name__ == '__main__':
    main()
