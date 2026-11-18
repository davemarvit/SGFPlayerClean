#!/usr/bin/env python3
"""Replay the AF660 white-stone incident without editing recordings or using saved move decisions."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.test_suites import Suite
from scripts.build_sources import resolve_sources
from scripts.shared_regressions import compile_suite

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--recording',type=Path,required=True)
    p.add_argument('--journal',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--expect-failure',action='store_true')
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    events=a.recording/'events.jsonl'
    records=[json.loads(line) for line in events.read_text().splitlines()]
    observations=[json.loads(line) for line in a.journal.read_text().splitlines()]
    by_stamp={r['captureUptime']:r for r in observations if r.get('event')=='observation' and 'captureUptime' in r}
    frames={r['frameID']:r for r in records if r.get('image')}
    selected=[]
    for row in records:
        if row.get('event')!='operation finished' or row.get('outcome') not in ['delivered to recorder','hand over board; waiting for clear frame']:continue
        frame=frames[row['frameID']];stamp=frame['captureUptime']
        if not 1427978.8<=stamp<=1428002:continue
        saved=by_stamp.get(stamp)
        if row['outcome']=='delivered to recorder':
            assert saved is not None,stamp
            # The journal is the actual observation delivered to GameRecorder;
            # the camera log supplies its measured outlines, not move decisions.
            readings=[dict(row=i//19,col=i%19,occupancy={'.':'empty','B':'black','W':'white','?':'uncertain'}[c],
                confidence=saved['readingConfidence'][i],delta=saved['readingDelta'][i]) for i,c in enumerate(saved['position'])]
        else:readings=row.get('readings') or []
        selected.append(dict(capturedAt=stamp,availableAt=row.get('recorderUptime') or row['uptime'],
            hand=True if row['outcome'].startswith('hand over') else saved.get('handObstructed'),
            lightingBlocked=row.get('lightingBlocked',False),readings=readings,shapes=row.get('footprints') or [],
            estimate=saved.get('clockPressEstimate') if saved else None))
    assert len(selected)>80
    first=next(f for f in selected if f['hand'] is False and f['readings'][72]['occupancy']=='white')
    payload=dict(frames=selected,expectedPressTime=(first['estimate'] or {}).get('time',first['capturedAt']))
    (a.output/'input.json').write_text(json.dumps(payload))
    suite=Suite('WhiteTurnAppearanceTests','app',('Tests/WhiteTurnAppearanceTests.swift',),optimized=False)
    sources=resolve_sources(ROOT,suite.sources(ROOT))
    paths=[events,a.journal,a.recording/'session.json',Path(__file__),*sources]
    hashes={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in paths}
    executable=a.output/suite.executable
    target=subprocess.check_output(['uname','-m'],text=True).strip()+'-apple-macosx14.0'
    compile_suite(ROOT,suite,sources,executable,target,debug=True)
    with (a.output/'tests.log').open('w') as log:
        result=subprocess.run([str(executable),str(a.output/'input.json'),str(a.output/'results.json'),
            *(['--expect-failure'] if a.expect_failure else [])],cwd=ROOT.parent,stdout=log,stderr=subprocess.STDOUT)
    (a.output/'manifest.json').write_text(json.dumps(hashes,indent=2,sort_keys=True)+'\n')
    print((a.output/'tests.log').read_text());result.check_returncode()
    assert hashes=={f:hashlib.sha256(Path(f).read_bytes()).hexdigest() for f in hashes}

if __name__=='__main__':main()
