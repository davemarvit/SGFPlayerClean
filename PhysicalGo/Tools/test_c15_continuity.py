#!/usr/bin/env python3
"""Replay the C15/B15 incident's identity exclusions without changing its saved game.

The journal omits full camera outlines. This checks the native identity component
using recorded classifications and accepted-turn events, not optical recognition.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.test_suites import Suite
from scripts.build_sources import resolve_sources
from scripts.shared_regressions import compile_suite


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--journal', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    suite = Suite('ReplayStoneIdentityJournal', 'app', ('Tools/ReplayStoneIdentityJournal.swift',), optimized=False)
    sources = resolve_sources(ROOT, suite.sources(ROOT))
    inputs = [*sources, args.journal, Path(__file__)]
    hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    executable = args.output / suite.executable
    target = subprocess.check_output(['uname', '-m'], text=True).strip() + '-apple-macosx14.0'
    compile_suite(ROOT, suite, sources, executable, target, debug=True)
    results = {}
    for mode in ['position', 'interpretedPosition']:
        path = args.output / (mode + '.json')
        with path.open('w') as log:
            subprocess.run([str(executable), str(args.journal), mode], stdout=log, check=True)
        rows = json.loads(path.read_text())
        assert len(rows) >= 100, 'Incident must include sustained observations after timed turn 13'
        for row in rows:
            record = next(r for r in row['newCandidates'] if r['number'] == 12)
            assert record['candidates'] and set(record['candidates']) <= {33, 52}, record
        excluded = Counter(point for row in rows for point in row['excludedWhite'])
        assert excluded[89] == 0 and excluded[111] == 0, 'Earlier ambiguity absorbed later white stones'
        results[mode] = dict(observations=len(rows), exclusions=dict(excluded), passed=True)
    assert hashes == {p: hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in hashes}
    (args.output / 'manifest.json').write_text(json.dumps(hashes, indent=2, sort_keys=True) + '\n')
    (args.output / 'results.json').write_text(json.dumps(results, indent=2, sort_keys=True) + '\n')
    print('PASS: both incident label streams retain B15/C15 and stop absorbing later white stones')


if __name__ == '__main__':
    main()
