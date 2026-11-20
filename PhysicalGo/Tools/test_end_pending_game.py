#!/usr/bin/env python3
"""Test ending an unresolved game using temporary copies of an explicit saved incident."""
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
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--incident',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=False)
    suite=Suite('EndPendingGameTests','app',('Tools/EndPendingGameTests.swift',),optimized=False)
    sources=resolve_sources(ROOT,suite.sources(ROOT))
    inputs=[*args.incident.iterdir(),*sources,Path(__file__)]
    hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs if p.is_file()}
    executable=args.output/suite.executable
    target=subprocess.check_output(['uname','-m'],text=True).strip()+'-apple-macosx14.0'
    compile_suite(ROOT,suite,sources,executable,target,debug=False)
    with (args.output/'tests.log').open('w') as log:
        result=subprocess.run([str(executable),str(args.incident),str(args.output)],cwd=ROOT.parent,stdout=log,stderr=subprocess.STDOUT)
    (args.output/'manifest.json').write_text(json.dumps(hashes,indent=2,sort_keys=True)+'\n')
    print((args.output/'tests.log').read_text())
    assert hashes=={p:hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in hashes}
    result.check_returncode()

if __name__=='__main__':main()
