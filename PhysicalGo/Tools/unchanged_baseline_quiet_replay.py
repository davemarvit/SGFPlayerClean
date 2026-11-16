#!/usr/bin/env python3
"""Replay a longer, reviewed quiet stretch from a native diagnostic archive.

Uses recorded unadapted readings (before live lighting/tracking corrections),
not the separately rerun pixel-classifier corpus used in the rapid-reply pilot.
Preserves selected images by hard link/copy, and relevant original event rows.
"""
import argparse
from collections import Counter
import json
import os
from pathlib import Path
import shutil

from unchanged_baseline_lab import Baseline, Observation, Sampler, METHODS, PROTOCOL, occupancy, features
from local_quality_lab import read_image, tally, digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--labels', type=Path, default=Path(__file__).with_name('unchanged_baseline_quiet_labels.json'))
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists() or args.output.resolve().is_relative_to(Path(__file__).resolve().parents[2]):
        parser.error('Choose a new external report folder')
    args.output.mkdir(parents=True)
    labels = json.loads(args.labels.read_text())
    expected = occupancy(labels['position'])
    frames, operations = {}, {}
    inputs = [Path(__file__), Path(__file__).with_name('unchanged_baseline_lab.py'),
              Path(__file__).with_name('local_quality_lab.py'), args.labels, args.archive/'events.jsonl']
    with (args.output/'source-events.jsonl').open('w') as saved:
        for line in (args.archive/'events.jsonl').open():
            row = json.loads(line)
            number = row.get('frameID')
            if number is None or not labels['first'] <= number <= labels['last']:
                continue
            saved.write(line)
            if row['event'] == 'frame':
                frames[number] = row
            elif row['event'] == 'operation finished' and row.get('unadaptedReadings'):
                if number in operations:
                    raise ValueError('Ambiguous duplicate analysis for frame '+str(number))
                operations[number] = row
    observations, sampler, anchor = [], None, None
    for number in sorted(operations):
        row, operation = frames[number], operations[number]
        source = args.archive/row['image']
        destination = args.output/'inputs'/row['image']
        destination.parent.mkdir(parents=True, exist_ok=True)
        try:
            os.link(source, destination)
        except OSError:
            shutil.copy2(source, destination)
        inputs.append(destination)
        image = read_image(destination, operation.get('calibration') or row['calibration'])
        if sampler is None:
            if number != labels['first']:
                raise ValueError('Trusted seed has no analyzed image')
            sampler = Sampler(image[0].shape)
            anchor = sampler.sample(image)
        core, wood = sampler.sample(image)
        hand = operation.get('handOutline', {}).get('obstructed')
        # Unknown tracking, obstruction, failed exposure or unaligned output
        # cannot establish a quiet interval.
        blocked = bool(operation.get('lightingBlocked') or operation.get('exposureFailure')
                       or operation.get('outcome') != 'delivered to recorder')
        observations.append(Observation(number, row['captureUptime'], hand, blocked,
                                        operation['unadaptedReadings'], core, features(core, wood, *anchor)))
    summary = {'scope': __doc__, 'labelProvenance': labels['provenance'], 'protocol': {**PROTOCOL, 'seedFrame': labels['first']},
               'frames': len(observations), 'elapsedSeconds': observations[-1].time-observations[0].time,
               'reviewedFramesDelivered': [o.frame for o in observations[1:] if o.frame in labels['reviewedFrames']], 'methods': {}}
    for method in METHODS:
        model = Baseline(method, observations[0], expected)
        counts = Counter()
        with (args.output/f'{method}.jsonl').open('w') as stream:
            for o in observations[1:]:
                result = model.step(o)
                predicted = [r['occupancy'] for r in o.raw]
                for p in result['emptySupport']:
                    predicted[p] = 'empty'
                counts['adaptations'] += sum(e['type'] == 'adaptation' for e in result['updates'])
                counts['rollbacks'] += sum(e['type'] == 'rollback' for e in result['updates'])
                counts['blockedFrames'] += result['blocked']
                entry = {'frame': o.frame, 'capturedAt': o.time, 'rawReadings': o.raw, 'imageFeatures': o.metrics,
                         'result': result, 'counterfactual': predicted}
                if o.frame in labels['reviewedFrames']:
                    scores = {'raw': tally(expected, [r['occupancy'] for r in o.raw]), 'counterfactual': tally(expected, predicted)}
                    entry['evaluation'] = scores
                    for prefix, score in scores.items():
                        for key, value in score.items():
                            counts[prefix+'_'+key] += value
                stream.write(json.dumps(entry, allow_nan=False)+'\n')
        summary['methods'][method] = dict(counts)
    summary['inputs'] = [{'path': str(p), 'sha256': digest(p)} for p in sorted(set(inputs))]
    (args.output/'summary.json').write_text(json.dumps(summary, indent=2, allow_nan=False)+'\n')
    print(json.dumps({k: v for k, v in summary.items() if k not in ('inputs', 'protocol')}, indent=2))


if __name__ == '__main__':
    main()
