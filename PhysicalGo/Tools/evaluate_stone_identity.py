#!/usr/bin/env python3
"""Offline continuity-first replay; saved turn certificates, original recordings.

Every-turn alternatives and restricted background schedules are injected controls.
This does not discover move identity/time from pixels or run the live app.
"""
import argparse
from dataclasses import asdict
import json
from pathlib import Path

from evaluate_turn_location import load_game, make_view, sha, write
from stone_identity_lab import Location, StoneIdentityLab
from turn_location_lab import neighbors, play, View


def replay(name, contexts, turns, observations, mode):
    model = StoneIdentityLab()
    events = [(t.certified_at, 0, n, t) for n, t in enumerate(turns)]
    events += [(r['availableAt'], 1, None, r) for r in observations
               if r['capturedAt'] >= turns[0].time and r['availableAt'] >= turns[0].certified_at]
    events.sort(key=lambda e: (e[0], e[1]))
    expected_ledger, owners, frames = [], {}, 0
    high_confidence_errors = []
    maximum_candidates, maximum_pending = 0, 0
    for _, kind, index, item in events:
        if kind == 0:
            point = contexts[index]['expected']
            candidates = {point} if mode == 'unique' else {point, *neighbors(point, 19)}
            # Deliberately use an often-wrong provisional display location. The
            # saved true intersection is an alternative, never a scoring feature.
            assert model.accept(item, candidates, preferred=min(candidates))
            expected_ledger.append(asdict(item))
            actual = play(tuple(contexts[index]['before']), item.color, point, 19)
            assert actual is not None
            victims = [owners.pop(p) for p in actual[1]]
            owners[point] = item.identity
            if victims:
                # Explicit supplied native/saved-game capture context; never
                # derive prisoner removal from the provisional guessed board.
                model.note_capture(item.identity, victims)
        else:
            if mode != 'no_location_evidence':
                relevant = {p for t in model.tracks.values() if not t.removed for p in t.locations}
                view = make_view(item, name, relevant)
                model.observe(view, {p: item['raw'][p][1] for p in view.reliable})
                model.reassess(4 if mode == 'slow_background' else 32)
            frames += 1
        assert model.ledger() == expected_ledger
        assert model.timing_review is None, 'Location uncertainty must not trigger timing review'
        maximum_candidates = max(maximum_candidates, sum(len(t.locations) for t in model.tracks.values()))
        maximum_pending = max(maximum_pending, len(model.dirty))
        for identity, track in model.tracks.items():
            if track.location_level == 'supported' and track.selected != contexts[track.number-1]['expected']:
                key = (track.number, track.selected)
                if key not in high_confidence_errors:
                    high_confidence_errors.append(key)
    # Drain background work without making additional recording observations.
    for _ in range(len(turns)*4):
        if not model.dirty:
            break
        model.reassess(32)
    before = model.ledger()
    truth = {t.identity: contexts[i]['expected'] for i, t in enumerate(turns)}
    final = model.finalize(truth)
    assert model.ledger() == before == expected_ledger
    assert len(model.turns) == len(turns)
    snapshot = model.snapshot()
    for track in snapshot.values():
        if track['locationConfidence'] == 'supported' and track['selected'] != contexts[track['number']-1]['expected']:
            key = (track['number'], track['selected'])
            if key not in high_confidence_errors:
                high_confidence_errors.append(key)
    return model, final, {
        'turns': len(model.turns), 'recordingObservations': frames,
        'locationInducedTimingReviews': 0, 'ledgerIdentical': True,
        'ledgerIdenticalAfterFinalSGF': True, 'maximumCandidates': maximum_candidates,
        'maximumBackgroundQueue': maximum_pending, 'remainingBackgroundQueue': len(model.dirty),
        'supportedLocations': sum(t['locationConfidence'] == 'supported' for t in snapshot.values()),
        'unresolvedLocations': sum(t['locationConfidence'] != 'supported' for t in snapshot.values()),
        'provisionalGuessErrors': [t['number'] for t in snapshot.values()
                                   if t['selected'] != contexts[t['number']-1]['expected']],
        'wrongSupportedLocations': high_confidence_errors,
        'physicalRemovedIdentities': [i for i, t in snapshot.items() if t['removed']],
        'verifiedCaptures': {i: c for i, c in final['captures'].items() if c},
        'provisionalCellConflicts': {p: ids for p, ids in model.provisional_board().items() if len(ids) > 1},
    }


def recorded_repositioning(root):
    folder = root/'Tests/Fixtures/RepositionedPending'
    records = json.loads((folder/'observations.json').read_text())
    # Supplied pending identity; the fixture has no certified clock timestamp.
    # Import it as an existing stone, never manufacture a timed turn.
    board = ['empty']*361
    board[15] = 'white'
    model = StoneIdentityLab(initial=board)
    track = model.tracks['setup:15']
    track.locations[34] = Location()
    track.location_level, track.established_location, track.user_confirmed = 'unresolved', None, False
    for n, r in enumerate(records):
        readings = sorted(r['readings'], key=lambda v: v['row']*19+v['col'])
        view = View(f'repositioned:{n}', r['captureUptime'], tuple(v['occupancy'] for v in readings),
                    frozenset(p for p in (15, 34) if readings[p]['confidence'] >= .98),
                    # No hand-state field is present: retain unknown, do not
                    # convert delivery to recorder into proof of hand clearance.
                    hand=None, lighting_ok=not r['lightingBlocked'])
        model.observe(view)
        model.reassess()
    assert not model.turns and len(model.tracks) == 1
    return {'observations': len(records), 'timedTurnsCreated': 0, 'identities': len(model.tracks),
            'state': model.snapshot(),
            'scope': 'Actual repositioning fixture, supplied existing identity, absent hand metadata means abstention.'}, [folder/'observations.json', folder/'README.txt']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    root = Path(__file__).resolve().parents[1]
    sources = [Path(__file__), Path(__file__).with_name('stone_identity_lab.py'),
               Path(__file__).with_name('test_stone_identity_lab.py'),
               Path(__file__).with_name('turn_location_lab.py'),
               Path(__file__).with_name('evaluate_turn_location.py')]
    originals = {str(p): sha(p) for p in [*sources, *sorted((root/'Sources').glob('*.swift'))]}
    inputs, summary = [], {}
    for name in ('game65', 'game85'):
        contexts, turns, observations, clock, timing_sources, paths = load_game(args.work, name)
        inputs += paths
        summary[name] = {}
        for mode in ('unique', 'all_ambiguous', 'no_location_evidence', 'slow_background'):
            model, final, result = replay(name, contexts, turns, observations, mode)
            summary[name][mode] = result
            write(args.output/f'{name}-{mode}-stones.json', model.snapshot())
            write(args.output/f'{name}-{mode}-audit.json', model.audit)
            write(args.output/f'{name}-{mode}-clock-input.json',
                  {'name': f'{name}-{mode}', 'original': [asdict(t) for t in turns],
                   'afterCorrection': model.ledger(), 'saved': clock['moves']})
            # This is a NEW offline export using supplied final ground truth;
            # original SGF and sidecars are never written.
            (args.output/f'{name}-{mode}-resolved.sgf').write_text(final['sgf']+'\n')
            print(name, mode, {k: result[k] for k in ('turns', 'maximumCandidates', 'supportedLocations',
                                                    'unresolvedLocations', 'wrongSupportedLocations',
                                                    'remainingBackgroundQueue')}, flush=True)
        summary[name]['timingSources'] = timing_sources
    repositioning, paths = recorded_repositioning(root)
    inputs += paths
    write(args.output/'recorded-repositioning.json', repositioning)
    summary['repositioning'] = {k: v for k, v in repositioning.items() if k != 'state'}
    summary['scope'] = ('Saved turn and capture certificates are supplied; alternative locations are injected. '
                        'Confidence is heuristic evidence, not a probability. Background work is simulated '
                        'in bounded serial slices, not installed in the app. No physical motion detector is added.')
    summary['sourcesUnchangedDuringRun'] = originals == {p: sha(Path(p)) for p in originals}
    assert summary['sourcesUnchangedDuringRun']
    write(args.output/'summary.json', summary)
    write(args.output/'manifest.json', {'sourcesBeforeAndAfter': originals,
                                      'inputs': {str(p): sha(p) for p in inputs},
                                      'calibrationPolicy': 'Original recording-specific observations; no AF660/iPhone calibration transfer.'})


if __name__ == '__main__':
    main()
