#!/usr/bin/env python3
"""Build and replay the dormant native implementation. Never install the app.

Source games supply turn/capture certificates. Modified outline controls are
explicit injections, not new recording evidence or measured recognition accuracy.
"""
import argparse
from dataclasses import asdict
import json
from pathlib import Path
import subprocess

from evaluate_turn_location import load_game, sha, write
from evaluate_occluded_identity import (episode_windows, native_contexts, context_at,
                                       anchors_for)
from occluded_identity_lab import disks_from_row
from turn_location_lab import neighbors, play


def disk_json(d):
    return {**asdict(d), 'points': sorted(d.points)}


def turn_json(t):
    return dict(id=t.identity, color=t.color, time=t.time, lower=t.lower, upper=t.upper,
                certifiedAt=t.certified_at, witnesses=list(t.witnesses),
                identityReliable=t.identity_reliable, timingReliable=t.timing_reliable,
                colorReliable=t.color_reliable, continuous=t.continuous)


def prepare_game(work, name):
    contexts, turns, rows, clock, _, paths = load_game(work, name)
    snapshot = Path(json.loads(next(p for p in paths if p.name == 'plan.json').read_text())['snapshot'])
    metadata = {r['frameID']: r for r in map(json.loads, (snapshot/'capture/events.jsonl').open()) if r['event'] == 'frame'}
    states, by_id = native_contexts(contexts, turns), {t.identity: t for t in turns}
    disks = {r['frame']: disks_from_row(r) for r in rows}
    def epoch(r):
        m = metadata[r['frame']]
        return f'{name}:{m.get("cameraID")}:{m.get("gridGeneration")}'
    episodes = []
    for i, first_clear, end in episode_windows(rows):
        before = rows[i-4:i]
        owners, _ = context_at(states, before[-1]['availableAt'])
        anchors, points = anchors_for(before, owners, by_id, disks, name)
        if not anchors or len({epoch(r) for r in before}) != 1:
            continue
        # Include every non-anchored known identity. Unstable neighboring stones
        # must not vanish from matching just because they could not form anchors.
        retained_centers = {token: p for p, token in owners.items()}
        views = []
        for r in rows[i:end]:
            current_owners, retired = context_at(states, r['availableAt'])
            retained_centers.update({token: p for p, token in current_owners.items()})
            blockers = [dict(identity=token, color=by_id[token].color,
                             centers=[dict(x=p % 19, y=p//19)])
                        for token, p in retained_centers.items() if token not in points]
            views.append(dict(id=f'{name}:{r["frame"]}', time=r['capturedAt'], epoch=epoch(r),
                              hand=r['hand'], lightingOK=not r['lightingBlocked'] and r['outcome'] == 'delivered to recorder',
                              gap=False, disks=[disk_json(d) for d in disks[r['frame']]],
                              captured=sorted(retired), removed=[], blockers=blockers))
        episodes.append(dict(id=f'{name}:{rows[i]["frame"]}', epoch=epoch(before[-1]),
                             anchors=[{**asdict(a), 'disk': disk_json(a.disk), 'witnesses': list(a.witnesses)} for a in anchors],
                             anchorPoints=points, views=views, availableAt=rows[end-1]['availableAt'],
                             startedAt=rows[i]['availableAt']))
    owners, records = {}, []
    for c,t,saved in zip(contexts, turns, clock['moves']):
        _, captured = play(tuple(c['before']), t.color, c['expected'], 19)
        victims = [owners.pop(p) for p in captured]
        owners[c['expected']] = t.identity
        records.append(dict(turn=turn_json(t), point=c['expected'],
                            alternatives=sorted({c['expected'], *neighbors(c['expected'], 19)}),
                            captured=victims, saved=saved))
    return dict(name=name, originalSGF=str(next(p for p in paths if p.suffix == '.sgf')),
                records=records, episodes=episodes), paths+[snapshot/'capture/events.jsonl']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    root = Path(__file__).resolve().parents[1]
    native = [root/'Sources'/f for f in ('LocalClockEngine.swift', 'DeferredStoneState.swift', 'DeferredCleanupAssociation.swift')]
    native += [root/'Tests/DeferredCleanupTests.swift']
    export_sources = [root.parent/'SGFPlayerClean/Models'/p for p in ('OGSModels.swift','OGSScoringState.swift','SGFPlayerEngine.swift')]
    export_sources += [root/'Tools/StoneIdentitySGFAudit.swift']
    helpers = [root/'Tools'/p for p in ('evaluate_turn_location.py','evaluate_occluded_identity.py',
                                      'occluded_identity_lab.py','turn_location_lab.py','stone_identity_lab.py')]
    tracked = native + export_sources + helpers + [Path(__file__)] + list((root/'Sources').glob('*.swift'))
    baseline = {str(p): sha(p) for p in tracked}
    games, inputs = [], []
    for name in ('game65', 'game85'):
        game, paths = prepare_game(args.work, name)
        games.append(game); inputs += paths
    fixture = root/'Tests/Fixtures/RepositionedPending/observations.json'
    # Missing hand flags remain missing. No certified turn/time is invented for
    # the known relocation fixture. Actual recorded outline centers are retained.
    rows = json.loads(fixture.read_text())
    relocation = []
    for n,r in enumerate(rows):
        raw = [[v['occupancy'], v['confidence']] for v in r['readings']]
        relocation.append(dict(id=f'relocation:{n}', time=r['captureUptime'], epoch='RepositionedPending:own-calibration',
                               hand=None, lightingOK=not r['lightingBlocked'], gap=False,
                               disks=[disk_json(d) for d in disks_from_row(dict(raw=raw, shapes=r['footprints']))],
                               captured=[], removed=[], blockers=[]))
    inputs.append(fixture)
    labels_path = root/'Tools/occluded_cleanup_labels.json'
    inputs.append(labels_path)
    labels = json.loads(labels_path.read_text())['cases']
    reviewed = [dict(episode=f'{l["game"]}:{l["handFirst"]}', point=l['point']) for l in labels if l['targetCovered']]
    write(args.output/'input.json', dict(games=games, relocation=relocation, reviewed=reviewed))
    executable = args.output/'DeferredCleanupTests'
    command = ['swiftc', '-swift-version', '5', '-O', *map(str,native), '-o', str(executable)]
    write(args.output/'build-command.json', command)
    subprocess.run(command, check=True)
    result = subprocess.run([str(executable), str(args.output/'input.json'), str(args.output/'results.json')],
                            text=True, capture_output=True)
    (args.output/'native-tests.log').write_text(result.stdout+result.stderr)
    result.check_returncode()
    print(result.stdout, end='')
    export_executable = args.output/'StoneIdentitySGFAudit'
    export_command = ['swiftc','-D','PHYSICAL_GO',*map(str,export_sources),'-o',str(export_executable)]
    write(args.output/'sgf-build-command.json', export_command)
    subprocess.run(export_command, check=True)
    export = subprocess.run([str(export_executable),str(args.output/'sgf-pairs.json')], text=True,capture_output=True)
    (args.output/'sgf-audit.json').write_text(export.stdout)
    (args.output/'sgf-audit-stderr.log').write_text(export.stderr)
    export.check_returncode()
    assert baseline == {p: sha(Path(p)) for p in baseline}
    write(args.output/'manifest.json', dict(sourcesBeforeAndAfter=baseline, inputs={str(p):sha(p) for p in inputs}))


if __name__ == '__main__':
    main()
