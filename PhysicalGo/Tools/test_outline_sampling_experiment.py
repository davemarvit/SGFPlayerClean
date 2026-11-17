import unittest

import numpy as np

from outline_sampling_experiment import eligible, geometry
from unchanged_baseline_lab import Sampler, features


class OutlineSamplingTests(unittest.TestCase):
    def test_off_center_stone_is_not_background(self):
        shape = {'row': 1, 'col': 4, 'center': {'x': 4.12, 'y': .72},
                 'radiusCol': .46, 'radiusRow': .4876, 'quality': .99}
        x, y, excluded = geometry((505, 505), eligible([shape]))
        reference = np.full((505, 505), .65)
        current = reference.copy()
        stone = ((x-4.12)/.46)**2+((y-.72)/.4876)**2 <= 1
        current[stone] = .08
        sampler = Sampler(current.shape)
        core, wood = sampler.core[23], sampler.wood[23]
        masked = wood[~excluded[wood]]
        self.assertGreater(len(wood)-len(masked), 0)
        self.assertGreaterEqual(len(masked), 12)
        self.assertTrue(np.any(stone.ravel()[wood]))
        self.assertFalse(np.any(stone.ravel()[masked]))
        result = features([current.ravel()[core]], [current.ravel()[masked]],
                          [reference.ravel()[core]], [reference.ravel()[masked]])[0]
        self.assertAlmostEqual(result['woodError'], 0)
        self.assertGreater(result['coreError'], .4)

    def test_absent_or_invalid_outlines_do_not_mask_evidence(self):
        shape = {'row': 1, 'col': 4, 'center': {'x': 4., 'y': 1.},
                 'radiusCol': .46, 'radiusRow': .48, 'quality': .99}
        for key, value in [('quality', .7), ('quality', float('nan')), ('radiusCol', 0), ('radiusRow', float('inf'))]:
            self.assertEqual(eligible([{**shape, key: value}]), [])
        self.assertEqual(eligible([{**shape, 'center': {'x': 5., 'y': 1.}}]), [])
        self.assertFalse(geometry((505, 505), [])[2].any())

    def test_missing_background_stays_unavailable(self):
        result = features([np.array([.1])], [np.array([])], [np.array([.6])], [np.array([])])[0]
        self.assertIsNone(result['gain'])
        self.assertIsNone(result['woodError'])
        self.assertEqual(result['woodPixels'], 0)


if __name__ == '__main__':
    unittest.main()
