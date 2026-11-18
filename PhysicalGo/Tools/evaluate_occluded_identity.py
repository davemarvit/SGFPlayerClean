#!/usr/bin/env python3
"""Replay real hand visits; supplied saved turns remain independent of association."""
import argparse
from dataclasses import asdict
import json
from pathlib import Path

from evaluate_turn_location import load_game, sha, write
from occluded_identity_lab import Anchor, OccludedIdentityBridge, disks_from_row, distance
from stone_identity_lab import StoneIdentityLab
from turn_location_lab import neighbors, play


def usable(row):
    return row['hand'] is False and not row['lightingBlocked'] and row['outcome'] == 'delivered to recorder'


def episode_windows(rows):
    for i in range(4, len(rows)):
        if rows[i]['hand'] is not True or not all(usable(r) for r in rows[i-4:i]):
            continue
        j = i
        while j < len(rows) and rows[j]['hand'] is not False:
            j += 1
        end = j
        while end < len(rows) and rows[end]['hand'] is False and rows[end]['capturedAt']-rows[j]['capturedAt'] <= 6:
            end += 1
        if j < len(rows):
            yield i, j, end


def native_contexts(contexts, turns):
    owners, retired, states = {}, set(), []
    for c, turn in zip(contexts, turns):
        _, captured = play(tuple(c['before']), turn.color, c['expected'], 19)
        for p in captured:
            retired.add(owners.pop(p))
        owners[c['expected']] = turn.identity
        states.append((turn.certified_at, dict(owners), set(retired)))
    return states


def context_at(states, time):
    return next(((owners, retired) for t, owners, retired in reversed(states) if t <= time), ({}, set()))


def anchors_for(before, owners, turns_by_id, disks, name):
    anchors, points = [], {}
    for p, token in owners.items():
        matches = [[d for d in disks[r['frame']] if p in d.points and d.color == turns_by_id[token].color]
                   for r in before]
        if any(len(m) != 1 for m in matches):
            continue
        observed = [m[0] for m in matches]
        # One pre-hand disk cannot anchor multiple known same-color identities.
        if any(sum(q in d.points and turns_by_id[t].color == d.color for q, t in owners.items()) != 1 for d in observed):
            continue
        if max(distance(observed[0], d) for d in observed) > .12:
            continue
        times = [r['capturedAt'] for r in before]
        if times[-1]-times[0] < .4 or any(b-a > .75 for a, b in zip(times, times[1:])):
            continue
        anchors.append(Anchor(token, observed[-1], tuple(f'{name}:{r["frame"]}' for r in before), times[0], times[-1]))
        points[token] = p
    return anchors, points


def replay_game(name, contexts, turns, rows, snapshot):
    states = native_contexts(contexts, turns)
    by_id = {t.identity: t for t in turns}
    disks = {r['frame']: disks_from_row(r) for r in rows}
    meta = {r['frameID']: r for r in map(json.loads, (snapshot/'capture/events.jsonl').open()) if r['event'] == 'frame'}
    def epoch(row):
        f = meta[row['frame']]
        return f'{name}:{f.get("cameraID")}:{f.get("gridGeneration")}'
    episodes = []
    for i, first_clear, end in episode_windows(rows):
        before = rows[i-4:i]
        owners, _ = context_at(states, before[-1]['availableAt'])
        anchors, points = anchors_for(before, owners, by_id, disks, name)
        if not anchors or len({epoch(r) for r in before}) != 1:
            continue
        variants = {}
        for variant in ('original', 'camera_gap', 'unknown_hand', 'all_anchors_captured'):
            model = OccludedIdentityBridge(anchors, epoch=epoch(before[-1]))
            first_hypotheses, disagreements, covered_support = {}, [], []
            for k in range(i, end):
                r = rows[k]
                _, retired = context_at(states, r['availableAt'])
                if variant == 'all_anchors_captured':
                    retired = retired | set(points)
                hand = None if variant == 'unknown_hand' and r['hand'] is True else r['hand']
                model.observe(f'{name}:{r["frame"]}', r['capturedAt'], disks[r['frame']], hand=hand,
                              epoch=epoch(r), lighting_ok=not r['lightingBlocked'],
                              gap_before=variant == 'camera_gap' and k == i, captured=retired)
                for token, h in model.hypotheses.items():
                    first_hypotheses.setdefault(token, h)
                    # Conditional check against the original saved intersection.
                    # Visual labels below independently review the moved samples.
                    if points[token] not in h['candidatePoints']:
                        disagreements.append({'identity': token, 'frame': r['frame'], 'points': h['candidatePoints']})
                    if r['hand'] is not False:
                        covered_support.append({'identity': token, 'frame': r['frame']})
            variants[variant] = {**model.result(), 'everSupported': first_hypotheses,
                                 'savedPointDisagreements': disagreements, 'supportedDuringRecordedHand': covered_support}
            if variant != 'original':
                assert not first_hypotheses, f'{variant} must not certify a fresh association'
        episodes.append({'game': name, 'before': before[-1]['frame'], 'handFirst': rows[i]['frame'],
                         'handLast': rows[first_clear-1]['frame'], 'firstClear': rows[first_clear]['frame'],
                         'preHandTime': before[-1]['capturedAt'], 'anchorPoints': points,
                         'resultAvailableAt': rows[end-1]['availableAt'] if end > i else rows[i]['availableAt'],
                         'anchorCount': len(anchors), 'observations': end-i, 'variants': variants})
    # Entire supplied chronological turn ledger remains live even if every
    # association above abstains. No hand-association result enters accept().
    ledger_model = StoneIdentityLab()
    chronology = [(t.certified_at, 0, n, t) for n, t in enumerate(turns)]
    chronology += [(e['resultAvailableAt'], 1, None, e) for e in episodes]
    updates, current_owners = 0, {}
    for _, kind, index, value in sorted(chronology, key=lambda x: (x[0], x[1])):
        if kind == 0:
            c, turn = contexts[index], value
            assert ledger_model.accept(turn, {c['expected'], *neighbors(c['expected'], 19)})
            _, captured = play(tuple(c['before']), turn.color, c['expected'], 19)
            victims = [current_owners.pop(p) for p in captured]
            current_owners[c['expected']] = turn.identity
            if victims:
                ledger_model.note_capture(turn.identity, victims)
        else:
            before = ledger_model.ledger()
            for token, hypothesis in value['variants']['original']['hypotheses'].items():
                track = ledger_model.tracks[token]
                assert track.color == hypothesis['color'] and track.capture_by is None
                # Retain the proposed physical center beside the existing token.
                # Do NOT convert a hidden-object hypothesis into certified
                # identity continuity or an authoritative historical edit.
                ledger_model.audit.append({'event': 'deferred physical association', **hypothesis})
                updates += 1
            assert ledger_model.ledger() == before
    assert ledger_model.ledger() == [asdict(t) for t in turns] and ledger_model.timing_review is None
    return episodes, ledger_model.ledger(), updates


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    root = Path(__file__).resolve().parents[1]
    source_paths = [Path(__file__), Path(__file__).with_name('occluded_identity_lab.py'),
                    Path(__file__).with_name('test_occluded_identity_lab.py'),
                    Path(__file__).with_name('occluded_cleanup_labels.json'),
                    Path(__file__).with_name('stone_identity_lab.py'),
                    Path(__file__).with_name('turn_location_lab.py'),
                    Path(__file__).with_name('evaluate_turn_location.py')]
    before_hashes = {str(p): sha(p) for p in source_paths+list((root/'Sources').glob('*.swift'))}
    labels = json.loads(Path(__file__).with_name('occluded_cleanup_labels.json').read_text())['cases']
    summary, inputs, all_episodes = {}, [], []
    for name in ('game65', 'game85'):
        contexts, turns, rows, clock, _, paths = load_game(args.work, name)
        snapshot = Path(json.loads(next(p for p in paths if p.name == 'plan.json').read_text())['snapshot'])
        inputs += paths+[snapshot/'capture/events.jsonl']
        episodes, ledger, updates = replay_game(name, contexts, turns, rows, snapshot)
        all_episodes += episodes
        write(args.output/f'{name}-episodes.json', episodes)
        write(args.output/f'{name}-clock-input.json', {'name': name, 'original': [asdict(t) for t in turns],
                                                    'afterCorrection': ledger, 'saved': clock['moves']})
        originals = [e['variants']['original'] for e in episodes]
        summary[name] = {'handVisitsWithStableAnchors': len(episodes),
                         'preHandIdentityEpisodes': sum(e['anchorCount'] for e in episodes),
                         'supportedIdentityEpisodes': sum(len(r['everSupported']) for r in originals),
                         'savedPointDisagreements': sum(len(r['savedPointDisagreements']) for r in originals),
                         'supportedDuringRecordedHand': sum(len(r['supportedDuringRecordedHand']) for r in originals),
                         'interruptedVisits': sum(r['interrupted'] is not None for r in originals),
                         'captureExclusions': sum(len(set(r['retired']) & set(e['anchorPoints'])) for e, r in zip(episodes, originals)),
                         'faultControlsAbstained': 3*len(episodes), 'turnsPreserved': len(turns),
                         'associationUpdatesInterleavedWithTurns': updates,
                         'clockCommandsFromAssociation': 0, 'ledgerIdentical': True}
        print(name, summary[name], flush=True)
        # Hash independently reviewed original recordings, not just their logs.
        wanted = {f for label in labels if label['game'] == name for f in label['reviewedFrames']}
        for line in (snapshot/'capture/events.jsonl').open():
            r = json.loads(line)
            if r['event'] == 'frame' and r['frameID'] in wanted:
                inputs.append(snapshot/'capture'/r['image'])
    checks = []
    for label in labels:
        episode = next((e for e in all_episodes if e['game'] == label['game'] and e['handFirst'] == label['handFirst']), None)
        token = next((i for i, p in episode['anchorPoints'].items() if p == label['point']), None) if episode else None
        result = episode['variants']['original'] if episode else None
        checks.append({**label, 'anchoredIdentity': token,
                       'association': result['everSupported'].get(token) if result else None,
                       'interruption': result['interrupted'] if result else 'no stable pre-hand episode'})
    write(args.output/'reviewed-cleanups.json', checks)
    summary['reviewedCases'] = len(checks)
    summary['handCoveredAdjustmentCases'] = sum(c['targetCovered'] for c in checks)
    summary['handCoveredAdjustmentsAssociated'] = sum(c['targetCovered'] and c['association'] is not None for c in checks)
    summary['scope'] = ('Source turns and capture facts supplied; identity hypotheses use recorded fractional outlines across real hand visits. '
                        'Neither physical object identity under complete occlusion nor physical clock accuracy is proven. '
                        'Labels review existing recordings; no new recording or live recognition changes.')
    assert before_hashes == {p: sha(Path(p)) for p in before_hashes}
    summary['sourcesUnchanged'] = True
    write(args.output/'summary.json', summary)
    write(args.output/'manifest.json', {'sourcesBeforeAndAfter': before_hashes,
                                      'inputs': {str(p): sha(p) for p in inputs}})


if __name__ == '__main__':
    main()
