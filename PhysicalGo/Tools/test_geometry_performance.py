#!/usr/bin/env python3
"""Compare all recognition evidence and alternate optimized before/after timing runs."""
import argparse
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.build_sources import resolve_sources
from scripts.test_suites import Suite

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--inputs',type=Path,required=True)
    p.add_argument('--baseline-revision',required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    cases=json.loads(a.inputs.read_text());assert cases and len({r['id'] for r in cases})==len(cases)
    benchmark=[r for r in cases if r.get('benchmark')];assert len(benchmark)>=6
    bench=a.output/'benchmark-inputs.json';bench.write_text(json.dumps(benchmark))
    sources=[p for p in resolve_sources(ROOT,Suite('GeometryPerformanceAudit','vision',('Tools/GeometryPerformanceAudit.swift',)).sources(ROOT)) if p.name!='TestArtifacts.swift']
    inputs={a.inputs,Path(__file__),*sources}
    inputs.update(Path(r[k]) for r in cases for k in ['image','reference'])
    hashes={str(p):sha(p) for p in sorted(inputs)}
    baseline=a.output/'StoneGeometry-baseline.swift'
    baseline.write_bytes(subprocess.check_output(['git','show',a.baseline_revision+':PhysicalGo/Sources/StoneGeometry.swift'],cwd=ROOT.parent))
    result=dict(passed=False,baselineRevision=a.baseline_revision,baselineGeometrySHA256=sha(baseline),sourceAndInputHashes=hashes)
    report=a.output/'comparison.json'
    def save():report.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    save()
    executables={}
    for variant in ['baseline','candidate']:
        executable=a.output/variant;executables[variant]=executable
        selected=[baseline if variant=='baseline' and p==ROOT/'Sources/StoneGeometry.swift' else p for p in sources]
        command=['xcrun','swiftc','-swift-version','5','-O','-D','PHYSICAL_GO',*map(str,selected),'-o',str(executable)]
        # resolve_sources canonicalizes paths on case-insensitive macOS volumes.
        if variant=='baseline':command=[str(baseline) if x==str((ROOT/'Sources/StoneGeometry.swift').resolve()) else x for x in command]
        with (a.output/(variant+'-build.log')).open('w') as log:subprocess.run(command,check=True,stdout=log,stderr=subprocess.STDOUT)
    def run(variant,inputs,name,repetitions):
        output=a.output/(name+'.json');print('Running '+name,flush=True)
        with (a.output/(name+'.log')).open('w') as log:
            subprocess.run([str(executables[variant]),str(inputs),str(output),str(repetitions)],check=True,stdout=log,stderr=subprocess.STDOUT)
        return json.loads(output.read_text())
    original=run('baseline',a.inputs,'all-baseline',1)
    candidate=run('candidate',a.inputs,'all-candidate',1)
    expected={r['id']:r['evidence'] for r in original}
    differences=[r['id'] for r in candidate if r['evidence']!=expected[r['id']]]
    result.update(cases=len(cases),distinctImages=len({r['image'] for r in cases}),differentEvidence=differences)
    save();assert not differences,differences
    totals={'baseline':[],'candidate':[]};times={'baseline':{},'candidate':{}}
    for i,variant in enumerate(['baseline','candidate','candidate','baseline']):
        rows=run(variant,bench,f'timing-{i}-{variant}',3)
        assert all(r['evidence']==expected[r['id']] for r in rows)
        totals[variant].append(sum(statistics.median(r['seconds']) for r in rows))
        for r in rows:times[variant].setdefault(r['id'],[]).extend(r['seconds'])
    before=statistics.median(totals['baseline']);after=statistics.median(totals['candidate'])
    result.update(benchmarkCases=len(benchmark),summedCaseMedianSecondsBefore=before,summedCaseMedianSecondsAfter=after,
        speedupFraction=1-after/before,alternatingTrialSeconds=totals,
        timingByCase={key:{variant:statistics.median(times[variant][key]) for variant in times} for key in times['baseline']})
    assert hashes=={p:sha(Path(p)) for p in hashes},'Inputs changed during validation'
    save();assert after<before*0.95,'No measured improvement of at least 5 percent'
    result['passed']=True;save();print(json.dumps({k:v for k,v in result.items() if k not in ['sourceAndInputHashes','timingByCase']},indent=2))

if __name__=='__main__':main()
