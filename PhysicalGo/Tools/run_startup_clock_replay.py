#!/usr/bin/env python3
"""Compile the native clock diagnostic into explicitly supplied external storage."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.build_sources import resolve_sources
from scripts.test_suites import Suite

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.resolve().is_relative_to(ROOT.parent):
        parser.error('Use an external output directory')
    args.output.mkdir(parents=True, exist_ok=False)
    suite = Suite('StartupClockReplay', 'recorder', ('Tools/StartupClockReplay.swift',), optimized=False)
    executable = args.output / suite.executable
    sources = resolve_sources(ROOT, suite.sources(ROOT))
    hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-D', 'PHYSICAL_GO', '-Onone',
                    '-target', 'arm64-apple-macosx14.0', *map(str, sources),
                    '-o', str(executable)], check=True)
    if any(hashlib.sha256(Path(p).read_bytes()).hexdigest() != h for p, h in hashes.items()):
        raise RuntimeError('Source changed during build; rerun into a new output directory')
    result = subprocess.run([str(executable)], text=True, capture_output=True, check=True)
    (args.output / 'result.json').write_text(result.stdout)
    (args.output / 'manifest.json').write_text(json.dumps({'sources': hashes,
        'scope': 'Native clock diagnostic; current working-tree sources, not installed-app binary replay'}, indent=2)+'\n')
    print(result.stdout)
