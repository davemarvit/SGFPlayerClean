import unittest
from dataclasses import replace

from turn_location_lab import TurnEvidence, TurnLocationLab, View, play


def turn(n, color=None, time=None, **kwargs):
    t = float(time if time is not None else n*3)
    return TurnEvidence(f'turn:{n}', color or ('black' if n % 2 else 'white'), t, t-.1, t+.1,
                        (f'{n}:a', f'{n}:b'), t+.3, **kwargs)


def views(model, values, start=10, reliable=None, **kwargs):
    for i in range(3):
        model.observe(View(f'view:{start}:{i}', start+i*.5, tuple(values),
                           frozenset(reliable if reliable is not None else range(len(values))), **kwargs))


class TurnLocationTests(unittest.TestCase):
    def test_ambiguity_is_one_immutable_press(self):
        m = TurnLocationLab(5)
        a = turn(1)
        self.assertTrue(m.accept(a, [0, 1]))
        original = m.ledger()
        self.assertEqual(m.clock_policy(), 'continue')
        self.assertEqual(m.unresolved(), {'turn:1': [0, 1]})
        self.assertTrue(m.accept(a, [2]))
        self.assertTrue(m.correct({0: 1}))
        self.assertEqual(m.paths[0].moves, (1,))
        self.assertEqual(original, m.ledger())
        self.assertFalse(m.correct({0: 2}))
        self.assertEqual(original, m.ledger())

    def test_later_play_resolves_occupied_alternative(self):
        m = TurnLocationLab(5)
        m.accept(turn(1), [0, 1])
        m.accept(turn(2), [0])
        self.assertEqual([p.moves for p in m.paths], [(1, 0)])
        self.assertFalse(m.unresolved())
        self.assertEqual(len(m.turns), 2)

    def test_stable_stone_resolves_but_one_flash_does_not(self):
        m = TurnLocationLab(5)
        m.accept(turn(1), [0, 1])
        board = ['empty']*25
        board[1] = 'black'
        m.observe(View('first', 9, tuple(board), frozenset([1])))
        self.assertEqual(len(m.paths), 2)
        views(m, board, reliable=[1])
        self.assertEqual(m.paths[0].moves, (1,))
        self.assertEqual(m.turns[0].time, 3)

    def test_unreliable_surroundings_are_unknown_not_empty(self):
        m = TurnLocationLab(5)
        m.accept(turn(1), [0, 1])
        views(m, ['empty']*25, reliable=[24])
        self.assertEqual(len(m.paths), 2)
        self.assertIsNone(m.position_review)

    def test_new_opponent_stone_waits_for_turn_certificate(self):
        m = TurnLocationLab(5)
        m.accept(turn(1), [0, 1])
        board = ['empty']*25
        board[0] = 'white'
        views(m, board, reliable=[0])
        self.assertEqual(len(m.paths), 2)
        self.assertIsNone(m.position_review)
        self.assertEqual(len(m.turns), 1)
        self.assertEqual(m.audit[-1]['event'], 'unassigned occupied evidence')
        m.accept(turn(2, time=12), [0])
        self.assertEqual(m.paths[0].moves, (1, 0))

    def test_hand_unknown_hand_and_lighting_cannot_prune(self):
        for options in ({'hand': True}, {'hand': None}, {'lighting_ok': False}):
            m = TurnLocationLab(5)
            m.accept(turn(1), [0, 1])
            views(m, ['empty']*25, **options)
            self.assertEqual(len(m.paths), 2)
            self.assertEqual(m.clock_policy(), 'continue')

    def test_gap_preserves_ledger_and_blocks_invented_turn(self):
        m = TurnLocationLab(5)
        m.accept(turn(1), [0, 1])
        original = m.ledger()
        views(m, ['empty']*25, gap_before=True)
        self.assertEqual(m.clock_policy(), 'timing_review')
        self.assertEqual(len(m.paths), 2)
        self.assertFalse(m.accept(turn(2, time=20), [2]))
        self.assertEqual(original, m.ledger())

    def test_sparse_views_do_not_accumulate_persistence(self):
        m = TurnLocationLab(5)
        m.accept(turn(1), [0, 1])
        board = ['empty']*25
        board[1] = 'black'
        for t in (10, 20, 30):
            m.observe(View(str(t), t, tuple(board), frozenset([1])))
        self.assertEqual(len(m.paths), 2)

    def test_uncertified_turns_and_overlapping_times_require_review(self):
        for flag in ('identity_reliable', 'color_reliable', 'timing_reliable', 'continuous', 'clear'):
            m = TurnLocationLab(5)
            self.assertFalse(m.accept(turn(1, **{flag: False}), [0, 1]))
            self.assertFalse(m.turns)
        m = TurnLocationLab(5)
        m.accept(turn(1), [0, 1])
        self.assertFalse(m.accept(turn(2, time=3.1), [2]))
        self.assertEqual(len(m.turns), 1)

    def test_duplicate_witnesses_cannot_make_another_move(self):
        m = TurnLocationLab(5)
        a = turn(1)
        m.accept(a, [0, 1])
        self.assertFalse(m.accept(replace(turn(2), witnesses=a.witnesses), [2]))
        self.assertEqual(len(m.turns), 1)

    def test_changed_timestamp_same_identity_rejected(self):
        m = TurnLocationLab(5)
        a = turn(1)
        m.accept(a, [0, 1])
        self.assertFalse(m.accept(replace(a, time=3.05), [0]))
        self.assertEqual(m.turns[0], a)

    def capture_model(self, capture_minimum=0):
        # White corner group (0,1) has its last liberty at 2.
        board = ['empty']*25
        for p in (0, 1):
            board[p] = 'white'
        for p in (5, 6):
            board[p] = 'black'
        m = TurnLocationLab(5, board, capture_minimum=capture_minimum)
        m.accept(turn(1), [2, 3])
        return m, board

    def test_delayed_removal_does_not_disprove_capture_even_after_long_delay(self):
        m, board = self.capture_model()
        for start in (10, 100, 1000):
            views(m, board, start=start, reliable=[0, 1])
        self.assertEqual(len(m.paths), 2)
        self.assertEqual([len(p.debt) for p in m.paths], [2, 0])

    def test_observed_capture_resolves_location_without_new_press(self):
        m, board = self.capture_model()
        ledger = m.ledger()
        board[0] = board[1] = 'empty'
        views(m, board, reliable=[0, 1])
        self.assertEqual(m.paths[0].moves, (2,))
        self.assertEqual(m.paths[0].captures, (frozenset([0, 1]),))
        self.assertFalse(m.paths[0].debt)
        self.assertEqual(m.ledger(), ledger)

    def test_remaining_stones_resolve_only_with_removal_completion_evidence(self):
        m, board = self.capture_model()
        views(m, board, reliable=[0, 1], removal_complete=frozenset([0, 1]))
        self.assertEqual(m.paths[0].moves, (3,))

    def test_capture_policy_remains_separate_from_turn_certainty(self):
        m, board = self.capture_model(capture_minimum=2)
        self.assertEqual(m.clock_policy(), 'capture_review')
        m.correct({0: 2})
        self.assertEqual(m.clock_policy(), 'capture_hold')
        board[0] = board[1] = 'empty'
        views(m, board, reliable=[0, 1])
        self.assertEqual(m.clock_policy(), 'continue')
        self.assertEqual(len(m.turns), 1)

    def test_partial_removal_keeps_hold(self):
        m, board = self.capture_model(capture_minimum=2)
        m.correct({0: 2})
        board[0] = 'empty'
        views(m, board, reliable=[0])
        self.assertEqual(len(m.paths[0].debt), 1)
        self.assertEqual(m.clock_policy(), 'capture_hold')

    def test_all_conflicting_positions_are_preserved_for_review(self):
        m = TurnLocationLab(5)
        m.accept(turn(1), [0, 1])
        old = list(m.paths)
        views(m, ['empty']*25)
        self.assertEqual(m.paths, old)
        self.assertIsNotNone(m.position_review)
        self.assertEqual(len(m.turns), 1)

    def test_budget_never_silently_selects_a_branch(self):
        m = TurnLocationLab(5, maximum_paths=2)
        m.accept(turn(1), [0, 1])
        old = list(m.paths)
        m.accept(turn(2), [2, 3])
        self.assertEqual(m.paths, old)
        self.assertIsNotNone(m.position_review)
        self.assertEqual(len(m.turns), 2)
        self.assertEqual(m.clock_policy(), 'continue')

    def test_multiple_unresolved_turns_batch_correction_is_atomic(self):
        m = TurnLocationLab(5)
        m.accept(turn(1), [0, 1])
        m.accept(turn(2), [2, 3])
        self.assertEqual(len(m.paths), 4)
        self.assertEqual(len(m.unresolved()), 2)
        original = m.ledger()
        self.assertFalse(m.correct({0: 0, 1: 0}))
        self.assertEqual(len(m.paths), 4)
        self.assertTrue(m.correct({0: 1, 1: 3}))
        self.assertEqual(m.paths[0].moves, (1, 3))
        self.assertEqual(m.ledger(), original)

    def test_repeated_recording_id_is_not_three_witnesses(self):
        m = TurnLocationLab(5)
        m.accept(turn(1), [0, 1])
        board = ['empty']*25
        board[1] = 'black'
        for t in (10, 10.5, 11):
            m.observe(View('same-recording-image', t, tuple(board), frozenset([1])))
        self.assertEqual(len(m.paths), 2)

    def test_simple_ko_and_suicide(self):
        board = ['empty']*25
        for p in (1, 5, 11):
            board[p] = 'black'
        for p in (6, 2, 8, 12):
            board[p] = 'white'
        result = play(tuple(board), 'black', 7, 5)
        self.assertEqual(result[1], frozenset([6]))
        self.assertIsNone(play(result[0], 'white', 6, 5, tuple(board)))
        surrounded = ['empty']*9
        for p in (1, 3, 5, 7):
            surrounded[p] = 'white'
        self.assertIsNone(play(tuple(surrounded), 'black', 4, 3))


if __name__ == '__main__':
    unittest.main()
