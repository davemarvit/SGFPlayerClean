#!/usr/bin/env python3
"""Inventory every analyzed frame and clock boundary without treating SGF as truth.

Outputs are offline review proposals. A disagreement with the saved position
may be an early real move, a prisoner awaiting removal, a shadow, or an error.
"""
import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path

import numpy as np

from fresh_game_confidence import ordered_readings, positions, contact_sheets
from local_quality_lab import digest, read_image
from recognition_parameter_search import write_json
from evaluate_unavailable_shadow import Pixels, point_scores
from placement_competition_lab import appearance_features
from unchanged_baseline_lab import Observation, features


def percentiles(values):
    return dict(zip(('minimum', 'median', 'p90', 'p99', 'maximum'),
                    map(float, np.quantile(values, [0, .5, .9, .99, 1])))) if values else {}


def audit(snapshot, output, labels_path=None):
    if output.resolve().is_relative_to(Path(__file__).resolve().parents[2]):
        raise ValueError('Use external output storage')
    output.mkdir(parents=True, exist_ok=False)
    source = snapshot/'capture/events.jsonl'
    frames, operations, starts, events = {}, {}, {}, Counter()
    for line in source.open():
        d = json.loads(line)
        events[d['event']] += 1
        if d['event'] == 'frame':
            frames[d['frameID']] = d
        elif d['event'] == 'operation finished':
            operations[d['frameID']] = d
        elif d['event'] == 'operation started':
            starts[d['frameID']] = d
    pending = next((snapshot/'recording').glob('*.pending.json'))
    size, signature = json.loads(pending.read_text())['signature'].split(':', 1)
    if size != '19':
        raise ValueError('19x19 only')
    moves = []
    for item in filter(None, signature.split(';')):
        color, xy = item.split(':')
        x, y = map(int, xy.split(','))
        moves.append((color, y*19+x))
    states, captures = positions(moves)
    recorded = defaultdict(list)
    for number, move in enumerate(moves, 1):
        recorded[move].append(number)
    journal_path = next((snapshot/'recording').glob('*.observations.jsonl'))
    journal = [json.loads(line) for line in journal_path.open()]
    accepted = {t['moveNumber']: {'processedAt': d.get('uptime'), **t}
                for d in journal if d['event'] == 'accepted move' for t in d.get('moveTimings', [])}
    clock_path = next((snapshot/'recording').glob('*.clock.json'))
    clock = json.loads(clock_path.read_text())
    evidence = {e['number']: e for e in clock['pressEvidence']}
    timing = []
    for move in clock['moves']:
        n, estimate, anchor = move['number'], move.get('estimate'), move['after'].get('anchor')
        state = ('no-estimate' if estimate is None else 'no-running-anchor' if anchor is None else
                 'applied' if abs(anchor-estimate['time']) < 1e-6 else 'estimate-not-applied')
        a = accepted.get(n, {})
        timing.append({'move': n, 'color': 'black' if move['black'] else 'white', 'state': state,
                       'estimate': estimate, 'appliedBoundary': anchor,
                       'pressEvidenceApplied': evidence.get(n, {}).get('applied'),
                       'recognizedAt': a.get('processedAt'), 'recognitionDelay': a.get('seconds'),
                       'timingScope': a.get('timingScope'),
                       'candidateHistory': a.get('candidateHistory'),
                       'before': move['before'], 'after': move['after']})
    write_json(output/'move-timing-ledger.json', timing)
    episodes, active, frame_rows = [], {}, []
    previous = None
    with (output/'candidate-observations.jsonl').open('w') as stream:
        for frame, op in sorted(operations.items()):
            meta = frames[frame]
            readings = op.get('unadaptedReadings') or op.get('readings', [])
            if len(readings) != 361:
                continue
            raw = ordered_readings(readings)
            count, stamp = meta['recorder']['moveCount'], meta['captureUptime']
            clear = (op['outcome'] == 'delivered to recorder' and
                     op.get('handOutline', {}).get('obstructed') is False and
                     not op.get('lightingBlocked') and not op.get('exposureFailure'))
            candidates, current_keys = [], set()
            for point, reading in enumerate(raw):
                color = reading['occupancy']
                if color not in ('black', 'white') or color == states[count][point]:
                    continue
                future = [n for n in recorded[(color, point)] if n > count]
                relation = ('future-recorded' if future else 'previously-recorded' if recorded[(color, point)] else 'never-recorded')
                item = {'point': point, 'color': color, 'confidence': reading['confidence'],
                        'relation': relation, 'futureMove': min(future) if future else None,
                        'savedOccupancy': states[count][point]}
                candidates.append(item)
                key = (point, color, relation)
                current_keys.add(key)
                if key not in active or stamp-active[key]['lastAt'] > .65:
                    ep = {'id': len(episodes)+1, 'point': point, 'color': color, 'relation': relation,
                          'firstFrame': frame, 'firstAt': stamp, 'frames': [], 'clearFrames': [],
                          'strongClearFrames': [], 'maximumConfidence': 0}
                    active[key] = ep
                    episodes.append(ep)
                ep = active[key]
                ep.update(lastFrame=frame, lastAt=stamp)
                ep['frames'].append(frame)
                ep['maximumConfidence'] = max(ep['maximumConfidence'], reading['confidence'])
                if clear:
                    ep['clearFrames'].append(frame)
                    if reading['confidence'] >= .9:
                        ep['strongClearFrames'].append(frame)
            active = {k: v for k, v in active.items() if k in current_keys}
            row = {'frame': frame, 'capturedAt': stamp, 'processedAt': op.get('recorderUptime'),
                   'operationFinishedAt': op['uptime'],
                   'savedMoveCount': count, 'clear': clear, 'hand': op.get('handOutline', {}).get('obstructed'),
                   'lightingBlocked': bool(op.get('lightingBlocked') or op.get('exposureFailure')),
                   'outcome': op['outcome'], 'candidates': candidates,
                   'uncertainPoints': [p for p, r in enumerate(raw) if r['occupancy'] == 'uncertain'],
                   'ageAtRecorder': (op.get('recorderUptime') or op['uptime'])-stamp,
                   'callbackSeconds': op['uptime']-(op.get('recorderUptime') or op['uptime']),
                   'operationSeconds': op['uptime']-starts.get(frame, op)['uptime'],
                   'analyzedCaptureGap': None if previous is None else stamp-previous}
            previous = stamp
            stream.write(json.dumps(row)+'\n')
            frame_rows.append(row)
    for ep in episodes:
        ep['duration'] = ep['lastAt']-ep['firstAt']
    write_json(output/'candidate-episodes.json', episodes)
    # Prioritize novel, strong clear-view contradictions. They remain unlabeled.
    ranked = sorted((e for e in episodes if e['relation'] == 'never-recorded' and e['strongClearFrames']),
                    key=lambda e: (-len(e['strongClearFrames']), -e['duration'], e['id']))
    proposals, images = [], {}
    for ep in ranked[:40]:
        frame = ep['strongClearFrames'][len(ep['strongClearFrames'])//2]
        if frame not in images:
            meta = frames[frame]
            gray, _ = read_image(snapshot/'capture'/meta['image'], operations[frame]['calibration'])
            images[frame] = np.rint(gray*255).astype(np.uint8)
        proposals.append({'id': f"episode-{ep['id']}", 'episode': ep['id'], 'frame': frame,
                          'point': ep['point'], 'truth': None, 'kind': 'unreviewed-conflict',
                          'proposedColor': ep['color'], 'clearSamples': len(ep['strongClearFrames'])})
    write_json(output/'review-proposals.json', proposals)
    contact_sheets(proposals, images, output, 'review')
    hand_entries = [r for r in frame_rows if r['hand'] is True]
    temporal = []
    for proposal in proposals:
        frame = proposal['frame']
        stamp = frames[frame]['captureUptime']
        following = next((r for r in hand_entries if r['capturedAt'] > stamp), None)
        temporal.append({**proposal, 'capturedAt': stamp,
                         'nextDetectedHandFrame': following['frame'] if following else None,
                         'secondsUntilDetectedHand': following['capturedAt']-stamp if following else None,
                         'retrospectiveEvidenceAvailableBy': following['operationFinishedAt'] if following else None,
                         'caution': 'Future hand evidence is unavailable to the original frame decision.'})
    write_json(output/'prehand-candidates.json', temporal)
    if labels_path:
        labels = json.loads(labels_path.read_text())
        if labels['sourceEventsSHA256'] != digest(source):
            raise ValueError('Labels belong to another capture')
        truth = {(r['frame'], r['point']): r['truth'] for r in labels['points']}
        pixels, reviewed, prepared_rows = Pixels(), [], {}
        for proposal in proposals:
            frame, point = proposal['frame'], proposal['point']
            if (frame, point) not in truth:
                continue
            op, meta = operations[frame], frames[frame]
            image, reference = snapshot/'capture'/meta['image'], snapshot/'capture'/meta['referenceImage']
            core, wood, _ = pixels.samples(image, op['calibration'])
            old_core, old_wood = pixels.reference(reference, meta['referenceCalibration'])
            observation = Observation(frame, meta['captureUptime'], False, False, [], core, features(core, wood, old_core, old_wood))
            appearance = appearance_features(observation, old_core)
            augmented = pixels.augment(image, op['calibration'], reference, meta['referenceCalibration'], appearance)
            reading = ordered_readings(op.get('unadaptedReadings') or op['readings'])[point]
            reviewed.append({'case': 'reviewed-edge-85', 'frame': frame, 'point': point,
                             'truth': truth[(frame, point)], 'kind': 'reviewed-edge', 'reading': reading,
                             'appearance': augmented[point], 'shapes': op.get('footprints', [])+op.get('placementFits', [])})
            prepared_rows[frame] = {'frame': frame, 'capturedAt': meta['captureUptime'], 'recordedOperation': op,
                                    'image': str(image), 'referenceImage': str(reference),
                                    'referenceCalibration': meta['referenceCalibration']}
        write_json(output/'reviewed-point-evidence.json', reviewed)
        write_json(output/'reviewed-point-scores.json', point_scores(reviewed))
        with (output/'evidence.jsonl').open('w') as stream:
            for row in prepared_rows.values():
                stream.write(json.dumps(row)+'\n')
    summary = {
        'status': 'OFFLINE DIAGNOSTIC; record disagreements are NOT truth labels',
        'events': dict(events), 'frames': len(frames), 'analyzedFrames': len(operations),
        'inventoriedFrames': len(frame_rows), 'moves': len(moves), 'captures': captures,
        'journalEvents': dict(Counter(d['event'] for d in journal)),
        'timingStates': dict(Counter(t['state'] for t in timing)),
        'noEstimateMoves': [t['move'] for t in timing if t['state'] == 'no-estimate'],
        'estimateMethods': dict(Counter(t['estimate']['method'] for t in timing if t['estimate'])),
        'recognitionDelayByScope': {scope: percentiles([t['recognitionDelay'] for t in timing if t['timingScope'] == scope and t['recognitionDelay'] is not None])
                                    for scope in {t['timingScope'] for t in timing if t['timingScope']}},
        'frameMetrics': {name: percentiles([r[name] for r in frame_rows if r[name] is not None]) for name in
                         ('ageAtRecorder', 'operationSeconds', 'callbackSeconds', 'analyzedCaptureGap')},
        'clearFrames': sum(r['clear'] for r in frame_rows),
        'candidateEpisodesByRelation': dict(Counter(e['relation'] for e in episodes)),
        'strongClearNeverRecordedEpisodes': len(ranked),
        'reviewProposals': len(proposals), 'clockAuthority': False,
        'limitations': ['Correlated frames are not independent trials.', 'No fitted probability or verified full-game chronology.',
                        'No-estimate does not mean no timestamp: inspect fallback anchors separately.',
                        'Operation duration includes recorder callback and diagnostic work; it is not isolated vision inference time.']}
    write_json(output/'summary.json', summary)
    input_paths = [source, pending, clock_path, journal_path, Path(__file__)] + ([labels_path] if labels_path else [])
    write_json(output/'manifest.json', {'inputs': {str(p): digest(p) for p in input_paths},
                                      'imagesCoveredBy': str(snapshot/'preservation.json')})
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--labels', type=Path)
    args = parser.parse_args()
    audit(args.snapshot, args.output, args.labels)
