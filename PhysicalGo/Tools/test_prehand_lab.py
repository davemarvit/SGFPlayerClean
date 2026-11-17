import copy
from dataclasses import replace
import unittest

from placement_competition_lab import View
from prehand_lab import PreHandCompetition


def view(n, hand=False, point=0):
    raw = [{'occupancy': 'empty', 'confidence': 1.} for _ in range(9)]
    raw[point] = {'occupancy': 'black', 'confidence': 1.}
    appearance = [dict(signedCoreDelta=-.4, measuredCoreDelta=-.4, gain=1.,
                       coreError=.4, woodError=.01, woodPixels=100) for _ in raw]
    return View(n, n*.2, hand, False, raw, appearance, False, {'press': 100., 'capture': 'unchanged'})


class PreHandTests(unittest.TestCase):
    def model(self, policy='retro_edge_shape', before=None, shapes=None):
        return PreHandCompetition(before or ['empty']*9, 'black', policy, shapes)

    def test_later_hand_revision_is_causal_and_does_not_rewrite(self):
        m = self.model()
        original = view(1)
        saved = copy.deepcopy(original)
        first = copy.deepcopy(m.step(original, .3))
        self.assertFalse(m.revisions)
        m.step(view(2, True), .7)
        self.assertEqual(original, saved)
        self.assertEqual(m.decisions[0]['result'], first)
        r, = m.revisions
        self.assertEqual((r['sourceCapturedAt'], r['availableAt']), (.2, .7))
        self.assertFalse(r['provesEmpty'])
        self.assertEqual(m.ledger[0]['weight'], 1.)
        self.assertEqual(m.ledger[0]['rawReading']['confidence'], 1.)
        self.assertEqual(m.step(view(3), .8)['state'], 'unknown')
        result = m.step(view(4), .9)
        self.assertEqual(result['firstSeen']['frame'], 1)
        self.assertEqual(result['firstSupported']['frame'], 3)
        self.assertEqual([w['frame'] for w in result['witnesses']], [3, 4])

    def test_committed_evidence_is_not_retracted(self):
        m = self.model()
        m.step(view(1))
        self.assertEqual(m.step(view(2))['state'], 'placement')
        m.step(view(3, True))
        self.assertFalse(m.revisions)

    def test_gap_breaks_retro_link_even_after_intermediate_frame(self):
        m = self.model()
        m.step(view(1))
        m.step(replace(view(2, True), gap_before=True))
        m.step(view(3, True))
        self.assertFalse(m.revisions)
        for n in (4, 5):
            self.assertEqual(m.step(view(n))['state'], 'unknown')

    def test_unknown_hand_cannot_discount_or_certify(self):
        m = self.model()
        m.step(view(1))
        for n in (2, 3):
            self.assertEqual(m.step(view(n, None))['state'], 'unknown')
        self.assertFalse(m.revisions)

    def test_lookback_does_not_reach_old_evidence(self):
        m = self.model()
        m.step(view(1))
        for n in (2, 3, 4, 5):
            m.step(view(n, None))
        m.step(view(6, True))
        self.assertFalse(m.revisions)

    def test_missing_outline_is_unknown_not_empty(self):
        m = self.model('edge_shape')
        for n in (1, 2, 3):
            r = m.step(view(n))
            self.assertEqual(r['state'], 'unknown')
            self.assertFalse(r['noMoveHasPositiveEvidence'])
            self.assertEqual(r['recordedFrameTiming'], view(n).recorded_timing)
            self.assertFalse(r['clockAuthority'])

    def test_shape_recovers_without_lending_old_witness_time(self):
        shape = dict(row=0, col=0, center=dict(x=0., y=0.), quality=.95, radiusRow=.45, radiusCol=.45)
        m = self.model('combined', shapes={2: [shape], 3: [shape]})
        m.step(view(1))
        m.step(view(2))
        r = m.step(view(3))
        self.assertEqual(r['selected'], 0)
        self.assertEqual(r['firstSupported']['frame'], 2)

    def test_capture_opposite_exposure_guards(self):
        for fault in ('capture', 'opposite', 'exposure'):
            before = ['empty']*9
            if fault == 'capture':
                before[1] = 'white'
            m = self.model('retro_all', before)
            for n in (1, 2, 3):
                v = view(n)
                if fault == 'opposite':
                    v.raw[8]['occupancy'] = 'white'
                if fault == 'exposure':
                    v = replace(v, lighting_blocked=True)
                r = m.step(v)
                self.assertEqual(r['state'], 'unknown')
                self.assertTrue(r['reasons'])
                self.assertEqual(r['recordedFrameTiming'], v.recorded_timing)

    def test_invalid_delivery_and_capture_times(self):
        for bad in (.1,):
            with self.assertRaises(ValueError):
                self.model().step(view(1), bad)
        m = self.model()
        m.step(view(1), .7)
        with self.assertRaises(ValueError):
            m.step(view(2), .6)
        with self.assertRaises(ValueError):
            self.model().step(replace(view(1), time=float('nan')))


if __name__ == '__main__':
    unittest.main()
