#!/usr/bin/env python3
"""Compare connected native recorder decisions on existing chronological observations."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
from evaluate_turn_location import load_game,sha

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.test_suites import Suite
from scripts.build_sources import resolve_sources
from scripts.shared_regressions import compile_suite


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--work',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    inputs=[];games=[]
    for name in ['game65','game85']:
        contexts,_,rows,_,_,paths=load_game(a.work,name);inputs+=paths
        journal=next(p for p in paths if p.name.endswith('observations.jsonl'))
        starts=[r['uptime'] for r in map(json.loads,journal.read_text().splitlines()) if r.get('event')=='game started']
        assert len(starts)==1
        # Camera setup precedes the actual Start button in these recordings.
        # Do not invent an active clock during that pre-game camera interval.
        rows=[r for r in rows if r['capturedAt']>=starts[0]-1.25]
        frames=[dict(capturedAt=r['capturedAt'],availableAt=r['availableAt'],hand=r['hand'],lightingBlocked=r['lightingBlocked'],
            shapes=r['shapes'],readings=[dict(row=i//19,col=i%19,occupancy=c,confidence=q,delta=0) for i,(c,q) in enumerate(r['raw'])]) for r in rows]
        games.append(dict(name=name,recordedStart=starts[0],expected=[c['expected'] for c in contexts],frames=frames))
    (a.output/'input.json').write_text(json.dumps(games))
    suite=Suite('DeferredFullRecordingTests','app',('Tests/DeferredFullRecordingTests.swift',),optimized=False)
    sources=resolve_sources(ROOT,suite.sources(ROOT));executable=a.output/suite.executable
    hashes={str(p):sha(p) for p in inputs+sources+[Path(__file__)]}
    target=subprocess.check_output(['uname','-m'],text=True).strip()+'-apple-macosx14.0'
    compile_suite(ROOT,suite,sources,executable,target,debug=True)
    with (a.output/'test.log').open('w') as log:
        subprocess.run([str(executable),str(a.output/'input.json'),str(a.output/'results.json')],cwd=ROOT.parent,stdout=log,stderr=subprocess.STDOUT,check=True)
    assert hashes=={p:sha(Path(p)) for p in hashes}
    results=json.loads((a.output/'results.json').read_text())
    for game in results:
        baseline,enabled=game['variants']
        assert all(v['expectedSavedSequence'] for v in game['variants']), game['game']
        for field in ['savedPoints','timedMoves','reviewTransitions','clockReview']:
            assert baseline[field]==enabled[field], (game['game'],field)
        assert len(baseline['pressTimes'])==len(enabled['pressTimes'])
        assert all(abs(x-y)<1e-6 for x,y in zip(baseline['pressTimes'],enabled['pressTimes'])), game['game']
        if game['game']=='game85':
            assert len(enabled['timedMoves'])==85 and enabled['reviewTransitions']==0
        else:
            # These reprocessed observations lack a retained first-turn timing
            # boundary in BOTH versions. Do not count this as 65 timed turns.
            assert enabled['timedMoves']==[] and enabled['reviewTransitions']==1
    (a.output/'manifest.json').write_text(json.dumps(hashes,indent=2,sort_keys=True)+'\n')
    print((a.output/'test.log').read_text())


if __name__=='__main__':main()
