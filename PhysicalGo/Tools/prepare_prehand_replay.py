#!/usr/bin/env python3
"""Cache causal pixel features for conditional turn replays of a preserved game.

The saved sequence supplies test contexts, NOT pixel labels or recognition input.
Only previously image-reviewed endpoints are labeled. Timing is never ground truth.
"""
import argparse
import gzip
import json
from pathlib import Path

import numpy as np

from fresh_game_confidence import ordered_readings, positions
from local_quality_lab import digest, read_image
from outline_sampling_experiment import eligible
from placement_competition_lab import appearance_features
from recognition_parameter_search import write_json
from unchanged_baseline_lab import Observation, Sampler, features
from unavailable_shadow_lab import measured_contrast


def load_game(snapshot):
    frames, operations = {}, {}
    for line in (snapshot/'capture/events.jsonl').open():
        d = json.loads(line)
        if d['event'] == 'frame':
            frames[d['frameID']] = d
        elif d['event'] == 'operation finished':
            operations[d['frameID']] = d
    signature = json.loads(next((snapshot/'recording').glob('*.pending.json')).read_text())['signature']
    size, tokens = signature.split(':', 1)
    assert int(size) == 19
    moves = []
    for token in filter(None, tokens.split(';')):
        color, xy = token.split(':')
        x, y = map(int, xy.split(','))
        moves.append((color, y*19+x))
    accepted = {}
    for line in next((snapshot/'recording').glob('*.observations.jsonl')).open():
        d = json.loads(line)
        if d['event'].startswith('accepted'):
            for t in d.get('moveTimings', []):
                accepted[t['moveNumber']] = {**t, 'recognizedAt': d['uptime']}
    return frames, operations, moves, accepted


def main(args):
    if args.output.resolve().is_relative_to(Path(__file__).resolve().parents[2]):
        raise ValueError('Use external storage')
    args.output.mkdir(parents=True, exist_ok=False)
    frames, operations, moves, accepted = load_game(args.snapshot)
    states, captures = positions(moves)
    labels = json.loads(args.labels.read_text())
    source = args.snapshot/'capture/events.jsonl'
    assert labels['sourceEventsSHA256'] == digest(source)
    # Reviewed endpoint frames come from the preparer's proposals; labels are
    # joined by frame/point, not inferred from saved move count.
    proposals = json.loads((args.prepared/'review-proposals.json').read_text())
    reviewed = {(r['frame'], r['point']): r['truth'] for r in labels['points']}
    endpoints = {r['move']: r for r in proposals if r['kind'] == 'placement-after'}
    contexts = []
    for n, (color, point) in enumerate(moves, 1):
        a, endpoint = accepted[n], endpoints[n]
        assert reviewed[(endpoint['frame'], point)] == color
        onset = a.get('candidateHistory', {}).get('firstAppearanceAt')
        if onset is None:
            onset = a['recognizedAt']-a.get('seconds', 1)
        contexts.append({'id': f'move-{n}', 'move': n, 'before': states[n-1], 'color': color,
            'expected': point, 'firstAt': onset-.8,
            'lastAt': max(a['recognizedAt']+.5, frames[endpoint['frame']]['captureUptime']+.3),
            'reviewedEndpoint': endpoint['frame'], 'capture': next((c for c in captures if c['move'] == n), None),
            'scope': 'Supplied prior position and bounded window; not independent chronology or a full-game decoder.'})
    if args.edge_labels:
        edge_labels = json.loads(args.edge_labels.read_text())
        assert edge_labels['sourceEventsSHA256'] == digest(source)
        for frame in sorted({r['frame'] for r in edge_labels['points']}):
            stamp, count = frames[frame]['captureUptime'], frames[frame]['recorder']['moveCount']
            contexts.append({'id': f'edge-{frame}', 'before': states[count], 'color': 'black' if count%2 == 0 else 'white',
                'expected': None, 'reviewedEmpty': [r['point'] for r in edge_labels['points'] if r['frame'] == frame],
                'reviewedEndpoint': frame, 'firstAt': stamp-.8, 'lastAt': stamp+2.5,
                'scope': 'Only the specified empty point/frame pairs are reviewed truth.'})
    write_json(args.output/'contexts.json', contexts)
    write_json(args.output/'plan.json', {'status': 'OFFLINE CONDITIONAL REPLAY', 'snapshot': str(args.snapshot),
        'images': 'Original camera images, current-frame outlines and original earlier reference only.',
        'contexts': 'Saved game supplies prior board/turn and test windows. No labels used in feature computation.',
        'emptyAppearance': 'Unmeasured empty points remain unknown; no no-move or baseline-learning claim.',
        'sparseFeatureScope': 'All stone candidates at empty points in any active supplied context, plus reviewed endpoints.'})
    sampler, references, processed = None, {}, 0
    inputs = {source, args.labels, args.prepared/'review-proposals.json', Path(__file__)}
    inputs.update((args.snapshot/'recording').iterdir())
    if args.edge_labels:
        inputs.add(args.edge_labels)
    with gzip.open(args.output/'observations.jsonl.gz', 'wt') as stream:
        for frame, op in sorted(operations.items()):
            meta = frames[frame]
            readings = op.get('unadaptedReadings') or op.get('readings', [])
            if len(readings) != 361:
                continue
            raw, stamp = ordered_readings(readings), meta['captureUptime']
            active = [c for c in contexts if c['firstAt'] <= stamp <= c['lastAt']]
            needed = {p for c in active for p, r in enumerate(raw)
                      if c['before'][p] == 'empty' and r['occupancy'] in ('black', 'white')}
            row = {'frame': frame, 'capturedAt': stamp, 'availableAt': op['uptime'],
                'hand': op.get('handOutline', {}).get('obstructed'),
                'lightingBlocked': bool(op.get('lightingBlocked') or op.get('exposureFailure') or
                    op['outcome'] not in ('delivered to recorder', 'hand over board; waiting for clear frame')),
                'outcome': op['outcome'], 'raw': [[r['occupancy'], r['confidence']] for r in raw],
                'shapes': op.get('footprints', [])+op.get('placementFits', []),
                'original': {}, 'outline_mask': {}, 'recordedTiming': op.get('clockPressEstimate'),
                'contexts': [c['id'] for c in active]}
            if needed:
                path, reference = args.snapshot/'capture'/meta['image'], args.snapshot/'capture'/meta['referenceImage']
                current = read_image(path, op['calibration'])
                key = (str(reference), json.dumps(meta['referenceCalibration'], sort_keys=True))
                if key not in references:
                    references[key] = read_image(reference, meta['referenceCalibration'])
                old = references[key]
                inputs.update((path, reference))
                if sampler is None:
                    sampler = Sampler(current[0].shape)
                flat = np.where(current[1], current[0], np.nan).ravel()
                old_flat = np.where(old[1], old[0], np.nan).ravel()
                shapes = eligible(row['shapes'])
                for p in sorted(needed):
                    core, wood = sampler.core[p], sampler.wood[p]
                    y, x = np.divmod(wood, current[0].shape[1])
                    x, y = x/24-1.5, y/24-1.5
                    excluded = np.zeros(len(wood), dtype=bool)
                    for s in shapes:
                        excluded |= ((x-s['center']['x'])/(s['radiusCol']+.08))**2+((y-s['center']['y'])/(s['radiusRow']+.08))**2 <= 1
                    for variant, index in [('original', wood), ('outline_mask', wood[~excluded])]:
                        metric = features([flat[core]], [flat[index]], [old_flat[core]], [old_flat[index]])
                        obs = Observation(frame, stamp, False, False, [], [flat[core]], metric)
                        appearance = appearance_features(obs, [old_flat[core]])[0]
                        appearance['measuredCoreDelta'] = measured_contrast(flat[core], old_flat[core], appearance)
                        row[variant][p] = appearance
            stream.write(json.dumps(row)+'\n')
            processed += 1
            if processed%200 == 0:
                print(f'{processed} analyzed frames cached', flush=True)
    inputs.update(Path(__file__).with_name(n) for n in ('outline_sampling_experiment.py', 'unchanged_baseline_lab.py',
        'local_quality_lab.py', 'placement_competition_lab.py', 'unavailable_shadow_lab.py'))
    write_json(args.output/'manifest.json', {'inputs': {str(p): digest(p) for p in sorted(inputs)},
                                           'analyzedFrames': processed, 'contexts': len(contexts), 'clockAuthority': False})
    print(f'Completed {processed} frames, {len(contexts)} contexts')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('snapshot', 'labels', 'prepared', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--edge-labels', type=Path)
    main(parser.parse_args())
