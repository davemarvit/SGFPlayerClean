#!/usr/bin/env python3
"""Fixed offline pre-hand ablations over preserved, conditional turn contexts."""
import argparse
from bisect import bisect_right
from collections import Counter
import gzip
import json
from pathlib import Path

from local_quality_lab import digest
from placement_competition_lab import View
from prehand_lab import PreHandCompetition, PROTOCOL
from recognition_parameter_search import write_json

UNKNOWN = {'signedCoreDelta': None, 'gain': None, 'coreError': None,
           'woodError': None, 'woodPixels': 0, 'measuredCoreDelta': None}
FAULTS = ('recorded', 'all_hands_missed', 'unknown_hand', 'hand_delayed_600ms',
          'camera_gap', 'gap_and_missed_hand', 'outline_dropout')
DECISION_KEYS = ('state', 'selected', 'firstSeen', 'firstSupported', 'confirmedAt',
                 'witnesses', 'recordedFrameTiming', 'clockAuthority', 'reasons')


def load_cache(path):
    rows = [json.loads(line) for line in gzip.open(path/'observations.jsonl.gz', 'rt')]
    return rows, json.loads((path/'contexts.json').read_text())


def views(rows, context, variant, fault):
    times = [r['capturedAt'] for r in rows]
    selected = [r for r in rows if context['id'] in r['contexts']]
    # Remove a fixed 900ms interval starting at the first candidate appearance.
    # A surviving later observation retains an explicit gap even if the short
    # context otherwise leaves only one post-gap frame.
    anchor = next((r['capturedAt'] for r in selected if context['expected'] is not None
                   and r['raw'][context['expected']][0] == context['color']),
                  context['firstAt']+.8)
    omitted = False
    for row in selected:
        t = row['capturedAt']
        if fault in ('camera_gap', 'gap_and_missed_hand') and anchor <= t < anchor+.9:
            omitted = True
            continue
        hand = row['hand']
        if fault in ('all_hands_missed', 'gap_and_missed_hand'):
            hand = False if hand is not None else None
        elif fault == 'unknown_hand':
            hand = None
        elif fault == 'hand_delayed_600ms':
            index = bisect_right(times, t-.6)-1
            hand = rows[index]['hand'] if index >= 0 else None
        raw = [dict(occupancy=o, confidence=c) for o, c in row['raw']]
        appearance = [row[variant].get(str(p), UNKNOWN) for p in range(len(raw))]
        yield row, View(row['frame'], t, hand, row['lightingBlocked'], raw, appearance,
                        omitted, row['recordedTiming'])
        omitted = False


def run_game(cache, output):
    rows, contexts = load_cache(cache)
    results, totals = [], {}
    with gzip.open(output/'decisions.jsonl.gz', 'wt') as stream:
        for variant in ('original', 'outline_mask'):
            for fault in FAULTS:
                aggregate = {p: Counter() for p in PROTOCOL['policies']}
                for context in contexts:
                    sequence = list(views(rows, context, variant, fault))
                    shape_map = {r['frame']: [] if fault == 'outline_dropout' else r['shapes'] for r, _ in sequence}
                    control = None
                    for policy in PROTOCOL['policies']:
                        model = PreHandCompetition(context['before'], context['color'], policy, shape_map)
                        first = None
                        decisions, selected_points = [], set()
                        count = aggregate[policy]
                        count['contexts'] += 1
                        for row, view in sequence:
                            result = model.step(view, row['availableAt'])
                            decision = {k: result[k] for k in DECISION_KEYS}
                            decisions.append(decision)
                            count['frames'] += 1
                            assert not result['clockAuthority']
                            assert result['recordedFrameTiming'] == row['recordedTiming']
                            assert not (result['state'] == 'placement' and result['reasons'])
                            if result['state'] == 'placement':
                                selected_points.add(result['selected'])
                                if first is None:
                                    first = {'point': result['selected'], 'frame': row['frame'],
                                             'capturedAt': view.time, 'availableAt': row['availableAt'],
                                             'firstSeen': result['firstSeen'], 'firstSupported': result['firstSupported']}
                                # Faults can conceal actual hands. Count these honestly,
                                # even when the point later really becomes a stone.
                                count['originallyObstructedSelections'] += row['hand'] is not False
                            count['guardRows'] += bool(result['reasons'])
                            stream.write(json.dumps({'variant': variant, 'fault': fault, 'context': context['id'],
                                'policy': policy, 'frame': view.frame, 'availableAt': row['availableAt'],
                                'result': result})+'\n')
                        if policy == 'control':
                            control = decisions
                        changed = sum(a != b for a, b in zip(control, decisions))
                        if policy.startswith('retro_'):
                            assert not changed, 'Retrospective ledger must not rewrite decisions'
                        expected = context['expected']
                        count['selectedContexts'] += first is not None
                        if expected is not None:
                            count['expectedSelectedContexts'] += expected in selected_points
                            count['wrongPointContexts'] += bool(selected_points-{expected})
                            count['captureContexts'] += context.get('capture') is not None
                        count['changedDecisionTimingRows'] += changed
                        count['revisions'] += len(model.revisions)
                        results.append({'variant': variant, 'fault': fault, 'context': context['id'],
                            'policy': policy, 'expected': expected, 'capture': context.get('capture'),
                            'firstSelected': first, 'selectedPoints': sorted(selected_points),
                            'changedDecisionTimingRows': changed, 'revisions': model.revisions,
                            'frames': len(sequence)})
                totals[variant+'/'+fault] = {p: dict(c) for p, c in aggregate.items()}
                print(cache.name, variant, fault, 'done', flush=True)
    write_json(output/'contexts.json', results)
    # Score ONLY reviewed endpoints, not arbitrary points throughout a turn.
    by_frame = {r['frame']: r for r in rows}
    endpoints = []
    for c in contexts:
        row = by_frame[c['reviewedEndpoint']]
        for point in ([c['expected']] if c['expected'] is not None else c['reviewedEmpty']):
            for variant in ('original', 'outline_mask'):
                raw = [dict(occupancy=o, confidence=v) for o, v in row['raw']]
                view = View(row['frame'], row['capturedAt'], row['hand'], row['lightingBlocked'], raw,
                            [row[variant].get(str(p), UNKNOWN) for p in range(len(raw))])
                for policy in PROTOCOL['policies']:
                    model = PreHandCompetition(c['before'], c['color'], policy, {row['frame']: row['shapes']})
                    support = model.filter(view, point, 1.)
                    endpoints.append({'context': c['id'], 'frame': row['frame'], 'point': point,
                        'truth': c['color'] if c['expected'] is not None else 'empty',
                        'raw': raw[point], 'variant': variant, 'policy': policy,
                        'support': support, 'outline': model.has_outline(row['frame'], point)})
    write_json(output/'endpoints.json', endpoints)
    write_json(output/'summary.json', totals)
    return totals


def main(args):
    args.output.mkdir(parents=True, exist_ok=False)
    all_results = {}
    inputs = set()
    for cache in args.cache:
        folder = args.output/cache.name
        folder.mkdir()
        all_results[cache.name] = run_game(cache, folder)
        inputs.update(cache/n for n in ('observations.jsonl.gz', 'contexts.json', 'manifest.json'))
    inputs.update(Path(__file__).with_name(n) for n in ('run_prehand_experiment.py', 'prehand_lab.py',
        'prehand_protocol.json', 'placement_competition_lab.py', 'placement_competition_protocol.json',
        'unavailable_shadow_lab.py', 'unavailable_shadow_protocol.json', 'outline_sampling_experiment.py'))
    write_json(args.output/'manifest.json', {'inputs': {str(p): digest(p) for p in sorted(inputs)},
        'limitations': 'Conditional supplied prior positions, not an autonomous game replay. Development data, not held-out validation.',
        'faults': list(FAULTS), 'clockAuthority': False})
    write_json(args.output/'summary.json', all_results)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', type=Path, action='append', required=True)
    parser.add_argument('--output', type=Path, required=True)
    main(parser.parse_args())
