#!/usr/bin/env python3
"""Paired native-detector comparison on the immutable photographic regression set."""
import argparse
import csv
import hashlib
import json
import subprocess
from collections import Counter, defaultdict
from pathlib import Path
from statistics import mean
import confidence_audit as audit


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def export(engine, corpus):
    frames = json.loads(subprocess.check_output([str(engine.resolve()), 'corpus', str(corpus.resolve())]))
    result = {}
    for f in frames:
        key = f['session'], f['frame']
        if key in result:
            raise ValueError(f'Duplicate native frame: {key}')
        result[key] = {'new': f['readings'], 'newShapes': f['shapes']}
        n = round(len(f['readings']) ** 0.5)
        for i, r in enumerate(f['readings']):
            if (r['row'], r['col']) != divmod(i, n):
                raise ValueError(f'Non-row-major readings: {key}')
    return frames, result


def metrics(rows):
    clear = [r for r in rows if r['truth'] != 'occluded']
    episodes = defaultdict(list)
    for r in clear:
        episodes[r['session'], r['point'], r['episode'], r['truth']].append(r)
    report = {'labeled': len(rows), 'scorable': len(clear), 'occluded': len(rows)-len(clear),
              'episodes': len(episodes)}
    for side in ['old', 'new']:
        counts = Counter('correct' if r[side] == r['truth'] else 'uncertain' if r[side] == 'uncertain' else 'wrong' for r in clear)
        report[side] = {name: counts[name] for name in ['correct', 'uncertain', 'wrong']}
        report[side].update(
            correct_rate=counts['correct']/len(clear) if clear else None,
            decision_coverage=(len(clear)-counts['uncertain'])/len(clear) if clear else None,
            accuracy_when_classified=counts['correct']/(len(clear)-counts['uncertain']) if len(clear)>counts['uncertain'] else None,
            episode_mean_correct=mean(mean(r[side] == r['truth'] for r in group) for group in episodes.values()) if episodes else None,
            confident_wrong=sum(r[side] not in [r['truth'], 'uncertain'] and r[side+'_score'] >= .9 for r in clear),
            occluded_stone_calls=sum(r['truth']=='occluded' and r[side] in ['black', 'white'] for r in rows))
    report.update(
        uncertain_to_correct=sum(r['old']=='uncertain' and r['new']==r['truth'] for r in clear),
        wrong_to_correct=sum(r['old'] not in ['uncertain', r['truth']] and r['new']==r['truth'] for r in clear),
        correct_to_uncertain=sum(r['old']==r['truth'] and r['new']=='uncertain' for r in clear),
        correct_to_wrong=sum(r['old']==r['truth'] and r['new'] not in ['uncertain', r['truth']] for r in clear),
        newly_wrong=sum(r['old'] in ['uncertain', r['truth']] and r['new'] not in ['uncertain', r['truth']] for r in clear))
    return report


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--baseline-engine', required=True, type=Path)
    parser.add_argument('--engine', required=True, type=Path)
    parser.add_argument('--corpus', type=Path, default=audit.FIXTURES/'ShadowRegression/v1')
    args=parser.parse_args()
    if args.output.exists():
        parser.error('Choose a new report directory')
    corpus=args.corpus
    for name, expected in json.loads((corpus/'checksums.json').read_text()).items():
        if digest(corpus/name) != expected:
            raise ValueError(f'Frozen corpus checksum mismatch: {name}')
    manifest=json.loads((corpus/'manifest.json').read_text())
    expected={(f['session'], f['frame']) for f in manifest['cases']}
    baseline, old=export(args.baseline_engine, corpus)
    current, new=export(args.engine, corpus)
    if set(old) != expected or set(new) != expected:
        raise ValueError('Native engines did not return every frozen frame')
    with (corpus/'labels.csv').open(newline='') as f:
        rows=list(csv.DictReader(f))
    seen=set()
    for r in rows:
        r['frame']=int(r['frame']);r['point']=int(r['point'])
        key=r['session'],r['frame'],r['point']
        if key in seen or r['truth'] not in ['black','white','empty','occluded']:
            raise ValueError(f'Invalid label: {key}')
        seen.add(key)
        audit.measure(r, 'old', old[r['session'], r['frame']], 'new')
        audit.measure(r, 'new', new[r['session'], r['frame']], 'new')
    clear=[r for r in rows if r['truth'] != 'occluded']
    episodes, confidence=audit.summarize(clear)
    report={'overall':metrics(rows),
            'splits':{s:metrics([r for r in rows if r['split']==s]) for s in sorted({r['split'] for r in rows})},
            'sessions':{s:metrics([r for r in rows if r['session']==s]) for s in sorted({r['session'] for r in rows})},
            'truth_classes':{s:metrics([r for r in clear if r['truth']==s]) for s in ['empty','black','white']},
            'confidence':confidence,
            'notes':['Selected historical regression cases, not an estimate of general live-game accuracy.',
                     'Splits retain their historical names; these published cases are not a new untouched holdout.',
                     'Heuristic confidence is not a calibrated probability. Occluded points are reported separately.']}
    args.output.mkdir(parents=True)
    for name,data in [('baseline.json',baseline),('current.json',current),('summary.json',report)]:
        (args.output/name).write_text(json.dumps(data,indent=2)+'\n')
    audit.write_table(args.output/'paired.csv', rows)
    audit.write_table(args.output/'changed.csv', [r for r in rows if r['old'] != r['new']])
    audit.write_table(args.output/'episodes.csv', episodes)
    audit.write_table(args.output/'wrong.csv', [r for r in clear if r['new'] not in [r['truth'],'uncertain']])
    provenance={'corpus_checksums_sha256':digest(corpus/'checksums.json'),
                'labels_sha256':digest(corpus/'labels.csv'),
                'baseline_engine_sha256':digest(args.baseline_engine), 'current_engine_sha256':digest(args.engine),
                'runner_sha256':digest(Path(__file__)), 'metrics_sha256':digest(Path(audit.__file__)),
                'frames':len(expected)}
    (args.output/'provenance.json').write_text(json.dumps(provenance,indent=2)+'\n')
    print(json.dumps({k:report[k] for k in ['overall','splits']},indent=2))


if __name__=='__main__':
    main()
