import unittest

import numpy as np

from unchanged_baseline_lab import Baseline, Observation, features, scenarios, PROTOCOL


class UnchangedBaselineTests(unittest.TestCase):
    def observation(self, frame, time, level=.6, gain=1., hand=False, reading='empty'):
        core = [np.full(32, level)]
        wood = [np.full(24, .6*gain)]
        return Observation(frame, time, hand, False, [{'occupancy': reading, 'confidence': 1.}], core,
                           features(core, wood, [np.full(32, .6)], [np.full(24, .6)]))

    def test_missed_hand_real_stone_is_not_learned_as_empty(self):
        seed = self.observation(0, 0)
        guarded, naive = [Baseline(method, seed, ['empty']) for method in ('guarded_adaptive', 'no_hand_only')]
        naive_absorbed = False
        for frame in range(1, 50):
            # Hidden hand; persistent dark stone and independently dark core.
            o = self.observation(frame, frame*.2, level=.12, hand=False, reading='black')
            result = guarded.step(o)
            self.assertEqual(result['emptySupport'], [])
            self.assertEqual(result['updates'], [])
            naive_absorbed |= bool(naive.step(o)['emptySupport'])
        self.assertTrue(naive_absorbed, 'Failure control must expose the no-hand-only assumption')
        self.assertEqual(guarded.expected, ('empty',))

    def test_no_interaction_control_remembers_hand_entry_or_gap(self):
        for hand, at in [(True, .2), (None, .2), (False, 2.)]:
            model = Baseline('no_interaction_since_seed', self.observation(0, 0), ['empty'])
            model.step(self.observation(1, at, hand=hand))
            for frame in range(2, 20):
                result = model.step(self.observation(frame, at+(frame-1)*.2))
                self.assertTrue(result['blocked'])
                self.assertFalse(result['updates'])
                self.assertFalse(result['emptySupport'])
        model = Baseline('no_interaction_since_seed', self.observation(0, 0), ['empty'])
        absorbed = False
        for frame in range(1, 40):
            # A completely missed hand, continuous frames, and stable real stone
            # expose the remaining blind spot of absence-of-hand evidence alone.
            result = model.step(self.observation(frame, frame*.2, level=.12, reading='black'))
            absorbed |= bool(result['emptySupport'])
        self.assertTrue(absorbed)

    def test_lighting_adapts_without_learning_core_texture(self):
        model = Baseline('guarded_adaptive', self.observation(0, 0), ['empty'])
        gained_support = False
        for frame in range(1, 31):
            result = model.step(self.observation(frame, frame*.2, level=.48, gain=.8, reading='uncertain'))
            gained_support |= bool(result['emptySupport'])
        self.assertTrue(gained_support)
        self.assertGreater(len(model.versions[0]), 1)
        np.testing.assert_allclose(model.anchor[0], .6)
        np.testing.assert_allclose(model.versions[0][-1]['core'], .48)
        self.assertTrue(all(p['at'] <= 6. for p in model.versions[0]))

    def test_unknown_hand_and_camera_gap_do_not_supply_continuity(self):
        for hand in (None, True):
            model = Baseline('guarded_adaptive', self.observation(0, 0), ['empty'])
            for frame in range(1, 20):
                result = model.step(self.observation(frame, frame*.2, hand=hand))
                self.assertTrue(result['blocked'])
                self.assertFalse(result['updates'])
                self.assertFalse(result['emptySupport'])
        model = Baseline('guarded_adaptive', self.observation(0, 0), ['empty'])
        for frame in range(1, 5):
            model.step(self.observation(frame, frame*.2))
        result = model.step(self.observation(99, 3., reading='black', level=.12))
        self.assertTrue(result['blocked'])
        self.assertIn('camera gap', result['reasons'])
        self.assertFalse(result['emptySupport'])
        self.assertEqual(len(model.versions[0]), 1)

    def test_late_hand_retracts_update_but_keeps_original_evidence(self):
        model = Baseline('guarded_adaptive', self.observation(0, 0), ['empty'])
        frame = 0
        while len(model.versions[0]) == 1:
            frame += 1
            self.assertLess(frame, 20)
            model.step(self.observation(frame, frame*.2, level=.48, gain=.8))
        activated = model.versions[0][-1]
        self.assertTrue(all(activated['frame'] > f for f in activated['witnesses']))
        result = model.step(self.observation(frame+1, (frame+1)*.2, hand=True))
        self.assertTrue(any(e['type'] == 'rollback' for e in result['updates']))
        self.assertEqual(len(model.versions[0]), 1)
        np.testing.assert_allclose(model.anchor[0], .6)
        self.assertFalse(result['emptySupport'])

    def test_established_stone_removal_blocks_learning(self):
        model = Baseline('guarded_adaptive', self.observation(0, 0), ['black'])
        result = model.step(self.observation(1, .2, reading='empty'))
        self.assertIn('established position changed', result['reasons'])
        self.assertFalse(result['emptySupport'])

    def test_unavailable_wood_is_unknown_not_empty_evidence(self):
        metric = features([np.full(32, .6)], [np.full(24, np.nan)], [np.full(32, .6)], [np.full(24, .6)])[0]
        self.assertIsNone(metric['gain'])
        model = Baseline('guarded_adaptive', self.observation(0, 0), ['empty'])
        for frame in range(1, 20):
            o = self.observation(frame, frame*.2)
            o.metrics = [metric]
            result = model.step(o)
            self.assertFalse(result['updates'])
            self.assertFalse(result['emptySupport'])

    def test_fault_injection_preserves_pixels_and_clock_timestamps(self):
        observations = [self.observation(frame, frame*.2, hand=317 <= frame <= 332) for frame in range(306, 411)]
        source = {o.frame: o for o in observations}
        for name, sequence, _ in scenarios(observations):
            for o in sequence:
                self.assertIs(o.core, source[o.frame].core)
                self.assertIs(o.raw, source[o.frame].raw)
                self.assertEqual(o.time, source[o.frame].time)
            if name == 'camera_gap_white8':
                self.assertFalse(any(317 <= o.frame <= 332 for o in sequence))
                self.assertGreater(source[333].time-source[316].time, PROTOCOL['maximumGap'])


if __name__ == '__main__':
    unittest.main()
