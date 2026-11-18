import unittest
from dataclasses import replace

from stone_identity_lab import StoneIdentityLab
from turn_location_lab import TurnEvidence, View


def turn(n, time=None):
    t = float(n*3 if time is None else time)
    return TurnEvidence(f'move:{n}', 'black' if n % 2 else 'white', t, t-.1, t+.1,
                        (f'witness:{n}:a', f'witness:{n}:b'), t+.2)


def observe(m, occupied, start=10, reliable=None, **kwargs):
    board = ['empty']*(m.size**2)
    for p, color in occupied.items():
        board[p] = color
    for i in range(4):
        m.observe(View(f'{start}:{i}', start+i*.3, tuple(board),
                       frozenset(range(m.size**2) if reliable is None else reliable), **kwargs))
        m.reassess(1000)


class StoneIdentityTests(unittest.TestCase):
    def test_every_move_may_remain_unresolved_without_stopping_turns(self):
        m = StoneIdentityLab()
        for n in range(1, 151):
            self.assertTrue(m.accept(turn(n), [0, 1, 2, 3, 4]))
            m.reassess()
        self.assertEqual(len(m.turns), 150)
        self.assertEqual(sum(len(t.locations) for t in m.tracks.values()), 750)
        self.assertIsNone(m.timing_review)
        self.assertEqual(len(m.provisional_board()[0]), 150)  # explicit display conflict

    def test_location_confidence_does_not_change_turn_certainty(self):
        m = StoneIdentityLab(5)
        m.accept(turn(1), [0, 1])
        ledger = m.ledger()
        observe(m, {1: 'black'})
        s = m.snapshot()['move:1']
        self.assertEqual(s['locationConfidence'], 'supported')
        self.assertEqual(s['selected'], 1)
        self.assertGreater(s['locations'][1]['evidenceScore'], s['locations'][0]['evidenceScore'])
        self.assertEqual(s['turnConfidence'], 'certified')
        self.assertEqual(ledger, m.ledger())

    def test_cleaned_up_stone_reassessed_without_another_move(self):
        m = StoneIdentityLab(5)
        m.accept(turn(1), [0, 1])
        observe(m, {0: 'black'})
        ledger = m.ledger()
        m.note_motion('move:1', identity_continuous=True)
        self.assertEqual(m.snapshot()['move:1']['locationConfidence'], 'unresolved')
        observe(m, {1: 'black'}, start=12)
        self.assertEqual(m.snapshot()['move:1']['selected'], 1)
        self.assertEqual(m.snapshot()['move:1']['locationConfidence'], 'supported')
        self.assertEqual(ledger, m.ledger())
        self.assertEqual(len(m.provisional_board()), 1)

    def test_disappearance_reappearance_is_not_silently_a_cleanup(self):
        m = StoneIdentityLab(5)
        m.accept(turn(1), [0, 1])
        observe(m, {0: 'black'})
        observe(m, {}, start=12)
        observe(m, {1: 'black'}, start=14)
        observe(m, {1: 'black'}, start=16)
        self.assertEqual(m.snapshot()['move:1']['locationConfidence'], 'needs review')
        self.assertEqual(m.snapshot()['move:1']['selected'], 0)
        self.assertEqual(len(m.turns), 1)
        self.assertIsNone(m.timing_review)  # association uncertainty is not a clock command

    def test_uncertain_motion_does_not_block_later_certified_turn(self):
        m = StoneIdentityLab(5)
        m.accept(turn(1), [0, 1])
        m.note_motion('move:1', new_locations=[2], identity_continuous=False)
        self.assertNotIn(2, m.tracks['move:1'].locations)
        self.assertTrue(m.accept(turn(2), [3, 4]))
        self.assertIsNone(m.timing_review)

    def test_same_color_identities_cannot_borrow_one_stone(self):
        m = StoneIdentityLab(5)
        m.accept(turn(1), [0, 1])
        m.accept(turn(2), [20])
        m.accept(turn(3), [0, 2])
        observe(m, {0: 'black', 20: 'white'})
        self.assertEqual(m.snapshot()['move:1']['locationConfidence'], 'unresolved')
        self.assertEqual(m.snapshot()['move:3']['locationConfidence'], 'unresolved')

    def test_stale_background_result_rejected_after_motion_or_new_turn(self):
        m = StoneIdentityLab(5)
        m.accept(turn(1), [0, 1])
        proposal = m.propose('move:1')
        m.note_motion('move:1', identity_continuous=True)
        self.assertFalse(m.apply(proposal))
        proposal = m.propose('move:1')
        m.accept(turn(2), [2])
        self.assertFalse(m.apply(proposal))

    def test_stale_background_result_rejected_after_new_recording(self):
        m = StoneIdentityLab(5)
        m.accept(turn(1), [0, 1])
        proposal = m.propose('move:1')
        observe(m, {1: 'black'})
        self.assertFalse(m.apply(proposal))

    def test_background_budget_does_not_starve_later_stones(self):
        m = StoneIdentityLab()
        for n in range(1, 86):
            m.accept(turn(n), [n])
        for _ in range(3):
            m.reassess(32)
        self.assertFalse(m.dirty)

    def test_hand_unknown_hand_and_lighting_add_no_confidence(self):
        for kwargs in ({'hand': True}, {'hand': None}, {'lighting_ok': False}):
            m = StoneIdentityLab(5)
            m.accept(turn(1), [0, 1])
            observe(m, {1: 'black'}, **kwargs)
            self.assertEqual(m.snapshot()['move:1']['locationConfidence'], 'unresolved')
            self.assertEqual(m.snapshot()['move:1']['locations'][1]['observations'], 0)

    def test_camera_gap_preserves_prior_turn_and_requires_real_timing_review(self):
        m = StoneIdentityLab(5)
        m.accept(turn(1), [0, 1])
        ledger = m.ledger()
        observe(m, {1: 'black'}, gap_before=True)
        self.assertEqual(m.ledger(), ledger)
        self.assertIsNotNone(m.timing_review)
        self.assertFalse(m.accept(turn(2), [2]))

    def test_repeated_image_cannot_create_confidence(self):
        m = StoneIdentityLab(5)
        m.accept(turn(1), [0, 1])
        board = tuple(['black']+['empty']*24)
        for t in (10, 10.5, 11):
            m.observe(View('same-image', t, board, frozenset([0])))
            m.reassess()
        self.assertEqual(m.snapshot()['move:1']['locationConfidence'], 'unresolved')

    def test_capture_waits_for_physical_removal_and_never_presses_again(self):
        initial = ['empty']*25
        for p in (0, 1):
            initial[p] = 'white'
        for p in (5, 6):
            initial[p] = 'black'
        m = StoneIdentityLab(5, initial)
        m.accept(turn(1), [2, 3])
        m.note_capture('move:1', ['setup:0', 'setup:1'])
        ledger = m.ledger()
        observe(m, {0: 'white', 1: 'white', 2: 'black', 5: 'black', 6: 'black'})
        self.assertEqual(m.snapshot()['setup:0']['presence'], 'awaiting removal')
        observe(m, {1: 'white', 2: 'black', 5: 'black', 6: 'black'}, start=12)
        self.assertTrue(m.tracks['setup:0'].removed)
        self.assertFalse(m.tracks['setup:1'].removed)
        observe(m, {2: 'black', 5: 'black', 6: 'black'}, start=14)
        self.assertTrue(m.tracks['setup:1'].removed)
        final = m.finalize({'move:1': 2})
        self.assertEqual(final['captures']['move:1'], ['setup:0', 'setup:1'])
        self.assertEqual(m.ledger(), ledger)
        with self.assertRaises(ValueError):
            m.finalize({'move:1': 3})
        self.assertEqual(m.ledger(), ledger)

    def test_empty_reading_without_capture_certificate_does_not_remove_identity(self):
        m = StoneIdentityLab(5)
        m.accept(turn(1), [0])
        observe(m, {})
        self.assertFalse(m.tracks['move:1'].removed)
        self.assertEqual(m.snapshot()['move:1']['presence'], 'absent')
        self.assertIsNone(m.timing_review)

    def test_final_sgf_is_deferred_and_atomic(self):
        m = StoneIdentityLab(5)
        m.accept(turn(1), [0, 1])
        m.accept(turn(2), [0, 2])
        ledger = m.ledger()
        with self.assertRaises(ValueError):
            m.finalize({'move:1': 0, 'move:2': 0})
        with self.assertRaises(ValueError):
            m.finalize({'move:1': 1})
        result = m.finalize({'move:1': 1, 'move:2': 0})
        self.assertIn(';B[ba];W[aa]', result['sgf'])
        self.assertEqual(m.ledger(), ledger)

    def test_missing_turn_continuity_cannot_be_exported_as_a_complete_game(self):
        m = StoneIdentityLab(5)
        m.accept(turn(1), [0, 1])
        observe(m, {0: 'black'}, gap_before=True)
        with self.assertRaises(ValueError):
            m.finalize({'move:1': 0})
        self.assertEqual(len(m.turns), 1)

    def test_duplicate_and_changed_turn_evidence(self):
        m = StoneIdentityLab(5)
        t = turn(1)
        self.assertTrue(m.accept(t, [0, 1]))
        self.assertTrue(m.accept(t, [2]))
        self.assertEqual(len(m.turns), 1)
        self.assertFalse(m.accept(replace(t, time=3.05), [0]))
        self.assertEqual(m.turns[0], t)


if __name__ == '__main__':
    unittest.main()
