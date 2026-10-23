import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def run(*command):
    subprocess.run(command, cwd=ROOT, check=True)


def icons():
    output = ROOT / 'Apps/iOS/Assets.xcassets/AppIcon.appiconset'
    output.mkdir(parents=True, exist_ok=True)
    run('sips', '-z', '1024', '1024', str(ROOT / 'Assets/AppIcon-master.png'), '--out', str(output / 'AppIcon.png'))
    (output / 'Contents.json').write_text(json.dumps({'images': [{'filename': 'AppIcon.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}], 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
    iconset = ROOT / 'build/AppIcon.iconset'
    iconset.mkdir(parents=True, exist_ok=True)
    for size in [16, 32, 128, 256, 512]:
        for scale in [1, 2]:
            pixels = size * scale
            run('sips', '-z', str(pixels), str(pixels), str(ROOT / 'Assets/AppIcon-master.png'), '--out', str(iconset / f'icon_{size}x{size}{"@2x" if scale == 2 else ""}.png'))
    run('iconutil', '-c', 'icns', str(iconset), '-o', str(ROOT / 'build/AppIcon.icns'))


def macos():
    os.environ['CLANG_MODULE_CACHE_PATH'] = str(ROOT / '.build/clang-cache')
    os.environ['SWIFTPM_MODULECACHE_OVERRIDE'] = str(ROOT / '.build/swiftpm-module-cache')
    command = ['swift', 'build', '-c', 'release', '--disable-sandbox', '--cache-path', str(ROOT / '.build/cache')]
    run(*command, '--product', 'LearningReader')
    run(*command, '--product', 'course')
    binary = Path(subprocess.check_output(command + ['--show-bin-path'], cwd=ROOT, text=True).strip())
    staging = ROOT / 'build/知序.app'
    if staging.exists():
        shutil.rmtree(staging)
    resources = staging / 'Contents/Resources'
    executable = staging / 'Contents/MacOS'
    executable.mkdir(parents=True)
    resources.mkdir(parents=True)
    for name in ['LearningReader', 'course']:
        shutil.copy2(binary / name, executable / name)
    for bundle in binary.glob('*.bundle'):
        shutil.copytree(bundle, resources / bundle.name)
    shutil.copy2(ROOT / 'build/AppIcon.icns', resources / 'AppIcon.icns')
    with (staging / 'Contents/Info.plist').open('wb') as handle:
        plistlib.dump({'CFBundleName': '知序', 'CFBundleDisplayName': '知序', 'CFBundleIdentifier': 'chatgpt.nice114514.mathreader', 'CFBundleExecutable': 'LearningReader', 'CFBundlePackageType': 'APPL', 'CFBundleVersion': '2', 'CFBundleShortVersionString': '2.0', 'CFBundleIconFile': 'AppIcon', 'LSMinimumSystemVersion': '13.0', 'NSHighResolutionCapable': True, 'NSAppTransportSecurity': {'NSAllowsLocalNetworking': True}}, handle)
    run('codesign', '--force', '--deep', '--sign', '-', str(staging))
    run('codesign', '--verify', '--deep', '--strict', str(staging))
    output = ROOT / 'Output'
    output.mkdir(exist_ok=True)
    final = output / '知序.app'
    if final.exists():
        shutil.rmtree(final)
    staging.rename(final)
    print(final)


parser = argparse.ArgumentParser()
parser.add_argument('target', choices=['icons', 'macos'])
args = parser.parse_args()
icons()
if args.target == 'macos':
    macos()
