#!/usr/bin/env python3
"""Offline calibration pilot: P(raw stone reading is correct), not a clock model.

Only explicit reviewed labels enter scoring. Older cases fit the calibrators;
the fresh session only evaluates them. Scores from the two correlated methods
are features, never multiplied as independent probabilities.
"""
import argparse
from collections import Counter
import json
from pathlib import Path

import numpy as np

from local_quality_lab import digest
from placement_competition_lab import candidate_weight, PROTOCOL
from recognition_parameter_search import live_fingerprint, write_json
from unchanged_baseline_lab import INITIAL, occupancy


def row(session, frame, point, reading, appearance, truth, kind):
    predicted = reading['occupancy']
    stone = predicted in ('black', 'white')
    raw, strength, adjusted = candidate_weight(reading, appearance, 'black_shadow_independent') if stone else (None, None, None)
    return dict(session=session, frame=frame, point=point, truth=truth, predicted=predicted,
                confidence=reading['confidence'], correct=predicted == truth,
                rawSupport=raw, shadowSupport=adjusted, appearanceStrength=strength,
                appearanceAvailable=appearance['signedCoreDelta'] is not None,
                kind=kind, episode=f'{session}/{point}/{predicted}/{truth}')


def weights(rows):
    counts = Counter(r['episode'] for r in rows)
    return np.array([1/counts[r['episode']] for r in rows])


def design(rows, joint):
    values = []
    for r in rows:
        x = [1., r['confidence'], float(r['predicted'] == 'black')]
        if joint:
            x += [r['rawSupport']-r['shadowSupport'], float(not r['appearanceAvailable'])]
        values.append(x)
    return np.array(values, dtype=float)


def sigmoid(x):
    return 1/(1+np.exp(-np.clip(x, -35, 35)))


def fit(rows, joint=False, ridge=1.):
    if not rows or any(r['session'] == 'fresh-game' for r in rows):
        raise ValueError('Calibration needs older data only')
    if {r['correct'] for r in rows} != {False, True}:
        raise ValueError('Both correct and incorrect examples required')
    x, y, w = design(rows, joint), np.array([r['correct'] for r in rows], float), weights(rows)
    beta = np.zeros(x.shape[1])
    penalty = np.full(len(beta), ridge)
    penalty[0] = 0.

    def objective(b):
        z = x@b
        return float(np.sum(w*(np.logaddexp(0, z)-y*z))+.5*np.sum(penalty*b*b))

    converged = False
    for _ in range(100):
        p = sigmoid(x@beta)
        gradient = x.T@(w*(p-y))+penalty*beta
        hessian = x.T@((w*p*(1-p))[:, None]*x)+np.diag(penalty)
        step = np.linalg.solve(hessian+np.eye(len(beta))*1e-10, gradient)
        scale = 1.
        while objective(beta-scale*step) > objective(beta) and scale > 1e-8:
            scale *= .5
        beta -= scale*step
        if np.max(np.abs(scale*step)) < 1e-8:
            converged = True
            break
    if not converged:
        raise RuntimeError('Calibration fit did not converge')
    return {'joint': joint, 'ridge': ridge, 'coefficients': beta.tolist(),
            'fitEpisodes': len(set(r['episode'] for r in rows)), 'fitRows': len(rows),
            'fitSessions': sorted(set(r['session'] for r in rows)), 'converged': converged}


def predict(model, rows):
    return sigmoid(design(rows, model['joint'])@np.array(model['coefficients']))


def metrics(rows, probabilities):
    if not rows:
        return None
    p, y, w = np.array(probabilities), np.array([r['correct'] for r in rows], float), weights(rows)
    clipped = np.clip(p, 1e-6, 1-1e-6)
    bins = []
    for low, high in ((0, .5), (.5, .75), (.75, .9), (.9, .97), (.97, 1.000001)):
        mask = (p >= low) & (p < high)
        if mask.any():
            bins.append({'low': low, 'high': min(1, high), 'rows': int(mask.sum()),
                         'episodeWeight': float(w[mask].sum()),
                         'meanScore': float(np.average(p[mask], weights=w[mask])),
                         'fractionCorrect': float(np.average(y[mask], weights=w[mask]))})
    return {'rows': len(rows), 'episodes': len(set(r['episode'] for r in rows)),
            'wrongRows': int((1-y).sum()), 'meanScore': float(np.average(p, weights=w)),
            'fractionCorrect': float(np.average(y, weights=w)),
            'brier': float(np.average((p-y)**2, weights=w)),
            'logLossClippedAt1eMinus6': float(np.average(-y*np.log(clipped)-(1-y)*np.log(1-clipped), weights=w)),
            'wrongRowsAtLeastPoint97': int(((p >= .97) & (y == 0)).sum()), 'reliabilityBins': bins}


def older_rows(previous, corpus):
    here = Path(__file__).parent
    labels = json.loads((here/'local_quality_labels.json').read_text())['timelineTruth']
    photos = {b['id']: b for b in json.loads((corpus/'boards.json').read_text()) if b['group'] != 'incident'}
    appearances = {}
    for line in (previous/'appearance-evidence.jsonl').open():
        a = json.loads(line)
        appearances[(a['case'], a.get('frame', 1))] = a['appearance']
    rows = []
    for line in (previous/'observations.jsonl').open():
        o = json.loads(line)
        case, frame = o['case'], o['frame']
        if case == 'rapid-recorded':
            if str(frame) not in labels or frame == 306 or o['hand'] is not False or o['lightingBlocked']:
                continue
            truth = occupancy({c: labels[str(frame)][c] for c in ('black', 'white')})
            eligible = [p for p, color in enumerate(occupancy(INITIAL)) if color == 'empty']
            session = 'older-rapid'
        elif case in photos and frame == 1:
            truth = photos[case]['expected']
            eligible = range(361)
            session = 'older-'+photos[case]['group'].replace('-empty', '')
        else:
            continue
        for point in eligible:
            reading = o['rawReadings'][point]
            if reading['occupancy'] in ('black', 'white'):
                rows.append(row(session, f'{case}:{frame}', point, reading,
                                appearances[(case, frame)][point], truth[point], 'previously-reviewed'))
    return rows


def fresh_rows(prepared, labels_path):
    labels = json.loads(labels_path.read_text())
    if labels['status'] != 'image-reviewed-point-labels':
        raise ValueError('Explicit image review required')
    manifest = json.loads((prepared/'manifest.json').read_text())
    event_hashes = [item['sha256'] for item in manifest['inputs'] if item['path'].endswith('/capture/events.jsonl')]
    if event_hashes != [labels.get('sourceEventsSHA256')]:
        raise ValueError('Labels belong to a different source capture')
    evidence = {d['frame']: d for d in map(json.loads, (prepared/'evidence.jsonl').open())}
    result, seen = [], set()
    for label in labels['points']:
        frame, point = label['frame'], label['point']
        if (frame, point) in seen:
            raise ValueError('Duplicate labeled observation')
        seen.add((frame, point))
        if label['truth'] not in ('empty', 'black', 'white') or not label.get('provenance'):
            raise ValueError('Unreviewed/invalid truth')
        d = evidence[frame]
        r = row('fresh-game', frame, point, d['rawReadings'][point], d['appearance'][point], label['truth'], label['kind'])
        r.update(id=label['id'], capturedAt=d['capturedAt'], proposedTruth=label['proposedTruth'])
        result.append(r)
    return result


def run(previous, corpus, prepared, labels, output):
    root = Path(__file__).resolve().parents[1]
    if output.exists() or output.resolve().is_relative_to(root.parent):
        raise ValueError('Use a new external output folder')
    output.mkdir(parents=True)
    live_before = live_fingerprint(root)
    training, fresh = older_rows(previous, corpus), fresh_rows(prepared, labels)
    stones = [r for r in fresh if r['predicted'] in ('black', 'white')]
    models = {name: fit(training, joint) for name, joint in (('confidence_and_color', False), ('plus_shadow_evidence', True))}
    write_json(output/'frozen-calibrators.json', models)
    summaries = {}
    for name, rows in (('olderDevelopment', training), ('freshStoneReadings', stones)):
        summaries[name] = {'nativeScoreAsProbabilityDiagnostic': metrics(rows, [r['confidence'] for r in rows]),
                           **{key: metrics(rows, predict(model, rows)) for key, model in models.items()}}
        for key, model in models.items():
            for r, value in zip(rows, predict(model, rows)):
                r[key] = float(value)
    for name, rows in (('older-rows', training), ('fresh-rows', fresh)):
        write_json(output/(name+'.json'), rows)
    support = {}
    for name, key in (('native', 'rawSupport'), ('blackShadow', 'shadowSupport')):
        after = [r for r in fresh if r['kind'] == 'placement-after']
        support[name] = {'reviewedAfterPlacementPoints': len(after),
                         'correctStoneReadings': sum(r['correct'] for r in after),
                         'correctWithSupportAtLeastPoint65': sum(r['correct'] and r[key] is not None and r[key] >= PROTOCOL['minimumIndependentSupport'] for r in after)}
    summary = {
        'status': 'OFFLINE ONLY; not promoted; limited point-label validation, not full temporal replay',
        'freshReviewedPoints': len(fresh), 'freshLabelCorrectionsToRecordProposals': sum(r['truth'] != r['proposedTruth'] for r in fresh),
        'freshWrongReadings': [r for r in fresh if not r['correct']],
        'freshUncertainReadings': sum(r['predicted'] == 'uncertain' for r in fresh),
        'freshCapturePointLabels': [r for r in fresh if r['kind'].startswith('capture-')],
        'supportComparison': support, 'calibration': summaries,
        'olderErrorSessions': sorted(set(r['session'] for r in training if not r['correct'])),
        'liveSourcesUnchanged': live_before == live_fingerprint(root),
        'limits': [
            'Calibration target is correctness of a raw STONE reading, not probability a move was played or its time.',
            'Older development data was already used to design shadow features; fitting results are not validation.',
            'Fresh successful placements plus selected disagreements are a biased audit sample, not an operational error-rate estimate.',
            'Fresh labels are excluded from fitting, but images were inspected during model design; this is not blinded validation.',
            'Episode weighting reduces duplicate-frame influence; episodes within a session remain correlated.',
            'Native and shadow methods share inputs. Missing appearance is unknown, not corroboration.',
            'Earlier-count crops can already contain the next move or a removed capture; labels follow pixels.',
            'Only selected points are reviewed, not every intersection/frame or the exact placement/removal instant.',
            'Sparse independent error sessions prevent a deployment-quality calibration claim.',
            'No decisions, timestamps, native clock/capture behavior, or app settings changed.',
        ]}
    write_json(output/'summary.json', summary)
    inputs = [labels, previous/'observations.jsonl', previous/'appearance-evidence.jsonl', previous/'manifest.json',
              corpus/'boards.json', prepared/'evidence.jsonl', prepared/'manifest.json', prepared/'plan.json',
              Path(__file__), Path(__file__).with_name('local_quality_labels.json'),
              Path(__file__).with_name('placement_competition_lab.py'), Path(__file__).with_name('placement_competition_protocol.json')]
    write_json(output/'manifest.json', {'inputs': [{'path': str(p.resolve()), 'sha256': digest(p)} for p in inputs],
                                      'liveSourceBefore': live_before, 'liveSourceAfter': live_fingerprint(root)})
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('previous', 'corpus', 'prepared', 'labels', 'output'):
        parser.add_argument('--'+key, required=True, type=Path)
    args = parser.parse_args()
    run(args.previous, args.corpus, args.prepared, args.labels, args.output)
