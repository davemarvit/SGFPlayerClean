"""Offline turn ledger and conservative legal-position forest. Never imported by the app.

TurnEvidence is an upstream certification contract, not a pixel classifier.
Location choices are deliberately absent from its identity and clock payload.
Only Japanese/simple-ko, no-suicide placements are supported in this prototype.
"""
from dataclasses import dataclass, replace, asdict
import math

EMPTY = 'empty'


def other(color):
    return 'white' if color == 'black' else 'black'


def neighbors(point, size):
    return tuple(q for q in (point-size, point+size, point-1, point+1)
                 if 0 <= q < size*size and
                 abs(q % size-point % size)+abs(q//size-point//size) == 1)


def play(board, color, point, size, previous=None):
    """Exact liberties/captures on a hypothesized board, never on raw readings."""
    if not 0 <= point < size*size or board[point] != EMPTY:
        return None
    result = list(board)
    result[point] = color

    def group(start):
        found, todo, liberties = set(), [start], set()
        while todo:
            p = todo.pop()
            if p in found:
                continue
            found.add(p)
            for q in neighbors(p, size):
                if result[q] == EMPTY:
                    liberties.add(q)
                elif result[q] == result[start] and q not in found:
                    todo.append(q)
        return found, liberties

    captured = set()
    for q in neighbors(point, size):
        if result[q] == other(color):
            stones, liberties = group(q)
            if not liberties:
                captured.update(stones)
                for p in stones:
                    result[p] = EMPTY
    if not group(point)[1] or tuple(result) == previous:
        return None
    return tuple(result), frozenset(captured)


@dataclass(frozen=True)
class TurnEvidence:
    identity: str  # source/session + tracked physical placement episode, NOT location
    color: str
    time: float
    lower: float
    upper: float
    witnesses: tuple[str, ...]
    certified_at: float
    identity_reliable: bool = True
    color_reliable: bool = True
    timing_reliable: bool = True
    continuous: bool = True
    clear: bool = True

    def valid(self):
        return (bool(self.identity) and self.color in ('black', 'white') and
                all(math.isfinite(t) for t in (self.lower, self.time, self.upper, self.certified_at)) and
                self.lower <= self.time <= self.upper <= self.certified_at and
                len(set(self.witnesses)) >= 2 and
                self.identity_reliable and self.color_reliable and self.timing_reliable and
                self.continuous and self.clear)


@dataclass(frozen=True)
class Path:
    board: tuple[str, ...]
    previous: tuple[str, ...] | None = None
    moves: tuple[int, ...] = ()
    captures: tuple[frozenset[int], ...] = ()
    # (intersection, color, original placement identity). Legal prisoners may
    # remain visible indefinitely; there is deliberately no removal timeout.
    debt: tuple[tuple[int, str, str], ...] = ()
    owners: tuple[str | None, ...] = ()
    captured_identities: tuple[frozenset[str], ...] = ()


@dataclass(frozen=True)
class View:
    identity: str
    time: float
    readings: tuple[str, ...]
    reliable: frozenset[int]
    hand: bool | None = False
    lighting_ok: bool = True
    gap_before: bool = False
    # Separately certified, local end of removal episode; never inferred from
    # elapsed time, hand exit alone, or classifier confidence alone.
    removal_complete: frozenset[int] = frozenset()


class TurnLocationLab:
    def __init__(self, size=19, initial=None, next_color='black', maximum_paths=256,
                 minimum_views=3, minimum_span=.8, maximum_gap=.75, capture_minimum=0):
        board = tuple(initial or [EMPTY]*(size*size))
        if len(board) != size*size or any(v not in (EMPTY, 'black', 'white') for v in board):
            raise ValueError('A trusted starting board is required')
        self.size, self.next_color = size, next_color
        self.maximum_paths = maximum_paths
        self.minimum_views, self.minimum_span, self.maximum_gap = minimum_views, minimum_span, maximum_gap
        self.capture_minimum = capture_minimum
        if next_color not in ('black', 'white') or maximum_paths < 1 or minimum_views < 2:
            raise ValueError('Invalid forest configuration')
        owners = tuple(f'setup:{p}' if c != EMPTY else None for p, c in enumerate(board))
        self.paths = [Path(board=board, owners=owners)]
        self.turns = []
        self.choices = []
        self.used_witnesses = set()
        self.runs = {}
        self.seen_views = set()
        self.last_view = None
        self.timing_review = None
        self.position_review = None
        self.audit = []

    def accept(self, evidence, locations):
        """Append exactly one immutable turn; assignment never presses a clock."""
        old = next((e for e in self.turns if e.identity == evidence.identity), None)
        if old is not None:
            if old != evidence:
                self.timing_review = 'same identity with changed clock evidence'
                return False
            return True  # idempotent delivery; locations require explicit correction
        if (self.timing_review or not evidence.valid() or evidence.color != self.next_color or
                self.used_witnesses.intersection(evidence.witnesses) or
                (self.turns and evidence.lower <= self.turns[-1].upper)):
            self.timing_review = self.timing_review or 'unreliable identity, color, order, or timing'
            return False
        locations = frozenset(locations)
        if not locations or any(type(p) is not int or not 0 <= p < self.size*self.size for p in locations):
            raise ValueError('Supply bounded possible intersections')
        self.turns.append(evidence)
        self.choices.append(locations)
        self.used_witnesses.update(evidence.witnesses)
        self.next_color = other(evidence.color)
        self.runs.clear()  # witnesses cannot straddle a board transition
        if not self.position_review:
            expanded = self._expand(self.paths, evidence, locations)
            if not expanded:
                self.position_review = 'no retained legal position; preserve turns for review'
            elif len(expanded) > self.maximum_paths:
                self.position_review = 'position budget exceeded; prior forest retained, no truncation'
            else:
                self.paths = expanded
        self.audit.append({'event': 'turn', 'identity': evidence.identity, 'time': evidence.time,
                           'alternatives': sorted(locations), 'positions': len(self.paths)})
        return True

    def _expand(self, paths, evidence, locations):
        result = []
        for path in paths:
            for point in sorted(locations):
                played = play(path.board, evidence.color, point, self.size, path.previous)
                if played is None:
                    continue
                board, captured = played
                owners = list(path.owners)
                debt = [d for d in path.debt if d[0] != point]
                debt.extend((p, path.board[p], owners[p]) for p in sorted(captured))
                for p in captured:
                    owners[p] = None
                owners[point] = evidence.identity
                result.append(Path(board, path.board, path.moves+(point,), path.captures+(captured,),
                                   tuple(debt), tuple(owners),
                                   path.captured_identities+(frozenset(path.owners[p] for p in captured),)))
                if len(result) > self.maximum_paths:
                    return result  # caller keeps the ENTIRE prior forest
        return result

    def observe(self, view):
        if len(view.readings) != self.size*self.size or not math.isfinite(view.time):
            raise ValueError('Invalid observation')
        if view.identity in self.seen_views:
            return  # redelivery is not independent persistence
        if self.last_view is not None and view.time <= self.last_view:
            raise ValueError('Observations must be chronological')
        self.seen_views.add(view.identity)
        gap = self.last_view is not None and view.time-self.last_view > self.maximum_gap
        self.last_view = view.time
        if view.gap_before:
            self.timing_review = 'camera gap: unobserved turns/times require review'
        if gap or view.gap_before or view.hand is not False or not view.lighting_ok:
            self.runs.clear()
        if view.hand is not False or not view.lighting_ok or self.position_review or self.timing_review:
            return
        stable = {}
        for p, value in enumerate(view.readings):
            if p not in view.reliable or value not in (EMPTY, 'black', 'white'):
                self.runs.pop(p, None)
                continue
            # Completion evidence must itself persist over the same clear run.
            signature = (value, p in view.removal_complete)
            run = self.runs.get(p)
            if run is None or run[0] != signature:
                run = (signature, view.time, 0)
            run = (run[0], run[1], run[2]+1)
            self.runs[p] = run
            if run[2] >= self.minimum_views and view.time-run[1] >= self.minimum_span:
                stable[p] = signature
        if not stable:
            return
        # A new stone can become visible before the upstream turn certificate
        # arrives. Globally unsupported occupied readings are unassigned turn
        # evidence, not grounds to delete every existing legal position. Preserve
        # their provenance; they cannot press a clock or select a location here.
        unassigned = {p for p, (value, _) in stable.items() if value != EMPTY and
                      not any(path.board[p] == value or any(d[0] == p and d[1] == value for d in path.debt)
                              for path in self.paths)}
        if unassigned:
            self.audit.append({'event': 'unassigned occupied evidence', 'view': view.identity,
                               'time': view.time, 'points': sorted(unassigned)})
            stable = {p: value for p, value in stable.items() if p not in unassigned}
        kept, rejected = [], []
        for path in self.paths:
            debt = list(path.debt)
            conflicts = []
            for p, (value, removal_complete) in stable.items():
                lingering = [d for d in debt if d[0] == p and d[1] == value]
                if value == path.board[p]:
                    # Empty, or a new stone replacing a prisoner, certifies that
                    # this old identity is gone, without generating a move.
                    debt = [d for d in debt if d[0] != p]
                elif lingering and not removal_complete:
                    continue
                else:
                    conflicts.append(p)
            if conflicts:
                rejected.append({'moves': path.moves, 'points': conflicts})
            else:
                kept.append(replace(path, debt=tuple(debt)))
        if not kept:
            self.position_review = 'sustained readings contradict every position; forest preserved'
        else:
            self.paths = kept
        if rejected:
            self.audit.append({'event': 'position evidence', 'view': view.identity,
                               'time': view.time, 'rejected': rejected,
                               'retainedPriorOnConflict': not bool(kept)})

    def correct(self, edits):
        """Select retained alternatives atomically; immutable turn ledger is untouched.

        Out-of-forest corrections need a full historical replay and are intentionally
        unsupported here. Never silently restore a visually eliminated branch.
        """
        if self.position_review or not edits or any(type(i) is not int or not 0 <= i < len(self.turns)
                                                    for i in edits):
            return False
        kept = [p for p in self.paths if all(p.moves[i] == point for i, point in edits.items())]
        if not kept:
            return False
        self.paths = kept
        self.runs.clear()
        self.audit.append({'event': 'location correction', 'edits': edits})
        return True

    def unresolved(self):
        if self.position_review:
            return {e.identity: sorted(c) for e, c in zip(self.turns, self.choices)}
        return {e.identity: sorted(points) for i, e in enumerate(self.turns)
                if len(points := {p.moves[i] for p in self.paths}) > 1}

    def clock_policy(self):
        # This is a recommendation to the existing native clock/capture policy,
        # not clock arithmetic. Capture consequences can legitimately require a
        # hold even when the placement's identity/time are known.
        if self.timing_review:
            return 'timing_review'
        if self.capture_minimum >= 2:
            if self.position_review:
                return 'capture_review'
            plans = {tuple((i, tuple(sorted(c))) for i, c in enumerate(p.captures)
                           if len(c) >= self.capture_minimum) for p in self.paths}
            if len(plans) > 1:
                return 'capture_review'
            if any(len(c) >= self.capture_minimum and any(d[2] in c for d in p.debt)
                   for p in self.paths for c in p.captured_identities):
                return 'capture_hold'
        return 'continue'

    def ledger(self):
        return [asdict(e) for e in self.turns]
