#!/usr/bin/env python3
"""Older photo/rapid-play follow-ups; synthetic probes are explicitly labeled."""
import argparse
from collections import Counter, defaultdict
from dataclasses import replace
import gzip
import json
from pathlib import Path

from fresh_game_confidence import ordered_readings
from local_quality_lab import digest
from placement_competition_lab import View
from prehand_lab import PreHandCompetition, PROTOCOL, edge
from recognition_parameter_search import write_json
from replay_outline_sampling import OutlinePixels
from run_prehand_experiment import DECISION_KEYS
from unchanged_baseline_lab import Observation, scenarios


def main(args):
    args.output.mkdir(parents=True, exist_ok=False)
    inputs = {args.evidence, args.shapes, args.corpus/'boards.json', args.sequence,
              args.previous/'appearance-evidence.jsonl', args.previous/'observations.jsonl',
              args.corpus/'timeline/boards.json'}
    shapes = {r['id']: r for r in json.loads(args.shapes.read_text())}
    boards = {b['id']: b for b in json.loads((args.corpus/'boards.json').read_text())}
    photos = defaultdict(list)
    for r in json.loads(args.evidence.read_text()):
        if r['kind'] == 'photo':
            photos[r['case']].append(r)
    photo_results, native_changes = [], []
    for case, rows in photos.items():
        rows.sort(key=lambda r: r['point'])
        assert len(rows) == 361
        # Cases use the original corpus ID prefixed with photo-.
        board_id = next((key for key in boards if case in (key, 'photo-'+key)), None)
        if board_id is None:
            raise ValueError(case)
        b, native = boards[board_id], shapes[board_id]
        raw = [r['reading'] for r in rows]
        current_raw = ordered_readings(native['readings'])
        native_changes.extend({'case': case, 'point': p} for p in range(361)
                              if any(raw[p][k] != current_raw[p][k] for k in ('occupancy', 'confidence')))
        original = [r['appearance'] for r in rows]
        pixels = OutlinePixels({b['image']: native['shapes']})
        masked = pixels.augment(b['image'], b['calibration'], b['reference'], b['referenceCalibration'], original)
        inputs |= pixels.inputs
        truth = [r['truth'] for r in rows]
        for variant, appearance in [('original', original), ('outline_mask', masked)]:
            for fault in ('recorded_shapes', 'outline_dropout'):
                current_shapes = native['shapes'] if fault == 'recorded_shapes' else []
                for point, color in enumerate(truth):
                    if color not in ('black', 'white'):
                        continue
                    before = list(truth)
                    before[point] = 'empty'
                    for policy in ('control', 'edge_shape', 'combined'):
                        model = PreHandCompetition(before, color, policy, {1: current_shapes, 2: current_shapes})
                        for frame in (1, 2):
                            result = model.step(View(frame, frame*.2, False, False, raw, appearance))
                        photo_results.append({'case': case, 'point': point, 'color': color,
                            'edge': edge(point), 'variant': variant, 'fault': fault, 'policy': policy,
                            'selected': result['selected'], 'reasons': result['reasons'],
                            'targetSupport': model.filter(View(2, .4, False, False, raw, appearance), point, 1.),
                            'outline': model.has_outline(2, point)})
    write_json(args.output/'photos.json', photo_results)
    write_json(args.output/'native-reading-changes.json', native_changes)

    # Replay real older temporal observations, including all existing faults.
    sequence = json.loads(args.sequence.read_text())
    metadata = {f['frameID']: f for f in sequence['frames']}
    shape_map = {f: m.get('footprints', [])+m.get('placementFits', []) for f, m in metadata.items()}
    appearances = {r['frame']: r['appearance'] for r in map(json.loads, (args.previous/'appearance-evidence.jsonl').open())
                   if r['case'] == 'rapid-recorded'}
    timeline = {int(b['id']): b for b in json.loads((args.corpus/'timeline/boards.json').read_text())}
    pixels = OutlinePixels({timeline[f]['image']: s for f, s in shape_map.items() if f in timeline})
    anchor = timeline[306]
    masked = {f: pixels.augment(timeline[f]['image'], timeline[f]['calibration'], anchor['image'], anchor['calibration'], a)
              for f, a in appearances.items()}
    inputs |= pixels.inputs
    # Original missing contrasts must be augmented from the same old reference.
    from evaluate_unavailable_shadow import Pixels
    original_pixels = Pixels()
    original = {f: original_pixels.augment(timeline[f]['image'], timeline[f]['calibration'], anchor['image'], anchor['calibration'], a)
                for f, a in appearances.items()}
    inputs |= original_pixels.inputs
    observed = [Observation(r['frame'], r['capturedAt'], r['hand'], r['lightingBlocked'], r['rawReadings'], [], [])
                for r in map(json.loads, (args.previous/'observations.jsonl').open()) if r['case'] == 'rapid-recorded']
    label_path = Path(__file__).with_name('local_quality_labels.json')
    inputs.add(label_path)
    labels = json.loads(label_path.read_text())
    contexts = [{'name': n, 'expected': p, **e} for n, p, e in zip(('white8', 'black9', 'white10'), (288, 309, 250), labels['episodes'])]
    contexts.append(dict(name='black-next', expected=None, first=367, last=410, color='black',
                         before={'black': [262, 280, 282, 300, 309], 'white': [60, 72, 288, 250]}))
    faults = list(scenarios(observed))+[('missing_black_timing_witnesses', [o for o in observed if o.frame not in (355, 356)], {})]
    rapid_results = []
    with gzip.open(args.output/'rapid-decisions.jsonl.gz', 'wt') as stream:
        for variant, appearance in [('original', original), ('outline_mask', masked)]:
            for fault, observations, _ in faults:
                views, last = [], None
                for o in observations:
                    views.append(View(o.frame, o.time, o.hand, o.lighting_blocked, o.raw, appearance[o.frame],
                                      last is not None and o.time-last > .5, metadata[o.frame].get('estimate')))
                    last = o.time
                for context in contexts:
                    before = ['empty']*361
                    for color, points in context['before'].items():
                        for p in points:
                            before[p] = color
                    control = None
                    for policy in PROTOCOL['policies']:
                        model = PreHandCompetition(before, context['color'], policy, shape_map)
                        decisions, selected, first, blocked = [], set(), None, 0
                        for view in views:
                            if not context['first'] <= view.frame <= context['last']:
                                continue
                            result = model.step(view)
                            assert not result['clockAuthority'] and result['recordedFrameTiming'] == view.recorded_timing
                            assert not (result['reasons'] and result['state'] != 'unknown')
                            decisions.append({k: result[k] for k in DECISION_KEYS})
                            if result['state'] == 'placement':
                                selected.add(result['selected'])
                                first = first or result['confirmedAt']
                                blocked += any(metadata[w['frame']]['handObstructed'] is not False for w in result['witnesses'])
                            stream.write(json.dumps(dict(variant=variant, fault=fault, context=context['name'],
                                                         policy=policy, frame=view.frame, result=result))+'\n')
                        if policy == 'control':
                            control = decisions
                        rapid_results.append(dict(variant=variant, fault=fault, context=context['name'], policy=policy,
                            selected=sorted(selected), first=first, expected=context['expected'], frames=len(decisions),
                            changedRows=sum(a != b for a, b in zip(control, decisions)),
                            originallyBlockedWitnessSelections=blocked, revisions=model.revisions))
    write_json(args.output/'rapid-contexts.json', rapid_results)
    summary = {'photos': {}, 'rapid': {}, 'nativeChangedPointReadings': len(native_changes),
               'limitations': 'Photos are two identical synthetic witnesses, not temporal validation. 12 Black edge point/frame probes represent two stones in one setup.'}
    for variant in ('original', 'outline_mask'):
        for fault in ('recorded_shapes', 'outline_dropout'):
            for policy in ('control', 'edge_shape', 'combined'):
                batch = [r for r in photo_results if (r['variant'], r['fault'], r['policy']) == (variant, fault, policy)]
                summary['photos']['/'.join((variant, fault, policy))] = {
                    'probes': len(batch), 'recognized': sum(r['selected'] == r['point'] for r in batch),
                    'wrongLocations': sum(r['selected'] is not None and r['selected'] != r['point'] for r in batch),
                    'blackEdgeProbes': sum(r['color'] == 'black' and r['edge'] for r in batch),
                    'blackEdgeRecognized': sum(r['color'] == 'black' and r['edge'] and r['selected'] == r['point'] for r in batch)}
        for policy in PROTOCOL['policies']:
            batch = [r for r in rapid_results if r['variant'] == variant and r['policy'] == policy]
            summary['rapid'][variant+'/'+policy] = {'contexts': len(batch), 'frames': sum(r['frames'] for r in batch),
                'changedDecisionTimingRows': sum(r['changedRows'] for r in batch),
                'wrongPoints': sum(bool(set(r['selected'])-({r['expected']} if r['expected'] is not None else set())) for r in batch),
                'originallyBlockedWitnessSelections': sum(r['originallyBlockedWitnessSelections'] for r in batch)}
    write_json(args.output/'summary.json', summary)
    inputs.update(Path(__file__).with_name(n) for n in ('run_prehand_legacy.py', 'prehand_lab.py', 'prehand_protocol.json',
        'replay_outline_sampling.py', 'outline_sampling_experiment.py', 'placement_competition_lab.py', 'unavailable_shadow_lab.py',
        'unchanged_baseline_lab.py', 'evaluate_unavailable_shadow.py'))
    write_json(args.output/'manifest.json', {'inputs': {str(p): digest(p) for p in sorted(inputs)}})
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('evidence', 'shapes', 'corpus', 'previous', 'sequence', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    main(parser.parse_args())
