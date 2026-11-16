#!/usr/bin/env python3
"""Replay conditional single-placement probes; never advances a live game."""
import argparse
import json
from pathlib import Path

import cv2

from local_quality_lab import digest
from placement_competition_lab import METHODS, PROTOCOL, PlacementCompetition, View, appearance_features
from recognition_parameter_search import input_signature, live_fingerprint, prepare, write_json
from unchanged_baseline_lab import occupancy, scenarios


def views(observations, appearances, recorded):
    previous = None
    result = []
    for o in observations:
        gap = previous is not None and o.time-previous > PROTOCOL['maximumGap']
        previous = o.time
        result.append(View(o.frame, o.time, o.hand, o.lighting_blocked, o.raw,
                           appearances[o.frame], gap, recorded.get(o.frame, {}).get('estimate')))
    return result


def snapshot_truth(before, color, truth):
    """Score only labeled, compatible one-placement/no-placement situations."""
    if any(old != 'empty' and value != old for old, value in zip(before, truth)):
        return None
    changes = [(p, value) for p, (old, value) in enumerate(zip(before, truth)) if old == 'empty' and value != 'empty']
    if not changes:
        return ('no_move', None)
    if len(changes) == 1 and changes[0][1] == color:
        return ('placement', changes[0][0])
    return None


def replay(name, sequence, before, color, method, truth, expected_point, output,
           original_hand=None, synthetic=False, retain_trace=True):
    model = PlacementCompetition(before, color, method)
    counts = dict(correctPlacements=0, wrongPlacements=0, correctNoMove=0, falseNoMove=0,
                  unknown=0, scoredFrames=0, guardViolations=0)
    first_selected = None
    selected_points = set()
    selections_using_original_hand = 0
    timing_witnesses = []
    trace = (output/(name+'.jsonl')).open('w') if retain_trace else None
    try:
        for view in sequence:
            row = model.step(view)
            if row['state'] == 'placement':
                selected_points.add(row['selected'])
                if first_selected is None:
                    first_selected = {k: row[k] for k in ('selected', 'confirmedAt', 'firstSeen', 'firstSupported', 'witnesses')}
                if original_hand:
                    selections_using_original_hand += any(original_hand.get(w['frame']) is not False for w in row['witnesses'])
            if row['reasons'] and row['state'] != 'unknown':
                counts['guardViolations'] += 1
            labeled = truth.get(view.frame)
            actual = snapshot_truth(before, color, labeled) if labeled else None
            # Photo repeats are persistence stress, not independent frames.
            # Count false decisions anywhere, but final-frame recall only once.
            score = None
            if actual:
                if row['state'] == 'placement':
                    score = 'correctPlacements' if actual == ('placement', row['selected']) else 'wrongPlacements'
                elif row['state'] == 'no_move':
                    score = 'correctNoMove' if actual[0] == 'no_move' else 'falseNoMove'
                else:
                    score = 'unknown'
                if not synthetic or view is sequence[-1] or score in ('wrongPlacements', 'falseNoMove'):
                    counts[score] += 1
                    counts['scoredFrames'] += 1
            if trace:
                trace.write(json.dumps({'frame': view.frame, 'capturedAt': view.time, 'result': row,
                                        'evaluation': score}, allow_nan=False)+'\n')
        histories = model.evidence()
        for history in histories:
            if history['point'] == 309 and history['color'] == 'black':
                timing_witnesses = [e for e in history['observations'] if e['frame'] in (355, 356)]
        if retain_trace:
            write_json(output/(name+'-histories.json'), histories)
    finally:
        if trace:
            trace.close()
    wrong_points = selected_points-({expected_point} if expected_point is not None else set())
    return {'counts': counts, 'firstSelection': first_selected, 'everSelectedPoints': sorted(selected_points),
            'expectedPoint': expected_point, 'recognizedExpectedPoint': expected_point in selected_points if expected_point is not None else None,
            'wrongSelectedPoints': sorted(wrong_points), 'blackTimingWitnesses': timing_witnesses,
            'selectionsUsingOriginallyHandBlockedWitnesses': selections_using_original_hand,
            'syntheticPersistence': synthetic}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--corpus', required=True, type=Path)
    parser.add_argument('--sequence', required=True, type=Path)
    parser.add_argument('--quiet', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    if args.output.exists() or args.output.resolve().is_relative_to(root.parent):
        parser.error('Use a new external output folder')
    args.output.mkdir(parents=True)
    cv2.setNumThreads(1)
    before_source = live_fingerprint(root)
    # These prior positions are supplied test contexts, NOT automatically
    # recovered moves. In particular the Black-next probe cannot claim to have
    # inferred move 10 merely because it starts with that move in its context.
    label_path = Path(__file__).with_name('local_quality_labels.json')
    labels = json.loads(label_path.read_text())
    contexts = [{'name': name, **episode, 'expectedPoint': target}
                for name, target, episode in zip(('white8', 'black9', 'white10'), (288, 309, 250), labels['episodes'])]
    final_position = {'black': [262, 280, 282, 300, 309], 'white': [60, 72, 288, 250]}
    contexts.append({'name': 'black-next-probe', 'first': 367, 'last': 410, 'color': 'black',
                     'before': final_position, 'expectedPoint': None})
    write_json(args.output/'plan.json', {'protocol': dict(PROTOCOL), 'methods': METHODS,
                                        'contexts': contexts, 'liveSourceBefore': before_source,
                                        'authority': 'Offline conditional suggestions only; no clock presses or legal history changes',
                                        'acceptance': ['No wrong placements or false no-move on reviewed frames',
                                                       'All three real locations retained in recorded conditional contexts',
                                                       'Black 355/356 witnesses preserved and selected by 356',
                                                       'Removing 355/356 cannot produce a Black placement in its context',
                                                       'Compare appearance-only and raw competition controls',
                                                       'No live integration; fresh-session and native-clock validation still required']})
    print('Preparing preserved captured pixels', flush=True)
    split = {'trainingPhotoGroups': ['shaded', 'shaded-empty', 'faint', 'faint-empty', 'club', 'club-empty'],
             'validationPhotoGroups': ['FaintCaptureQ3', 'JadeWhiteA19']}
    training, validation, _, inputs = prepare(args.corpus, args.sequence, args.quiet, split, args.output)
    signature = input_signature(training+validation)
    rapid, quiet = training[:2]
    photos = training[2:]+validation
    recorded = {f['frameID']: f for f in json.loads(args.sequence.read_text())['frames']}
    write_json(args.output/'recorded-native-frames.json', list(recorded.values()))
    appearances = {o.frame: appearance_features(o, rapid.observations[0].core) for o in rapid.observations}
    quiet_appearance = {o.frame: appearance_features(o, quiet.observations[0].core) for o in quiet.observations}
    photo_sequences = {}
    for case in photos:
        # These deliberately repeated views all reference the same captured
        # photo. Sampling it repeatedly supplies no new appearance information.
        evidence = appearance_features(case.observations[1], case.observations[0].core)
        photo_sequences[case.name] = views(case.observations[1:],
                                           {o.frame: evidence for o in case.observations[1:]}, {})
    with (args.output/'appearance-evidence.jsonl').open('w') as stream:
        for case, values in ((rapid, appearances), (quiet, quiet_appearance)):
            for o in case.observations:
                stream.write(json.dumps({'case': case.name, 'frame': o.frame, 'capturedAt': o.time,
                                         'appearance': values[o.frame]}, allow_nan=False)+'\n')
        for case in photos:
            stream.write(json.dumps({'case': case.name, 'syntheticPersistence': True,
                                     'appearance': photo_sequences[case.name][0].appearance}, allow_nan=False)+'\n')
    injected = list(scenarios(rapid.observations))
    injected.append(('missing_black_timing_witnesses', [o for o in rapid.observations if o.frame not in (355, 356)],
                     {'description': 'Remove only Black timing witnesses; preserve the resulting real camera gap'}))
    results = {}
    original_hand = {o.frame: o.hand for o in rapid.observations}
    for method in METHODS:
        print('Evaluating '+method, flush=True)
        folder = args.output/method
        folder.mkdir()
        method_result = {'scenarios': {}, 'photos': {}}
        for scenario, observations, description in injected:
            sequence = views(observations, appearances, recorded)
            result = {}
            for context in contexts:
                selected_views = [v for v in sequence if context['first'] <= v.frame <= context['last']]
                result[context['name']] = replay(scenario+'-'+context['name'], selected_views,
                                                occupancy(context['before']), context['color'], method,
                                                rapid.labels, context['expectedPoint'], folder, original_hand)
            method_result['scenarios'][scenario] = {'description': description, 'contexts': result}
        method_result['quiet'] = replay('quiet', views(quiet.observations, quiet_appearance, {})[1:],
                                        quiet.expected, 'black', method, quiet.labels, None, folder)
        for case in photos:
            physical = case.labels[25]
            sequence = photo_sequences[case.name]
            # Supplied prior-position probes, one missing actual stone at a
            # time. Other stones are known context; never decoded from labels.
            probes = {}
            targets = [p for p, color in enumerate(physical) if color != 'empty']
            for point in targets:
                prior = list(physical)
                prior[point] = 'empty'
                probe = replay(case.name+'-point-'+str(point), sequence, prior, physical[point], method,
                               case.labels, point, folder, synthetic=True, retain_trace=False)
                probes[str(point)] = probe
            # All physical stones already known: no additional placement.
            no_move = replay(case.name+'-no-move', sequence, physical, 'black', method,
                             case.labels, None, folder, synthetic=True, retain_trace=False)
            method_result['photos'][case.name] = {'knownPositionProbe': no_move, 'onePlacementProbes': probes}
        results[method] = method_result

    aggregation = {}
    for method, result in results.items():
        recorded_contexts = result['scenarios']['recorded']['contexts']
        targets = [recorded_contexts[n] for n in ('white8', 'black9', 'white10')]
        all_contexts = [c for s in result['scenarios'].values() for c in s['contexts'].values()]
        photo_probes = [p for photo in result['photos'].values() for p in photo['onePlacementProbes'].values()]
        all_probes = photo_probes+[p['knownPositionProbe'] for p in result['photos'].values()]
        black = recorded_contexts['black9']
        negative = result['scenarios']['missing_black_timing_witnesses']['contexts']['black9']
        aggregation[method] = {
            'recordedRealLocationsRecognized': sum(c['recognizedExpectedPoint'] for c in targets),
            'recordedWrongLocationContexts': sum(bool(c['wrongSelectedPoints']) for c in recorded_contexts.values()),
            'blackNextProbeWrongPoints': recorded_contexts['black-next-probe']['wrongSelectedPoints'],
            'blackConfirmedBy356': bool(black['firstSelection'] and black['firstSelection']['confirmedAt']['frame'] <= 356),
            'black355356SupportPreserved': len(black['blackTimingWitnesses']) == 2 and all(e['supported'] for e in black['blackTimingWitnesses']),
            'missingBlackWitnessesAbstained': not negative['everSelectedPoints'],
            'allScenarioWrongLocationContexts': sum(bool(c['wrongSelectedPoints']) for c in all_contexts),
            'allScenarioFalseNoMoveReadings': sum(c['counts']['falseNoMove'] for c in all_contexts),
            'allScenarioGuardViolations': sum(c['counts']['guardViolations'] for c in all_contexts),
            'faultSelectionsUsingOriginallyHandBlockedWitnesses': sum(c['selectionsUsingOriginallyHandBlockedWitnesses'] for c in all_contexts),
            'quietCounts': result['quiet']['counts'],
            'photoStoneProbes': len(photo_probes),
            'photoStoneProbesRecognized': sum(c['recognizedExpectedPoint'] for c in photo_probes),
            'photoProbesWithWrongLocation': sum(bool(c['wrongSelectedPoints']) for c in all_probes),
            'photoProbesWithFalseNoMove': sum(bool(c['counts']['falseNoMove']) for c in all_probes)}
    live_unchanged = before_source == live_fingerprint(root)
    evidence_unchanged = signature == input_signature(training+validation)
    if not live_unchanged or not evidence_unchanged:
        raise AssertionError('Live source or preserved observations changed')
    inputs.update([Path(__file__), Path(__file__).with_name('placement_competition_lab.py'),
                   Path(__file__).with_name('placement_competition_protocol.json'),
                   Path(__file__).with_name('recognition_parameter_search.py'),
                   Path(__file__).with_name('unchanged_baseline_lab.py'), Path(__file__).with_name('local_quality_lab.py')])
    manifest = {'inputs': [{'path': str(p.resolve()), 'sha256': digest(p)} for p in sorted(inputs)],
                'observationSHA256': signature, 'methods': METHODS, 'protocol': dict(PROTOCOL)}
    write_json(args.output/'manifest.json', manifest)
    summary = {'status': 'OFFLINE ONLY; no automatic promotion', 'aggregation': aggregation,
               'liveSourcesUnchanged': live_unchanged, 'observationsUnchanged': evidence_unchanged,
               'limits': ['Conditional prior positions are supplied, not automatically inferred; no end-to-end game or clock claim.',
                          'Native recorded timing estimates are preserved as unassigned frame metadata, never synthesized per candidate.',
                          'Photo repeats and one-stone-missing contexts are synthetic stress probes, not independent played moves.',
                          'All captured sessions were examined previously. This is a development experiment, not fresh validation.',
                          'The captured early B19 false reading is not an image of the later saved phantom move 11.',
                          'Appearance and competition contributions must be assessed with their separate controls.'],
               'results': results}
    write_json(args.output/'summary.json', summary)
    print(json.dumps({k: v for k, v in summary.items() if k != 'results'}, indent=2), flush=True)


if __name__ == '__main__':
    main()
