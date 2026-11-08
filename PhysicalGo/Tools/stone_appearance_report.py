#!/usr/bin/env python3
"""Summarize the native leave-one-session-out appearance experiment."""
import argparse, collections, csv, hashlib, json, subprocess
from pathlib import Path

def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output',type=Path)
    parser.add_argument('--engine',type=Path,required=True)
    parser.add_argument('--corpus',type=Path,default=Path('PhysicalGo/Tests/Fixtures/ShadowRegression/v1'))
    args=parser.parse_args()
    if args.output.exists(): parser.error('Choose a new report directory')
    for name,expected in json.loads((args.corpus/'checksums.json').read_text()).items():
        if digest(args.corpus/name)!=expected: raise ValueError(f'Frozen corpus changed: {name}')
    raw=subprocess.check_output([str(args.engine.resolve()),str(args.corpus.resolve())])
    result=json.loads(raw);rows=result['rows'];visible=[r for r in rows if r['truth']!='occluded']
    fields=['baseline','model','contextModel','proposal','contextProposal']
    def metrics(group,field):
        counts=collections.Counter('correct' if r[field]==r['truth'] else 'uncertain' if r[field]=='uncertain' else 'wrong' for r in group)
        return {**{k:counts[k] for k in ['correct','uncertain','wrong']},
                'newly_wrong':sum(r['baseline'] in ['uncertain',r['truth']] and r[field] not in ['uncertain',r['truth']] for r in group)}
    summary={'visible_labels':len(visible),'occluded_labels':len(rows)-len(visible),
             'overall':{f:metrics(visible,f) for f in fields},
             'occlusion':{f:{'decided':sum(r[f]!='uncertain' for r in rows if r['truth']=='occluded'), 'newly_decided':sum(r['baseline']=='uncertain' and r[f]!='uncertain' for r in rows if r['truth']=='occluded')} for f in fields},
             'sessions':{s:{f:metrics([r for r in visible if r['session']==s],f) for f in fields} for s in sorted({r['session'] for r in rows})},
             'folds':result['folds'],
             'notes':[
                 'Selected historical error corpus, not general live-game accuracy.',
                 'Each session is tested only against models fitted on other sessions; training uses one explicit label per point/episode.',
                 'All recordings come from the existing equipment/setup; this is not independent board/camera validation.',
                 'Training neighborhood information uses only explicit adjacent human labels. Missing neighbors remain unknown.',
                 'Test neighborhood context uses current detector evidence, never held-out ground truth.',
                 'The proposal only resolves uncertain readings with a sufficiently separated appearance match and existing strong stone outline or visible-grid evidence.',
                 'The app exposes experimental comparisons only; this offline proposal is not enabled for automatic moves.',
                 'The proposal also turns one occluded uncertain example into an empty estimate. It needs a separate reliable obstruction guard before any live dispatch use.',
                 'No shadow-context training components met minimum coverage in this corpus; only exposed-empty components were available. Guided calibration will collect missing neighborhoods.',
                 'Ranges describe observed features; compatibility scores are not calibrated probabilities.']}
    args.output.mkdir(parents=True)
    (args.output/'native.json').write_bytes(raw)
    (args.output/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    with (args.output/'paired.csv').open('w',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
    (args.output/'provenance.json').write_text(json.dumps({'engine_sha256':digest(args.engine),
        'labels_sha256':digest(args.corpus/'labels.csv'),'manifest_sha256':digest(args.corpus/'manifest.json'),
        'checksums_sha256':digest(args.corpus/'checksums.json'),'reporter_sha256':digest(Path(__file__))},indent=2)+'\n')
    print(json.dumps(summary['overall'],indent=2))

if __name__=='__main__':main()
