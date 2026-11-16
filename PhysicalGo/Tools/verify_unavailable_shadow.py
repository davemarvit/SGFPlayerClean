#!/usr/bin/env python3
"""Verify frozen-control parity, complete photo probes and preserved inputs."""
import argparse
from collections import defaultdict
import json
from pathlib import Path

from local_quality_lab import digest
from placement_competition_lab import PlacementCompetition, View
from recognition_parameter_search import write_json
from unavailable_shadow_lab import SupportFilter


def verify(evaluation, previous, output):
    if output.exists():
        raise ValueError('Use new output directory')
    output.mkdir(parents=True)
    old = previous/'black_shadow_independent'
    neutral = [json.loads(line) for line in (evaluation/'rapid-neutral.jsonl').open()]
    proposed = [json.loads(line) for line in (evaluation/'rapid-contrast_black.jsonl').open()]
    cache = {}
    for row in neutral:
        context = 'black-next-probe' if row['context'] == 'black-next' else row['context']
        name = row['scenario']+'-'+context
        if name not in cache:
            cache[name] = {d['frame']: d['result'] for d in map(json.loads, (old/(name+'.jsonl')).open())}
        assert row['result'] == cache[name][row['frame']], (name, row['frame'])
    keys = ('state', 'selected', 'firstSeen', 'firstSupported', 'confirmedAt', 'witnesses',
            'recordedFrameTiming', 'clockAuthority', 'reasons')
    assert len(neutral) == len(proposed)
    for a, b in zip(neutral, proposed):
        assert (a['scenario'], a['context'], a['frame']) == (b['scenario'], b['context'], b['frame'])
        assert all(a['result'][k] == b['result'][k] for k in keys)
    photos = defaultdict(list)
    for row in json.loads((evaluation/'point-evidence.json').read_text()):
        if row['kind'] == 'photo':
            photos[row['case']].append(row)
    counts = {'probes': 0, 'recognized': 0, 'wrongLocations': 0, 'pairedDecisionFrames': 0}
    for case, rows in photos.items():
        rows.sort(key=lambda r: r['point'])
        assert [r['point'] for r in rows] == list(range(361))
        truth = [r['truth'] for r in rows]
        readings = [r['reading'] for r in rows]
        appearance = [r['appearance'] for r in rows]
        for point, color in enumerate(truth):
            if color == 'empty':
                continue
            before = list(truth)
            before[point] = 'empty'
            models = [PlacementCompetition(before, color, 'black_shadow_independent', support_filter=SupportFilter(policy, {}))
                      for policy in ('neutral', 'contrast_black')]
            selected = set()
            for frame in range(1, 26):
                view = View(frame, frame*.2, False, False, readings, appearance)
                a, b = [model.step(view) for model in models]
                assert all(a[k] == b[k] for k in keys), (case, point, frame)
                counts['pairedDecisionFrames'] += 1
                if b['state'] == 'placement':
                    selected.add(b['selected'])
            counts['probes'] += 1
            counts['recognized'] += point in selected
            counts['wrongLocations'] += bool(selected-{point})
    expected = json.loads((previous/'summary.json').read_text())['aggregation']['black_shadow_independent']
    assert counts['probes'] == expected['photoStoneProbes']
    assert counts['recognized'] == expected['photoStoneProbesRecognized']
    manifest = json.loads((evaluation/'manifest.json').read_text())
    for item in manifest['inputs']:
        assert digest(Path(item['path'])) == item['sha256'], item['path']
    result = {'neutralExactReplayParityRows': len(neutral), 'contrastDecisionTimingDifferences': 0,
              'photoProbes': counts, 'evaluationInputHashesChecked': len(manifest['inputs']),
              'limits': 'Photo repeats are synthetic, supplied-prior-position probes; no real-time or native clock claim.'}
    write_json(output/'verification.json', result)
    write_json(output/'manifest.json', {'inputs': [{'path': str(p.resolve()), 'sha256': digest(p)} for p in
        (Path(__file__), evaluation/'manifest.json', evaluation/'point-evidence.json', evaluation/'rapid-neutral.jsonl',
         evaluation/'rapid-contrast_black.jsonl', previous/'summary.json')]})
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('evaluation', 'previous', 'output'):
        parser.add_argument('--'+key, required=True, type=Path)
    args = parser.parse_args()
    verify(args.evaluation, args.previous, args.output)
