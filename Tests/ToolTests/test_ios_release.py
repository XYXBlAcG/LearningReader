import hashlib
import importlib.util
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('publish_ios', Path(__file__).resolve().parents[2] / 'Tools/publish_ios.py')
publish_ios = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publish_ios)


class IOSReleaseTests(unittest.TestCase):
    def test_version_identity_architecture_and_checksum(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            config = root / 'version.xcconfig'
            config.write_text('MARKETING_VERSION = 2.11\nCURRENT_PROJECT_VERSION = 15\n')
            ipa = root / 'input.ipa'
            with zipfile.ZipFile(ipa, 'w') as archive:
                prefix = 'Payload/LearningReader.app/'
                archive.writestr(prefix + 'Info.plist', plistlib.dumps({'CFBundleShortVersionString': '2.11', 'CFBundleVersion': '15', 'CFBundleIdentifier': 'chatgpt.nice114514.MathLearning'}))
                archive.writestr(prefix + 'LearningReader', struct.pack('<II', 0xfeedfacf, 0x100000c))
                for name in ['text-map.js', 'glossary-ui.js', 'ai-answer.js']:
                    archive.writestr(prefix + 'LearningCore.bundle/Resources/Reader/' + name, '')
            version, assets = publish_ios.prepare(ipa, root / 'out', config, 'v2.11.0')
            self.assertEqual(version, '2.11')
            self.assertIn(hashlib.sha256(ipa.read_bytes()).hexdigest(), assets[1].read_text())
            with self.assertRaises(ValueError):
                publish_ios.prepare(ipa, root / 'wrong', config, 'v2.10.0')
            config.write_text('MARKETING_VERSION = 2.11\nCURRENT_PROJECT_VERSION = 16\n')
            with self.assertRaises(ValueError):
                publish_ios.prepare(ipa, root / 'wrong', config, 'v2.11.0')
