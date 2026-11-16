#!/usr/bin/env python3
"""Score the frozen stage8 rule on a new captured game; never fit parameters."""
import argparse
from collections import Counter
import json
from pathlib import Path

import cv2

from evaluate_unavailable_shadow import Pixels, point_scores
from fresh_game_confidence import ordered_readings
from local_quality_lab import digest
from recognition_parameter_search import write_json

FROZEN = {
    'unavailable_shadow_lab.py': '1b1c596928568f7932c620249bfcb6ca31d7a996d6ee94f1f7faa13f2e1563f1',
    'unavailable_shadow_protocol.json': '5be0e6b384955c3e07ce2bf43bd983a493225a01489bb336b30ca96367ccdd0c',
    'placement_competition_lab.py': '116bb835f93252ba0978ae39175228a07dbb461b07e167f5d7b10f3326a581ff',
}


def run(snapshot, prepared, labels_path, output):
    if output.exists() or output.resolve().is_relative_to(Path(__file__).resolve().parents[2]):
        raise ValueError('Use a new external output directory')
    for name, expected in FROZEN.items():
        if digest(Path(__file__).with_name(name)) != expected:
            raise ValueError('Frozen validation policy changed: '+name)
    output.mkdir(parents=True)
    write_json(output/'plan.json', {'frozenCommit': 'cb56891', 'frozenHashes': FROZEN,
        'fitOrTuning': False, 'scope': 'New-session reviewed point support; no clock/capture authority or full-game temporal replay'})
    labels = json.loads(labels_path.read_text())
    assert labels['status'] == 'image-reviewed-point-labels'
    assert labels['sourceEventsSHA256'] == digest(snapshot/'capture/events.jsonl')
    evidence = {d['frame']: d for d in map(json.loads, (prepared/'evidence.jsonl').open())}
    frames, operations, event_counts = {}, {}, Counter()
    for line in (snapshot/'capture/events.jsonl').open():
        d = json.loads(line)
        event_counts[d['event']] += 1
        if d['event'] == 'frame':
            frames[d['frameID']] = d
        elif d['event'] == 'operation finished':
            operations[d['frameID']] = d
    pixels, rows = Pixels(), []
    for frame, d in evidence.items():
        meta, op = frames[frame], d['recordedOperation']
        d['augmented'] = pixels.augment(d['image'], op['calibration'], d['referenceImage'],
                                        meta['referenceCalibration'], d['appearance'])
    for label in labels['points']:
        d, p = evidence[label['frame']], label['point']
        op = d['recordedOperation']
        rows.append({'case': 'validation-85', 'frame': d['frame'], 'point': p,
                     'truth': label['truth'], 'kind': label['kind'], 'move': label['move'],
                     'reading': d['rawReadings'][p], 'appearance': d['augmented'][p],
                     'shapes': op.get('footprints', [])+op.get('placementFits', [])})
    scores = point_scores(rows)
    # Full move history is only proposed context, not independent image truth.
    from fresh_game_confidence import positions
    sampling = json.loads((prepared/'sampling.json').read_text())
    states, captures = positions(sampling['moves'])
    latest = operations[max(operations)]
    latest_readings = ordered_readings(latest['readings'])
    final_diff = [{'point': p, 'expectedFromRecord': t, 'reading': r}
                  for p, (t, r) in enumerate(zip(states[-1], latest_readings)) if t != r['occupancy']]
    events, warnings, pauses, resumes, corrections = Counter(), [], [], [], []
    journal = next((snapshot/'recording').glob('*.observations.jsonl'))
    for line in journal.open():
        d = json.loads(line)
        events[d['event']] += 1
        compact = {k: d.get(k) for k in ('event', 'time', 'moveCount', 'status', 'clock')}
        if d['event'] == 'clock automatically paused':
            pauses.append(compact)
        elif d['event'] == 'clock automatically resumed':
            resumes.append(compact)
        elif d['event'] == 'recording warning: prolonged blocked view':
            warnings.append(compact)
        if d.get('clock', {}).get('needsCorrection'):
            corrections.append(compact)
    clock_path = next((snapshot/'recording').glob('*.clock.json'))
    clock = json.loads(clock_path.read_text())
    session = json.loads((snapshot/'capture/session.json').read_text())
    result = {'status': 'OFFLINE ONLY; frozen new-session point validation, not promoted',
        'frozenCommit': 'cb56891', 'frozenHashes': FROZEN, 'captureStatus': session['status'],
        'captureStopReason': session.get('reason'), 'captureFrames': len(frames),
        'capturedSavedMoveCounts': sorted(set(f['recorder']['moveCount'] for f in frames.values())),
        'captureAppVersion': session.get('appVersion'), 'captureSourceHash': session.get('sourceHash'),
        'savedMoves': len(sampling['moves']), 'pendingMoves': 0 if not json.loads(next((snapshot/'recording').glob('*.pending.json')).read_text())['history']['paths'] else None,
        'capturesFromRecord': captures, 'finalPhysicalStonesFromRecord': dict(Counter(states[-1])),
        'latestAnalysisFrame': max(operations), 'finalRecordVsReadingDifferences': final_diff,
        'reviewedPoints': len(rows), 'labelCorrectionsToRecordProposals': sum(l['truth'] != l['proposedTruth'] for l in labels['points']),
        'rawWrongReviewedReadings': [r for r in rows if r['reading']['occupancy'] != r['truth']],
        'policySummary': {p: {k: v for k, v in score.items() if k != 'rows'} for p, score in scores.items()},
        'captureEvents': dict(event_counts), 'journalEvents': dict(events), 'blockedViewWarnings': warnings,
        'automaticPauses': pauses, 'automaticResumes': resumes,
        'automaticPauseDurations': [r['time']-p['time'] for p, r in zip(pauses, resumes)],
        'clockCorrectionObservations': len(corrections), 'finalClockNeedsCorrection': clock['needsCorrection'],
        'firstMoveClockBefore': clock['moves'][0]['before'], 'firstMoveClockAfter': clock['moves'][0]['after'],
        'limits': ['Image labels are assistant-reviewed selected points, not user-certified full-board/timing truth.',
                   'No threshold tuning or calibration fitting used this game.',
                   'Static support retention does not establish temporal latency or native clock accuracy.',
                   'Saved move count can lag placement; before-count crops are labeled from pixels.',
                   'The automatic startup pause leaves move 1 with zero charged time; no clock-accuracy claim.',
                   'False-reading counts refer to selected samples, not whole-game error rates.']}
    write_json(output/'summary.json', result)
    write_json(output/'point-evidence.json', rows)
    write_json(output/'policy-rows.json', scores)
    inputs = pixels.inputs | {labels_path, prepared/'evidence.jsonl', prepared/'sampling.json', journal, clock_path,
                              snapshot/'capture/events.jsonl', snapshot/'capture/session.json', Path(__file__)}
    inputs.update(Path(__file__).with_name(n) for n in FROZEN)
    inputs.update(Path(__file__).with_name(n) for n in ('evaluate_unavailable_shadow.py', 'fresh_game_confidence.py', 'local_quality_lab.py'))
    write_json(output/'manifest.json', {'inputs': [{'path': str(p.resolve()), 'sha256': digest(p)} for p in sorted(inputs)]})
    print(json.dumps({k: result[k] for k in ('savedMoves', 'captureFrames', 'capturesFromRecord',
        'reviewedPoints', 'labelCorrectionsToRecordProposals', 'policySummary', 'automaticPauseDurations',
        'clockCorrectionObservations', 'finalRecordVsReadingDifferences')}, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('snapshot', 'prepared', 'labels', 'output'):
        parser.add_argument('--'+key, required=True, type=Path)
    args = parser.parse_args()
    cv2.setNumThreads(1)
    run(args.snapshot, args.prepared, args.labels, args.output)
