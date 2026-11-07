#!/usr/bin/env python3
"""List the compiled sources (and their per-file flags) of a target in an .xcodeproj.

Usage: pbx2files.py <project.xcodeproj> [target]
Without a target, prints the target names.
Output lines: <path relative to the project dir>\t<COMPILER_FLAGS>
"""
import os
import re
import sys


def tokenize(text):
    text = text.split('\n', 1)[1] if text.startswith('//') else text
    pos = 0
    tokens = []
    pattern = re.compile(r'(?:\s|/\*.*?\*/)*(?:("(?:[^"\\]|\\.)*")|([{}()=;,])|([^\s{}()=;,"]+))', re.S)
    while pos < len(text):
        m = pattern.match(text, pos)
        if not m or m.end() == pos:
            break
        pos = m.end()
        if m.group(1) is not None:
            tokens.append(('s', bytes(m.group(1)[1:-1], 'utf-8').decode('unicode_escape') if '\\' in m.group(1) else m.group(1)[1:-1]))
        elif m.group(2) is not None:
            tokens.append(('p', m.group(2)))
        elif m.group(3) is not None:
            tokens.append(('s', m.group(3)))
    return tokens


def parse(tokens, i=0):
    kind, value = tokens[i]
    if kind == 'p' and value == '{':
        obj = {}
        i += 1
        while tokens[i] != ('p', '}'):
            key = tokens[i][1]
            assert tokens[i + 1] == ('p', '=')
            val, i = parse(tokens, i + 2)
            obj[key] = val
            assert tokens[i] == ('p', ';'), tokens[i]
            i += 1
        return obj, i + 1
    if kind == 'p' and value == '(':
        arr = []
        i += 1
        while tokens[i] != ('p', ')'):
            val, i = parse(tokens, i)
            arr.append(val)
            if tokens[i] == ('p', ','):
                i += 1
        return arr, i + 1
    return value, i + 1


def load(proj):
    text = open(os.path.join(proj, 'project.pbxproj'), encoding='utf-8').read()
    root, _ = parse(tokenize(text))
    return root


def build_paths(objects, root_group):
    paths = {}

    def walk(key, parent):
        obj = objects[key]
        tree = obj.get('sourceTree', '<group>')
        path = obj.get('path')
        if tree == '<group>':
            base = os.path.join(parent, path) if path else parent
        elif tree == 'SOURCE_ROOT':
            base = path or ''
        else:
            base = '$(%s)/%s' % (tree, path)
        paths[key] = os.path.normpath(base) if base else ''
        for child in obj.get('children', []):
            walk(child, base)

    walk(root_group, '')
    return paths


def main():
    proj = sys.argv[1]
    data = load(proj)
    objects = data['objects']
    project = objects[data['rootObject']]
    paths = build_paths(objects, project['mainGroup'])
    targets = {objects[t]['name']: objects[t] for t in project['targets']}
    if len(sys.argv) < 3:
        for name in targets:
            print(name)
        return
    target = targets[sys.argv[2]]
    for phase_key in target['buildPhases']:
        phase = objects[phase_key]
        if phase['isa'] != 'PBXSourcesBuildPhase':
            continue
        for bf_key in phase['files']:
            bf = objects[bf_key]
            ref = bf.get('fileRef')
            if ref is None or ref not in paths:
                continue
            flags = bf.get('settings', {}).get('COMPILER_FLAGS', '') if isinstance(bf.get('settings'), dict) else ''
            print('%s\t%s' % (paths[ref], flags))


if __name__ == '__main__':
    main()
