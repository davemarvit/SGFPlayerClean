#!/usr/bin/env python3
"""Offline parameter search over guarded unchanged-board evidence.

No app imports, clocks, SGF writes, or production configuration. Selection sees
training cases only; the selected setting is frozen before validation is scored.
"""
import argparse
from concurrent.futures import ProcessPoolExecutor, as_completed
from dataclasses import dataclass
import hashlib
import json
import multiprocessing
from pathlib import Path
import random
import time

import cv2
import numpy as np

from local_quality_lab import digest, read_image, tally
from unchanged_baseline_lab import (Baseline, INITIAL, Observation, PROTOCOL,
                                    Sampler, TUNABLE, features, occupancy,
                                    parameters, scenarios)


@dataclass
class Case:
    name: str
    kind: str
    observations: list
    expected: list
    labels: dict


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, allow_nan=False) + '\n')


def live_fingerprint(root):
    return {str(p.relative_to(root)): digest(p) for p in sorted(root.rglob('*.swift'))}


def prepare(corpus, sequence, quiet, space, output):
    """Read captured pixels once. Truth never enters image features or Baseline."""
    here = Path(__file__).parent
    inputs = set()

    def document(path):
        inputs.add(path)
        return json.loads(path.read_text())

    def sample(path, calibration, sampler=None):
        path = Path(path)
        inputs.add(path)
        image = read_image(path, calibration)
        sampler = sampler or Sampler(image[0].shape)
        return sampler, sampler.sample(image)

    timeline_boards = {int(b['id']): b for b in document(corpus/'timeline/boards.json')}
    timeline_raw = {int(b['board']): b['readings'] for b in document(corpus/'timeline/baseline.json')}
    timeline_labels = {int(k): occupancy({c: row[c] for c in ('black', 'white')})
                       for k, row in document(here/'local_quality_labels.json')['timelineTruth'].items()}
    rapid, sampler, anchor = [], None, None
    for frame in document(sequence)['frames']:
        number = frame['frameID']
        if number < PROTOCOL['seedFrame']:
            continue
        board = timeline_boards[number]
        sampler, patches = sample(board['image'], board['calibration'], sampler)
        if anchor is None:
            if number != PROTOCOL['seedFrame']:
                raise ValueError('Missing trusted rapid-reply seed')
            anchor = patches
        rapid.append(Observation(number, frame['capturedAt'], frame.get('handObstructed'),
                                 frame.get('lightingBlocked', False), timeline_raw[number],
                                 patches[0], features(*patches, *anchor)))
    training = [Case('rapid-recorded', 'recorded', rapid, occupancy(INITIAL), timeline_labels)]
    validation = []

    # The quiet continuation is the SAME session, so it stays on the training
    # side. Read preserved images/events, not the rotating live capture folder.
    quiet_labels = document(here/'unchanged_baseline_quiet_labels.json')
    events_path = quiet/'source-events.jsonl'
    inputs.add(events_path)
    frames, operations = {}, {}
    with events_path.open() as stream:
        for line in stream:
            row = json.loads(line)
            number = row.get('frameID')
            if number is None or not quiet_labels['first'] <= number <= quiet_labels['last']:
                continue
            if row['event'] == 'frame':
                if number in frames:
                    raise ValueError('Duplicate quiet frame')
                frames[number] = row
            elif row['event'] == 'operation finished' and row.get('unadaptedReadings'):
                if number in operations:
                    raise ValueError('Duplicate quiet operation')
                operations[number] = row
    quiet_observations, sampler, anchor = [], None, None
    for number, operation in sorted(operations.items()):
        row = frames[number]
        sampler, patches = sample(quiet/'inputs'/row['image'], operation.get('calibration') or row['calibration'], sampler)
        if anchor is None:
            if number != quiet_labels['first']:
                raise ValueError('Missing trusted quiet seed')
            anchor = patches
        blocked = bool(operation.get('lightingBlocked') or operation.get('exposureFailure')
                       or operation.get('outcome') != 'delivered to recorder')
        quiet_observations.append(Observation(number, row['captureUptime'],
                                             operation.get('handOutline', {}).get('obstructed'), blocked,
                                             operation['unadaptedReadings'], patches[0], features(*patches, *anchor)))
    expected = occupancy(quiet_labels['position'])
    training.append(Case('quiet-continuation', 'recorded', quiet_observations, expected,
                         {f: expected for f in quiet_labels['reviewedFrames']}))

    photo_raw = {b['board']: b['readings'] for b in document(corpus/'baseline.json')}
    for board in document(corpus/'boards.json'):
        group = board['group']
        if group == 'incident':  # Overlaps rapid reply; never duplicate it.
            continue
        if group in space['trainingPhotoGroups']:
            destination = training
        elif group in space['validationPhotoGroups']:
            destination = validation
        else:
            raise ValueError('Unassigned photo group: ' + group)
        sampler, anchor = sample(board['reference'], board['referenceCalibration'])
        _, patches = sample(board['image'], board['calibration'], sampler)
        empty = [{'occupancy': 'empty', 'confidence': 1.}] * 361
        seed = Observation(0, 0., False, False, empty, anchor[0], features(*anchor, *anchor))
        metrics = features(*patches, *anchor)
        held = [seed] + [Observation(f, f*.2, False, False, photo_raw[board['id']], patches[0], metrics)
                         for f in range(1, 26)]
        destination.append(Case(board['id'], 'synthetic-photo-hold', held, ['empty']*361,
                                {f: board['expected'] for f in range(1, 26)}))

    robustness = [Case('rapid-'+name, 'recorded-fault-injection', observations,
                       occupancy(INITIAL), timeline_labels)
                  for name, observations, _ in scenarios(rapid) if name != 'recorded']
    # Save the measured input features with original capture times and raw
    # readings. No trial overwrites these observations.
    with (output/'observations.jsonl').open('w') as stream:
        for case in training + validation:
            for o in case.observations:
                stream.write(json.dumps({'case': case.name, 'kind': case.kind, 'frame': o.frame,
                                         'capturedAt': o.time, 'hand': o.hand, 'lightingBlocked': o.lighting_blocked,
                                         'rawReadings': o.raw, 'imageFeatures': o.metrics}, allow_nan=False)+'\n')
    return training, validation, robustness, inputs


def input_signature(cases):
    """Hash the immutable observations before/after evaluation, including pixels."""
    h = hashlib.sha256()
    for case in cases:
        h.update(case.name.encode())
        for o in case.observations:
            h.update(json.dumps([o.frame, o.time, o.hand, o.lighting_blocked, o.raw, o.metrics], sort_keys=True).encode())
            for core in o.core:
                h.update(core.tobytes())
    return h.hexdigest()


def evaluate(config, cases, traces=None, batch=True, method='guarded_adaptive'):
    totals = dict(realStoneEmptySupport=0, blockedFrameOutput=0, timingAnchorLoss=0,
                  phantomPointCases=0, uncertainPointFrames=0, missedStonePointFrames=0,
                  falseStonePointFrames=0, adaptations=0, rollbacks=0, scoredFrames=0)
    results = {}
    for case in cases:
        model = Baseline(method, case.observations[0], case.expected, config, batch=batch)
        harmed, phantoms = set(), set()
        counts = {k: 0 for k in totals}
        raw_counts = dict(falseStone=0, missedStone=0, wrongColor=0, uncertain=0)
        stream = (traces/f'{case.name}.jsonl').open('w') if traces else None
        try:
            for o in case.observations[1:]:
                result = model.step(o)
                support = set(result['emptySupport'])
                counts['blockedFrameOutput'] += int(result['blocked'] and bool(support or result['updates'] and
                                                        any(e['type'] == 'adaptation' for e in result['updates'])))
                counts['adaptations'] += sum(e['type'] == 'adaptation' for e in result['updates'])
                counts['rollbacks'] += sum(e['type'] == 'rollback' for e in result['updates'])
                # These two native clock anchors must never be turned into
                # empty evidence, even under missed/delayed hand scenarios.
                if case.name.startswith('rapid-') and o.frame in (355, 356):
                    counts['timingAnchorLoss'] += int(309 in support)
                predicted = ['empty' if p in support else r['occupancy'] for p, r in enumerate(o.raw)]
                truth = case.labels.get(o.frame)
                if truth is not None:
                    harmed.update(p for p in support if truth[p] != 'empty')
                score_here = truth is not None and (case.kind != 'synthetic-photo-hold' or o.frame == 25)
                if score_here:
                    phantoms.update(p for p, (t, r) in enumerate(zip(truth, predicted)) if t == 'empty' and r in ('black', 'white'))
                    score = tally(truth, predicted)
                    original = tally(truth, [r['occupancy'] for r in o.raw])
                    for key in raw_counts:
                        raw_counts[key] += original[key]
                    counts['uncertainPointFrames'] += score['uncertain']
                    counts['missedStonePointFrames'] += score['missedStone']
                    counts['falseStonePointFrames'] += score['falseStone']
                    counts['scoredFrames'] += 1
                if stream:
                    stream.write(json.dumps({'frame': o.frame, 'capturedAt': o.time,
                                             'result': result, 'counterfactual': predicted}, allow_nan=False)+'\n')
        finally:
            if stream:
                stream.close()
        counts['realStoneEmptySupport'] = len(harmed)
        counts['phantomPointCases'] = len(phantoms)
        results[case.name] = {'kind': case.kind, 'counts': counts, 'raw': raw_counts,
                              'realStonePointsSuppressed': sorted(harmed), 'phantomPoints': sorted(phantoms)}
        for key in totals:
            totals[key] += counts[key]
    safe = not any(totals[k] for k in ('realStoneEmptySupport', 'blockedFrameOutput', 'timingAnchorLoss'))
    return {'safe': safe, 'totals': totals, 'cases': results}


def incumbent():
    return {k: PROTOCOL[k] for k in TUNABLE}


def distance(config, space):
    return sum(abs(config[k]-PROTOCOL[k])/(max(values)-min(values))
               for k, values in space['parameters'].items())


def rank(trial, space):
    score = trial['training']
    counts = score['totals']
    return (not score['safe'], counts['realStoneEmptySupport'] + counts['blockedFrameOutput'] + counts['timingAnchorLoss'],
            counts['phantomPointCases'], counts['uncertainPointFrames'], distance(trial['parameters'], space), trial['id'])


def candidates(space):
    """Incumbent, one-factor endpoints, then reproducible broad random search."""
    baseline, seen = incumbent(), set()

    def unique(config):
        key = json.dumps(config, sort_keys=True)
        if key in seen:
            return False
        seen.add(key)
        return True

    unique(baseline)
    yield 'incumbent', baseline
    for key, values in space['parameters'].items():
        for value in (min(values), max(values)):
            config = {**baseline, key: value}
            if unique(config):
                yield 'sensitivity:' + key, config
    rng = random.Random(space['seed'])
    for _ in range(space['randomTrials']):
        config = {k: rng.choice(v) for k, v in space['parameters'].items()}
        if unique(config):
            yield 'random', config


def refinement(best, space, previous):
    """Change one neighboring grid value around the TRAINING winner only."""
    seen = {json.dumps(row['parameters'], sort_keys=True) for row in previous}
    configs = []
    for key, values in space['parameters'].items():
        values = sorted(values)
        index = values.index(best[key])
        for neighbor in (index-1, index+1):
            if 0 <= neighbor < len(values):
                config = {**best, key: values[neighbor]}
                signature = json.dumps(config, sort_keys=True)
                if signature not in seen:
                    seen.add(signature)
                    configs.append(('refinement:' + key, config))
    random.Random(space['seed']+1).shuffle(configs)
    return configs[:space['refinementTrials']]


_TRAINING = None


def initialize_worker(cases):
    global _TRAINING
    cv2.setNumThreads(1)
    _TRAINING = cases


def run_trial(task):
    number, phase, config = task
    started = time.monotonic()
    result = evaluate(config, _TRAINING)
    return {'id': number, 'phase': phase, 'parameters': config,
            'seconds': time.monotonic()-started, 'training': result}


def search(training, space, workers, output):
    rows = []
    with ProcessPoolExecutor(max_workers=workers, mp_context=multiprocessing.get_context('spawn'),
                             initializer=initialize_worker, initargs=(training,)) as executor:
        def run_batch(configs):
            tasks = [(len(rows)+i, phase, config) for i, (phase, config) in enumerate(configs)]
            futures = [executor.submit(run_trial, task) for task in tasks]
            with (output/'trials.jsonl').open('a') as stream:
                for future in as_completed(futures):
                    row = future.result()
                    rows.append(row)
                    stream.write(json.dumps(row, allow_nan=False)+'\n')
                    stream.flush()
                    print(json.dumps({'trial': row['id'], 'phase': row['phase'], 'safe': row['training']['safe'],
                                      'counts': row['training']['totals']}), flush=True)
        run_batch(list(candidates(space)))
        best = min(rows, key=lambda row: rank(row, space))
        run_batch(refinement(best['parameters'], space, rows))
    rows.sort(key=lambda row: row['id'])
    return rows, min(rows, key=lambda row: rank(row, space))


def validate_space(space):
    if set(space['parameters']) != set(TUNABLE):
        raise ValueError('Search must expose exactly the nine approved parameters')
    if set(space['trainingPhotoGroups']) & set(space['validationPhotoGroups']):
        raise ValueError('Training and validation groups overlap')
    for key, values in space['parameters'].items():
        if len(set(values)) < 2 or PROTOCOL[key] not in values:
            raise ValueError('Each search axis must contain the incumbent and alternatives')
        for value in values:
            parameters({key: value})
    for key in ('randomTrials', 'refinementTrials'):
        if not isinstance(space[key], int) or space[key] < 0:
            raise ValueError('Invalid search budget')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--corpus', type=Path, required=True)
    parser.add_argument('--sequence', type=Path, required=True)
    parser.add_argument('--quiet', type=Path, required=True, help='Preserved quiet-replay output folder')
    parser.add_argument('--space', type=Path, default=Path(__file__).with_name('recognition_parameter_space.json'))
    parser.add_argument('--workers', type=int, default=2)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    if args.output.exists() or args.output.resolve().is_relative_to(root.parent) or args.workers < 1:
        parser.error('Use a new external output directory and at least one worker')
    space = json.loads(args.space.read_text())
    validate_space(space)
    args.output.mkdir(parents=True)
    cv2.setNumThreads(1)
    before = live_fingerprint(root)
    write_json(args.output/'plan.json', {'space': space, 'fixedProtocol': {k: v for k, v in PROTOCOL.items() if k not in TUNABLE},
                                        'liveSourceBefore': before, 'promotion': 'Offline only; never automatic'})
    print('Preparing captured pixels and frozen session-level split', flush=True)
    training, validation, robustness, inputs = prepare(args.corpus, args.sequence, args.quiet, space, args.output)
    all_cases = training + validation + robustness
    signature = input_signature(all_cases)
    for case in all_cases:
        times = [o.time for o in case.observations]
        if any(b <= a for a, b in zip(times, times[1:])):
            raise ValueError('Non-monotonic capture times: ' + case.name)
    inputs.update([args.space, Path(__file__), Path(__file__).with_name('unchanged_baseline_lab.py'),
                   Path(__file__).with_name('local_quality_lab.py')])
    write_json(args.output/'manifest.json', {'inputs': [{'path': str(p.resolve()), 'sha256': digest(p)} for p in sorted(inputs)],
                                           'training': [c.name for c in training], 'validation': [c.name for c in validation],
                                           'robustness': [c.name for c in robustness], 'observationSHA256': signature,
                                           'numpy': np.__version__, 'opencv': cv2.__version__})
    print('Searching training cases only', flush=True)
    rows, best = search(training, space, args.workers, args.output)
    # Write the frozen selection BEFORE evaluating validation. Validation is
    # rejection-only; it cannot choose another candidate or drive refinement.
    write_json(args.output/'selected.json', {'trial': best['id'], 'parameters': best['parameters'],
                                           'training': best['training'], 'selectionUsedValidation': False})
    print('Selection frozen; checking reserved groups and fault scenarios', flush=True)
    checks = {}
    for name, config in [('incumbent', incumbent()), ('selected', best['parameters'])]:
        trace_path = args.output/name
        trace_path.mkdir()
        checks[name] = {'training': evaluate(config, training, trace_path),
                        'validation': evaluate(config, validation, trace_path),
                        'robustness': evaluate(config, robustness, trace_path)}
    # Compare the optional fast evaluator against the original scalar path on
    # the incident and one held photo, including adaptation/rollback traces.
    equivalence = {}
    for name, config in [('incumbent', incumbent()), ('selected', best['parameters'])]:
        subset = [training[0], validation[0]]
        scalar_path = args.output/(name+'-scalar-check')
        scalar_path.mkdir()
        scalar = evaluate(config, subset, scalar_path, batch=False)
        expected = {c.name: checks[name]['training' if c in training else 'validation']['cases'][c.name] for c in subset}
        equivalence[name] = scalar['cases'] == expected and all(
            (scalar_path/f'{c.name}.jsonl').read_bytes() == (args.output/name/f'{c.name}.jsonl').read_bytes() for c in subset)
    after = live_fingerprint(root)
    unchanged = signature == input_signature(all_cases)
    live_unchanged = before == after
    if not unchanged or not live_unchanged or not all(equivalence.values()):
        raise AssertionError('Evidence, live-source or evaluator-equivalence safeguard failed')
    selected_safe = all(checks['selected'][split]['safe'] for split in checks['selected'])
    train_better = rank(best, space)[:4] < rank(rows[0], space)[:4]
    summary = {'status': 'OFFLINE ONLY', 'trialCount': len(rows), 'safeTrainingTrials': sum(r['training']['safe'] for r in rows),
               'selectedTrial': best['id'], 'selectedParameters': best['parameters'],
               'strictTrainingImprovement': train_better, 'selectedPassesAllSafetyChecks': selected_safe,
               'automaticPromotion': False, 'requiresFreshSessionValidation': True,
               'observationEvidenceUnchanged': unchanged, 'liveSourcesUnchanged': live_unchanged,
               'scalarBatchTraceEquivalence': equivalence, 'checks': checks,
               'limits': ['Only unchanged-board evidence is tuned; pixel classifier and move competition remain outside this search.',
                          'No clock presses or balances are simulated by this stage. Preserving two anchors is not an end-to-end clock-accuracy measurement.',
                          'Capture/removal contradictions block evidence; this stage does not resolve legal captures.',
                          'Unknown readings are not calibrated probabilities or measured pauses. No confirmation latency for real moves is claimed.',
                          space['splitNote']]}
    write_json(args.output/'summary.json', summary)
    print(json.dumps({k: v for k, v in summary.items() if k != 'checks'}, indent=2), flush=True)


if __name__ == '__main__':
    main()
