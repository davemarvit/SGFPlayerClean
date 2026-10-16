import json
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile
from import_review_analysis import prepare


class LegacyImportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.app = self.root / 'Main.app'
        self.resources = self.app / 'Contents/Resources'
        self.resources.mkdir(parents=True)
        for name in ('kata1-b18.bin.gz', 'analysis.cfg'):
            (self.resources / name).write_bytes(name.encode())
        self.exe = self.root / 'engine'
        self.exe.write_bytes(b'fixture engine')
        os.utime(self.exe, (1, 1))
        self.cache = self.root / 'caches'
        self.prefs = self.root / 'prefs'; self.prefs.mkdir()
        self.archives = self.root / 'archives'; self.archives.mkdir()
        for name in ('01-SGF Player Offline Review.zip', '02-SGF Player OGS Review.zip'):
            with zipfile.ZipFile(self.archives / name, 'w') as archive:
                for p in self.resources.iterdir():
                    archive.writestr('Review.app/Contents/Resources/' + p.name, p.read_bytes())
        self.source = self.cache / 'com.davemarvit.SGFPlayerClean.ogs-review/AICache/v3-fixture.json'
        self.source.parent.mkdir(parents=True)
        self.source.write_text(json.dumps(dict(analyses={'0': {}}, fingerprints={'0': 'position'}, contextFingerprint='rules')))

    def tearDown(self):
        self.temp.cleanup()

    def run_import(self, apply=False):
        return prepare(self.app, self.cache, self.prefs, self.archives, self.exe, apply)

    def testDryRunAndImportPreserveSourcesAndProduceManifest(self):
        original = self.source.read_bytes()
        self.assertEqual(len(self.run_import()['sources'][1]['copiedFiles']), 1)
        destination = self.cache / 'SGFPlayerClean/AICache/ReviewImports/ogs-review'
        self.assertFalse(destination.exists())
        result = self.run_import(True)
        self.assertEqual(self.source.read_bytes(), original)
        self.assertEqual((destination / self.source.name).read_bytes(), original)
        manifest = json.loads((destination / 'manifest.json').read_text())
        self.assertEqual(manifest['engineIdentity'], result['engineIdentity'])
        self.assertIn(self.source.name, manifest['files'])

    def testCustomReviewConfigurationAndNewerEngineAreSkipped(self):
        (self.prefs / 'com.davemarvit.SGFPlayerClean.ogs-review.plist').write_bytes(plistlib.dumps({'customAIModelPath': '/another/model'}))
        self.assertIn('skippedReason', self.run_import()['sources'][1])
        for p in self.prefs.iterdir():
            p.unlink()
        os.utime(self.exe, (self.source.stat().st_mtime + 10,) * 2)
        result = self.run_import()['sources'][1]
        self.assertEqual(result['copiedFiles'], [])
        self.assertEqual(result['skippedFiles'], [self.source.name])

    def testMismatchedAssetsAndCustomMainSettingsFailClosed(self):
        (self.resources / 'analysis.cfg').write_bytes(b'different settings')
        with self.assertRaises(ValueError):
            self.run_import()
        (self.prefs / 'com.davemarvit.SGFPlayerClean.plist').write_bytes(plistlib.dumps({'customKataGoPath': '/another/engine'}))
        with self.assertRaises(ValueError):
            self.run_import()


if __name__ == '__main__':
    unittest.main()
