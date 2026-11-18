#!/usr/bin/env python3
"""Run the existing recorder and new ledger offline, using the app test runtime."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.test_suites import Suite
from scripts.build_sources import resolve_sources
from scripts.shared_regressions import compile_suite
from evaluate_turn_location import sha


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    suite = Suite('DeferredRecorderReplayTests','app',('Tests/DeferredRecorderReplayTests.swift',),optimized=False)
    sources = resolve_sources(ROOT,suite.sources(ROOT))
    fixture = ROOT/'Tests/Fixtures/RapidReplyShadow/sequence.json'
    baseline = {str(p):sha(p) for p in sources+[fixture,Path(__file__)]}
    executable = args.output/suite.executable
    target = subprocess.check_output(['uname','-m'],text=True).strip()+'-apple-macosx14.0'
    compile_suite(ROOT,suite,sources,executable,target)
    result = subprocess.run([str(executable),str(args.output/'results.json')],cwd=ROOT.parent,text=True,capture_output=True)
    (args.output/'test.log').write_text(result.stdout+result.stderr)
    result.check_returncode()
    print(result.stdout,end='')
    assert baseline == {p:sha(Path(p)) for p in baseline}
    (args.output/'manifest.json').write_text(json.dumps(baseline,indent=2,sort_keys=True)+'\n')


if __name__ == '__main__':
    main()
