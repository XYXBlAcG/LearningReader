import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / '.build/release/course'


class CourseChecks(unittest.TestCase):
    def run_course(self, *args):
        return subprocess.run([str(CLI), *map(str, args)], text=True, capture_output=True)

    def test_templates(self):
        for name in ['minimal-course', 'machine-learning-course']:
            with self.subTest(name=name):
                result = self.run_course('validate', ROOT / 'Templates' / name)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_export_contains_reader_and_course_without_app_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary) / 'site'
            result = self.run_course('export', ROOT / 'Templates/machine-learning-course', destination)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((destination / 'reader/index.html').is_file())
            self.assertTrue((destination / 'content/note/lessons/01-introduction.md').is_file())
            self.assertFalse((destination / 'course.json').exists())
            self.assertEqual(json.loads((destination / 'content/index.json').read_text())['notes'][0]['path'], 'lessons/01-introduction.md')

    def test_real_zip_installs(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary) / 'course.zip'
            source = ROOT / 'Templates/machine-learning-course'
            with zipfile.ZipFile(archive, 'w') as output:
                for file in source.rglob('*'):
                    if file.is_file():
                        output.write(file, 'repository/' + file.relative_to(source).as_posix())
            result = self.run_course('archive', archive)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_archive_rejects_traversal(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary) / 'bad.zip'
            with zipfile.ZipFile(archive, 'w') as output:
                output.writestr('repository/../outside.md', '# Outside')
            self.assertNotEqual(self.run_course('archive', archive, '--markdown').returncode, 0)

    def test_plain_markdown_skips_dependencies(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'README.md').write_text('# Course')
            (root / 'node_modules').mkdir()
            (root / 'node_modules/bad.md').write_text('# Bad\n[[missing]]')
            result = self.run_course('validate', root, '--markdown')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('1 篇文章', result.stdout)
            self.assertIn('Course', result.stdout)

    def test_manifest_rejects_missing_entry_and_escaping_assets(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'README.md').write_text('# Course')
            manifest = {'schemaVersion': 1, 'title': 'Course', 'entry': 'missing.md', 'sections': [{'kind': 'note', 'path': '.', 'title': 'Lessons'}], 'assets': []}
            (root / 'course.json').write_text(json.dumps(manifest))
            self.assertNotEqual(self.run_course('validate', root).returncode, 0)
            manifest.update(entry='README.md', assets=['../outside'])
            (root / 'course.json').write_text(json.dumps(manifest))
            self.assertNotEqual(self.run_course('validate', root).returncode, 0)


if __name__ == '__main__':
    unittest.main()
