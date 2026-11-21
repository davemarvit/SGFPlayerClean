#!/usr/bin/env python3
"""Exercise the lossless writer at camera cadence with a concurrent clip burst."""
import argparse
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root))
from scripts.test_suites import Suite
from scripts.build_sources import resolve_sources
from scripts.shared_regressions import compile_suite


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--recording', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    suite = Suite('RecordingWriterTests', 'app', ('Tests/RecordingWriterTests.swift',), optimized=False)
    executable = output/'RecordingWriterTests'
    compile_suite(root, suite, resolve_sources(root, suite.sources(root)), executable, 'arm64-apple-macosx14.0')
    with (output/'test.log').open('w') as log:
        subprocess.run([str(executable), str(args.recording.resolve()), str(output/'recordings')],
                       cwd=root.parent, stdout=log, stderr=subprocess.STDOUT, check=True)
    print((output/'test.log').read_text())


if __name__ == '__main__': main()
