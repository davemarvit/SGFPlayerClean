#!/usr/bin/env python3
"""Connected recorder tests; no installed app access. Reuse native test runtime."""
import argparse
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.test_suites import Suite
from scripts.build_sources import resolve_sources
from scripts.shared_regressions import compile_suite


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output',type=Path,required=True)
    args=p.parse_args();args.output.mkdir(parents=True,exist_ok=False)
    suite=Suite('RecordingStoneLedgerTests','app',('Tests/RecordingStoneLedgerTests.swift',),optimized=False)
    executable=args.output/suite.executable
    target=subprocess.check_output(['uname','-m'],text=True).strip()+'-apple-macosx14.0'
    compile_suite(ROOT,suite,resolve_sources(ROOT,suite.sources(ROOT)),executable,target,debug=True)
    r=subprocess.run([str(executable)],cwd=ROOT.parent,text=True,capture_output=True)
    (args.output/'tests.log').write_text(r.stdout+r.stderr)
    print(r.stdout,end='');r.check_returncode()


if __name__ == '__main__':
    main()
