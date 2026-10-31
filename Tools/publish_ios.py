import hashlib
import json
import os
from pathlib import Path
import plistlib
import struct
import subprocess
import zipfile


def prepare(source, destination, version_file, tag):
    values = dict(line.split('=', 1) for line in version_file.read_text().splitlines() if '=' in line)
    values = {key.strip(): value.strip() for key, value in values.items()}
    version = values['MARKETING_VERSION']
    if tag != 'v' + (version + '.0' if len(version.split('.')) == 2 else version):
        raise ValueError('Release 标签必须与 iOS 版本一致')
    checksum = hashlib.sha256(source.read_bytes()).hexdigest()
    with zipfile.ZipFile(source) as archive:
        if archive.testzip() is not None:
            raise ValueError('IPA ZIP 无效')
        if any('.xctest/' in name or 'paper-fixtures' in name for name in archive.namelist()):
            raise ValueError('IPA 不应包含测试资源')
        root = 'Payload/LearningReader.app/'
        info = plistlib.loads(archive.read(root + 'Info.plist'))
        if (info['CFBundleShortVersionString'], info['CFBundleVersion'], info['CFBundleIdentifier']) != (version, values['CURRENT_PROJECT_VERSION'], 'chatgpt.nice114514.MathLearning'):
            raise ValueError('IPA 版本或应用标识不一致')
        if struct.unpack('<II', archive.read(root + 'LearningReader')[:8]) != (0xfeedfacf, 0x100000c):
            raise ValueError('IPA 架构必须为 arm64')
        for resource in ['text-map.js', 'glossary-ui.js', 'ai-answer.js']:
            if not any(name.endswith('/Reader/' + resource) for name in archive.namelist()):
                raise ValueError('IPA 缺少离线资源：' + resource)
    destination.mkdir(parents=True, exist_ok=True)
    ipa = destination / ('LearningReader-iOS-' + version + '-unsigned.ipa')
    ipa.write_bytes(source.read_bytes())
    sums = destination / ('LearningReader-' + version + '-SHA256SUMS.txt')
    sums.write_text(checksum + '  ' + ipa.name + '\n')
    return version, [ipa, sums]


def release_metadata(tag):
    result = subprocess.run(['gh', 'release', 'view', tag, '--json', 'apiUrl', '--jq', '.apiUrl'], text=True, capture_output=True)
    if result.returncode:
        if 'release not found' in result.stderr.lower():
            return None
        raise RuntimeError(result.stderr)
    return json.loads(subprocess.check_output(['gh', 'api', result.stdout.strip()], text=True))


def publish():
    tag = os.environ['GITHUB_REF_NAME']
    repository = os.environ['GITHUB_REPOSITORY']
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    target = subprocess.check_output(['gh', 'api', 'repos/' + repository + '/commits/' + tag, '--jq', '.sha'], text=True).strip()
    if commit != target:
        raise ValueError('标签与已验证源码不一致')
    version, assets = prepare(Path('build/release-input/LearningReader-unsigned.ipa'), Path('build/publish'), Path('Config/iOS-Version.xcconfig'), tag)
    notes = Path('build/publish/notes.md')
    notes.write_text(Path('docs/releases/iOS.md').read_text() + '\n\n构建记录：https://github.com/' + repository + '/actions/runs/' + os.environ['GITHUB_RUN_ID'] + '\n')
    release = release_metadata(tag)
    if release is None:
        subprocess.run(['gh', 'release', 'create', tag, '--verify-tag', '--draft', '--title', '知序 ' + version, '--notes-file', str(notes)], check=True)
        release = release_metadata(tag)
    if release is None:
        raise RuntimeError('无法读取待发布的 Release')
    for asset in assets:
        expected = 'sha256:' + hashlib.sha256(asset.read_bytes()).hexdigest()
        existing = next((item for item in release['assets'] if item['name'] == asset.name), None)
        if existing:
            if existing.get('digest') != expected or existing['size'] != asset.stat().st_size:
                raise ValueError('已有附件与本次构建不一致，拒绝覆盖：' + asset.name)
        else:
            subprocess.run(['gh', 'release', 'upload', tag, str(asset)], check=True)
    uploaded = release_metadata(tag)
    if uploaded is None:
        raise RuntimeError('无法校验 Release 附件')
    for asset in assets:
        expected = 'sha256:' + hashlib.sha256(asset.read_bytes()).hexdigest()
        if not any(item['name'] == asset.name and item.get('digest') == expected for item in uploaded['assets']):
            raise ValueError('上传校验失败：' + asset.name)
    subprocess.run(['gh', 'release', 'edit', tag, '--draft=false', '--prerelease=false', '--latest'], check=True)


if __name__ == '__main__':
    publish()
