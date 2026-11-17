#!/usr/bin/env python3
"""Bounded follow-up after outline-dropout regression, using unchanged controls."""
import argparse
from collections import Counter, defaultdict
import gzip
import json
from pathlib import Path

from edge_probation_lab import probation, WAIT_SECONDS
from local_quality_lab import digest
from outline_sampling_experiment import eligible
from placement_competition_lab import View
from prehand_lab import PreHandCompetition
from recognition_parameter_search import write_json
from run_prehand_experiment import DECISION_KEYS, load_cache


def main(args):
    args.output.mkdir(parents=True, exist_ok=False)
    counts, details, inputs = {}, [], {Path(__file__), Path(__file__).with_name('edge_probation_lab.py')}
    for cache in args.cache:
        rows, _ = load_cache(cache)
        outlines = {r['frame']: {s['row']*19+s['col'] for s in eligible(r['shapes'])} for r in rows}
        source = args.replay/cache.name/'decisions.jsonl.gz'
        inputs |= {source, cache/'observations.jsonl.gz', cache/'manifest.json'}
        count = Counter()
        for row in map(json.loads, gzip.open(source, 'rt')):
            if row['policy'] != 'control':
                continue
            current_shapes = set() if row['fault'] == 'outline_dropout' else outlines[row['frame']]
            old = row['result']
            new = probation(old, current_shapes)
            count['rows'] += 1
            changed = any(old[k] != new[k] for k in DECISION_KEYS)
            count['changedRows'] += changed
            if changed:
                details.append({'game': cache.name, **{k: row[k] for k in ('variant', 'fault', 'context', 'frame')}, 'old': old, 'new': new})
            assert new['recordedFrameTiming'] == old['recordedFrameTiming'] and not new['clockAuthority']
        counts[cache.name] = dict(count)
    evidence = defaultdict(list)
    for r in json.loads(args.evidence.read_text()):
        if r['kind'] == 'photo':
            evidence[r['case']].append(r)
    photos = []
    for case, batch in evidence.items():
        batch.sort(key=lambda r: r['point'])
        truth, raw, appearance = ([r[k] for r in batch] for k in ('truth', 'reading', 'appearance'))
        for point, color in enumerate(truth):
            if color not in ('black', 'white'):
                continue
            before = list(truth)
            before[point] = 'empty'
            model = PreHandCompetition(before, color)
            first_control = first_probation = None
            for frame in range(1, 26):
                result = model.step(View(frame, frame*.2, False, False, raw, appearance))
                filtered = probation(result, set())  # Complete outline failure.
                if result['selected'] == point and first_control is None:
                    first_control = frame*.2
                if filtered['selected'] == point and first_probation is None:
                    first_probation = frame*.2
            photos.append(dict(case=case, point=point, color=color, firstControl=first_control,
                               firstProbation=first_probation,
                               addedDelay=None if first_control is None or first_probation is None else first_probation-first_control))
    write_json(args.output/'photos.json', photos)
    write_json(args.output/'decision-changes.json', details)
    summary = {'status': 'offline follow-up, fixed .8s sustained witness span; no clock authority',
        'recentGames': counts, 'photoOutlineDropout': {
            'probes': len(photos), 'controlRecognized': sum(r['firstControl'] is not None for r in photos),
            'probationRecognized': sum(r['firstProbation'] is not None for r in photos),
            'delayedProbes': sum((r['addedDelay'] or 0) > 0 for r in photos),
            'maxAddedDelay': max(r['addedDelay'] or 0 for r in photos)},
        'limitations': 'Photo timing uses synthetic repeated images, not physical placement time. Recent games contain no true Black edge moves. No extra false-decision prevention demonstrated.'}
    write_json(args.output/'summary.json', summary)
    inputs |= {args.evidence, Path(__file__).with_name('prehand_lab.py'), Path(__file__).with_name('placement_competition_lab.py')}
    write_json(args.output/'manifest.json', {'inputs': {str(p): digest(p) for p in sorted(inputs)}})
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', type=Path, action='append', required=True)
    for name in ('replay', 'evidence', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    main(parser.parse_args())
