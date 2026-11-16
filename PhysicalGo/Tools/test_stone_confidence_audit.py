import unittest
import json
from pathlib import Path
import tempfile

import numpy as np

from fresh_game_confidence import ordered_readings, positions
from stone_confidence_audit import fit, fresh_rows, metrics, predict, row, weights


class ConfidenceAuditTests(unittest.TestCase):
    def example(self, correct, strength=1., session='older-example', point=0):
        appearance = {'signedCoreDelta': -.2*strength if strength is not None else None}
        return row(session, point, point, {'occupancy': 'black', 'confidence': 1.},
                   appearance, 'black' if correct else 'empty', 'test')

    def test_correlated_missing_appearance_is_not_second_vote(self):
        r = self.example(False, None)
        self.assertFalse(r['appearanceAvailable'])
        self.assertIsNone(r['appearanceStrength'])
        self.assertEqual(r['rawSupport'], r['shadowSupport'])

    def test_no_fresh_labels_in_fit(self):
        with self.assertRaises(ValueError):
            fit([self.example(True), self.example(False, session='fresh-game')])

    def test_single_class_cannot_calibrate(self):
        with self.assertRaises(ValueError):
            fit([self.example(True)])

    def test_labels_must_be_reviewed_and_bound_to_capture(self):
        with tempfile.TemporaryDirectory() as folder:
            p = Path(folder)
            labels = p/'labels.json'
            labels.write_text(json.dumps({'status': 'unreviewed'}))
            with self.assertRaisesRegex(ValueError, 'Explicit image review'):
                fresh_rows(p, labels)
            labels.write_text(json.dumps({'status': 'image-reviewed-point-labels', 'sourceEventsSHA256': 'a'}))
            (p/'manifest.json').write_text(json.dumps({'inputs': [{'path': '/capture/events.jsonl', 'sha256': 'b'}]}))
            with self.assertRaisesRegex(ValueError, 'different source'):
                fresh_rows(p, labels)

    def test_joint_features_can_learn_useful_disagreement(self):
        rows = [self.example(True, point=i) for i in range(20)]
        rows += [self.example(False, 0., point=20+i) for i in range(20)]
        simple, joint = fit(rows), fit(rows, True)
        self.assertTrue(joint['converged'])
        a, b = predict(simple, rows), predict(joint, rows)
        self.assertLess(metrics(rows, b)['brier'], metrics(rows, a)['brier'])
        self.assertGreater(float(b[0]), float(b[-1]))

    def test_episode_duplicates_do_not_gain_weight(self):
        a, b = self.example(True), self.example(False, point=1)
        np.testing.assert_allclose(weights([a, a, b]), [.5, .5, 1.])
        score = metrics([a, a, b], [1., 1., 1.])
        self.assertEqual(score['brier'], .5)
        self.assertTrue(np.isfinite(score['logLossClippedAt1eMinus6']))

    def test_supplied_history_removes_captured_group(self):
        states, captures = positions([('white', 4), ('black', 1), ('black', 3),
                                      ('black', 5), ('black', 7)], size=3)
        self.assertEqual(states[-2][4], 'white')
        self.assertEqual(states[-1][4], 'empty')
        self.assertEqual(captures, [{'move': 5, 'points': [4]}])

    def test_supplied_history_rejects_overwrite(self):
        with self.assertRaises(ValueError):
            positions([('white', 4), ('black', 4)], size=3)

    def test_readings_are_indexed_by_coordinates(self):
        readings = [{'row': i//2, 'col': i % 2} for i in range(4)]
        self.assertEqual(ordered_readings(list(reversed(readings)), 2), readings)
        with self.assertRaises(ValueError):
            ordered_readings(readings[:-1], 2)
        with self.assertRaises(ValueError):
            ordered_readings(readings+[readings[0]], 2)


if __name__ == '__main__':
    unittest.main()
