"""Bounded geometry and information-loss controls, no native runtime claims."""
import unittest
import cv2
import numpy as np
from probe import analyze, project, PITCH, MARGIN, SIDE

class ProbeTests(unittest.TestCase):
    def setUp(self):
        self.h = np.array([[PITCH, 0, MARGIN], [0, PITCH, MARGIN], [0, 0, 1]], float)
        self.board = np.full((SIDE, SIDE, 3), (150, 185, 210), np.uint8)
        for i in range(19):
            p = MARGIN + i * PITCH
            cv2.line(self.board, (MARGIN, p), (SIDE-MARGIN-1, p), (70, 80, 90), 2)
            cv2.line(self.board, (p, MARGIN), (p, SIDE-MARGIN-1), (70, 80, 90), 2)

    def check_supported(self, image):
        result, _, _ = analyze(image, self.h)
        self.assertTrue(result['geometrySupported'])
        self.assertLess(result['maxPriorDisplacementGridUnits'], .06)
        self.assertTrue(all(c['stoneState'] == 'unknown' and c['freshClearance'] is False for c in result['intersections']))
        return result

    def test_clean(self):
        self.check_supported(self.board)

    def test_partial_clipped_glare(self):
        self.board[260:500, 260:500] = 255
        result = self.check_supported(self.board)
        self.assertGreater(result['intersections'][9*19+9]['clippedFraction'], .99)
        self.assertEqual(result['intersections'][9*19+9]['nearbyRailProbeCounts'], [0, 0])

    def test_unsaturated_flat_occlusion(self):
        self.board[260:500, 260:500] = (110, 145, 175)
        result = self.check_supported(self.board)
        self.assertEqual(result['intersections'][9*19+9]['clippedFraction'], 0)
        self.assertEqual(result['intersections'][9*19+9]['nearbyRailProbeCounts'], [0, 0])

    def test_black_white_stones(self):
        for row in [3, 6, 9, 12, 15]:
            for col in [3, 6, 9, 12, 15]:
                value = 245 if (row+col) % 2 else 20
                cv2.circle(self.board, (MARGIN+col*PITCH, MARGIN+row*PITCH), 17, (value,)*3, -1)
        self.check_supported(self.board)

    def test_hidden_states_indistinguishable(self):
        images = []
        for value in [20, 245, None]:
            image = self.board.copy()
            if value is not None:
                cv2.circle(image, (380,380), 17, (value,)*3, -1)
            # Complete clipping destroys the underlying state, by construction.
            image[345:415,345:415] = 255
            images.append(image)
        self.assertTrue(np.array_equal(images[0],images[1]) and np.array_equal(images[1],images[2]))
        for image in images:
            self.check_supported(image)

    def test_blank_rejected(self):
        self.assertFalse(analyze(np.full_like(self.board, 220), self.h)[0]['geometrySupported'])

    def test_half_board_covered_rejected(self):
        self.board[:, SIDE//2:] = 180
        self.assertFalse(analyze(self.board, self.h)[0]['geometrySupported'])

    def test_moved_beyond_local_search_rejected(self):
        shifted = cv2.warpAffine(self.board, np.array([[1.,0.,14.],[0.,1.,14.]]), (SIDE,SIDE), borderValue=(180,)*3)
        self.assertFalse(analyze(shifted, self.h)[0]['geometrySupported'])

    def test_small_motion_measured(self):
        shifted = cv2.warpAffine(self.board, np.array([[1.,0.,3.],[0.,1.,2.]]), (SIDE,SIDE), borderValue=(180,)*3)
        result = analyze(shifted, self.h)[0]
        self.assertTrue(result['geometrySupported'])
        fitted = np.asarray(result['diagnosticBoardToImage'])
        actual = project(fitted, [[9,9]])[0] - project(self.h, [[9,9]])[0]
        self.assertLess(np.linalg.norm(actual - [3,2]), 1.5)

if __name__ == '__main__':
    unittest.main()
