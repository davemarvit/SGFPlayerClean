#!/usr/bin/env python3
"""Chronological offline resolver experiments with explicitly supplied turn ledgers.

The two recorded games supply turn identity/order/time. Adjacent alternatives are
injected stress cases, not detector discoveries. Recording observations supply
location evidence. Never write a recording, calibration, SGF or clock sidecar.
"""
import argparse
from dataclasses import asdict, replace
import gzip
import hashlib
import json
from pathlib import Path

from turn_location_lab import TurnEvidence, TurnLocationLab, View, neighbors, play


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True)+'\n')


def load_game(work, name):
    cache = work/'prehand-stage9'/f'{name}-cache'
    plan = json.loads((cache/'plan.json').read_text())
    snapshot = Path(plan['snapshot'])
    folder = snapshot/'recording'
    clock_path = next(folder.glob('*.clock.json'))
    journal_path = next(folder.glob('*.observations.jsonl'))
    clock = json.loads(clock_path.read_text())
    rows = [json.loads(line) for line in journal_path.open()]
    accepted = {r['moveCount']: r for r in rows if r['event'] == 'accepted move'}
    contexts = [c for c in json.loads((cache/'contexts.json').read_text()) if c['expected'] is not None]
    with gzip.open(cache/'observations.jsonl.gz', 'rt') as stream:
        observations = [json.loads(line) for line in stream]
    turns, timing_sources = [], []
    for c, saved in zip(contexts, clock['moves']):
        n = c['move']
        assert saved['number'] == n
        estimate = saved.get('estimate')
        if estimate:
            t = estimate['time']
            lo, hi = estimate.get('observedLower', t), estimate.get('observedUpper', t)
            lo, hi = min(lo, t), max(hi, t)
            source = 'saved estimate'
        else:
            t = saved['after'].get('anchor')
            if t is None:
                raise ValueError(f'{name} move {n} has no recorded clock boundary')
            lo = hi = t
            source = 'saved clock anchor; physical uncertainty unavailable'
        # These identify two authoritative SAVED RECORDS, not two new image
        # witnesses. This adapter intentionally supplies the upstream contract.
        e = TurnEvidence(f'{name}:saved-turn:{n}', c['color'], t, lo, hi,
                         (f'{name}:clock:{n}', f'{name}:accepted-journal:{n}'),
                         max(accepted[n]['uptime'], hi))
        turns.append(e)
        timing_sources.append(source)
    assert len(turns) == len(contexts) == len(clock['moves'])
    inputs = [cache/'plan.json', cache/'contexts.json', cache/'observations.jsonl.gz',
              clock_path, journal_path, next(folder.glob('*.sgf')), snapshot/'capture/session.json']
    return contexts, turns, observations, clock, timing_sources, inputs


def discriminating_points(model):
    if model.position_review:
        return set()
    points = {p for path in model.paths for p, _, _ in path.debt}
    points.update(p for p in range(model.size**2) if len({path.board[p] for path in model.paths}) > 1)
    return points


def make_view(row, name, relevant, *, withhold=False):
    # Scores are heuristics, not calibrated probabilities. A high-quality bounded
    # centered outline is needed for occupied assignment; empty has its own gate.
    # Restrict this experiment to points that distinguish retained positions.
    # Surrounding camera readings never overwrite a trusted legal board.
    centered = {s['row']*19+s['col'] for s in row['shapes']
                if s.get('quality', 0) >= .9 and
                abs(s['center']['x']-s['col']) <= .24 and
                abs(s['center']['y']-s['row']) <= .24}
    reliable = {p for p in relevant if row['raw'][p][1] >= .98 and
                (row['raw'][p][0] == 'empty' or p in centered)}
    if withhold:
        reliable.clear()
    return View(f'{name}:frame:{row["frame"]}', row['capturedAt'],
                tuple(r[0] for r in row['raw']), frozenset(reliable),
                row['hand'], not row['lightingBlocked'] and row['outcome'] == 'delivered to recorder')


def experiment(name, contexts, turns, observations, target, policy, delay, multiple=False):
    start = target-1
    c = contexts[start]
    model = TurnLocationLab(19, c['before'], c['color'])
    # Trusted supplied setup includes the earlier position for simple ko.
    if start:
        from dataclasses import replace
        model.paths[0] = replace(model.paths[0], previous=tuple(contexts[start-1]['before']))
    alternatives = {c['expected']}
    alternatives.update(p for p in neighbors(c['expected'], 19)
                        if play(tuple(c['before']), c['color'], p, 19, model.paths[0].previous) is not None)
    events = [(e.certified_at, 0, i, e) for i, e in enumerate(turns) if i >= start]
    events += [(r['availableAt'], 1, None, r) for r in observations
               if r['availableAt'] >= turns[start].certified_at and r['capturedAt'] >= turns[start].time]
    events.sort(key=lambda e: (e[0], e[1]))
    max_paths, resolved, retained_truth, fed = 0, None, True, 0
    clock_policies = set()
    ledger_expected = []
    original_time = turns[start].time
    for now, kind, index, row in events:
        if kind == 0:
            locations = alternatives if index == start else {contexts[index]['expected']}
            if multiple:
                locations = {contexts[index]['expected'], *neighbors(contexts[index]['expected'], 19)}
            if not model.accept(row, locations):
                break
            ledger_expected.append(asdict(row))
        else:
            relevant = discriminating_points(model)
            view = make_view(row, name, relevant, withhold=policy == 'legality_only' or
                             row['capturedAt'] < original_time+delay)
            model.observe(view)
            fed += 1
        max_paths = max(max_paths, len(model.paths))
        clock_policies.add(model.clock_policy())
        if model.turns and not model.position_review:
            truth = tuple(x['expected'] for x in contexts[start:start+len(model.turns)])
            retained_truth &= any(p.moves == truth for p in model.paths)
            if resolved is None and len({p.moves[0] for p in model.paths}) == 1:
                resolved = {'availableAt': now, 'afterTurns': len(model.turns),
                            'point': model.paths[0].moves[0],
                            'cause': 'subsequent legal play' if kind == 0 else 'sustained recording evidence'}
        assert model.ledger() == ledger_expected
    before = model.ledger()
    pending = model.unresolved()
    correction = model.correct({i: contexts[start+i]['expected'] for i in range(len(model.turns))}
                               if multiple else {0: c['expected']})
    assert model.ledger() == before
    return {'move': target, 'expected': c['expected'], 'alternatives': sorted(alternatives),
            'ambiguousInitially': len(alternatives) > 1, 'maxPositions': max_paths,
            'resolved': resolved, 'truthRetained': retained_truth,
            'positionReview': model.position_review, 'timingReview': model.timing_review,
            'turnsAccepted': len(model.turns), 'expectedTurns': len(turns)-start,
            'recordingViews': fed, 'ledgerIdentical': model.ledger() == ledger_expected,
            'unresolvedBeforeCorrection': pending, 'clockPolicies': sorted(clock_policies),
            'correctionAccepted': correction, 'correctionPreservedLedger': model.ledger() == before,
            'audit': model.audit}


def complete_record_control(name, contexts, turns, clock):
    m = TurnLocationLab(19, capture_minimum=0)
    captures = []
    for i, (context, evidence) in enumerate(zip(contexts, turns)):
        assert m.paths[0].board == tuple(context['before'])
        assert m.accept(evidence, [context['expected']])
        assert not m.position_review and not m.timing_review
        if m.paths[0].captures[-1]:
            captures.append({'move': i+1, 'points': sorted(m.paths[0].captures[-1])})
    original = m.ledger()
    for i, c in enumerate(contexts):
        assert m.correct({i: c['expected']})
    assert original == m.ledger()
    return {'turns': len(m.turns), 'positions': len(m.paths), 'captures': captures,
            'ledgerIdenticalAfterCorrections': True,
            'correctedLedger': m.ledger(),
            'savedClockPayloadSHA256': hashlib.sha256(json.dumps(clock, sort_keys=True).encode()).hexdigest(),
            'clockScope': 'Original payload retained, no new clock arithmetic or physical timing claim.'}


def certificate_controls(name, contexts, journal_path):
    """Actual native candidate witness IDs; no invented timing from still images."""
    results = []
    for row in map(json.loads, journal_path.open()):
        if row['event'] != 'observed turn clock press':
            continue
        h = row['candidateHistory']
        estimate = h['pressEstimate']
        e = TurnEvidence(f'{name}:native-turn:{row["number"]}', h['color'], row['pressTime'],
                         estimate.get('observedLower', row['pressTime']),
                         estimate.get('observedUpper', row['pressTime']),
                         (h['firstSupportedObservationID'], h['confirmation']['observationID']), row['uptime'])
        context = contexts[row['number']-1]
        locations = {context['expected'], *neighbors(context['expected'], 19)}
        m = TurnLocationLab(19, context['before'], e.color)
        assert m.accept(e, locations)
        original = m.ledger()
        assert m.accept(e, locations) and m.correct({0: context['expected']})
        assert m.ledger() == original
        rejected = []
        mutations = {'missing_witness': replace(e, witnesses=e.witnesses[:1]),
                     'camera_gap': replace(e, continuous=False),
                     'hand_obscured': replace(e, clear=False),
                     'unreliable_color': replace(e, color_reliable=False),
                     'unreliable_identity': replace(e, identity_reliable=False),
                     'unknown_time': replace(e, timing_reliable=False)}
        for reason, bad in mutations.items():
            control = TurnLocationLab(19, context['before'], e.color)
            assert not control.accept(bad, locations) and not control.turns
            rejected.append(reason)
        results.append({'number': row['number'], 'certificate': asdict(e),
                        'correctedWithoutNewTurnOrTimestampChange': True, 'negativeControlsRejected': rejected})
    return results


def static_negative_controls(work):
    """The stage-11 static records have no independent chronological certification."""
    path = work/'lens-line-stage11/historical-fixture-decisions.json'
    rows = json.loads(path.read_text())
    controls = []
    for row in rows:
        m = TurnLocationLab()
        e = TurnEvidence(f'static:{row["case"]}:{row["point"]}', 'black', 1, 1, 1,
                         (), 1, identity_reliable=False, timing_reliable=False)
        accepted = m.accept(e, [row['point']])
        assert not accepted and not m.turns
        controls.append({'case': row['case'], 'point': row['point'], 'acceptedTurns': 0,
                         'reason': 'Static geometry cannot certify turn identity or placement time',
                         'originalAssignmentOffset': row.get('originalAssignmentOffset')})
    return controls, [path]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    root = Path(__file__).resolve().parents[1]
    live = {str(p): sha(p) for p in sorted((root/'Sources').glob('*.swift'))}
    scripts = {str(p): sha(p) for p in (Path(__file__), Path(__file__).with_name('turn_location_lab.py'),
                                      Path(__file__).with_name('test_turn_location_lab.py'))}
    inputs, summary = [], {}
    for name in ('game65', 'game85'):
        contexts, turns, observations, clock, sources, paths = load_game(args.work, name)
        inputs += paths
        certs = certificate_controls(name, contexts, next(p for p in paths if p.name.endswith('.observations.jsonl')))
        write(args.output/f'{name}-certificates.json', certs)
        control = complete_record_control(name, contexts, turns, clock)
        corrected_ledger = control.pop('correctedLedger')
        # Consumed by the separate native clock audit, using the real engine.
        write(args.output/f'{name}-clock-audit-input.json',
              {'name': name, 'original': [asdict(e) for e in turns],
               'afterCorrection': corrected_ledger, 'saved': clock['moves']})
        summary[name] = {'control': control,
                         'observations': len(observations), 'timingSources': sources,
                         'nativeCertificates': len(certs), 'certificateNegativeControls': sum(len(c['negativeControlsRejected']) for c in certs),
                         'policies': {}}
        for policy, delay in [('legality_only', 0), ('sustained', 0), ('delayed_assignment', 5)]:
            rows = [experiment(name, contexts, turns, observations, n, policy, delay)
                    for n in range(1, len(turns)+1)]
            write(args.output/f'{name}-{policy}.json', rows)
            summary[name]['policies'][policy] = {
                'probes': len(rows), 'injectedAmbiguities': sum(r['ambiguousInitially'] for r in rows),
                'resolvedBeforeCorrection': sum(r['resolved'] is not None for r in rows),
                'truthLost': [r['move'] for r in rows if not r['truthRetained']],
                'wrongResolutions': [r['move'] for r in rows if r['resolved'] and r['resolved']['point'] != r['expected']],
                'positionReviews': [r['move'] for r in rows if r['positionReview']],
                'timingReviews': [r['move'] for r in rows if r['timingReview']],
                'ledgerFailures': [r['move'] for r in rows if not r['ledgerIdentical'] or not r['correctionPreservedLedger']],
                'correctionAccepted': sum(r['correctionAccepted'] for r in rows),
                'unresolvedWithoutReview': sum(r['resolved'] is None and not r['positionReview'] for r in rows)}
            print(name, policy, summary[name]['policies'][policy], flush=True)
        multiple = experiment(name, contexts, turns, observations, 1, 'sustained', 0, multiple=True)
        write(args.output/f'{name}-multiple-ambiguities.json', multiple)
        summary[name]['multipleAmbiguities'] = {k: v for k, v in multiple.items() if k not in ('audit', 'unresolvedBeforeCorrection')}
        summary[name]['multipleAmbiguities']['unresolvedCount'] = len(multiple['unresolvedBeforeCorrection'])
        print(name, 'multiple', summary[name]['multipleAmbiguities'], flush=True)
    controls, paths = static_negative_controls(args.work)
    inputs += paths
    write(args.output/'static-controls.json', controls)
    summary['staticControls'] = len(controls)
    summary['liveSourcesUnchanged'] = live == {str(p): sha(p) for p in sorted((root/'Sources').glob('*.swift'))}
    assert scripts == {p: sha(Path(p)) for p in scripts}, 'Source changed during experiment; rerun with frozen sources'
    summary['scope'] = ('Conditional resolver stress replay. Saved native ledger supplies turns and times; '
                        'adjacent alternatives are injected. Recording observations are chronological. '
                        'No new identity detector, clock press certification, physical timing accuracy, '
                        'calibration transfer, or production promotion is claimed.')
    inputs += [Path(__file__), Path(__file__).with_name('turn_location_lab.py'),
               Path(__file__).with_name('test_turn_location_lab.py')]
    write(args.output/'manifest.json', {'inputs': [{'path': str(p), 'sha256': sha(p)} for p in inputs],
                                      'liveSources': live,
                                      'cameraPolicy': 'Use each recording’s existing native observations. No lens/grid fitting or device transfer.'})
    write(args.output/'summary.json', summary)


if __name__ == '__main__':
    main()
