import fcntl
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('trim', Path(__file__).parents[1]/'Tools/trim_recording_tail.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class TailTrimmingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root/'frames').mkdir()
        (self.root/'assets').mkdir()
        (self.root/'assets/reference.png').write_bytes(b'reference')
        (self.root/'KEEP').touch()
        self.manifest = dict(schemaVersion=1, status='complete', framesSaved=10)
        (self.root/'session.json').write_text(json.dumps(self.manifest))
        self.rows = []
        for i in range(1, 11):
            image = f'frames/{i:06}.png'
            (self.root/image).write_bytes(bytes([i])*100)
            self.rows.append(dict(event='frame', frameID=i, captureUptime=i*10, image=image))
        self.rows.insert(4, dict(event='clock press', frameID=4, press={'time':40, 'move':1}))
        (self.root/'events.jsonl').write_text(''.join(json.dumps(row)+'\n' for row in self.rows))

    def test_reviewed_tail_keeps_postroll_final_image_and_all_timing(self):
        original = (self.root/'events.jsonl').read_bytes()
        plan = module.trim(self.root, 3)
        self.assertEqual(plan['images'], [f'frames/{i:06}.png' for i in [7, 8, 9]])
        self.assertEqual(len(list((self.root/'frames').iterdir())), 10)
        result = module.trim(self.root, 3, apply=True)
        self.assertTrue(result['applied'])
        self.assertEqual((Path(result['audit'])/'events-before.jsonl').read_bytes(), original)
        rows = [json.loads(line) for line in (self.root/'events.jsonl').read_text().splitlines()]
        self.assertEqual(next(row for row in rows if row['event']=='clock press'), self.rows[4])
        self.assertTrue((self.root/'assets/reference.png').is_file())
        self.assertTrue((self.root/'KEEP').is_file())
        self.assertEqual([row['frameID'] for row in rows if row['event']=='frame'], [1,2,3,4,5,6,10])
        self.assertEqual([row['captureUptime'] for row in rows if row['event']=='image trimmed'], [70,80,90])
        self.assertEqual(module.trim(self.root, 3, apply=True)['images'], [])

    def test_active_writer_is_untouched(self):
        with (self.root/'.writer.lock').open('w') as lease:
            fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaises(BlockingIOError):
                module.trim(self.root, 3, apply=True)
        self.assertEqual(len(list((self.root/'frames').iterdir())), 10)

    def test_incomplete_recording_and_short_postroll_rejected(self):
        self.manifest['status']='recording'
        (self.root/'session.json').write_text(json.dumps(self.manifest))
        with self.assertRaises(ValueError): module.trim(self.root, 3, apply=True)
        with self.assertRaises(ValueError): module.trim(self.root, 3, 1, apply=True)

    def test_linked_image_is_untouched(self):
        (self.root/'frames/000008.png').unlink()
        (self.root/'frames/000008.png').symlink_to(self.root/'assets/reference.png')
        with self.assertRaises(ValueError): module.trim(self.root, 3, apply=True)
        self.assertEqual((self.root/'assets/reference.png').read_bytes(), b'reference')
        self.assertTrue((self.root/'frames/000007.png').is_file())


if __name__ == '__main__': unittest.main()
