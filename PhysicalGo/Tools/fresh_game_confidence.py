#!/usr/bin/env python3
"""Prepare image-reviewable, OFFLINE confidence evidence from a saved game.

The game record proposes samples; it never supplies verified truth. No app
imports, clock commands, capture mutations, or automatic model promotion.
"""
import argparse
from collections import Counter
import json
from pathlib import Path

import cv2
import numpy as np

from local_quality_lab import digest, read_image
from placement_competition_lab import appearance_features
from recognition_parameter_search import live_fingerprint, write_json
from unchanged_baseline_lab import Observation, Sampler, features


def ordered_readings(readings, size=19):
    result = [None] * (size * size)
    for r in readings:
        point = r['row'] * size + r['col']
        if not 0 <= point < len(result) or result[point] is not None:
            raise ValueError('Invalid/duplicate reading')
        result[point] = r
    if any(r is None for r in result):
        raise ValueError('Incomplete readings')
    return result


def positions(moves, size=19):
    """Replay supplied moves only to propose review locations, including captures."""
    board = ['empty'] * (size * size)
    states = [list(board)]
    captures = []

    def neighbors(p):
        return [q for q in (p-size, p+size, p-1, p+1)
                if 0 <= q < len(board) and abs(q % size-p % size)+abs(q // size-p // size) == 1]

    def group(start):
        found, todo, liberties = set(), [start], set()
        while todo:
            p = todo.pop()
            if p in found:
                continue
            found.add(p)
            for q in neighbors(p):
                if board[q] == 'empty':
                    liberties.add(q)
                elif board[q] == board[p] and q not in found:
                    todo.append(q)
        return found, liberties

    for n, (color, point) in enumerate(moves, 1):
        if color not in ('black', 'white') or board[point] != 'empty':
            raise ValueError('Unsupported/invalid supplied move')
        board[point] = color
        removed = set()
        for q in neighbors(point):
            if board[q] not in ('empty', color):
                stones, liberties = group(q)
                if not liberties:
                    removed.update(stones)
                    for p in stones:
                        board[p] = 'empty'
        if not group(point)[1]:
            raise ValueError('Suicide in supplied record')
        states.append(list(board))
        if removed:
            captures.append({'move': n, 'points': sorted(removed)})
    return states, captures


def contact_sheets(rows, images, output, prefix):
    """Unaltered grayscale crops, nearest-neighbor enlarged; no predicted overlays."""
    for start in range(0, len(rows), 40):
        batch = rows[start:start+40]
        sheet = np.full((int(np.ceil(len(batch)/5))*146, 5*168), 245, np.uint8)
        for i, row in enumerate(batch):
            p, frame = row['point'], row['frame']
            x, y = round((p % 19+1.5)*24), round((p // 19+1.5)*24)
            crop = images[frame][y-18:y+19, x-18:x+19]
            crop = cv2.resize(crop, (111, 111), interpolation=cv2.INTER_NEAREST)
            top, left = i//5*146, i % 5*168
            sheet[top+32:top+143, left+26:left+137] = crop
            cv2.putText(sheet, row['id'], (left+3, top+12), cv2.FONT_HERSHEY_SIMPLEX, .34, 0, 1)
            cv2.putText(sheet, f"f{frame} p{p}", (left+3, top+27), cv2.FONT_HERSHEY_SIMPLEX, .34, 0, 1)
        cv2.imwrite(str(output/f'{prefix}-{start//40+1:02d}.png'), sheet)


def prepare(snapshot, output):
    if output.exists():
        raise ValueError('Use a new output directory')
    root = Path(__file__).resolve().parents[1]
    if output.resolve().is_relative_to(root.parent):
        raise ValueError('Use external output storage')
    output.mkdir(parents=True)
    source_hash = live_fingerprint(root)
    write_json(output/'plan.json', {
        'version': 1, 'status': 'OFFLINE ONLY', 'liveSourceBefore': source_hash,
        'sampling': 'First delivered clear analyzed frame at each saved move count 0..65. Each move point reviewed at previous and current count; all stone predictions conflicting with supplied count also reviewed.',
        'truth': 'SGF/pending proposes locations only. Explicit image-reviewed labels required for scoring.',
        'comparison': 'Frozen raw and Black-shadow support; score correctness only where visually labeled. Correlated methods, not independent votes.',
        'calibration': 'Fit only previously reviewed older data. Fresh session held out. Equal weight per session/point/color/truth episode; no adjacent-frame random split. Confidence-only and confidence-plus-shadow controls.',
        'safeguards': 'No live deployment or timestamp/clock/capture changes. Point correctness is not move-time accuracy. Capture labels separate.',
    })
    capture = snapshot/'capture'
    frames, operations = {}, {}
    events_path = capture/'events.jsonl'
    for line in events_path.open():
        event = json.loads(line)
        if event['event'] == 'frame':
            frames[event['frameID']] = event
        elif event['event'] == 'operation finished':
            operations[event['frameID']] = event
    pending = next((snapshot/'recording').glob('*.pending.json'))
    signature = json.loads(pending.read_text())['signature']
    size, tokens = signature.split(':', 1)
    if int(size) != 19:
        raise ValueError('This pilot requires 19x19')
    moves = []
    for token in tokens.split(';'):
        if not token:
            continue
        color, xy = token.split(':')
        x, y = map(int, xy.split(','))
        moves.append((color, y*19+x))
    states, captures = positions(moves)
    selected = {}
    for frame, op in sorted(operations.items()):
        count = frames[frame]['recorder']['moveCount']
        if (count not in selected and op['outcome'] == 'delivered to recorder'
                and not op.get('lightingBlocked', False) and len(op.get('readings', [])) == 361):
            selected[count] = frame
    if set(selected) != set(range(len(moves)+1)):
        raise ValueError('Missing clear samples at some move counts; review sampling manually')
    inputs = {events_path, pending, Path(__file__)} | set((snapshot/'recording').iterdir())
    inputs.update(Path(__file__).with_name(name) for name in (
        'local_quality_lab.py', 'unchanged_baseline_lab.py', 'placement_competition_lab.py',
        'placement_competition_protocol.json', 'recognition_parameter_search.py'))
    evidence, review, images, references = {}, [], {}, {}
    for count, frame in sorted(selected.items()):
        op, meta = operations[frame], frames[frame]
        path, reference = capture/meta['image'], capture/meta['referenceImage']
        reference_key = (str(reference), json.dumps(meta['referenceCalibration'], sort_keys=True))
        current = read_image(path, op['calibration'])
        sampler = Sampler(current[0].shape)
        if reference_key not in references:
            references[reference_key] = sampler.sample(read_image(reference, meta['referenceCalibration']))
        old_core, old_wood = references[reference_key]
        core, wood = sampler.sample(current)
        source = 'unadaptedReadings' if op.get('unadaptedReadings') else 'readings'
        readings = ordered_readings(op[source])
        observation = Observation(frame, meta['captureUptime'], False, False, readings, core,
                                  features(core, wood, old_core, old_wood))
        appearance = appearance_features(observation, old_core)
        images[frame] = np.rint(current[0]*255).astype(np.uint8)
        evidence[frame] = {'frame': frame, 'capturedAt': meta['captureUptime'],
                           'savedMoveCount': count, 'rawReadings': readings, 'readingSource': source,
                           'appearance': appearance, 'recordedOperation': op,
                           'image': str(path), 'referenceImage': str(reference)}
        inputs.update((path, reference))
    def add(identifier, move, frame, point, proposed, kind):
        review.append({'id': identifier, 'move': move, 'frame': frame, 'point': point,
                       'proposedTruth': proposed, 'truth': None, 'kind': kind,
                       'provenance': 'UNREVIEWED; proposal from saved record only'})
    for n, (color, point) in enumerate(moves, 1):
        add(f'm{n:02d}-before', n, selected[n-1], point, 'empty', 'placement-before')
        add(f'm{n:02d}-after', n, selected[n], point, color, 'placement-after')
    for capture_event in captures:
        n = capture_event['move']
        for point in capture_event['points']:
            for count, kind in ((max(0, n-2), 'earlier'), (n-1, 'before'), (n, 'after')):
                add(f'capture{n}-{kind}', n, selected[count], point, states[count][point], 'capture-'+kind)
    for count, frame in sorted(selected.items()):
        for p, reading in enumerate(evidence[frame]['rawReadings']):
            if reading['occupancy'] in ('black', 'white') and reading['occupancy'] != states[count][p]:
                if not any(r['frame'] == frame and r['point'] == p for r in review):
                    add(f'extra-{frame}-{p}', count, frame, p, states[count][p], 'record-disagreement')
    write_json(output/'review-proposals.json', review)
    write_json(output/'sampling.json', {'selectedFrames': selected, 'moves': moves, 'captures': captures})
    with (output/'evidence.jsonl').open('w') as stream:
        for e in evidence.values():
            stream.write(json.dumps(e, allow_nan=False)+'\n')
    contact_sheets(review, images, output, 'review')
    write_json(output/'manifest.json', {'inputs': [{'path': str(p.resolve()), 'sha256': digest(p)} for p in sorted(inputs)],
                                      'liveSourcesUnchanged': source_hash == live_fingerprint(root),
                                      'reviewedLabels': 0})
    print(json.dumps({'frames': len(evidence), 'proposals': len(review), 'kinds': Counter(r['kind'] for r in review)}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    cv2.setNumThreads(1)
    prepare(args.snapshot, args.output)
