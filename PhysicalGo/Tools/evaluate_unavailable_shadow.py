#!/usr/bin/env python3
"""Offline ablations on reviewed points, older delivery faults and focused video."""
import argparse
from collections import Counter
import json
from pathlib import Path

import cv2
import numpy as np

from fresh_game_confidence import contact_sheets, ordered_readings
from local_quality_lab import digest, read_image
from placement_competition_lab import PlacementCompetition, View, appearance_features
from recognition_parameter_search import live_fingerprint, write_json
from unchanged_baseline_lab import Observation, Sampler, features, occupancy, scenarios
from unavailable_shadow_lab import POLICIES, PROTOCOL, SupportFilter, assess, measured_contrast


class Pixels:
    def __init__(self):
        self.sampler = None
        self.references = {}
        self.inputs = set()

    def samples(self, path, calibration):
        self.inputs.add(Path(path))
        image = read_image(Path(path), calibration)
        if self.sampler is None:
            self.sampler = Sampler(image[0].shape)
        core, wood = self.sampler.sample(image)
        return core, wood, image[0]

    def reference(self, path, calibration):
        key = (str(path), json.dumps(calibration, sort_keys=True))
        if key not in self.references:
            self.references[key] = self.samples(path, calibration)[:2]
        return self.references[key]

    def augment(self, path, calibration, reference, reference_calibration, appearances):
        result = [dict(a) for a in appearances]
        missing = [p for p, a in enumerate(result) if a['signedCoreDelta'] is None]
        if missing:
            core, _, _ = self.samples(path, calibration)
            old, _ = self.reference(reference, reference_calibration)
            for p in missing:
                result[p]['measuredCoreDelta'] = measured_contrast(core[p], old[p], result[p])
        return result


def point_scores(rows):
    result = {}
    for policy in POLICIES:
        scored = [{**{k: r[k] for k in ('case', 'frame', 'point', 'truth', 'kind')},
                   'predicted': r['reading']['occupancy'],
                   **assess(policy, r['point'], r['reading'], r['appearance'], r['shapes'])}
                  for r in rows if r['reading']['occupancy'] in ('black', 'white')]
        result[policy] = {'rows': scored,
            'strongCorrect': sum(r['predicted'] == r['truth'] and r['support'] >= .65 for r in scored),
            'strongWrong': sum(r['predicted'] != r['truth'] and r['support'] >= .65 for r in scored),
            'afterPlacementStrong': sum(r['kind'] == 'placement-after' and r['predicted'] == r['truth'] and r['support'] >= .65 for r in scored),
            'lostCorrectVersusNeutral': [r for r in scored if r['predicted'] == r['truth'] and r['baselineSupport'] >= .65 > r['support']]}
    return result


def old_replays(previous, sequence, corpus, pixels, output):
    labels = json.loads(Path(__file__).with_name('local_quality_labels.json').read_text())
    shapes = {f['frameID']: f.get('footprints', [])+f.get('placementFits', []) for f in sequence['frames']}
    metadata = {f['frameID']: f for f in sequence['frames']}
    appearances = {a['frame']: a['appearance'] for a in map(json.loads, (previous/'appearance-evidence.jsonl').open()) if a['case'] == 'rapid-recorded'}
    boards = {int(b['id']): b for b in json.loads((corpus/'timeline/boards.json').read_text())}
    anchor = boards[306]
    for frame, values in appearances.items():
        b = boards[frame]
        appearances[frame] = pixels.augment(b['image'], b['calibration'], anchor['image'], anchor['calibration'], values)
    observed = [Observation(o['frame'], o['capturedAt'], o['hand'], o['lightingBlocked'], o['rawReadings'], [], [])
                for o in map(json.loads, (previous/'observations.jsonl').open()) if o['case'] == 'rapid-recorded']
    contexts = [{'name': name, **ep, 'expected': target} for name, target, ep in
                zip(('white8', 'black9', 'white10'), (288, 309, 250), labels['episodes'])]
    contexts.append({'name': 'black-next', 'first': 367, 'last': 410, 'color': 'black', 'expected': None,
                     'before': {'black': [262, 280, 282, 300, 309], 'white': [60, 72, 288, 250]}})
    faults = list(scenarios(observed))
    faults.append(('missing_black_timing_witnesses', [o for o in observed if o.frame not in (355, 356)], {}))
    summary = {}
    for policy in POLICIES:
        results = {}
        with (output/f'rapid-{policy}.jsonl').open('w') as stream:
            for scenario, observations, _ in faults:
                previous_time = None
                views = []
                for o in observations:
                    gap = previous_time is not None and o.time-previous_time > .5
                    views.append(View(o.frame, o.time, o.hand, o.lighting_blocked, o.raw, appearances[o.frame], gap, metadata[o.frame].get('estimate')))
                    previous_time = o.time
                for context in contexts:
                    gate = SupportFilter(policy, shapes)
                    model = PlacementCompetition(occupancy(context['before']), context['color'], 'black_shadow_independent', support_filter=gate)
                    chosen, first, violations, blocked_witness = set(), None, 0, 0
                    for view in views:
                        if not context['first'] <= view.frame <= context['last']:
                            continue
                        result = model.step(view)
                        assert result['recordedFrameTiming'] == metadata[view.frame].get('estimate')
                        assert not result['clockAuthority']
                        if result['state'] == 'placement':
                            chosen.add(result['selected'])
                            if first is None:
                                first = {k: result[k] for k in ('selected', 'confirmedAt', 'firstSeen', 'firstSupported', 'witnesses')}
                            blocked_witness += any(metadata[w['frame']]['handObstructed'] is not False for w in result['witnesses'])
                        violations += bool(result['reasons']) and result['state'] != 'unknown'
                        stream.write(json.dumps({'scenario': scenario, 'context': context['name'], 'frame': view.frame, 'capturedAt': view.time, 'result': result})+'\n')
                    results[f'{scenario}/{context["name"]}'] = {'selected': sorted(chosen), 'first': first,
                        'recognizedExpected': context['expected'] in chosen if context['expected'] is not None else None,
                        'wrongPoints': sorted(chosen-({context['expected']} if context['expected'] is not None else set())),
                        'guardViolations': int(violations), 'originallyBlockedWitnessSelections': blocked_witness}
        summary[policy] = results
    return summary


def focused_video(snapshot, pixels, output):
    """Causal per-point support runs; NOT a full-game or capture decoder.

    Windows chosen from the already inspected failure and real-stone regression.
    Original gaps/hand flags are preserved. No future clean frame is consulted.
    """
    windows = [('real-black21', 73, 520, 575), ('empty-edge', 75, 1230, 1330)]
    frames, operations = {}, {}
    for line in (snapshot/'capture/events.jsonl').open():
        d = json.loads(line)
        if d['event'] == 'frame':
            frames[d['frameID']] = d
        elif d['event'] == 'operation finished':
            operations[d['frameID']] = d
    rows, images, proposals = [], {}, []
    for name, point, first, last in windows:
        previous = None
        for frame, op in sorted(operations.items()):
            if not first <= frame <= last or len(op.get('unadaptedReadings', op.get('readings', []))) != 361:
                continue
            meta = frames[frame]
            core, wood, gray = pixels.samples(snapshot/'capture'/meta['image'], op.get('calibration') or meta['calibration'])
            old_core, old_wood = pixels.reference(snapshot/'capture'/meta['referenceImage'], meta['referenceCalibration'])
            metric = features([core[point]], [wood[point]], [old_core[point]], [old_wood[point]])
            o = Observation(frame, meta['captureUptime'], False, False, [], [core[point]], metric)
            appearance = appearance_features(o, [old_core[point]])[0]
            appearance['measuredCoreDelta'] = measured_contrast(core[point], old_core[point], appearance)
            hand = op.get('handOutline', {}).get('obstructed')
            blocked = bool(op.get('lightingBlocked') or op.get('exposureFailure') or op['outcome'] != 'delivered to recorder')
            gap = previous is not None and meta['captureUptime']-previous > .5
            previous = meta['captureUptime']
            reading = ordered_readings(op.get('unadaptedReadings') or op['readings'])[point]
            rows.append({'case': name, 'frame': frame, 'capturedAt': meta['captureUptime'], 'point': point,
                         'reading': reading, 'appearance': appearance, 'shapes': op.get('footprints', [])+op.get('placementFits', []),
                         'hand': hand, 'lightingBlocked': blocked, 'gapBefore': gap})
            images[frame] = np.rint(gray*255).astype(np.uint8)
            proposals.append({'id': f'{name}-{frame}', 'frame': frame, 'point': point, 'truth': None,
                              'case': name, 'hand': hand, 'lightingBlocked': blocked})
    write_json(output/'focused-observations.json', rows)
    write_json(output/'focused-review-proposals.json', proposals)
    contact_sheets(proposals, images, output, 'focused-review')
    results = {}
    for policy in POLICIES:
        cases = {}
        contexts = [(name, name, first, last) for name, _, first, last in windows]
        # Explicit supplied-context probe after a visually reviewed empty frame.
        # It does not silently reset the original window's latched camera gap.
        contexts.append(('real-black21-reviewed-context', 'real-black21', 534, 575))
        for name, source_case, first, last in contexts:
            run, first_seen, first_selected, decisions, gap_review = [], None, None, [], False
            for r in [r for r in rows if r['case'] == source_case and first <= r['frame'] <= last]:
                point = r['point']
                gap_review |= r['gapBefore']
                stone = r['reading']['occupancy'] == 'black'
                stamp = {'frame': r['frame'], 'capturedAt': r['capturedAt']}
                if stone and first_seen is None:
                    first_seen = stamp
                assessment = assess(policy, point, r['reading'], r['appearance'], r['shapes']) if stone else None
                supported = stone and r['hand'] is False and not r['lightingBlocked'] and not gap_review and assessment['support'] >= .65
                if supported:
                    run.append(stamp)
                else:
                    run.clear()
                eligible = len(run) >= 2 and run[-1]['capturedAt']-run[0]['capturedAt'] >= .12
                decision = {'frame': r['frame'], 'capturedAt': r['capturedAt'], 'supported': bool(supported),
                            'eligible': eligible, 'firstSeen': first_seen, 'witnesses': list(run),
                            'firstSupported': run[0] if run else None, 'gapReview': gap_review,
                            'assessment': assessment, 'clockAuthority': False}
                decisions.append(decision)
                if eligible and first_selected is None:
                    first_selected = decision
            cases[name] = {'firstEligible': first_selected, 'eligibleFrames': [d['frame'] for d in decisions if d['eligible']],
                           'supportedFrames': [d['frame'] for d in decisions if d['supported']], 'decisions': decisions,
                           'conditionalContext': ('Manually reviewed empty point at frame534, after an earlier gap. Point-only probe, not automatic recovery.'
                                                  if name.endswith('reviewed-context') else 'Original window: gaps latch review without reset.')}
        results[policy] = cases
    write_json(output/'focused-results.json', results)
    labels_path = Path(__file__).with_name('unavailable_shadow_focus_labels.json')
    labels = json.loads(labels_path.read_text())
    assert labels['status'] == 'assistant-image-reviewed-points'
    assert labels['sourceEventsSHA256'] == digest(snapshot/'capture/events.jsonl')
    truth = {(r['case'], r['frame'], r['point']): r['truth'] for r in labels['points']}
    scored = {}
    for policy in POLICIES:
        counts = Counter()
        for r in rows:
            label = truth[(r['case'], r['frame'], r['point'])]
            counts['excludedOccluded'] += label is None
            if label is None:
                continue
            counts['reviewedPoints'] += 1
            if r['reading']['occupancy'] != 'black':
                continue
            strong = assess(policy, r['point'], r['reading'], r['appearance'], r['shapes'])['support'] >= .65
            counts['strongCorrectPointFrames' if label == 'black' else 'strongFalsePointFrames'] += strong
            if r['hand'] is False and not r['lightingBlocked']:
                counts['clearStrongCorrectPointFrames' if label == 'black' else 'clearStrongFalsePointFrames'] += strong
        scored[policy] = dict(counts)
    write_json(output/'focused-point-scores.json', scored)
    return results


def main(args):
    if args.output.exists() or args.output.resolve().is_relative_to(Path(__file__).resolve().parents[2]):
        raise ValueError('Use a new external output folder')
    args.output.mkdir(parents=True)
    root = Path(__file__).resolve().parents[1]
    before = live_fingerprint(root)
    write_json(args.output/'plan.json', {'protocol': dict(PROTOCOL), 'liveSourceBefore': before,
                                        'limitations': 'Previously inspected development data; current-pixel and conditional replay evidence only. No clock/capture authority.'})
    pixels = Pixels()
    prepared = {d['frame']: d for d in map(json.loads, (args.prepared/'evidence.jsonl').open())}
    labels_path = Path(__file__).with_name('fresh_game_confidence_labels.json')
    labels = json.loads(labels_path.read_text())
    assert labels['sourceEventsSHA256'] == digest(args.snapshot/'capture/events.jsonl')
    fresh = []
    for frame, d in prepared.items():
        meta = d['recordedOperation']
        # Reference calibration is in the saved capture's session and is constant
        # in this game; verify that with the capture frame records below.
        reference_cal = json.loads((args.snapshot/'capture/session.json').read_text())['referenceCalibration']
        d['augmented'] = pixels.augment(d['image'], meta['calibration'], d['referenceImage'], reference_cal, d['appearance'])
    expected_ref = json.loads((args.snapshot/'capture/session.json').read_text())['referenceCalibration']
    for line in (args.snapshot/'capture/events.jsonl').open():
        d = json.loads(line)
        if d['event'] == 'frame' and d['frameID'] in prepared:
            assert d['referenceCalibration'] == expected_ref
    for label in labels['points']:
        d, p = prepared[label['frame']], label['point']
        op = d['recordedOperation']
        fresh.append({'case': 'fresh-reviewed', 'frame': d['frame'], 'point': p, 'truth': label['truth'], 'kind': label['kind'],
                      'reading': d['rawReadings'][p], 'appearance': d['augmented'][p], 'shapes': op.get('footprints', [])+op.get('placementFits', [])})
    print('Scoring reviewed fresh points and older photos', flush=True)
    fresh_scores = point_scores(fresh)
    appearances = {a['case']: a['appearance'] for a in map(json.loads, (args.previous/'appearance-evidence.jsonl').open()) if a.get('syntheticPersistence')}
    readings = {b['board']: b['readings'] for b in json.loads((args.corpus/'baseline.json').read_text())}
    photos = []
    for b in json.loads((args.corpus/'boards.json').read_text()):
        if b['group'] == 'incident':
            continue
        augmented = pixels.augment(b['image'], b['calibration'], b['reference'], b['referenceCalibration'], appearances[b['id']])
        for p, truth in enumerate(b['expected']):
            photos.append({'case': b['id'], 'frame': 1, 'point': p, 'truth': truth, 'kind': 'photo',
                           'reading': readings[b['id']][p], 'appearance': augmented[p], 'shapes': []})
    photo_scores = point_scores(photos)
    print('Replaying older hand/gap/capture guards', flush=True)
    sequence = json.loads(args.sequence.read_text())
    replay = old_replays(args.previous, sequence, args.corpus, pixels, args.output)
    print('Measuring focused video windows', flush=True)
    focused = focused_video(args.snapshot, pixels, args.output)
    write_json(args.output/'point-evidence.json', fresh+photos)
    summary = {'status': 'OFFLINE ONLY; inspected development data; not promoted',
               'fresh': fresh_scores, 'photos': photo_scores, 'rapidReplay': replay,
               'focusedPointScores': json.loads((args.output/'focused-point-scores.json').read_text()),
               'focused': {policy: {case: {k: v for k, v in r.items() if k != 'decisions'} for case, r in cases.items()} for policy, cases in focused.items()},
               'liveSourcesUnchanged': before == live_fingerprint(root),
               'limits': ['All data inspected development data; no generalization claim.',
                          '65-point check measures support, not end-to-end move timing.',
                          'Photo outline metadata unavailable; outline-only ablation conservatively holds missing evidence there.',
                          'Focused candidate runs do not resolve full-board legality or captures.',
                          'Missing-hand injections cannot prove actual hands absent; original-blocked witnesses are reported.',
                          'Contrast margin is heuristic, not a probability or statistical error bound.']}
    write_json(args.output/'summary.json', summary)
    inputs = pixels.inputs | {args.prepared/'evidence.jsonl', args.previous/'observations.jsonl', args.previous/'appearance-evidence.jsonl',
                              args.snapshot/'capture/events.jsonl', args.snapshot/'capture/session.json', labels_path, args.sequence,
                              args.corpus/'boards.json', args.corpus/'baseline.json'}
    inputs.add(args.corpus/'timeline/boards.json')
    inputs.update(Path(__file__).with_name(n) for n in ('evaluate_unavailable_shadow.py', 'unavailable_shadow_lab.py', 'unavailable_shadow_protocol.json',
                  'placement_competition_lab.py', 'placement_competition_protocol.json', 'local_quality_labels.json', 'unchanged_baseline_lab.py', 'local_quality_lab.py'))
    inputs.add(Path(__file__).with_name('unavailable_shadow_focus_labels.json'))
    write_json(args.output/'manifest.json', {'inputs': [{'path': str(p.resolve()), 'sha256': digest(p)} for p in sorted(inputs)],
                                           'liveSourceBefore': before, 'liveSourceAfter': live_fingerprint(root)})
    print(json.dumps({'freshStrongAfter': {p: s['afterPlacementStrong'] for p, s in fresh_scores.items()},
                      'freshStrongWrong': {p: s['strongWrong'] for p, s in fresh_scores.items()},
                      'photoLost': {p: len(s['lostCorrectVersusNeutral']) for p, s in photo_scores.items()},
                      'liveSourcesUnchanged': summary['liveSourcesUnchanged']}, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('previous', 'corpus', 'prepared', 'snapshot', 'sequence', 'output'):
        parser.add_argument('--'+name, required=True, type=Path)
    cv2.setNumThreads(1)
    main(parser.parse_args())
