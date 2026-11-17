import copy
import unittest

from edge_probation_lab import probation
from placement_competition_lab import View
from prehand_lab import PreHandCompetition


def view(n, hand=False, point=18):
    raw = [dict(occupancy='empty', confidence=1.) for _ in range(361)]
    raw[point]['occupancy'] = 'black'
    appearance = [dict(signedCoreDelta=-.4, gain=1., coreError=.4, woodError=.01, woodPixels=100) for _ in raw]
    return View(n, n*.2, hand, False, raw, appearance, False, {'clockPress': 123.})


class ProbationTests(unittest.TestCase):
    def test_wait_does_not_rewrite_source_or_clock_metadata(self):
        model = PreHandCompetition(['empty']*361, 'black')
        results = []
        for n in range(1, 6):
            original = model.step(view(n))
            saved = copy.deepcopy(original)
            result = probation(original, set())
            self.assertEqual(original, saved)
            self.assertEqual(result['recordedFrameTiming'], {'clockPress': 123.})
            self.assertFalse(result['clockAuthority'])
            self.assertFalse(result['noMoveHasPositiveEvidence'])
            results.append(result)
        self.assertTrue(all(r['state'] == 'unknown' for r in results[:4]))
        self.assertEqual(results[4]['selected'], 18)
        self.assertEqual(results[4]['firstSupported']['capturedAt'], .2)
        self.assertEqual(results[4]['confirmedAt']['capturedAt'], 1.)

    def test_outline_does_not_need_extra_wait(self):
        model = PreHandCompetition(['empty']*361, 'black')
        model.step(view(1))
        result = model.step(view(2))
        self.assertEqual(probation(result, {18}), result)

    def test_later_hand_resets_pending_witnesses(self):
        model = PreHandCompetition(['empty']*361, 'black')
        for n in range(1, 8):
            result = probation(model.step(view(n, hand=n in (3, 4))), set())
            self.assertEqual(result['state'], 'unknown')

    def test_sustained_shadow_can_still_pass_without_hand_evidence(self):
        # Counterexample: this filter adds persistence, not proof of a stone.
        model = PreHandCompetition(['empty']*361, 'black')
        for n in range(1, 6):
            result = probation(model.step(view(n)), set())
        self.assertEqual(result['state'], 'placement')


if __name__ == '__main__':
    unittest.main()
