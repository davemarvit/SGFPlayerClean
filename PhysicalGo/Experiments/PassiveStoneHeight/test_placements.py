import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import placements as p


def fixture():
    frames = []
    for i, point in enumerate([[1, 1], [17, 1], [1, 9], [17, 9], [1, 17], [17, 17], [9, 3], [9, 15]]):
        for frame in range(3):
            frames.append({'setupID': 'setup-a', 'cameraEpoch': 'epoch-a',
                'calibrationSHA256': 'a'*64, 'stoneSetID': 'set-a', 'color': 'black',
                'estimatorVersion': 'body-v1', 'labelKind': 'acceptedTentative',
                'gameID': 'fixture-game', 'moveIndex': i, 'recordID': f'row-{i}-{frame}',
                'placementID': f'move-{i}', 'frameID': f'{i}-{frame}', 'sourceID': 'measurements',
                'point': point, 'offset': [.006*v + .02 for v in point],
                'split': 'train' if i < 6 else 'heldOut', 'quality': dict.fromkeys(p.QUALITY, True)})
    return {'schemaVersion': 1, 'units': 'gridCells', 'frames': frames,
            'sources': [{'id': 'measurements', 'path': 'measurements.json', 'sha256': 'a'*64}]}


class PlacementTests(unittest.TestCase):
    def test_exact_field_and_no_authority(self):
        r = p.evaluate(fixture(), hold_out_regions=True)
        self.assertEqual(r['placementCount'], 8)
        self.assertFalse(r['physicalThicknessIdentified'])
        self.assertFalse(r['changesRecognition'])
        self.assertFalse(r['grantsMotion'])
        g = r['groups'][0]
        self.assertAlmostEqual(g['diagnosticOpticalField']['k'], .006)
        self.assertTrue(all(v['fieldErrorCells'] < 1e-10 for v in g['evaluation']))

    def test_frames_are_not_independent_placements(self):
        d = fixture()
        original = p.evaluate(d)['groups'][0]['diagnosticOpticalField']
        for i in range(100):
            row = copy.deepcopy(d['frames'][0]); row['frameID'] = f'extra-{i}'
            d['frames'].append(row)
        r = p.evaluate(d)
        self.assertEqual(r['placementCount'], 8)
        self.assertEqual(original, r['groups'][0]['diagnosticOpticalField'])

    def test_split_leak_rejected_even_if_bad_quality(self):
        d = fixture(); d['frames'][0]['split'] = 'heldOut'; d['frames'][0]['quality'] = {}
        with self.assertRaisesRegex(ValueError, 'crosses split'):
            p.evaluate(d)

    def test_duplicate_frame_rejected(self):
        d = fixture(); d['frames'].append(copy.deepcopy(d['frames'][0]))
        with self.assertRaisesRegex(ValueError, 'Duplicate frame'):
            p.evaluate(d)

    def test_renamed_placement_cannot_leak_across_split(self):
        d = fixture()
        row = copy.deepcopy(d['frames'][0])
        row['placementID'] = 'renamed-copy'; row['split'] = 'heldOut'
        d['frames'].append(row)
        with self.assertRaisesRegex(ValueError, 'multiple placement IDs'):
            p.evaluate(d)

    def test_context_change_same_placement_rejected(self):
        d = fixture(); d['frames'][0]['cameraEpoch'] = 'epoch-b'
        with self.assertRaisesRegex(ValueError, 'crosses split'):
            p.evaluate(d)

    def test_unknown_clearance_and_numeric_truth_rejected(self):
        d = fixture(); d['frames'][0]['quality'].pop('handClear'); d['frames'][1]['quality']['laserDark'] = 1
        r = p.evaluate(d)
        self.assertEqual(len(r['rejectedFrames']), 2)
        self.assertEqual(r['placements'][0]['frameCount'], 1)

    def test_nonfinite_missing_pending_provenance(self):
        for key, value in [('offset', [float('nan'), 0]), ('labelKind', 'pendingAI'), ('sourceID', 'absent'), ('calibrationSHA256', 'bad')]:
            d = fixture(); d['frames'][0][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                p.evaluate(d)

    def test_controls_and_heldout_never_train(self):
        d = fixture(); original = p.evaluate(d)['groups'][0]['diagnosticOpticalField']
        for row in d['frames']:
            if row['split'] == 'heldOut':
                row['offset'] = [8, -8]
                if row['placementID'] == 'move-7':
                    row['split'] = 'misplacedControl'
        result = p.evaluate(d)['groups'][0]
        self.assertEqual(original, result['diagnosticOpticalField'])
        self.assertTrue(all(e['fieldErrorCells'] > 10 for e in result['evaluation']))
        self.assertEqual({e['split'] for e in result['evaluation']}, {'heldOut', 'misplacedControl'})

    def test_color_and_label_regimes_not_pooled(self):
        d = fixture()
        for row in d['frames']:
            if row['placementID'] in ('move-4', 'move-5'):
                row['color'] = 'white'; row['labelKind'] = 'explicitlyCentered'
        groups = p.evaluate(d)['groups']
        self.assertEqual(len(groups), 2)
        self.assertTrue(all('abstention' in g for g in groups))

    def test_coincident_collinear_and_narrow_abstain(self):
        self.assertEqual(p.support([[9, 9]]*20), 'narrowSpatialSupport')
        self.assertEqual(p.support([[i, i] for i in range(10)]), 'nearlyCollinearSupport')
        self.assertEqual(p.support([[1, 1], [17, 17]]), 'fewerThanSixIndependentPlacements')

    def test_region_leak_rejected(self):
        d = fixture()
        for row in d['frames']:
            if row['placementID'] == 'move-6': row['point'] = [2, 2]
        with self.assertRaisesRegex(ValueError, 'regions overlap'):
            p.evaluate(d, hold_out_regions=True)

    def test_bounded_input(self):
        d = fixture(); d['frames'] = [{}]*(p.MAX_FRAMES+1)
        with self.assertRaisesRegex(ValueError, '10000'):
            p.evaluate(d)

    def test_cli_hashes_and_exclusive_output(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); source = root/'measurements.json'; source.write_text('{"fixture":true}')
            d = fixture(); d['sources'][0]['sha256'] = hashlib.sha256(source.read_bytes()).hexdigest()
            manifest = root/'manifest.json'; manifest.write_text(json.dumps(d)); out = root/'report.json'
            cmd = [sys.executable, str(Path(p.__file__)), str(manifest), str(out), '--hold-out-regions']
            first = subprocess.run(cmd, capture_output=True, text=True)
            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertEqual(json.loads(out.read_text())['manifest']['sha256'], hashlib.sha256(manifest.read_bytes()).hexdigest())
            self.assertNotEqual(subprocess.run(cmd, capture_output=True).returncode, 0)
            source.write_text('{"changed":true}')
            cmd[3] = str(root/'other.json')
            changed = subprocess.run(cmd, capture_output=True, text=True)
            self.assertNotEqual(changed.returncode, 0)
            self.assertIn('hash mismatch', changed.stderr)
            self.assertFalse((root/'other.json').exists())


if __name__ == '__main__':
    unittest.main()
