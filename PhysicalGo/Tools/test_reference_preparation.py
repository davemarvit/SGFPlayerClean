#!/usr/bin/env python3
"""Test exact background reference preparation without accessing the installed app."""
from pathlib import Path
import argparse
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.build_sources import resolve_sources
from scripts.test_suites import Suite

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=False)
    suite=Suite('ReferencePreparationTests','vision',('Tests/ReferencePreparationTests.swift',),extra=(
        'Sources/CameraAnalysisPipeline.swift','Sources/AutoGridDetector.swift','Sources/EstablishedStoneTracker.swift',
        'Sources/BoardRectifier.swift','Sources/StoneAspectEstimator.swift'))
    sources=[p for p in resolve_sources(ROOT,suite.sources(ROOT)) if p.name!='TestArtifacts.swift']
    executable=args.output/'tests'
    with (args.output/'build.log').open('w') as log:
        subprocess.run(['xcrun','swiftc','-swift-version','5','-O','-D','PHYSICAL_GO',*map(str,sources),'-o',str(executable)],check=True,stdout=log,stderr=subprocess.STDOUT)
    with (args.output/'tests.log').open('w') as log:subprocess.run([str(executable)],check=True,cwd=ROOT.parent,stdout=log,stderr=subprocess.STDOUT)
    print((args.output/'tests.log').read_text())
if __name__=='__main__':main()
