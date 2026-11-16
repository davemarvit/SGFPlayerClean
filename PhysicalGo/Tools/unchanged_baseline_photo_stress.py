#!/usr/bin/env python3
"""Hold captured photos after a simulated unobserved interaction.

This is a constructed persistence stress, NOT an actual video sequence. Score
each photograph once; repeated frames provide no additional independent data.
"""
import argparse
import json
from pathlib import Path

from unchanged_baseline_lab import Baseline, Observation, Sampler, METHODS, features
from local_quality_lab import read_image, tally, digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--corpus', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists() or args.output.resolve().is_relative_to(Path(__file__).resolve().parents[2]):
        parser.error('Choose a new external output directory')
    args.output.mkdir(parents=True)
    boards = json.loads((args.corpus/'boards.json').read_text())
    raw = {b['board']: b['readings'] for b in json.loads((args.corpus/'baseline.json').read_text())}
    report = {'scope': __doc__, 'artificialCadenceSeconds': .2, 'artificialHoldSeconds': 5., 'cases': []}
    inputs = [Path(__file__), Path(__file__).with_name('unchanged_baseline_lab.py'),
              Path(__file__).with_name('local_quality_lab.py'), args.corpus/'boards.json', args.corpus/'baseline.json']
    for board in boards:
        if board.get('group') == 'incident':
            continue
        reference = read_image(board['reference'], board['referenceCalibration'])
        image = read_image(board['image'], board['calibration'])
        sampler = Sampler(reference[0].shape)
        anchor = sampler.sample(reference)
        core, wood = sampler.sample(image)
        seed = Observation(0, 0., False, False, [{'occupancy': 'empty', 'confidence': 1.}] * 361,
                           anchor[0], features(*anchor, *anchor))
        metrics = features(core, wood, *anchor)
        entry = {'board': board['id'], 'raw': tally(board['expected'], [r['occupancy'] for r in raw[board['id']]]), 'methods': {}}
        for method in METHODS:
            estimator = Baseline(method, seed, ['empty'] * 361)
            ever_suppressed = set()
            ever_changed = set()
            trace = []
            for frame in range(1, 26):
                observation = Observation(frame, frame*.2, False, False, raw[board['id']], core, metrics)
                result = estimator.step(observation)
                # Score any false empty decision during the hold, not just a
                # conveniently chosen final frame between baseline updates.
                for p in result['emptySupport']:
                    if board['expected'][p] != 'empty':
                        ever_suppressed.add(p)
                    if observation.raw[p]['occupancy'] != 'empty':
                        ever_changed.add(p)
                trace.append({'artificialTime': frame*.2, 'emptySupport': result['emptySupport'], 'updates': result['updates']})
            entry['methods'][method] = {'realStonePointsWithEmptySupport': sorted(ever_suppressed),
                                        'everChangedPoints': sorted(ever_changed)}
            (args.output/f'{board["id"]}-{method}.json').write_text(json.dumps(trace, allow_nan=False)+'\n')
        report['cases'].append(entry)
        inputs.extend([Path(board['image']), Path(board['reference'])])
    report['totals'] = {method: {'photosWithSuppressedRealStones': sum(bool(c['methods'][method]['realStonePointsWithEmptySupport']) for c in report['cases']),
                                'stonePhotoPairsWithEmptySupport': sum(len(c['methods'][method]['realStonePointsWithEmptySupport']) for c in report['cases'])}
                        for method in METHODS}
    report['inputs'] = [{'path': str(p), 'sha256': digest(p)} for p in sorted(set(inputs))]
    (args.output/'summary.json').write_text(json.dumps(report, indent=2, allow_nan=False)+'\n')
    print(json.dumps(report['totals'], indent=2))


if __name__ == '__main__':
    main()
