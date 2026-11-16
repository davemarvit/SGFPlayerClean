import copy
import json
from pathlib import Path
import unittest

import numpy as np

from recognition_parameter_search import (Case, candidates, evaluate, incumbent,
                                          input_signature, rank, refinement,
                                          validate_space)
from unchanged_baseline_lab import (Baseline, Observation, PROTOCOL, TUNABLE,
                                    batch_residuals, features, parameters, residual)


class ParameterSearchTests(unittest.TestCase):
    def setUp(self):
        self.space = json.loads(Path(__file__).with_name('recognition_parameter_space.json').read_text())

    def observation(self, frame, level=.6, gain=1., hand=False, reading='empty', time=None):
        core, wood = [np.full(32, level)], [np.full(24, .6*gain)]
        return Observation(frame, frame*.2 if time is None else time, hand, False,
                           [{'occupancy': reading, 'confidence': 1.}], core,
                           features(core, wood, [np.full(32, .6)], [np.full(24, .6)]))

    def test_fixed_safeguards_and_configuration_isolation(self):
        for key in set(PROTOCOL)-set(TUNABLE):
            with self.assertRaises(ValueError):
                parameters({key: PROTOCOL[key]})
        for overrides in ({'coreError': float('nan')}, {'emptyWitnesses': 1},
                          {'learningFrames': 2.5}, {'emptySeconds': 0}, {'minimumGain': 1.1}):
            with self.assertRaises(ValueError):
                parameters(overrides)
        overrides = {'coreError': .03}
        model = Baseline('guarded_adaptive', self.observation(0), ['empty'], overrides)
        overrides['coreError'] = .9
        self.assertEqual(model.config['coreError'], .03)
        self.assertEqual(PROTOCOL['coreError'], .045)
        with self.assertRaises(TypeError):
            model.config['coreError'] = .9

    def test_batched_residual_matches_scalar_with_missing_pixels_and_shapes(self):
        rng = np.random.default_rng(45)
        a, b = [rng.random(32).astype(np.float32) for _ in range(4)], [rng.random(32).astype(np.float32) for _ in range(4)]
        a[1][0] = np.nan  # Coverage sufficient.
        a[2][:4] = np.nan  # Coverage insufficient.
        a[3][:] = np.nan
        np.testing.assert_array_equal(batch_residuals(a, b), [residual(x, y) for x, y in zip(a, b)])
        a[0], b[0] = a[0][:24], b[0][:24]
        np.testing.assert_array_equal(batch_residuals(a, b), [residual(x, y) for x, y in zip(a, b)])

    def test_every_search_candidate_keeps_hand_gap_and_capture_guards(self):
        for _, config in candidates(self.space):
            for hand in (True, None):
                model = Baseline('guarded_adaptive', self.observation(0), ['empty'], config, batch=True)
                for f in range(1, 15):
                    result = model.step(self.observation(f, hand=hand))
                    self.assertTrue(result['blocked'])
                    self.assertFalse(result['emptySupport'])
                    self.assertFalse(result['updates'])
            model = Baseline('guarded_adaptive', self.observation(0), ['empty'], config)
            self.assertTrue(model.step(self.observation(1, time=2.))['blocked'])
            model = Baseline('guarded_adaptive', self.observation(0, reading='black'), ['black'], config)
            self.assertTrue(model.step(self.observation(1, reading='empty'))['blocked'])

    def test_evaluation_rejects_absorbing_stones_even_if_raw_already_missed(self):
        observations = [self.observation(0)] + [self.observation(f, level=.12) for f in range(1, 26)]
        case = Case('missed-hand', 'synthetic-photo-hold', observations, ['empty'], {f: ['black'] for f in range(1, 26)})
        original = input_signature([case])
        safe = evaluate(incumbent(), [case])
        unsafe = evaluate(incumbent(), [case], method='no_hand_only')
        self.assertTrue(safe['safe'])
        self.assertFalse(unsafe['safe'])
        self.assertEqual(unsafe['totals']['realStoneEmptySupport'], 1)
        self.assertEqual(original, input_signature([case]))

    def test_late_hand_rolls_back_all_candidate_adaptations_without_erasing_evidence(self):
        # Test the most permissive endpoint for each learning dimension as well
        # as the incumbent; a late signal must still revoke young adaptations.
        for config in (incumbent(), {**incumbent(), 'learningFrames': 3, 'learningSeconds': .4,
                                     'emptyWitnesses': 2, 'emptySeconds': .2}):
            model = Baseline('guarded_adaptive', self.observation(0), ['empty'], config, batch=True)
            for f in range(1, 30):
                observation = self.observation(f, level=.48, gain=.8)
                result = model.step(observation)
                if result['updates']:
                    break
            else:
                self.fail('Expected a lighting adaptation')
            original = observation.core[0].copy()
            result = model.step(self.observation(f+1, hand=True))
            self.assertEqual(result['updates'][0]['type'], 'rollback')
            np.testing.assert_array_equal(observation.core[0], original)
            np.testing.assert_allclose(model.anchor[0], .6)

    def test_reproducible_search_and_incumbent_wins_ties(self):
        validate_space(self.space)
        self.assertEqual(list(candidates(self.space)), list(candidates(self.space)))
        totals = dict(realStoneEmptySupport=0, blockedFrameOutput=0, timingAnchorLoss=0,
                      phantomPointCases=2, uncertainPointFrames=10)
        base = {'id': 0, 'parameters': incumbent(), 'training': {'safe': True, 'totals': totals}}
        changed = copy.deepcopy(base)
        changed['id'] = 1
        changed['parameters']['coreError'] = .06
        # Even an attractive validation score cannot enter the training rank.
        changed['validation'] = {'perfect': True}
        self.assertLess(rank(base, self.space), rank(changed, self.space))
        self.assertEqual(refinement(incumbent(), self.space, [base]), refinement(incumbent(), self.space, [base]))
        bad = copy.deepcopy(base)
        bad['training']['safe'] = False
        bad['training']['totals'].update(realStoneEmptySupport=1, phantomPointCases=0, uncertainPointFrames=0)
        self.assertLess(rank(base, self.space), rank(bad, self.space))

    def test_split_rejects_leaking_groups_and_missing_axes(self):
        bad = copy.deepcopy(self.space)
        bad['validationPhotoGroups'].append('club')
        with self.assertRaises(ValueError):
            validate_space(bad)
        bad = copy.deepcopy(self.space)
        del bad['parameters']['coreError']
        with self.assertRaises(ValueError):
            validate_space(bad)


if __name__ == '__main__':
    unittest.main()
