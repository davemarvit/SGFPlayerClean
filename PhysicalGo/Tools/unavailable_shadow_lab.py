#!/usr/bin/env python3
"""Offline missing-shadow ablation. Never supplies clock or capture authority."""
import json
import math
from pathlib import Path
from types import MappingProxyType

import numpy as np

from placement_competition_lab import PROTOCOL as PLACEMENT, candidate_weight

PROTOCOL = MappingProxyType(json.loads(Path(__file__).with_name('unavailable_shadow_protocol.json').read_text()))
POLICIES = tuple(PROTOCOL['policies'])


def measured_contrast(core, reference, appearance):
    """Retain measured contrast even when background residual invalidates it.

    This does NOT make signedCoreDelta available or assert a statistical bound.
    The caller must account for the background mismatch separately.
    """
    gain = appearance.get('gain')
    finite = np.isfinite(core) & np.isfinite(reference)
    if (gain is None or not math.isfinite(gain)
            or not PLACEMENT['minimumGain'] <= gain <= PLACEMENT['maximumGain']
            or not len(core) or finite.sum() < .9*len(core)):
        return None
    return float(np.median(core[finite]-gain*reference[finite]))


def missing_reasons(appearance):
    if appearance['signedCoreDelta'] is not None:
        return []
    reasons = []
    gain, wood = appearance.get('gain'), appearance.get('woodError')
    if appearance.get('woodPixels', 0) < 12:
        reasons.append('insufficient background samples')
    if gain is None or not math.isfinite(gain) or not PLACEMENT['minimumGain'] <= gain <= PLACEMENT['maximumGain']:
        reasons.append('background gain unavailable/outside bounds')
    if wood is None or not math.isfinite(wood) or wood > PLACEMENT['maximumWoodError']:
        reasons.append('background does not match reference')
    core_error = appearance.get('coreError')
    if core_error is None or not math.isfinite(core_error):
        reasons.append('core coverage unavailable')
    return reasons or ['core contrast unavailable']


def outline_witness(point, shapes, size=19):
    """Current-frame disk fit, not a tracked or previously accepted stone."""
    for shape in shapes:
        if shape['row']*size+shape['col'] != point:
            continue
        values = [shape['quality'], shape['center']['x'], shape['center']['y']]
        if not all(math.isfinite(v) for v in values):
            continue
        if (shape['quality'] >= PROTOCOL['outlineMinimumQuality']
                and max(abs(shape['center']['x']-point % size),
                        abs(shape['center']['y']-point//size)) <= PROTOCOL['outlineMaximumAxisOffset']):
            return shape
    return None


def assess(policy, point, reading, appearance, shapes=(), size=19):
    if policy not in POLICIES:
        raise ValueError('Unknown policy')
    raw, strength, baseline = candidate_weight(reading, appearance, 'black_shadow_independent')
    missing = strength is None
    witness = outline_witness(point, shapes, size) if missing else None
    weight, reason = baseline, 'available appearance'
    if missing:
        reason = 'unavailable appearance retained by control'
        applies = policy == 'hold_all' or (policy in ('hold_black', 'outline_black', 'contrast_black') and reading['occupancy'] == 'black')
        if applies:
            measured = appearance.get('measuredCoreDelta')
            # Only background-residual failure is eligible. Missing coverage,
            # unstable gain or missing metrics remain unknown. This contrast
            # margin is a heuristic feature, not a calibrated probability.
            contrast = (policy == 'contrast_black'
                        and missing_reasons(appearance) == ['background does not match reference']
                        and measured is not None and math.isfinite(measured)
                        and appearance.get('woodError') is not None
                        and math.isfinite(appearance['woodError'])
                        and -measured-appearance['woodError'] >= PROTOCOL['contrastMargin'])
            if policy == 'outline_black' and witness is not None:
                reason = 'current-frame outline supports unavailable appearance'
            elif contrast:
                reason = 'center darkening exceeds background residual plus margin'
            else:
                weight, reason = 0., 'unavailable appearance held pending'
    return {'rawSupport': raw, 'baselineSupport': baseline, 'support': weight,
            'appearanceAvailable': not missing, 'missingReasons': missing_reasons(appearance),
            'outline': witness, 'reason': reason, 'clockAuthority': False}


class SupportFilter:
    def __init__(self, policy, shapes_by_frame, size=19):
        self.policy, self.shapes, self.size = policy, shapes_by_frame, size
        self.audit = []

    def __call__(self, view, point, weight):
        result = assess(self.policy, point, view.raw[point], view.appearance[point],
                        self.shapes.get(view.frame, ()), self.size)
        self.audit.append({'frame': view.frame, 'capturedAt': view.time, 'point': point, **result})
        # Compatible only with the frozen Black-shadow method; never amplify.
        return min(weight, result['support'])
