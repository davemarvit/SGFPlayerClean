#!/usr/bin/env python3
"""Offline unchanged-board reference experiment. Never imports or controls the app.

Requires numpy and opencv-python. Actual captured pixels are used unchanged;
missed-hand/delayed-hand/gap scenarios modify delivery metadata only.
"""
import argparse
from collections import Counter
from dataclasses import dataclass
import json
from pathlib import Path

import cv2
import numpy as np

from local_quality_lab import PROTOCOL as RECTIFICATION, read_image, tally, digest

# Frozen before outcome inspection. Not fitted to the labeled frames.
PROTOCOL = dict(version=2, seedFrame=306, maximumGap=.5, coreRadius=.32,
                woodInner=.60, woodOuter=1.30, stoneExclusion=.55,
                minimumWoodPixels=12, minimumCoreCoverage=.9,
                coreError=.045, woodError=.035, minimumGain=.5, maximumGain=1.6,
                stableGainRange=.035, learningFrames=4, learningSeconds=.6,
                quarantineSeconds=.8, emptyWitnesses=3, emptySeconds=.4)
METHODS = ('fixed_reference', 'no_hand_only', 'no_interaction_since_seed', 'guarded_fixed', 'guarded_adaptive')
INITIAL = {'black': [262, 280, 282, 300], 'white': [60, 72]}


def occupancy(points):
    values = ['empty'] * 361
    for color, indexes in points.items():
        for point in indexes:
            values[point] = color
    return values


class Sampler:
    def __init__(self, shape, size=19):
        y, x = np.mgrid[:shape[0], :shape[1]]
        x = x / RECTIFICATION['pixelsPerInterval'] - RECTIFICATION['margin']
        y = y / RECTIFICATION['pixelsPerInterval'] - RECTIFICATION['margin']
        wood = ((x-np.rint(x))**2 + (y-np.rint(y))**2 > PROTOCOL['stoneExclusion']**2)
        wood &= (x >= 0) & (y >= 0) & (x <= size-1) & (y <= size-1)
        self.core, self.wood = [], []
        for point in range(size*size):
            radius = (x-point % size)**2 + (y-point // size)**2
            self.core.append(np.flatnonzero(radius <= PROTOCOL['coreRadius']**2))
            self.wood.append(np.flatnonzero(wood & (radius >= PROTOCOL['woodInner']**2) & (radius <= PROTOCOL['woodOuter']**2)))

    def sample(self, frame):
        image, valid = frame
        flat = np.where(valid, image, np.nan).ravel()
        return [flat[index].copy() for index in self.core], [flat[index].copy() for index in self.wood]


def residual(a, b):
    finite = np.isfinite(a) & np.isfinite(b)
    if finite.sum() < PROTOCOL['minimumCoreCoverage'] * len(a):
        return float('inf')
    return float(np.quantile(np.abs(a[finite]-b[finite]), .8))


def features(core, wood, anchor_core, anchor_wood):
    rows = []
    for current, background, old, old_background in zip(core, wood, anchor_core, anchor_wood):
        valid = np.isfinite(background) & np.isfinite(old_background) & (old_background > .03)
        if valid.sum() < PROTOCOL['minimumWoodPixels']:
            rows.append({'gain': None, 'coreError': None, 'woodError': None, 'woodPixels': int(valid.sum())})
            continue
        gain = float(np.median(background[valid] / old_background[valid]))
        error = residual(current, old*gain)
        rows.append({'gain': gain, 'coreError': error if np.isfinite(error) else None,
                     'woodError': float(np.quantile(np.abs(background[valid]-old_background[valid]*gain), .8)),
                     'woodPixels': int(valid.sum())})
    return rows


def compatible(feature):
    return (feature['gain'] is not None and feature['coreError'] is not None
            and PROTOCOL['minimumGain'] <= feature['gain'] <= PROTOCOL['maximumGain']
            and feature['coreError'] <= PROTOCOL['coreError']
            and feature['woodError'] <= PROTOCOL['woodError'])


@dataclass
class Observation:
    frame: int
    time: float
    hand: object
    lighting_blocked: bool
    raw: list
    core: list
    metrics: list


class Baseline:
    """Versioned appearance references; expected occupancy never changes.

    The guarded learner may update illumination at independently matching empty
    points while other points are frozen. It never learns a new core texture or
    accepts a move/capture. Labels are not available to this class.
    """
    def __init__(self, method, seed, expected):
        self.method, self.expected = method, tuple(expected)
        self.anchor = [a.copy() for a in seed.core]
        self.versions = [[{'at': seed.time, 'frame': seed.frame, 'gain': 1., 'core': a.copy(), 'witnesses': [seed.frame]}]
                         for a in seed.core]
        self.pending = [[] for _ in expected]
        self.witnesses = [[] for _ in expected]
        self.last = seed.time
        self.serial = 0
        self.interaction_seen = False

    def step(self, observation):
        o = observation
        continuous = 0 < o.time-self.last <= PROTOCOL['maximumGap']
        self.last = o.time
        blocked = o.hand is not False or o.lighting_blocked
        # A missing established stone could be a capture, hand, or camera shift.
        context_ok = all(old == 'empty' or (r['occupancy'] == old and r['confidence'] >= .9)
                         for old, r in zip(self.expected, o.raw))
        if blocked or not continuous or not context_ok:
            self.interaction_seen = True
        interval_untrusted = self.method == 'no_interaction_since_seed' and self.interaction_seen
        events, support = [], []
        if blocked or not continuous or not context_ok or interval_untrusted:
            self.pending = [[] for _ in self.expected]
            self.witnesses = [[] for _ in self.expected]
            if o.hand is not False or not continuous:
                # Revoke recently activated adaptations, not original evidence.
                for point, versions in enumerate(self.versions):
                    while len(versions) > 1 and o.time-versions[-1]['at'] <= PROTOCOL['quarantineSeconds']:
                        removed = versions.pop()
                        events.append({'type': 'rollback', 'point': point, 'version': removed['version'],
                                       'reason': 'hand/unknown gate or camera gap'})
            return {'emptySupport': [], 'updates': events, 'blocked': True,
                    'reasons': [name for name, value in [('hand or unknown gate', blocked), ('camera gap', not continuous), ('established position changed', not context_ok), ('no uninterrupted unchanged interval since seed', interval_untrusted)] if value]}

        for point, (raw, core, metric, old) in enumerate(zip(o.raw, o.core, o.metrics, self.expected)):
            if old != 'empty':
                continue
            version = self.versions[point][-1]
            matches = residual(core, version['core']) <= PROTOCOL['coreError']
            if self.method in ('guarded_fixed', 'guarded_adaptive'):
                matches = matches and compatible(metric)
            run = self.witnesses[point]
            if matches:
                run.append((o.time, o.frame))
                run[:] = run[-12:]
                if len(run) >= PROTOCOL['emptyWitnesses'] and o.time-run[0][0] >= PROTOCOL['emptySeconds']:
                    support.append(point)
            else:
                run.clear()

            if self.method in ('fixed_reference', 'guarded_fixed'):
                continue
            # Decisions above always precede learning from this observation.
            eligible = self.method in ('no_hand_only', 'no_interaction_since_seed') or compatible(metric)
            pending = self.pending[point]
            if not eligible:
                pending.clear()
                continue
            gain = metric['gain'] if metric['gain'] is not None else 1.
            if pending and self.method == 'guarded_adaptive' and abs(gain-pending[0]['gain']) > PROTOCOL['stableGainRange']:
                pending.clear()
            pending.append({'at': o.time, 'frame': o.frame, 'gain': gain, 'core': core.copy()})
            if len(pending) < PROTOCOL['learningFrames'] or o.time-pending[0]['at'] < PROTOCOL['learningSeconds']+PROTOCOL['quarantineSeconds']:
                continue
            matured = [p for p in pending if o.time-p['at'] >= PROTOCOL['quarantineSeconds']]
            if len(matured) < PROTOCOL['learningFrames'] or matured[-1]['at']-matured[0]['at'] < PROTOCOL['learningSeconds']:
                continue
            new_gain = float(np.median([p['gain'] for p in matured]))
            new_core = (self.anchor[point]*new_gain if self.method == 'guarded_adaptive'
                        else np.median(np.stack([p['core'] for p in matured]), axis=0))
            self.serial += 1
            new = {'at': o.time, 'frame': o.frame, 'gain': new_gain, 'core': new_core,
                   'version': self.serial, 'witnesses': [p['frame'] for p in matured]}
            self.versions[point].append(new)
            events.append({'type': 'adaptation', 'point': point, 'version': self.serial, 'gain': new_gain,
                           'witnesses': new['witnesses'], 'sourceTimes': [p['at'] for p in matured]})
            pending.clear()
            # New reference needs fresh witnesses; old support cannot certify it.
            self.witnesses[point].clear()
        return {'emptySupport': support, 'updates': events, 'blocked': False, 'reasons': []}


def scenarios(observations):
    yield 'recorded', observations, {'description': 'Unmodified pixels, gates and capture timestamps'}
    ranges = {'white8': (317, 332), 'black9': (344, 353), 'white10': (358, 366)}
    def copy(o, hand):
        return Observation(o.frame, o.time, hand, o.lighting_blocked, o.raw, o.core, o.metrics)
    yield 'all_hands_missed', [copy(o, False) for o in observations], {'description': 'Every detected hand suppressed; pixels and timestamps unchanged'}
    yield 'unknown_hand', [copy(o, None) for o in observations], {'description': 'No hand-tracker result; must not treat unavailable as clear'}
    for name, (first, last) in ranges.items():
        yield f'missed_hand_{name}', [copy(o, False if first <= o.frame <= last else o.hand) for o in observations], {'description': f'Hand flags suppressed only for frames {first}–{last}'}
        kept = [o for o in observations if not first <= o.frame <= last]
        yield f'camera_gap_{name}', kept, {'description': f'Frames {first}–{last} withheld; original timestamps retained', 'omittedFrames': [o.frame for o in observations if first <= o.frame <= last]}
    kept = [copy(o, False) for o in observations if not any(a <= o.frame <= b for a, b in ranges.values())]
    yield 'all_gaps_and_missed_hands', kept, {'description': 'All three placement intervals withheld and remaining hand flags suppressed; timestamps retained'}
    delayed = []
    for o in observations:
        earlier = [p for p in observations if p.time <= o.time-.6]
        delayed.append(copy(o, earlier[-1].hand if earlier else None))
    yield 'hand_signal_delayed_600ms', delayed, {'description': 'Only hand metadata delayed 0.6 s; current images and timestamps unchanged'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--corpus', type=Path, required=True)
    parser.add_argument('--sequence', type=Path, required=True)
    parser.add_argument('--labels', type=Path, default=Path(__file__).with_name('local_quality_labels.json'))
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists() or args.output.resolve().is_relative_to(Path(__file__).resolve().parents[2]):
        parser.error('Choose a new report folder outside the repository')
    args.output.mkdir(parents=True)
    boards_file, raw_file = args.corpus/'timeline/boards.json', args.corpus/'timeline/baseline.json'
    boards = {int(b['id']): b for b in json.loads(boards_file.read_text())}
    readings = {int(b['board']): b['readings'] for b in json.loads(raw_file.read_text())}
    frames = json.loads(args.sequence.read_text())['frames']
    source_paths = [Path(__file__), Path(__file__).with_name('local_quality_lab.py'), args.sequence, args.labels, boards_file, raw_file]
    manifest = {'protocol': PROTOCOL, 'initialPosition': INITIAL, 'inputs': [], 'scenarios': {},
                'scope': 'Offline pilot. A single trusted initial position, not per-frame truth. No moves, clocks, captures or live baselines are changed.',
                'runtime': {'numpy': np.__version__, 'opencv': cv2.__version__}}
    observations, sampler, anchor = [], None, None
    for frame in frames:
        frame_id = frame['frameID']
        if frame_id < PROTOCOL['seedFrame']:
            continue
        board = boards[frame_id]
        image = read_image(board['image'], board['calibration'])
        source_paths.append(Path(board['image']))
        if sampler is None:
            if frame_id != PROTOCOL['seedFrame']:
                raise ValueError('Missing designated seed frame')
            sampler = Sampler(image[0].shape)
            anchor = sampler.sample(image)
        core, wood = sampler.sample(image)
        observations.append(Observation(frame_id, frame['capturedAt'], frame.get('handObstructed'), frame.get('lightingBlocked', False),
                                        readings[frame_id], core, features(core, wood, *anchor)))
    with (args.output/'evidence.jsonl').open('w') as stream:
        for o in observations:
            stream.write(json.dumps({'frame': o.frame, 'capturedAt': o.time, 'recordedHand': o.hand,
                                     'lightingBlocked': o.lighting_blocked, 'rawReadings': o.raw, 'imageFeatures': o.metrics}, allow_nan=False)+'\n')
    # Labels enter scoring only. No frame truth is passed to the estimator.
    labels = {int(k): occupancy(v) for k, v in
              ((k, {color: row[color] for color in ('black', 'white')}) for k, row in json.loads(args.labels.read_text())['timelineTruth'].items())}
    expected = occupancy(INITIAL)
    summary = {'promotion': 'OFFLINE ONLY: no production integration authorized by this experiment', 'scenarios': {}}
    for name, sequence, description in scenarios(observations):
        manifest['scenarios'][name] = description
        case = {'deliveredFrames': len(sequence), 'labeledFrames': sum(o.frame in labels for o in sequence[1:]), 'methods': {}}
        for method in METHODS:
            estimator = Baseline(method, sequence[0], expected)
            stats = Counter()
            true_points_suppressed = set()
            details = []
            with (args.output/f'{name}-{method}.jsonl').open('w') as stream:
                for o in sequence[1:]:
                    result = estimator.step(o)
                    prediction = [r['occupancy'] for r in o.raw]
                    changes = []
                    for point in result['emptySupport']:
                        if prediction[point] != 'empty':
                            changes.append(point)
                            prediction[point] = 'empty'
                    row = {'frame': o.frame, 'capturedAt': o.time, 'scenarioHand': o.hand,
                           'result': result, 'counterfactual': prediction, 'changedPoints': changes}
                    stats['adaptations'] += sum(e['type'] == 'adaptation' for e in result['updates'])
                    stats['rollbacks'] += sum(e['type'] == 'rollback' for e in result['updates'])
                    stats['blockedFrames'] += result['blocked']
                    if o.frame in labels:
                        truth = labels[o.frame]
                        original = tally(truth, [r['occupancy'] for r in o.raw])
                        revised = tally(truth, prediction)
                        for key in original:
                            stats['raw_'+key] += original[key]
                            stats['counterfactual_'+key] += revised[key]
                        harmed = [p for p in changes if truth[p] != 'empty']
                        # Count evidence against real placements even if raw reading
                        # already said empty; do not hide preexisting classifier misses.
                        absorbed = [p for p in result['emptySupport'] if truth[p] != 'empty']
                        stats['realStoneEmptySupport'] += len(absorbed)
                        stats['newlySuppressedRealStoneReadings'] += len(harmed)
                        true_points_suppressed.update(absorbed)
                        details.append({'frame': o.frame, 'raw': original, 'counterfactual': revised,
                                        'changedPoints': changes, 'realStoneEmptySupport': absorbed})
                        row['evaluation'] = details[-1]
                    stream.write(json.dumps(row, allow_nan=False)+'\n')
            case['methods'][method] = {'counts': dict(stats), 'realStonePointsSuppressed': sorted(true_points_suppressed), 'labeledDetails': details}
        summary['scenarios'][name] = case
    for path in sorted(set(source_paths)):
        manifest['inputs'].append({'path': str(path), 'sha256': digest(path)})
    for name, document in [('summary', summary), ('manifest', manifest)]:
        (args.output/f'{name}.json').write_text(json.dumps(document, indent=2, allow_nan=False)+'\n')
    print(json.dumps({name: {method: value['counts'] for method, value in case['methods'].items()}
                      for name, case in summary['scenarios'].items()}, indent=2))


if __name__ == '__main__':
    main()
