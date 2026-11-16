#!/usr/bin/env python3
"""Offline, non-authoritative local quality and single-placement competition.

Dependencies: numpy, opencv-python. Never modifies source captures or app state.
Scores are heuristic rankings, not calibrated probabilities or clock evidence.
"""
import argparse
import hashlib
import json
from pathlib import Path

import cv2
import numpy as np

PROTOCOL = {
    'version': 1, 'pixelsPerInterval': 24, 'margin': 1.5,
    'woodExclusionRadius': .57, 'ringInner': .65, 'ringOuter': 1.35,
    'minimumWoodPixels': 80, 'darkeningStart': .025, 'darkeningScale': .12,
    'changeStart': .015, 'changeScale': .10,
    'residualStart': .02, 'residualScale': .12,
    'poorQuality': .4, 'weakConfidence': .97,
    'nullWeight': .25, 'winnerShare': .6, 'winnerMargin': .25,
    'maximumFrameGap': .5, 'recoveryFrames': 3, 'recoverySeconds': .4,
}


def rectify(image, calibration):
    size = calibration['size']
    scale, margin = PROTOCOL['pixelsPerInterval'], PROTOCOL['margin']
    side = round((size - 1 + 2 * margin) * scale) + 1
    y, x = np.mgrid[:side, :side].astype(np.float32)
    u, v = (x / scale - margin) / (size - 1), (y / scale - margin) / (size - 1)
    h = calibration['h']
    denominator = h[6] * u + h[7] * v + 1
    mx = (h[0] * u + h[1] * v + h[2]) / denominator * (image.shape[1] - 1)
    my = (h[3] * u + h[4] * v + h[5]) / denominator * (image.shape[0] - 1)
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY).astype(np.float32) / 255
    value = cv2.remap(gray, mx, my, cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT)
    valid = (mx >= 0) & (my >= 0) & (mx < image.shape[1] - 1) & (my < image.shape[0] - 1)
    return value, valid


def geometry(shape, size):
    y, x = np.mgrid[:shape[0], :shape[1]]
    scale, margin = PROTOCOL['pixelsPerInterval'], PROTOCOL['margin']
    x, y = x / scale - margin, y / scale - margin
    # Exclude EVERY potential stone body, independent of predictions or labels.
    wood = ((x - np.rint(x)) ** 2 + (y - np.rint(y)) ** 2 > PROTOCOL['woodExclusionRadius'] ** 2)
    wood &= (x >= 0) & (y >= 0) & (x <= size - 1) & (y <= size - 1)
    rings = []
    for point in range(size * size):
        d = (x - point % size) ** 2 + (y - point // size) ** 2
        rings.append(wood & (d >= PROTOCOL['ringInner'] ** 2) & (d <= PROTOCOL['ringOuter'] ** 2))
    return wood, rings


def quality(current, reference, geometry_masks, previous=None):
    image, valid = current
    anchor, anchor_valid = reference
    wood, rings = geometry_masks
    valid = valid & anchor_valid
    logratio = np.log(np.maximum(image, .03)) - np.log(np.maximum(anchor, .03))
    if (wood & valid).sum() < PROTOCOL['minimumWoodPixels']:
        return ([{'quality': None, 'woodPixels': 0, 'reason': 'insufficient visible background'} for _ in rings], None)
    global_shift = float(np.median(logratio[wood & valid]))
    relative = logratio - global_shift
    residual = np.abs(image - np.clip(anchor * np.exp(global_shift), 0, 1))
    temporal = None if previous is None else np.abs(image - previous[0])
    results = []
    for mask in rings:
        mask = mask & valid
        count = int(mask.sum())
        if count < PROTOCOL['minimumWoodPixels']:
            results.append({'quality': None, 'woodPixels': count, 'reason': 'insufficient visible background'})
            continue
        dark = max(0., -float(np.median(relative[mask])))
        texture = float(np.quantile(residual[mask], .8))
        change = None
        if temporal is not None:
            temporal_mask = mask & previous[1]
            if temporal_mask.sum() >= PROTOCOL['minimumWoodPixels']:
                change = float(np.quantile(temporal[temporal_mask], .8))
        penalties = [max(0., (dark - PROTOCOL['darkeningStart']) / PROTOCOL['darkeningScale']),
                     max(0., (texture - PROTOCOL['residualStart']) / PROTOCOL['residualScale'])]
        if change is not None:
            penalties.append(max(0., (change - PROTOCOL['changeStart']) / PROTOCOL['changeScale']))
        results.append({'quality': max(0., 1 - max(penalties)), 'woodPixels': count,
                        'relativeDarkening': dark, 'backgroundResidual': texture,
                        'temporalChange': change})
    return results, global_shift


def compete(readings, estimates, baseline, expected_color, hand, continuous):
    """Conditional alternatives for ONE placement; never a sequence decoder.

    Do not infer captures or multi-turn catch-up from a normalized winner.
    A persistent alternative is retained in output, never erased by competition.
    """
    candidates = []
    reasons = []
    if hand is not False:
        reasons.append('hand blocked or gate unavailable')
    if not continuous:
        reasons.append('camera interval not continuous')
    for i, (reading, old, estimate) in enumerate(zip(readings, baseline, estimates)):
        value = reading['occupancy']
        if old != 'empty':
            if value != old:
                reasons.append('retained stone changed; capture/occlusion needs separate handling')
            continue
        if value not in ('black', 'white'):
            continue
        if value != expected_color:
            reasons.append('opposite-color addition; single-placement assumption unsupported')
            continue
        evidence = max(0., (reading['confidence'] - .5) / .5) ** 4
        q = estimate['quality']
        candidates.append({'point': i, 'confidence': reading['confidence'], 'quality': q,
                           'independentWeight': evidence, 'weight': evidence * (q if q is not None else 0.)})
    total = PROTOCOL['nullWeight'] + sum(x['weight'] for x in candidates)
    for candidate in candidates:
        candidate['share'] = candidate['weight'] / total
    ranked = sorted(candidates, key=lambda x: (-x['share'], x['point']))
    null_share = PROTOCOL['nullWeight'] / total
    winner = ranked[0] if ranked else None
    runner = max(null_share, ranked[1]['share'] if len(ranked) > 1 else 0.)
    selected = None
    if not reasons and winner and winner['share'] >= PROTOCOL['winnerShare'] and winner['share'] - runner >= PROTOCOL['winnerMargin']:
        selected = winner['point']
    return {'candidates': candidates, 'noMoveOrUnknownShare': null_share, 'selected': selected,
            'abstentionReasons': sorted(set(reasons)), 'conditionalOn': 'at most one new placement of the expected color',
            'meaning': 'relative heuristic support, not calibrated probability'}


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_image(path, calibration):
    image = cv2.imread(str(path))
    if image is None:
        raise ValueError(f'Unreadable image: {path}')
    return rectify(image, calibration)


def tally(truth, predictions):
    result = dict(correct=0, falseStone=0, missedStone=0, wrongColor=0, uncertain=0)
    for expected, predicted in zip(truth, predictions):
        if expected == predicted:
            result['correct'] += 1
        elif predicted not in ('empty', 'black', 'white'):
            result['uncertain'] += 1
        elif expected == 'empty':
            result['falseStone'] += 1
        elif predicted == 'empty':
            result['missedStone'] += 1
        else:
            result['wrongColor'] += 1
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--corpus', type=Path, required=True, help='Prior recognizer-comparison corpus')
    parser.add_argument('--sequence', type=Path, required=True, help='RapidReplyShadow/sequence.json')
    parser.add_argument('--labels', type=Path, default=Path(__file__).with_name('local_quality_labels.json'))
    parser.add_argument('--output', type=Path, required=True, help='New folder outside repository')
    args = parser.parse_args()
    if args.output.exists() or args.output.resolve().is_relative_to(Path(__file__).resolve().parents[2]):
        parser.error('Use a new output folder outside the repository')
    args.output.mkdir(parents=True)
    labels = json.loads(args.labels.read_text())
    frames = {str(x['frameID']): x for x in json.loads(args.sequence.read_text())['frames']}
    manifest = {'protocol': PROTOCOL, 'programSHA256': digest(__file__), 'labelsSHA256': digest(args.labels),
                'sequenceSHA256': digest(args.sequence), 'inputs': [], 'runtime': {'numpy': np.__version__, 'opencv': cv2.__version__},
                'authority': 'offline only; no recorder, clock, capture, classifier output or source image is modified'}
    output, comparisons = [], []
    for dataset in ('static', 'timeline'):
        directory = args.corpus if dataset == 'static' else args.corpus / 'timeline'
        boards = json.loads((directory / 'boards.json').read_text())
        baseline = {x['board']: x['readings'] for x in json.loads((directory / 'baseline.json').read_text())}
        for path in (directory / 'boards.json', directory / 'baseline.json'):
            manifest['inputs'].append({'path': str(path), 'sha256': digest(path)})
        previous, previous_time, anchor, masks = None, None, None, None
        streaks = [[] for _ in range(361)]
        for board in boards:
            if dataset == 'static' and board.get('group') == 'incident':
                continue  # Same photos occur in timeline; never double-count.
            size = board['calibration']['size']
            if size != 19:
                raise ValueError('This initial evaluation protocol expects 19x19 boards')
            image = read_image(board['image'], board['calibration'])
            manifest['inputs'].append({'path': board['image'], 'sha256': digest(board['image'])})
            if dataset == 'static':
                anchor = read_image(board['reference'], board['referenceCalibration'])
                manifest['inputs'].append({'path': board['reference'], 'sha256': digest(board['reference'])})
            elif anchor is None:
                anchor = image  # Fixed causal baseline, never future/label-selected frames.
            if masks is None:
                masks = geometry(image[0].shape, size)
            frame = frames.get(board['id'], {}) if dataset == 'timeline' else {}
            now = frame.get('capturedAt')
            continuous = now is not None and previous_time is not None and 0 < now - previous_time <= PROTOCOL['maximumFrameGap']
            estimates, exposure = quality(image, anchor, masks, previous if continuous else None)
            hand = frame.get('handObstructed')
            for point, estimate in enumerate(estimates):
                if not continuous or hand is not False or estimate['quality'] is None or estimate['quality'] < .8:
                    streaks[point] = []
                else:
                    streaks[point].append(now)
                times = streaks[point]
                estimate['backgroundRecovered'] = bool(len(times) >= PROTOCOL['recoveryFrames'] and times[-1] - times[0] >= PROTOCOL['recoverySeconds'])
                estimate['shadowClearance'] = 'unknown'  # Recovery of sampled wood is not proof that a hand shadow has gone.
            readings = baseline[board['id']]
            counterfactual = [r['occupancy'] if not (r['occupancy'] in ('black', 'white') and r['confidence'] < PROTOCOL['weakConfidence']
                              and q['quality'] is not None and q['quality'] < PROTOCOL['poorQuality']) else 'uncertain'
                              for r, q in zip(readings, estimates)]
            entry = {'dataset': dataset, 'board': board['id'], 'captureTime': now, 'handObstructed': hand,
                     'globalLogExposureShift': exposure, 'rawReadings': readings, 'localQuality': estimates,
                     'recordedDecision': frame or None, 'weakDemotionCounterfactual': counterfactual}
            if dataset == 'timeline':
                episode = next((e for e in labels['episodes'] if e['first'] <= int(board['id']) <= e['last']), None)
                if episode:
                    before = ['empty'] * 361
                    for color, points in episode['before'].items():
                        for point in points:
                            before[point] = color
                    entry['placementCompetition'] = compete(readings, estimates, before, episode['color'], hand, continuous)
                    entry['competitionWithoutQuality'] = compete(readings, [{'quality': 1.} for _ in readings], before, episode['color'], hand, continuous)
                    entry['episodeBaseline'] = before
            output.append(entry)
            truth = board['expected'] if dataset == 'static' else None
            annotation = labels['timelineTruth'].get(board['id']) if dataset == 'timeline' else None
            if annotation:
                truth = ['empty'] * 361
                for color in ('black', 'white'):
                    for point in annotation[color]:
                        truth[point] = color
            if truth:
                if 'placementCompetition' in entry:
                    true_additions = [i for i, (a, b) in enumerate(zip(entry['episodeBaseline'], truth)) if a == 'empty' and b != 'empty']
                    entry['competitionEvaluation'] = {'trueAdditions': true_additions}
                    for method in ('competitionWithoutQuality', 'placementCompetition'):
                        choice = entry[method]['selected']
                        entry['competitionEvaluation'][method] = ('abstain' if choice is None else 'correct' if true_additions == [choice] else 'wrong')
                comparisons.append({'dataset': dataset, 'board': board['id'],
                                    'baseline': tally(truth, [r['occupancy'] for r in readings]),
                                    'weakDemotion': tally(truth, counterfactual)})
            # Only recorded analyzed frames establish continuity. Unanalyzed images
            # can be inspected, but must not manufacture temporal support.
            if now is not None:
                previous, previous_time = image, now
    summary = {'promotion': 'NOT PROMOTED: descriptive pilot; no clock or capture timing validation for counterfactual decisions',
               'frames': len(output), 'comparisons': comparisons, 'totals': {}}
    for dataset in ('static', 'timeline'):
        subset = [r for r in comparisons if r['dataset'] == dataset]
        summary['totals'][dataset] = {'labeledFrames': len(subset)}
        for method in ('baseline', 'weakDemotion'):
            summary['totals'][dataset][method] = {key: sum(r[method][key] for r in subset) for key in ('correct', 'falseStone', 'missedStone', 'wrongColor', 'uncertain')}
    evaluated = [entry['competitionEvaluation'] for entry in output if 'competitionEvaluation' in entry]
    summary['conditionalPlacementCompetition'] = {
        method: {outcome: sum(row[method] == outcome for row in evaluated) for outcome in ('correct', 'wrong', 'abstain')}
        for method in ('competitionWithoutQuality', 'placementCompetition')}
    summary['conditionalPlacementCompetition']['scope'] = 'Selected 16 labeled timeline frames; repeated views of three placements. This is not live-recorder accuracy, independent games, or clock timing.'
    for name, value in [('observations', output), ('summary', summary), ('manifest', manifest)]:
        (args.output / f'{name}.json').write_text(json.dumps(value, indent=2, allow_nan=False) + '\n')
    print(json.dumps({'frames': len(output), 'totals': summary['totals'], 'promotion': summary['promotion']}, indent=2))


if __name__ == '__main__':
    main()
