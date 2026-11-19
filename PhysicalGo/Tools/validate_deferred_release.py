#!/usr/bin/env python3
"""Build and validate a deferred-location candidate without installing or launching it."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.build_sources import resolve_sources
from scripts.test_suites import Suite


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--white-recording',type=Path)
    parser.add_argument('--white-journal',type=Path)
    parser.add_argument('--geometry-comparison',type=Path)
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=False)
    if bool(args.white_recording)!=bool(args.white_journal):parser.error('Supply both white-incident paths.')
    sources=resolve_sources(ROOT,Suite('runtime','app',()).sources(ROOT))
    paths=set(sources+[ROOT/'Sources/PhysicalGoApp.swift',ROOT/'build.py'])
    paths.update((ROOT/'scripts').glob('*.py'))
    paths.update((ROOT/'Tools').glob('*.py'))
    paths.update((ROOT/'Tests').glob('*.swift'))
    hashes={str(p):sha(p) for p in sorted(paths)}
    result=dict(readyForInstallation=False,checks=[],sourceHashes=hashes)
    if args.geometry_comparison:
        comparison=json.loads(args.geometry_comparison.read_text())
        assert comparison.get('passed') is True and comparison.get('differentEvidence')==[], 'Geometry comparison failed'
        assert all(sha(Path(p))==h for p,h in comparison['sourceAndInputHashes'].items()), 'Geometry comparison inputs changed'
        result['geometryComparison']=dict(path=str(args.geometry_comparison.resolve()),sha256=sha(args.geometry_comparison))
    validation=args.output/'validation.json'
    def save():validation.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    save()
    def run(name,command,enabled=False):
        env=dict(os.environ);env.pop('PHYSICAL_GO_DEFERRED_LOCATIONS',None)
        if enabled:env['PHYSICAL_GO_DEFERRED_LOCATIONS']='1'
        print('Running '+name,flush=True)
        with (args.output/(name+'.log')).open('w') as log:
            completed=subprocess.run(command,cwd=ROOT.parent,env=env,stdout=log,stderr=subprocess.STDOUT)
        result['checks'].append(dict(name=name,command=list(map(str,command)),passed=completed.returncode==0))
        save();completed.check_returncode()
    py=sys.executable
    run('connected',[py,ROOT/'Tools/test_recording_stone_ledger.py','--output',args.output/'connected'])
    if args.white_recording:
        run('white-appearance',[py,ROOT/'Tools/test_white_turn_appearance.py','--recording',args.white_recording,
            '--journal',args.white_journal,'--output',args.output/'white-appearance'])
    run('recordings',[py,ROOT/'Tools/test_deferred_full_recordings.py','--work',args.work,'--output',args.output/'recordings'])
    flags=['provisional-play','capture-clock','observation-replay','storage-flow','historical-correction',
           'undo-move','session-resume','repositioning','crowded-white','hand-clock','workflow-ui',
           'clock-awaiting-turn','missing-provisional-review','transient-clock-pause','candidate-history','shadow-recognition']
    if args.geometry_comparison:
        flags+=['faint-capture','shaded-white','jade-white','hand-stone-pipeline']
    run('enabled-regressions',[py,ROOT/'build.py','--debug-tests',*['--'+f+'-test' for f in flags]],enabled=True)
    run('disabled-regressions',[py,ROOT/'build.py','--debug-tests','--storage-flow-test',
        '--workflow-ui-test','--provisional-play-test','--missing-provisional-review-test'])
    run('identity-tests',[py,'-m','unittest','discover','-s',ROOT/'Tools','-p','test_*identity_lab.py','-v'])
    run('app-build',[py,ROOT/'build.py'])
    assert hashes=={p:sha(Path(p)) for p in hashes},'Sources changed during validation'
    if args.geometry_comparison:
        assert sha(args.geometry_comparison)==result['geometryComparison']['sha256'], 'Geometry comparison changed'
    result['appExecutableSHA256']=sha(ROOT/'.build/Physical Go.app/Contents/MacOS/PhysicalGo')
    result['baseCommit']=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT.parent,text=True).strip()
    result['readyForInstallation']=True
    save();print(validation,flush=True)


if __name__=='__main__':main()
