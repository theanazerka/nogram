#!/usr/bin/env python3
"""Assemble the Telegram.app resource folder for Theos from the Xcode project.

Usage: gen-telegram-resources.py <telegram dir> <output dir>

Mirrors Xcode's "Copy Bundle Resources" phase: plain files and bundles go to the
bundle root, localized variants into <lang>.lproj/. iOS 6 has no asset catalogs and
no launch storyboards, so icons and launch images come as plain PNGs and Info.plist
is rewritten accordingly.
"""
import importlib.util
import os
import plistlib
import shutil
import sys

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('pbx', os.path.join(here, 'pbx2files.py'))
pbx = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pbx)

ROOT = os.path.abspath(sys.argv[1])
OUT = os.path.abspath(sys.argv[2])

SKIP_EXT = ('.xib', '.storyboard', '.xcassets')
ROOT_IMAGES = ['Icon.png', 'Icon@2x.png', 'Icon-57.png', 'Icon-72.png', 'Icon-72@2x.png', 'Icon-76.png',
               'Icon-76@2x.png', 'Icon-60@2x.png', 'Icon-60@3x.png', 'Icon-40.png', 'Icon-40@2x.png',
               'Icon-40@3x.png', 'Icon-Small@2x.png', 'Icon-87.png', 'Icon-167.png',
               'Default@2x.png', 'Default-568h@2x.png', 'iPad-Landscape.png', 'iPad-Landscape@2x.png',
               'iPad-Portrait.png', 'iPad-Portrait@2x.png']


def copy(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if os.path.isdir(src):
        if os.path.exists(dst):
            shutil.rmtree(dst)
        shutil.copytree(src, dst, symlinks=False)
    else:
        shutil.copy2(src, dst)


def main():
    os.chdir(ROOT)
    data = pbx.load('Telegraph.xcodeproj')
    objects = data['objects']
    project = objects[data['rootObject']]
    paths = pbx.build_paths(objects, project['mainGroup'])
    target = [objects[t] for t in project['targets'] if objects[t]['name'] == 'Telegraph'][0]

    if os.path.exists(OUT):
        shutil.rmtree(OUT)
    os.makedirs(OUT)

    count = 0
    for phase_key in target['buildPhases']:
        phase = objects[phase_key]
        if phase['isa'] != 'PBXResourcesBuildPhase':
            continue
        for bf_key in phase['files']:
            ref_key = objects[bf_key].get('fileRef')
            ref = objects.get(ref_key, {})
            if ref.get('isa') == 'PBXVariantGroup':
                for child in ref['children']:
                    src = paths.get(child)
                    if not src or not os.path.exists(src):
                        continue
                    lang_dir = os.path.basename(os.path.dirname(src))
                    if not lang_dir.endswith('.lproj'):
                        lang_dir = 'Base.lproj'
                    copy(src, os.path.join(OUT, lang_dir, os.path.basename(src)))
                    count += 1
                continue
            src = paths.get(ref_key)
            if not src or src.endswith(SKIP_EXT) or not os.path.exists(src):
                continue
            copy(src, os.path.join(OUT, os.path.basename(src)))
            count += 1

    for name in ROOT_IMAGES:
        if os.path.exists(name):
            copy(name, os.path.join(OUT, name))
    # iPhone launch image for 3.5" non-retina devices is optional; reuse @2x name scheme.

    with open('Telegraph/Telegraph-Info.plist', 'rb') as f:
        info = plistlib.load(f)
    subst = {
        '${TELEGRAM_APP_NAME}': 'Telegram',
        '${EXECUTABLE_NAME}': 'Telegram',
        '$(TELEGRAPH_BUNDLE_ID)': 'org.telegram.legacy',
        '${PRODUCT_NAME}': 'Telegram',
    }

    def fix(value):
        if isinstance(value, str):
            for k, v in subst.items():
                value = value.replace(k, v)
            return value
        if isinstance(value, list):
            return [fix(v) for v in value]
        if isinstance(value, dict):
            return {k: fix(v) for k, v in value.items()}
        return value

    info = fix(info)
    info['CFBundleExecutable'] = 'Telegram'
    info['CFBundleIdentifier'] = 'org.telegram.legacy'
    info['MinimumOSVersion'] = '6.0'
    info.pop('UILaunchStoryboardName', None)
    info['CFBundleIconFiles'] = [n for n in ROOT_IMAGES if n.startswith('Icon')]
    info['UIRequiredDeviceCapabilities'] = ['armv7']
    info.pop('NSExtension', None)
    with open(os.path.join(OUT, 'Info.plist'), 'wb') as f:
        plistlib.dump(info, f)

    print('resources: %d entries -> %s' % (count, OUT))


if __name__ == '__main__':
    main()
