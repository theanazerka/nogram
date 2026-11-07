#!/usr/bin/env python3
"""Build a flat Cydia/APT repository from CI artifacts.

Usage: make-cydia-repo.py <artifacts dir> <output dir> <public base url>

Output layout (add <public base url> as a source in Cydia):
  Packages, Packages.gz, Packages.bz2, Release, CydiaIcon.png, index.html, debs/*.deb, ipa/*.ipa
"""
import bz2
import time
import gzip
import hashlib
import html
import os
import shutil
import subprocess
import sys

ART, OUT, URL = sys.argv[1], sys.argv[2], sys.argv[3].rstrip('/') + '/'
HERE = os.path.dirname(os.path.abspath(__file__))

if os.path.exists(OUT):
    shutil.rmtree(OUT)
os.makedirs(os.path.join(OUT, 'debs'))
os.makedirs(os.path.join(OUT, 'ipa'))

debs, ipas = [], []
for root, _, names in os.walk(ART):
    for name in sorted(names):
        src = os.path.join(root, name)
        if name.endswith('.deb'):
            shutil.copy2(src, os.path.join(OUT, 'debs', name))
            debs.append(name)
        elif name.endswith('.ipa'):
            shutil.copy2(src, os.path.join(OUT, 'ipa', name))
            ipas.append(name)
if not debs:
    sys.exit('make-cydia-repo: no .deb files found in %s' % ART)

packages = subprocess.check_output(['dpkg-scanpackages', '-m', 'debs', '/dev/null'], cwd=OUT, text=True)
with open(os.path.join(OUT, 'Packages'), 'w') as f:
    f.write(packages)
raw = packages.encode()
with gzip.open(os.path.join(OUT, 'Packages.gz'), 'wb') as f:
    f.write(raw)
with bz2.open(os.path.join(OUT, 'Packages.bz2'), 'wb') as f:
    f.write(raw)

lines = [
    'Origin: nogram',
    'Label: nogram',
    'Suite: stable',
    'Version: 1.0',
    'Codename: ios',
    'Architectures: iphoneos-arm',
    'Components: main',
    'Description: Original Telegram 4.9.1 rebuilt for iOS 6, built by GitHub Actions',
    'Date: ' + time.strftime('%a, %d %b %Y %H:%M:%S UTC', time.gmtime()),
]
for algo, field in (('md5', 'MD5Sum'), ('sha256', 'SHA256')):
    lines.append(field + ':')
    for name in ('Packages', 'Packages.gz', 'Packages.bz2'):
        data = open(os.path.join(OUT, name), 'rb').read()
        lines.append(' %s %d %s' % (hashlib.new(algo, data).hexdigest(), len(data), name))
with open(os.path.join(OUT, 'Release'), 'w') as f:
    f.write('\n'.join(lines) + '\n')

icon = os.path.join(HERE, '..', 'telegram', 'Icon@2x.png')
if os.path.exists(icon):
    shutil.copy2(icon, os.path.join(OUT, 'CydiaIcon.png'))

entries = []
for block in packages.strip().split('\n\n'):
    fields = {}
    for line in block.splitlines():
        if ':' in line and not line.startswith(' '):
            k, v = line.split(':', 1)
            fields[k] = v.strip()
    entries.append('<li><b>%s</b> %s — <a href="%s">%s</a></li>' % (
        html.escape(fields.get('Name', fields.get('Package', ''))), html.escape(fields.get('Version', '')),
        html.escape(fields.get('Filename', '')), html.escape(os.path.basename(fields.get('Filename', '')))))
ipa_links = ''.join('<li><a href="ipa/%s">%s</a></li>' % (html.escape(n), html.escape(n)) for n in ipas)

page = '''<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>nogram repo</title>
<style>body{font-family:Helvetica,Arial,sans-serif;margin:16px;line-height:1.4}code{background:#eee;padding:2px 4px}</style>
</head><body>
<h1>nogram — Cydia repo</h1>
<p>Cydia → Sources → Edit → Add:<br><code>%s</code></p>
<h3>Packages</h3><ul>%s</ul>
<h3>IPA (AppSync)</h3><ul>%s</ul>
</body></html>
''' % (html.escape(URL), ''.join(entries), ipa_links)
with open(os.path.join(OUT, 'index.html'), 'w') as f:
    f.write(page)
open(os.path.join(OUT, '.nojekyll'), 'w').close()
print('make-cydia-repo: %d debs, %d ipas -> %s' % (len(debs), len(ipas), OUT))
