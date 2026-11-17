#!/usr/bin/env python3
"""Causal pending-evidence experiment, separate from all production decisions."""
import json
import math
from pathlib import Path

from outline_sampling_experiment import eligible
from placement_competition_lab import PlacementCompetition
from unavailable_shadow_lab import assess

PROTOCOL = json.loads(Path(__file__).with_name('prehand_protocol.json').read_text())


def edge(point, size=19):
    return min(point % size, point // size, size-1-point % size, size-1-point // size) <= PROTOCOL['edgeWidth']


class PreHandCompetition:
    def __init__(self, before, color, policy='control', shapes=None):
        if policy not in PROTOCOL['policies']:
            raise ValueError('Unknown policy')
        self.policy, self.shapes = policy, shapes or {}
        self.before, self.color = tuple(before), color
        self.size = round(len(before)**.5)
        self.outlined = {frame: {s['row']*self.size+s['col'] for s in eligible(values)}
                         for frame, values in self.shapes.items()}
        self.ledger, self.revisions, self.decisions, self.committed = [], [], [], set()
        self.last_time = None
        self.epoch = 0
        self.last_available = None
        self.model = PlacementCompetition(before, color, 'black_shadow_independent', support_filter=self.filter)

    def has_outline(self, frame, point):
        return point in self.outlined.get(frame, ())

    def filter(self, view, point, weight):
        value = assess('contrast_black', point, view.raw[point], view.appearance[point], self.shapes.get(view.frame, []), self.size)['support']
        if (self.policy in ('edge_shape', 'combined') and view.raw[point]['occupancy'] == 'black'
                and edge(point, self.size) and not self.has_outline(view.frame, point)):
            return 0.
        return min(weight, value)

    def step(self, view, available_at=None):
        available_at = view.time if available_at is None else available_at
        if not math.isfinite(view.time) or not math.isfinite(available_at):
            raise ValueError('Evidence timestamps must be finite')
        if available_at < view.time:
            raise ValueError('Evidence cannot arrive before capture')
        if self.last_time is not None and view.time <= self.last_time:
            raise ValueError('Capture times must increase')
        if self.last_available is not None and available_at < self.last_available:
            raise ValueError('Delivery times must not go backwards')
        gap = view.gap_before or (self.last_time is not None and view.time-self.last_time > .5)
        self.last_time = view.time
        self.last_available = available_at
        if gap:
            self.epoch += 1
        retro = self.policy.startswith('retro_') or self.policy == 'combined'
        if retro and view.hand is True and not gap:
            for item in self.ledger:
                key = (item['point'], item['color'])
                if (key in self.committed or item['discounted'] or not item['usable'] or item['color'] != 'black' or item['epoch'] != self.epoch
                        or not 0 <= view.time-item['capturedAt'] <= PROTOCOL['lookbackSeconds']):
                    continue
                if self.policy != 'retro_all' and not edge(item['point'], self.size):
                    continue
                if self.policy in ('retro_edge_shape', 'combined') and item['outline']:
                    continue
                # The original reading/weight/timestamp and all already emitted
                # decisions remain intact. This is a new revision, not hindsight.
                item['discounted'] = True
                self.revisions.append({'point': item['point'], 'sourceFrame': item['frame'],
                    'sourceCapturedAt': item['capturedAt'], 'handFrame': view.frame,
                    'handCapturedAt': view.time, 'availableAt': available_at,
                    'originalWeight': item['weight'], 'effectiveWeight': 0.,
                    'reason': 'subsequent hand entry; pending dark evidence', 'provesEmpty': False})
        result = self.model.step(view)
        for candidate in result['candidates']:
            self.ledger.append({'point': candidate['point'], 'color': candidate['color'], 'frame': view.frame,
                                'capturedAt': view.time, 'rawReading': dict(view.raw[candidate['point']]),
                                'epoch': self.epoch,
                                'weight': candidate['weight'], 'usable': view.hand is False and not view.lighting_blocked and not gap,
                                'outline': self.has_outline(view.frame, candidate['point']), 'discounted': False})
        if result['state'] == 'placement':
            self.committed.add((result['selected'], result['color']))
        self.decisions.append({'frame': view.frame, 'availableAt': available_at, 'result': result})
        return result
