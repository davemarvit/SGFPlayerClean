import copy
import unittest

import numpy as np

from placement_competition_lab import PlacementCompetition, View
from unavailable_shadow_lab import SupportFilter, assess, measured_contrast


def appearance(known=False, measured=-.5, wood=.2):
    return {'signedCoreDelta': -.3 if known else None, 'measuredCoreDelta': measured,
            'gain': 1., 'coreError': .5, 'woodError': wood, 'woodPixels': 100}


def view(frame, evidence=None, hand=False, gap=False):
    readings = [{'occupancy': 'empty', 'confidence': 1.} for _ in range(9)]
    readings[4] = {'occupancy': 'black', 'confidence': 1.}
    estimates = [{'signedCoreDelta': 0., 'gain': 1., 'woodError': 0., 'coreError': 0., 'woodPixels': 100} for _ in range(9)]
    estimates[4] = evidence or appearance()
    return View(frame, frame*.2, hand, False, readings, estimates, gap,
                {'time': 17., 'scope': 'original unassigned frame metadata'})


class UnavailableShadowTests(unittest.TestCase):
    def model(self, policy='contrast_black', before=None, shapes=None):
        return PlacementCompetition(before or ['empty']*9, 'black', 'black_shadow_independent',
                                    support_filter=SupportFilter(policy, shapes or {}, size=3))

    def test_signal_margin_keeps_stone_but_holds_broad_shadow(self):
        reading = {'occupancy': 'black', 'confidence': 1.}
        self.assertEqual(assess('contrast_black', 4, reading, appearance())['support'], 1.)
        weak = appearance(measured=-.05, wood=.33)
        self.assertEqual(assess('contrast_black', 4, reading, weak)['support'], 0.)
        self.assertEqual(assess('neutral', 4, reading, weak)['support'], 1.)

    def test_unavailable_coverage_or_gain_never_recovers(self):
        for key, value in (('gain', None), ('gain', 3.), ('coreError', None),
                           ('coreError', float('nan')), ('coreError', float('inf')),
                           ('woodPixels', 0), ('woodError', None), ('measuredCoreDelta', None)):
            a = appearance()
            a[key] = value
            self.assertEqual(assess('contrast_black', 4, {'occupancy': 'black', 'confidence': 1.}, a)['support'], 0.)

    def test_available_shadow_contradiction_cannot_be_overruled(self):
        a = appearance(known=True)
        a['signedCoreDelta'] = -.02
        result = assess('contrast_black', 4, {'occupancy': 'black', 'confidence': 1.}, a)
        self.assertEqual(result['support'], .25)

    def test_white_control_retains_support(self):
        for policy in ('hold_black', 'outline_black', 'contrast_black'):
            self.assertEqual(assess(policy, 4, {'occupancy': 'white', 'confidence': 1.}, appearance())['support'], 1.)

    def test_outline_requires_current_location_quality_and_center(self):
        shape = {'row': 1, 'col': 1, 'center': {'x': 1., 'y': 1.}, 'quality': .95}
        r = {'occupancy': 'black', 'confidence': 1.}
        self.assertEqual(assess('outline_black', 4, r, appearance(), [shape], size=3)['support'], 1.)
        shape['quality'] = .88
        self.assertEqual(assess('outline_black', 4, r, appearance(), [shape], size=3)['support'], 0.)

    def test_pending_is_not_empty_and_cannot_lend_time_to_later_stone(self):
        model = self.model()
        blocked = view(1, appearance(measured=-.05, wood=.33))
        original = copy.deepcopy(blocked)
        result = model.step(blocked)
        self.assertEqual(result['state'], 'unknown')
        self.assertFalse(result['noMoveHasPositiveEvidence'])
        self.assertEqual(len(result['candidates']), 1)
        self.assertEqual(model.step(view(2))['state'], 'unknown')
        result = model.step(view(3))
        self.assertEqual(result['selected'], 4)
        self.assertEqual(result['firstSeen']['frame'], 1)
        self.assertEqual(result['firstSupported']['frame'], 2)
        self.assertEqual([w['frame'] for w in result['witnesses']], [2, 3])
        self.assertEqual(result['recordedFrameTiming'], blocked.recorded_timing)
        self.assertFalse(result['clockAuthority'])
        self.assertEqual(blocked, original)

    def test_hand_gap_exposure_capture_opposite_guards_remain_authoritative(self):
        for fault in ('hand', 'unknown-hand', 'gap', 'exposure', 'capture', 'opposite'):
            prior = ['empty']*9
            if fault == 'capture':
                prior[1] = 'white'
            model = self.model(before=prior)
            for frame in (1, 2, 3):
                v = view(frame, hand=True if fault == 'hand' else None if fault == 'unknown-hand' else False,
                         gap=fault == 'gap' and frame == 1)
                if fault == 'exposure':
                    v = View(v.frame, v.time, v.hand, True, v.raw, v.appearance)
                if fault == 'opposite':
                    v.raw[8] = {'occupancy': 'white', 'confidence': 1.}
                result = model.step(v)
                self.assertEqual(result['state'], 'unknown', fault)
                self.assertTrue(result['reasons'], fault)

    def test_neutral_filter_is_identical_to_frozen_control(self):
        baseline = PlacementCompetition(['empty']*9, 'black', 'black_shadow_independent')
        filtered = self.model('neutral')
        for frame in range(1, 5):
            v = view(frame)
            self.assertEqual(baseline.step(v), filtered.step(v))
        self.assertEqual(baseline.evidence(), filtered.evidence())

    def test_filter_cannot_amplify_or_inject_nan(self):
        for value in (2., float('nan'), -1.):
            model = PlacementCompetition(['empty']*9, 'black', 'black_shadow_independent',
                                         support_filter=lambda v, p, w: value)
            with self.assertRaises(ValueError):
                model.step(view(1))

    def test_measured_contrast_requires_actual_coverage(self):
        self.assertAlmostEqual(measured_contrast(np.full(10, .1), np.full(10, .6), appearance()), -.5)
        self.assertIsNone(measured_contrast(np.full(10, np.nan), np.full(10, .6), appearance()))


if __name__ == '__main__':
    unittest.main()
