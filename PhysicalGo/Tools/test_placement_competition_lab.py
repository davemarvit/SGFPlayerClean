import copy
import unittest

import numpy as np

from evaluate_placement_competition import snapshot_truth
from placement_competition_lab import PlacementCompetition, View, appearance_features
from unchanged_baseline_lab import Observation, features


class PlacementCompetitionTests(unittest.TestCase):
    def view(self, frame, candidates=(), time=None, hand=False, gap=False):
        readings = [{'occupancy': 'empty', 'confidence': 1.} for _ in range(9)]
        appearance = [{'gain': 1., 'coreError': 0., 'woodError': 0., 'signedCoreDelta': 0.} for _ in readings]
        for point, color, confidence, delta in candidates:
            readings[point] = {'occupancy': color, 'confidence': confidence}
            appearance[point] = {'gain': 1., 'coreError': abs(delta) if delta is not None else None,
                                 'woodError': .01, 'signedCoreDelta': delta}
        return View(frame, frame*.2 if time is None else time, hand, False, readings, appearance, gap,
                    {'time': 123., 'method': 'unassigned-test-frame-metadata'})

    def model(self, method='appearance_competition', before=None):
        return PlacementCompetition(before or ['empty']*9, 'black', method)

    def test_strong_location_inhibits_weak_alternative_without_deleting_it(self):
        model = self.model()
        candidates = [(2, 'black', 1., -.3), (5, 'black', .8, -.04)]
        first = self.view(1, candidates)
        original = copy.deepcopy(first)
        self.assertEqual(model.step(first)['state'], 'unknown')
        result = model.step(self.view(2, candidates))
        self.assertEqual(result['selected'], 2)
        self.assertEqual(len(result['candidates']), 2)
        self.assertAlmostEqual(result['noMoveShare']+sum(c['share'] for c in result['candidates']), 1.)
        self.assertEqual(first, original)
        self.assertEqual(len(model.histories[(5, 'black')].evidence), 2)

    def test_equal_candidates_and_weak_only_candidate_do_not_force_winner(self):
        for candidates in ([(2, 'black', 1., -.3), (5, 'black', 1., -.3)],
                           [(2, 'black', 1., -.03)]):
            model = self.model()
            for frame in range(1, 6):
                self.assertEqual(model.step(self.view(frame, candidates))['state'], 'unknown')

    def test_raw_control_accepts_shadow_but_appearance_control_does_not(self):
        results = {}
        for method in ('raw_competition', 'appearance_independent', 'appearance_competition'):
            model = self.model(method)
            for frame in (1, 2):
                results[method] = model.step(self.view(frame, [(2, 'black', 1., -.03)]))
        self.assertEqual(results['raw_competition']['selected'], 2)
        self.assertEqual(results['appearance_competition']['state'], 'unknown')
        self.assertEqual(results['appearance_independent']['state'], 'unknown')

    def test_competition_ablation_exposes_crowding_instead_of_hiding_it(self):
        candidates = [(2, 'black', 1., -.3), (5, 'black', 1., -.06)]
        independent, competitive = self.model('appearance_independent'), self.model()
        for frame in (1, 2):
            a, b = independent.step(self.view(frame, candidates)), competitive.step(self.view(frame, candidates))
        self.assertEqual(a['selected'], 2)
        self.assertEqual(b['state'], 'unknown')

    def test_color_specific_shadow_control_preserves_low_contrast_white_evidence(self):
        for color, delta, expected in (('white', .03, 'placement'), ('black', -.03, 'unknown')):
            models = [PlacementCompetition(['empty']*9, color, method)
                      for method in ('black_shadow_independent', 'black_shadow_competition')]
            for model in models:
                for frame in (1, 2):
                    result = model.step(self.view(frame, [(2, color, 1., delta)]))
                self.assertEqual(result['state'], expected)

    def test_no_move_requires_positive_full_board_evidence(self):
        model = self.model()
        self.assertEqual(model.step(self.view(1))['state'], 'unknown')
        self.assertEqual(model.step(self.view(2))['state'], 'no_move')
        for frame in (3, 4):
            missing = self.view(frame)
            missing.appearance[4]['signedCoreDelta'] = None
            self.assertEqual(model.step(missing)['state'], 'unknown')

    def test_missing_appearance_is_neutral_not_zero_or_empty(self):
        model = self.model()
        result = model.step(self.view(1, [(2, 'black', 1., None)]))
        candidate = result['candidates'][0]
        self.assertTrue(candidate['appearanceUnknown'])
        self.assertEqual(candidate['weight'], candidate['rawSupport'])
        self.assertFalse(result['noMoveHasPositiveEvidence'])

    def test_candidate_times_are_separate_and_survive_later_hand(self):
        model = self.model()
        model.step(self.view(1, [(5, 'black', 1., -.03)]))
        model.step(self.view(2, [(2, 'black', 1., -.3)]))
        result = model.step(self.view(3, [(2, 'black', 1., -.3)]))
        self.assertEqual(result['firstSeen']['frame'], 2)
        self.assertEqual(result['firstSupported']['frame'], 2)
        self.assertEqual(result['confirmedAt']['frame'], 3)
        self.assertEqual([w['frame'] for w in result['witnesses']], [2, 3])
        original = copy.deepcopy(model.histories[(2, 'black')].evidence)
        blocked = model.step(self.view(4, hand=True))
        self.assertEqual(blocked['state'], 'unknown')
        self.assertEqual(model.histories[(2, 'black')].evidence, original)
        self.assertFalse(result['clockAuthority'])
        self.assertEqual(result['recordedFrameTiming']['time'], 123.)

    def test_hand_unknown_exposure_capture_and_opposite_color_force_unknown(self):
        for fault in ('hand', 'unknown', 'exposure', 'capture', 'opposite'):
            before = ['empty']*9
            if fault == 'capture':
                before[4] = 'white'
            model = self.model(before=before)
            for frame in (1, 2, 3):
                v = self.view(frame, [(2, 'black', 1., -.3)], hand=True if fault == 'hand' else None if fault == 'unknown' else False)
                if fault == 'exposure':
                    v = View(v.frame, v.time, v.hand, True, v.raw, v.appearance)
                if fault == 'opposite':
                    v.raw[5] = {'occupancy': 'white', 'confidence': 1.}
                result = model.step(v)
                self.assertEqual(result['state'], 'unknown')
                self.assertTrue(result['reasons'])

    def test_reappearing_candidate_cannot_inherit_earlier_supported_timestamp(self):
        for interruption in ('empty', 'weak', 'hand'):
            model = self.model('black_shadow_competition')
            model.step(self.view(1, [(2, 'black', 1., -.3)]))
            interrupted = self.view(2, [(2, 'black', .6, -.3)] if interruption == 'weak' else (),
                                    hand=interruption == 'hand')
            model.step(interrupted)
            model.step(self.view(3, [(2, 'black', 1., -.3)]))
            result = model.step(self.view(4, [(2, 'black', 1., -.3)]))
            self.assertEqual(result['selected'], 2)
            self.assertEqual(result['firstSeen']['frame'], 1)
            self.assertEqual(result['firstSupported']['frame'], 3)
            self.assertEqual(result['candidates'][0]['firstSupportedEver']['frame'], 1)
            self.assertEqual([w['frame'] for w in result['witnesses']], [3, 4])

    def test_gap_latches_review_without_compressing_time_or_deleting_evidence(self):
        model = self.model()
        model.step(self.view(1, [(2, 'black', 1., -.3)]))
        for frame, time in ((2, 2.), (3, 2.2), (4, 2.4)):
            result = model.step(self.view(frame, [(2, 'black', 1., -.3)], time=time))
            self.assertEqual(result['state'], 'unknown')
        self.assertEqual(model.histories[(2, 'black')].first_seen['capturedAt'], .2)
        self.assertEqual(model.histories[(2, 'black')].evidence[-1]['capturedAt'], 2.4)
        with self.assertRaises(ValueError):
            model.step(self.view(5, time=2.4))
        # A gap preceding the first supplied view must not disappear at slicing.
        fresh = self.model()
        self.assertEqual(fresh.step(self.view(1, gap=True))['state'], 'unknown')
        self.assertTrue(fresh.gap_review)

    def test_contradiction_delays_confirmation_without_reassigning_first_support(self):
        model = self.model()
        for frame in (1, 2):
            result = model.step(self.view(frame, [(2, 'black', 1., -.3), (5, 'white', 1., .03)]))
            self.assertEqual(result['state'], 'unknown')
        result = model.step(self.view(3, [(2, 'black', 1., -.3)]))
        self.assertEqual(result['selected'], 2)
        self.assertEqual(result['firstSupported']['frame'], 1)
        self.assertEqual(result['confirmedAt']['frame'], 3)

    def test_local_wood_gain_removes_shared_darkening_but_preserves_stone_change(self):
        reference = [np.full(32, .6)]
        old_wood = [np.full(24, .6)]
        for level, expected in ((.42, 0.), (.1, -.32)):
            core, wood = [np.full(32, level)], [np.full(24, .42)]
            observation = Observation(1, .2, False, False, [], core, features(core, wood, reference, old_wood))
            appearance = appearance_features(observation, reference)
            self.assertAlmostEqual(appearance[0]['signedCoreDelta'], expected)

    def test_multimove_or_capture_truth_is_not_scored_as_single_placement(self):
        before = ['empty']*9
        self.assertEqual(snapshot_truth(before, 'black', before), ('no_move', None))
        truth = list(before)
        truth[2] = 'black'
        self.assertEqual(snapshot_truth(before, 'black', truth), ('placement', 2))
        truth[4] = 'white'
        self.assertIsNone(snapshot_truth(before, 'black', truth))
        before[8] = 'white'
        self.assertIsNone(snapshot_truth(before, 'black', truth))


if __name__ == '__main__':
    unittest.main()
