#!/usr/bin/env python3
"""Non-authoritative single-placement competition with per-candidate histories.

This module does not import the app, infer clock presses, resolve captures, or
advance a game. The caller supplies an explicit trusted prior position/turn.
"""
from dataclasses import dataclass, field
import json
import math
from pathlib import Path
from types import MappingProxyType

import numpy as np

PROTOCOL = MappingProxyType(json.loads(Path(__file__).with_name('placement_competition_protocol.json').read_text()))
METHODS = ('raw_competition', 'appearance_independent', 'appearance_competition',
           'black_shadow_independent', 'black_shadow_competition')


@dataclass(frozen=True)
class View:
    frame: int
    time: float
    hand: object
    lighting_blocked: bool
    raw: list
    appearance: list
    gap_before: bool = False
    recorded_timing: object = None


@dataclass
class History:
    first_seen: dict
    first_supported: object = None
    evidence: list = field(default_factory=list)
    run: list = field(default_factory=list)


def appearance_features(observation, anchor_core):
    """Measure directional stone-center change after neighboring wood gain.

    The reference is a trusted earlier image, not a future clean frame. Broad
    darkness alone is not a stone; missing/unstable wood is unknown. No labels
    or predicted color enter this feature calculation.
    """
    result = []
    for core, old, metric in zip(observation.core, anchor_core, observation.metrics):
        row = dict(metric)
        gain = metric['gain']
        finite = np.isfinite(core) & np.isfinite(old)
        usable = (gain is not None and metric['coreError'] is not None
                  and metric['woodError'] is not None
                  and PROTOCOL['minimumGain'] <= gain <= PROTOCOL['maximumGain']
                  and metric['woodError'] <= PROTOCOL['maximumWoodError']
                  and finite.sum() >= .9*len(core))
        row['signedCoreDelta'] = float(np.median(core[finite]-gain*old[finite])) if usable else None
        result.append(row)
    return result


def candidate_weight(reading, appearance, method):
    confidence = max(0., min(1., reading['confidence']))
    raw = max(0., (confidence-PROTOCOL['confidenceFloor'])/(1-PROTOCOL['confidenceFloor'])) ** PROTOCOL['confidenceExponent']
    delta = appearance['signedCoreDelta']
    strength = None
    if delta is not None:
        directed = delta if reading['occupancy'] == 'white' else -delta
        strength = max(0., min(1., (directed-PROTOCOL['contrastStart']) /
                               (PROTOCOL['contrastFull']-PROTOCOL['contrastStart'])))
    # A dark core can be explained by shared wood darkening. Low contrast is
    # not analogous negative evidence for a white stone against pale wood.
    # This color-specific ablation was added after the v1 development result;
    # it must not be presented as an independently validated improvement.
    white_control = method.startswith('black_shadow_') and reading['occupancy'] == 'white'
    factor = (1. if method == 'raw_competition' or strength is None or white_control else
              PROTOCOL['appearanceFloor']+(1-PROTOCOL['appearanceFloor'])*strength)
    return raw, strength, raw*factor


def unchanged(reading, appearance):
    return (reading['occupancy'] == 'empty' and reading['confidence'] >= PROTOCOL['unchangedConfidence']
            and appearance['signedCoreDelta'] is not None
            and appearance['coreError'] is not None and appearance['woodError'] is not None
            and PROTOCOL['unchangedMinimumGain'] <= appearance['gain'] <= PROTOCOL['unchangedMaximumGain']
            and appearance['coreError'] <= PROTOCOL['unchangedCoreError']
            and appearance['woodError'] <= PROTOCOL['unchangedWoodError'])


class PlacementCompetition:
    """Suggest one location, explicit no-move, or unknown within a fixed turn.

    A camera gap latches review until the caller supplies a new trusted context.
    Candidate timestamps describe observations, never estimated clock presses.
    Hands/gaps reset usable runs but preserve every earlier evidence record.
    """
    def __init__(self, before, color, method='appearance_competition', *, support_filter=None):
        if method not in METHODS or color not in ('black', 'white'):
            raise ValueError('Unsupported method/color')
        self.before, self.color, self.method = tuple(before), color, method
        # Offline experiments may only reduce support. Keep original readings,
        # histories, temporal gates and capture/turn checks authoritative.
        self.support_filter = support_filter
        self.histories = {}
        self.last_time = None
        self.gap_review = False
        self.no_move_run = []

    @staticmethod
    def qualified(run):
        return (len(run) >= PROTOCOL['minimumWitnesses']
                and run[-1]['capturedAt']-run[0]['capturedAt'] >= PROTOCOL['minimumWitnessSeconds'])

    def step(self, view):
        if len(view.raw) != len(self.before) or len(view.appearance) != len(self.before):
            raise ValueError('Mismatched board dimensions')
        if self.last_time is not None and view.time <= self.last_time:
            raise ValueError('Capture timestamps must increase')
        gap = view.gap_before or (self.last_time is not None and view.time-self.last_time > PROTOCOL['maximumGap'])
        self.last_time = view.time
        self.gap_review |= gap
        image_usable = view.hand is False and not view.lighting_blocked and not gap
        reasons = []
        if view.hand is not False:
            reasons.append('hand obstructed or unavailable')
        if view.lighting_blocked:
            reasons.append('lighting/exposure unavailable')
        if self.gap_review:
            reasons.append('camera gap requires a new trusted context')
        if any(old != 'empty' and r['occupancy'] != old for old, r in zip(self.before, view.raw)):
            reasons.append('retained stone changed; capture or occlusion requires existing resolver')
        if not image_usable:
            for history in self.histories.values():
                history.run.clear()

        candidates, present = [], set()
        for point, (old, reading, appearance) in enumerate(zip(self.before, view.raw, view.appearance)):
            color = reading['occupancy']
            if old != 'empty' or color not in ('black', 'white'):
                continue
            key = (point, color)
            present.add(key)
            stamp = {'frame': view.frame, 'capturedAt': view.time}
            history = self.histories.setdefault(key, History(dict(stamp)))
            raw, strength, weight = candidate_weight(reading, appearance, self.method)
            if self.support_filter is not None:
                filtered = self.support_filter(view, point, weight)
                if not math.isfinite(filtered) or not 0 <= filtered <= weight:
                    raise ValueError('Support filter may only reduce finite support')
                weight = filtered
            supported = image_usable and weight >= PROTOCOL['minimumIndependentSupport']
            evidence = {**stamp, 'rawConfidence': reading['confidence'], 'weight': weight,
                        'appearanceStrength': strength, 'imageUsable': image_usable,
                        'supported': supported}
            history.evidence.append(evidence)
            if supported:
                if history.first_supported is None:
                    history.first_supported = dict(stamp)
                history.run.append(evidence)
                history.run[:] = history.run[-12:]
            else:
                history.run.clear()
            if color != self.color:
                reasons.append('opposite-color addition; single-placement assumption unsupported')
            candidates.append({'point': point, 'color': color, 'rawSupport': raw,
                               'appearanceStrength': strength, 'appearanceUnknown': strength is None,
                               'weight': weight, 'qualified': self.qualified(history.run),
                               'firstSeen': history.first_seen,
                               # Keep first-ever evidence for diagnosis, but a
                               # vanished/weak/occluded candidate cannot lend
                               # its timestamp to a later supported run.
                               'firstSupportedEver': history.first_supported,
                               'firstSupported': ({'frame': history.run[0]['frame'],
                                                   'capturedAt': history.run[0]['capturedAt']}
                                                  if history.run else None),
                               'witnesses': [{'frame': e['frame'], 'capturedAt': e['capturedAt']} for e in history.run]})
        for key, history in self.histories.items():
            if key not in present:
                history.run.clear()

        alternatives = [c for c in candidates if c['color'] == self.color]
        total = PROTOCOL['noMoveWeight']+sum(c['weight'] for c in alternatives)
        null_share = PROTOCOL['noMoveWeight']/total
        for c in candidates:
            c['share'] = c['weight']/total if c['color'] == self.color else None
        ranked = sorted(alternatives, key=lambda c: (-c['share'], c['point']))
        selected = None
        if not reasons:
            if self.method.endswith('_independent'):
                eligible = [c for c in alternatives if c['qualified']]
                if len(eligible) == 1:
                    selected = eligible[0]
            elif ranked:
                best = ranked[0]
                runner = max(null_share, ranked[1]['share'] if len(ranked) > 1 else 0.)
                if (best['qualified'] and best['share'] >= PROTOCOL['winnerShare']
                        and best['share']-runner >= PROTOCOL['winnerMargin']):
                    selected = best

        # A large null share alone is NOT positive evidence of an unchanged
        # board. Weak candidates and unseen intersections yield unknown.
        no_move_evidence = not reasons and not candidates and all(
            old != 'empty' or unchanged(r, a) for old, r, a in zip(self.before, view.raw, view.appearance))
        if no_move_evidence:
            self.no_move_run.append({'frame': view.frame, 'capturedAt': view.time})
            self.no_move_run[:] = self.no_move_run[-12:]
        else:
            self.no_move_run.clear()
        state = 'placement' if selected else ('no_move' if self.qualified(self.no_move_run) else 'unknown')
        return {'state': state, 'selected': selected['point'] if selected else None,
                'color': self.color if selected else None,
                'confirmedAt': {'frame': view.frame, 'capturedAt': view.time} if selected else None,
                'firstSeen': selected['firstSeen'] if selected else None,
                'firstSupported': selected['firstSupported'] if selected else None,
                'witnesses': selected['witnesses'] if selected else [],
                'candidates': candidates, 'noMoveShare': null_share,
                'noMoveHasPositiveEvidence': no_move_evidence, 'reasons': sorted(set(reasons)),
                'recordedFrameTiming': view.recorded_timing,
                'clockAuthority': False, 'conditionalOn': 'supplied prior position and at most one new placement'}

    def evidence(self):
        return [{'point': point, 'color': color, 'firstSeen': h.first_seen,
                 'firstSupported': h.first_supported, 'observations': h.evidence}
                for (point, color), h in sorted(self.histories.items())]
