import unittest
from dataclasses import replace

from occluded_identity_lab import Anchor, Disk, OccludedIdentityBridge, disks_from_row


def disk(x=0., y=0., color='black'):
    return Disk(color, x, y, .46, .46, .99, frozenset([round(y)*19+round(x)]))


def anchor(identity='old', x=0., y=0., color='black'):
    return Anchor(identity, disk(x, y, color), (identity+'1', identity+'2', identity+'3'), 0., .5)


def finish(model, disks, **kwargs):
    for i, t in enumerate((1.5, 1.8, 2.1, 2.4)):
        model.observe('clear'+str(i), t, disks, hand=False, epoch='camera-a', **kwargs)


class OccludedIdentityTests(unittest.TestCase):
    def test_hand_covered_cleanup_keeps_identity_and_fractional_center(self):
        m = OccludedIdentityBridge([anchor()], epoch='camera-a')
        m.observe('hand', 1., [disk(.5)], hand=True, epoch='camera-a')
        self.assertFalse(m.hypotheses)
        finish(m, [disk(.45)])
        h = m.hypotheses['old']
        self.assertEqual(h['center'], [.45, 0.])
        self.assertFalse(h['clockAuthority'])
        self.assertFalse(h['physicalIdentityProven'])
        self.assertEqual(m.result()['newTurnEvents'], [])
        self.assertEqual(m.result()['clockCommands'], [])

    def test_two_same_color_candidates_abstain_instead_of_nearest_guess(self):
        m = OccludedIdentityBridge([anchor()], epoch='camera-a')
        m.observe('hand', 1., [], hand=True, epoch='camera-a')
        finish(m, [disk(.2), disk(.55)])
        self.assertFalse(m.hypotheses)
        self.assertEqual(m.result()['unresolved'], ['old'])

    def test_two_old_stones_cannot_claim_one_outline(self):
        m = OccludedIdentityBridge([anchor(), anchor('second', 1.)], epoch='camera-a')
        m.observe('hand', 1., [], hand=True, epoch='camera-a')
        finish(m, [disk(.5)])
        self.assertEqual(m.result()['unresolved'], ['old', 'second'])

    def test_capture_blocks_same_color_replacement(self):
        m = OccludedIdentityBridge([anchor()], epoch='camera-a')
        m.observe('hand', 1., [], hand=True, epoch='camera-a', captured=['old'])
        finish(m, [disk()])
        self.assertFalse(m.hypotheses)
        self.assertEqual(m.result()['retired'], ['old'])

    def test_later_capture_retracts_prior_hypothesis_without_clock_event(self):
        m = OccludedIdentityBridge([anchor()], epoch='camera-a')
        m.observe('hand', 1., [], hand=True, epoch='camera-a')
        finish(m, [disk()])
        m.observe('capture', 2.6, [disk()], hand=False, epoch='camera-a', captured=['old'])
        self.assertFalse(m.hypotheses)
        self.assertFalse(m.result()['clockCommands'])

    def test_camera_gap_keeps_unresolved_identity(self):
        m = OccludedIdentityBridge([anchor()], epoch='camera-a')
        m.observe('hand', 1., [], hand=True, epoch='camera-a')
        finish(m, [disk()], gap_before=True)
        self.assertTrue(m.interrupted)
        self.assertFalse(m.hypotheses)
        self.assertEqual(m.result()['unresolved'], ['old'])

    def test_camera_change_does_not_transfer_geometry(self):
        m = OccludedIdentityBridge([anchor()], epoch='camera-a')
        m.observe('hand', 1., [], hand=True, epoch='iphone')
        finish(m, [disk()])
        self.assertTrue(m.interrupted)
        self.assertFalse(m.hypotheses)

    def test_unknown_hand_and_missing_hand_cannot_supply_clean_episode(self):
        for hand in (None, False):
            m = OccludedIdentityBridge([anchor()], epoch='camera-a')
            m.observe('hand', 1., [], hand=hand, epoch='camera-a')
            finish(m, [disk()])
            self.assertFalse(m.hypotheses)

    def test_reentry_retracts_fresh_result(self):
        m = OccludedIdentityBridge([anchor()], epoch='camera-a')
        m.observe('hand', 1., [], hand=True, epoch='camera-a')
        finish(m, [disk()])
        self.assertTrue(m.hypotheses)
        m.observe('reenter', 2.6, [], hand=True, epoch='camera-a')
        self.assertFalse(m.hypotheses)
        self.assertEqual(len(m.anchors), 1)

    def test_duplicate_observation_does_not_make_persistence(self):
        m = OccludedIdentityBridge([anchor()], epoch='camera-a')
        m.observe('hand', 1., [], hand=True, epoch='camera-a')
        for t in (1.5, 1.8, 2.1, 2.4):
            m.observe('same', t, [disk()], hand=False, epoch='camera-a')
        self.assertFalse(m.hypotheses)

    def test_drift_is_bounded_to_first_post_hand_outline(self):
        m = OccludedIdentityBridge([anchor()], epoch='camera-a')
        m.observe('hand', 1., [], hand=True, epoch='camera-a')
        for i, x in enumerate((.1, .2, .3, .4, .5)):
            m.observe(str(i), 1.3+i*.3, [disk(x)], hand=False, epoch='camera-a')
        self.assertFalse(m.hypotheses)

    def test_coherent_board_shift_abstains(self):
        m = OccludedIdentityBridge([anchor(str(i), 3.*i) for i in range(4)], epoch='camera-a')
        m.observe('hand', 1., [], hand=True, epoch='camera-a')
        finish(m, [disk(3.*i+.2) for i in range(4)])
        self.assertEqual(m.interrupted, 'possible camera/board movement')

    def test_color_or_outline_size_change_cannot_reuse_identity(self):
        for d in (disk(color='white'), replace(disk(), rx=.61)):
            m = OccludedIdentityBridge([anchor()], epoch='camera-a')
            m.observe('hand', 1., [], hand=True, epoch='camera-a')
            finish(m, [d])
            self.assertFalse(m.hypotheses)

    def test_raw_candidate_preserved_without_centering_or_borrowed_color(self):
        row = {'raw': [['black', 1.]], 'shapes': [dict(row=0, col=0, center={'x': .45, 'y': 0},
                                                    radiusCol=.46, radiusRow=.46, quality=.99)]}
        self.assertEqual(disks_from_row(row)[0].x, .45)
        row['raw'][0] = ['uncertain', 1.]
        self.assertFalse(disks_from_row(row))
        row['raw'][0] = ['black', .5]
        self.assertFalse(disks_from_row(row))

    def test_background_clearance_latency_cannot_change_old_turn_time(self):
        from stone_identity_lab import StoneIdentityLab
        from turn_location_lab import TurnEvidence
        game = StoneIdentityLab(5)
        e = TurnEvidence('old', 'black', 0, 0, 0, ('a', 'b'), 0)
        game.accept(e, [0, 1])
        before = game.ledger()
        bridge = OccludedIdentityBridge([anchor()], epoch='camera-a')
        bridge.observe('hand', 1, [], hand=True, epoch='camera-a')
        finish(bridge, [disk(.45)])
        self.assertTrue(bridge.hypotheses)
        self.assertEqual(game.ledger(), before)
        self.assertTrue(game.accept(TurnEvidence('next', 'white', 3, 2.9, 3.1, ('c','d'), 3.2), [3,4]))
        self.assertEqual(game.turns[0], e)


if __name__ == '__main__':
    unittest.main()
