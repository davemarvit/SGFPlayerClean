import copy
import unittest

import numpy as np
from local_quality_lab import PROTOCOL, compete, geometry, quality


class LocalQualityTests(unittest.TestCase):
    def test_background_distinguishes_local_shadow_from_stone_core(self):
        size, scale, margin = 19, PROTOCOL['pixelsPerInterval'], PROTOCOL['margin']
        side = round((size - 1 + 2 * margin) * scale) + 1
        gray = np.full((side, side), .65, dtype=np.float32)
        valid = np.ones(gray.shape, dtype=bool)
        masks = geometry(gray.shape, size)
        y, x = np.mgrid[:side, :side]
        center = (9 + margin) * scale
        stone = gray.copy()
        stone[(x-center)**2 + (y-center)**2 < (.5*scale)**2] = .05
        q, _ = quality((stone, valid), (gray, valid), masks)
        self.assertEqual(q[180]['quality'], 1)
        shadow = gray.copy()
        shadow[(x-center)**2 + (y-center)**2 < (2*scale)**2] *= .65
        q, _ = quality((shadow, valid), (gray, valid), masks)
        self.assertLess(q[180]['quality'], .4)
        self.assertGreater(q[20]['quality'], .9)
        q, shift = quality((gray*.8, valid), (gray, valid), masks)
        self.assertAlmostEqual(q[180]['relativeDarkening'], 0, places=5)
        self.assertLess(shift, 0)

    def test_unknown_coverage_is_not_clean(self):
        a = np.full((505, 505), .5, dtype=np.float32)
        v = np.zeros(a.shape, dtype=bool)
        q, _ = quality((a, v), (a, np.ones(a.shape, dtype=bool)), geometry(a.shape, 19))
        self.assertIsNone(q[180]['quality'])

    def test_competition_retains_evidence_and_null(self):
        readings = [{'occupancy': 'empty', 'confidence': 1.} for _ in range(9)]
        estimates = [{'quality': 1.} for _ in readings]
        before = ['empty'] * 9
        empty = compete(readings, estimates, before, 'black', False, True)
        self.assertEqual(empty['noMoveOrUnknownShare'], 1)
        self.assertIsNone(empty['selected'])
        readings[2] = {'occupancy': 'black', 'confidence': .99}
        readings[5] = {'occupancy': 'black', 'confidence': .7}
        raw = copy.deepcopy(readings)
        result = compete(readings, estimates, before, 'black', False, True)
        self.assertEqual(result['selected'], 2)
        self.assertEqual(len(result['candidates']), 2)
        self.assertEqual(readings, raw)
        self.assertAlmostEqual(sum(c['share'] for c in result['candidates']) + result['noMoveOrUnknownShare'], 1)
        readings[5]['confidence'] = .99
        self.assertIsNone(compete(readings, estimates, before, 'black', False, True)['selected'])
        estimates[2]['quality'] = 0
        estimates[5]['quality'] = 0
        self.assertIsNone(compete(readings, estimates, before, 'black', False, True)['selected'])

    def test_hand_gap_capture_and_multiple_turns_cannot_be_overruled(self):
        readings = [{'occupancy': 'empty', 'confidence': 1.} for _ in range(9)]
        readings[2] = {'occupancy': 'black', 'confidence': 1.}
        estimates = [{'quality': 1.} for _ in readings]
        before = ['empty'] * 9
        for hand, continuous in [(True, True), (None, True), (False, False)]:
            self.assertIsNone(compete(readings, estimates, before, 'black', hand, continuous)['selected'])
        before[4] = 'white'  # Possible capture; preserve separate capture handling.
        self.assertIsNone(compete(readings, estimates, before, 'black', False, True)['selected'])
        before[4] = 'empty'
        readings[4] = {'occupancy': 'white', 'confidence': 1.}
        self.assertIsNone(compete(readings, estimates, before, 'black', False, True)['selected'])


if __name__ == '__main__':
    unittest.main()
