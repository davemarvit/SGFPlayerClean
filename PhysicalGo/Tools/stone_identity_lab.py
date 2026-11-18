"""Offline per-stone evidence; one provisional board, no position-history tree.

Scores are bounded evidence summaries, NOT calibrated probabilities. The turn
certifier and native capture resolver remain upstream authorities. Background
proposals cannot write the immutable turn ledger or command a clock.
"""
from collections import deque
from dataclasses import asdict, dataclass, field
import math

from turn_location_lab import EMPTY, TurnEvidence, View, other, play


@dataclass
class Location:
    votes: deque = field(default_factory=lambda: deque(maxlen=8))
    run_value: int = 0
    run_first: float = 0
    run_count: int = 0

    def interrupt(self):
        self.run_value = self.run_count = 0

    def add(self, identity, time, value, strength):
        self.votes.append((identity, time, value, strength))
        if self.run_value != value:
            self.run_value, self.run_first, self.run_count = value, time, 0
        self.run_count += 1

    @property
    def score(self):
        return sum(v[2]*v[3] for v in self.votes)/len(self.votes) if self.votes else 0.

    def sustained(self, value, now):
        return self.run_value == value and self.run_count >= 3 and now-self.run_first >= .8


@dataclass
class StoneTrack:
    identity: str
    color: str
    number: int | None
    locations: dict[int, Location]
    selected: int
    location_level: str = 'unresolved'
    presence: str = 'unobserved'
    revision: int = 0
    motion_review: bool = False
    capture_by: str | None = None
    removed: bool = False
    user_confirmed: bool = False
    cleanup_continuous: bool = False
    established_location: int | None = None


@dataclass(frozen=True)
class Proposal:
    identity: str
    track_revision: int
    context_revision: int
    selected: int
    level: str
    presence: str
    reason: str


class StoneIdentityLab:
    def __init__(self, size=19, initial=None, next_color='black'):
        self.size, self.next_color = size, next_color
        self.initial_player = next_color
        self.initial = tuple([EMPTY]*(size*size) if initial is None else initial)
        if len(self.initial) != size*size or any(c not in (EMPTY, 'black', 'white') for c in self.initial):
            raise ValueError('Trusted initial board required')
        self.turns: list[TurnEvidence] = []
        self.tracks: dict[str, StoneTrack] = {}
        for p, color in enumerate(self.initial):
            if color != EMPTY:
                key = f'setup:{p}'
                self.tracks[key] = StoneTrack(key, color, None, {p: Location()}, p,
                                              'supplied', user_confirmed=True, established_location=p)
        self.used_witnesses, self.seen_views = set(), set()
        self.last_time = None
        self.context_revision = 0
        self.dirty = set()
        self.cursor = ''
        self.timing_review = None
        self.audit = []

    def accept(self, turn, locations, preferred=None):
        prior = next((e for e in self.turns if e.identity == turn.identity), None)
        if prior is not None:
            if prior != turn:
                self.timing_review = 'Changed evidence for an existing turn'
            return prior == turn
        if (self.timing_review or not turn.valid() or
                not all(isinstance(w, str) and w for w in turn.witnesses) or
                turn.color != self.next_color or self.used_witnesses.intersection(turn.witnesses) or
                (self.turns and turn.lower <= self.turns[-1].upper)):
            self.timing_review = self.timing_review or 'Turn identity, order or timing needs review'
            return False
        locations = set(locations)
        if not locations or any(type(p) is not int or not 0 <= p < self.size**2 for p in locations):
            raise ValueError('Invalid location alternatives')
        if preferred is not None and preferred not in locations:
            raise ValueError('Preferred point must be an alternative')
        self.turns.append(turn)
        self.used_witnesses.update(turn.witnesses)
        self.next_color = other(turn.color)
        self.tracks[turn.identity] = StoneTrack(turn.identity, turn.color, len(self.turns),
                                               {p: Location() for p in sorted(locations)},
                                               preferred if preferred is not None else min(locations))
        self.context_revision += 1
        self.dirty.update(self.tracks)
        return True

    def note_motion(self, identity, *, new_locations=(), identity_continuous=False):
        """Upstream motion evidence invalidates current assignment evidence.

        Missing/reappearing stones alone do not certify identity continuity. A
        confidently tracked cleanup may add candidates; otherwise retain the
        old identity and mark the association for review. Never append a turn.
        """
        track = self.tracks[identity]
        points = set(new_locations)
        if any(type(p) is not int or not 0 <= p < self.size**2 for p in points):
            raise ValueError('Invalid new location')
        track.motion_review = not identity_continuous or track.capture_by is not None or track.removed
        track.cleanup_continuous = identity_continuous and not track.motion_review
        prior_evidence = {p: list(e.votes) for p, e in track.locations.items()}
        if identity_continuous and not track.capture_by and not track.removed:
            for p in points:
                track.locations.setdefault(p, Location())
        for location in track.locations.values():
            # Retain past evidence in the audit, but fresh cleanup cannot borrow
            # a former location's accumulated certainty.
            location.interrupt()
            location.votes.clear()
        track.location_level = 'needs review' if track.motion_review else 'unresolved'
        track.presence = 'moving'
        track.user_confirmed = False
        track.revision += 1
        self.context_revision += 1
        self.dirty.update(self.tracks)
        self.audit.append({'event': 'motion', 'identity': identity,
                           'identityContinuous': identity_continuous, 'newLocations': sorted(points),
                           'priorEvidence': prior_evidence})

    def note_capture(self, turn_identity, identities):
        """Accept a VERIFIED native capture certificate, never a guessed board.

        This adapter does not derive capture legality or a clock hold. Captured
        stones remain physically tracked until removal is separately verified.
        """
        turn = next(t for t in self.turns if t.identity == turn_identity)
        identities = set(identities)
        if any(i not in self.tracks or self.tracks[i].color != other(turn.color) or
               (self.tracks[i].number or 0) >= self.tracks[turn_identity].number or
               self.tracks[i].capture_by not in (None, turn_identity) for i in identities):
            raise ValueError('Invalid capture identities')
        for identity in identities:
            track = self.tracks[identity]
            track.capture_by = turn_identity
            track.revision += 1
        self.context_revision += 1
        self.dirty.update(self.tracks)
        self.audit.append({'event': 'native capture certificate', 'turn': turn_identity,
                           'identities': sorted(identities)})

    def observe(self, view: View, strengths=None):
        if len(view.readings) != self.size**2 or not math.isfinite(view.time):
            raise ValueError('Invalid observation')
        if view.identity in self.seen_views:
            return
        if self.last_time is not None and view.time <= self.last_time:
            raise ValueError('Observations must be chronological')
        gap = self.last_time is not None and view.time-self.last_time > .75
        self.last_time = view.time
        self.seen_views.add(view.identity)
        if view.gap_before:
            self.timing_review = 'Camera gap: turn timing requires upstream review'
        clear = view.hand is False and view.lighting_ok and not view.gap_before
        for track in self.tracks.values():
            if track.removed:
                continue
            for point, location in track.locations.items():
                if gap or not clear:
                    location.interrupt()
                if not clear or point not in view.reliable or view.readings[point] == 'uncertain':
                    location.interrupt()
                    continue
                value = 1 if view.readings[point] == track.color else -1
                strength = 1. if strengths is None else strengths.get(point, 0.)
                if not math.isfinite(strength) or not 0 <= strength <= 1:
                    raise ValueError('Evidence strength must be finite and bounded')
                location.add(view.identity, view.time, value, strength)
            track.revision += 1
            self.dirty.add(track.identity)
            if not clear:
                track.presence = 'occluded or unavailable'
        if view.gap_before:
            self.context_revision += 1

    def propose(self, identity):
        """Read-only background result, stamped to reject stale application."""
        track = self.tracks[identity]
        now = self.last_time if self.last_time is not None else 0.
        supported = [p for p, e in track.locations.items() if e.sustained(1, now) and e.score >= .8]
        absent = all(e.sustained(-1, now) for e in track.locations.values())
        selected, level = track.selected, track.location_level
        presence = 'seen' if supported else ('absent' if absent else track.presence)
        reason = 'Insufficient independent local evidence'
        if track.motion_review:
            level, reason = 'needs review', 'Movement identity is unresolved'
        elif track.removed:
            reason, presence = 'Verified removed identity cannot become a new move', 'removed'
        elif track.capture_by:
            # Physical absence can verify removal, not the old SGF intersection.
            presence = 'removed' if absent else 'awaiting removal'
            reason = 'Native capture known; physical removal checked independently'
        elif len(supported) == 1:
            point = supported[0]
            competing = [t.identity for t in self.tracks.values() if t.identity != identity and
                         t.color == track.color and not t.removed and point in t.locations and
                         not (t.location_level in ('supported', 'supplied') and t.selected != point)]
            if competing:
                level, reason = 'unresolved', 'Another same-color identity can explain this stone'
            elif track.established_location is not None and track.established_location != point and not track.cleanup_continuous:
                level, reason = 'needs review', 'Possible relocation needs identity continuity; turn ledger is unchanged'
            else:
                selected, level = point, 'supported'
                reason = 'Sustained local evidence with unique identity attribution'
        elif supported:
            level, reason = 'unresolved', 'Several visible stones; identity association is ambiguous'
        elif absent and not track.user_confirmed:
            level, reason = 'unresolved', 'Disappearance alone is neither a capture nor a new turn'
        return Proposal(identity, track.revision, self.context_revision, selected, level, presence, reason)

    def apply(self, proposal):
        track = self.tracks[proposal.identity]
        if proposal.context_revision != self.context_revision or proposal.track_revision != track.revision:
            return False
        old = (track.selected, track.location_level, track.presence)
        track.selected, track.location_level, track.presence = proposal.selected, proposal.level, proposal.presence
        if proposal.level == 'needs review':
            track.motion_review = True
        if proposal.level == 'supported':
            track.established_location = proposal.selected
            track.cleanup_continuous = False
        if proposal.presence == 'removed':
            track.removed = True
        self.dirty.discard(track.identity)
        if old != (track.selected, track.location_level, track.presence):
            self.audit.append({'event': 'reassessment', **asdict(proposal)})
            # Identity ownership changed: pending background results must recheck.
            self.context_revision += 1
            if old[:2] != (track.selected, track.location_level):
                self.dirty.update(i for i, t in self.tracks.items() if i != track.identity and
                                  not t.removed and t.color == track.color and
                                  set(t.locations).intersection(track.locations))
        return True

    def reassess(self, maximum=32):
        """Bounded work slice; live adaptation could schedule these off-thread."""
        ordered = sorted(self.dirty)
        ordered = [i for i in ordered if i > self.cursor]+[i for i in ordered if i <= self.cursor]
        for identity in ordered[:maximum]:
            self.apply(self.propose(identity))
            self.cursor = identity

    def snapshot(self):
        return {i: {'number': t.number, 'color': t.color, 'selected': t.selected,
                    'locationConfidence': t.location_level, 'presence': t.presence,
                    'identityConfidence': 'needs review' if t.motion_review else 'supplied',
                    'colorConfidence': 'certified' if t.number else 'setup',
                    'timingConfidence': 'certified' if t.number else 'not applicable',
                    'turnConfidence': 'certified' if t.number else 'setup',
                    'captureBy': t.capture_by, 'removed': t.removed,
                    'locations': {p: {'evidenceScore': e.score, 'observations': len(e.votes),
                                      'consecutiveViews': e.run_count} for p, e in t.locations.items()}}
                for i, t in self.tracks.items()}

    def provisional_board(self):
        # Preserve conflicts rather than drawing one identity twice or silently
        # moving a second stone to its next-best candidate to make the board fit.
        cells = {}
        for identity, track in self.tracks.items():
            if not track.removed:
                cells.setdefault(track.selected, []).append(identity)
        return cells

    def ledger(self):
        return [asdict(t) for t in self.turns]

    def finalize(self, locations):
        """After-game explicit resolution; exact replay, atomic, no clock edits.

        All move identities must be supplied, including stones already captured.
        Confirmed native capture identities constrain the final legal replay.
        """
        if self.timing_review:
            raise ValueError('Turn continuity is incomplete; cannot claim a complete game export')
        if set(locations) != {t.identity for t in self.turns}:
            raise ValueError('Resolve every move identity')
        board, previous = self.initial, None
        owners = {p: f'setup:{p}' for p, c in enumerate(board) if c != EMPTY}
        captures, encoded = {}, []
        for turn in self.turns:
            point = locations[turn.identity]
            if type(point) is not int or not 0 <= point < self.size**2:
                raise ValueError('Invalid final intersection')
            result = play(board, turn.color, point, self.size, previous)
            if result is None:
                raise ValueError(f'Illegal move for {turn.identity}')
            after, removed = result
            captured = {owners.pop(p) for p in removed}
            expected = {i for i, t in self.tracks.items() if t.capture_by == turn.identity}
            if not expected.issubset(captured):
                raise ValueError('Final locations contradict a verified capture')
            owners[point] = turn.identity
            captures[turn.identity] = sorted(captured)
            previous, board = board, after
            encoded.append(f';{turn.color[0].upper()}[{chr(97+point%self.size)}{chr(97+point//self.size)}]')
        setup = ''.join(prop+''.join(f'[{chr(97+p%self.size)}{chr(97+p//self.size)}]'
                                     for p, c in enumerate(self.initial) if c == color)
                        for prop, color in (('AB', 'black'), ('AW', 'white')) if color in self.initial)
        return {'board': board, 'captures': captures,
                'sgf': f'(;GM[1]FF[4]SZ[{self.size}]RU[Japanese]PL[{self.initial_player[0].upper()}]{setup}'+''.join(encoded)+')'}
