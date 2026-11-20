#!/usr/bin/env python3
"""Replay the AF660 resting-hands failure through camera analysis and the recorder.

Keeps recorded calibration and delivery times, reruns pixels and Vision poses,
and compares the saved defective hand gate with the corrected production gate.
Never opens the installed app or writes to the original recording.
"""
import argparse
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
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--recording', type=Path, required=True)
    p.add_argument('--journal', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    a.output.mkdir(parents=True, exist_ok=False)
    events = [json.loads(l) for l in (a.recording/'events.jsonl').open()]
    journal = [json.loads(l) for l in a.journal.open()]
    start = next(r['uptime'] for r in journal if r['event'] == 'game started')
    frames = {r['frameID']: r for r in events if r['event'] == 'frame'}
    selected = []
    paths = {a.recording/'events.jsonl', a.recording/'session.json', a.journal, Path(__file__)}
    for op in events:
        if op['event'] != 'operation finished' or op.get('outcome') not in (
                'delivered to recorder', 'hand over board; waiting for clear frame'):
            continue
        f = frames[op['frameID']]
        if f['frameID'] > 300:
            continue
        image, reference = a.recording/f['image'], a.recording/f['referenceImage']
        assert image.is_file() and reference.is_file(), image
        assert not op.get('exposureFailure') and op.get('calibration'), op['frameID']
        paths.update((image, reference))
        selected.append(dict(id=f['frameID'], image=str(image), reference=str(reference),
            calibration=op['calibration'], referenceCalibration=f['referenceCalibration'],
            threshold=f['threshold'], capturedAt=f['captureUptime'],
            availableAt=op.get('recorderUptime') or op['uptime'],
            originalOutline=op.get('handOutline'), originalPose=op.get('handPose')))
    assert len(selected) >= 280
    (a.output/'input.json').write_text(json.dumps(dict(start=start, frames=selected)))
    suite = Suite('RestingHandsRecordingTests', 'app', ('Tests/RestingHandsRecordingTests.swift',), optimized=False)
    sources = resolve_sources(ROOT, suite.sources(ROOT))
    paths.update(sources)
    hashes = {str(f): hashlib.sha256(f.read_bytes()).hexdigest() for f in paths}
    executable = a.output/suite.executable
    target = subprocess.check_output(['uname', '-m'], text=True).strip()+'-apple-macosx14.0'
    compile_suite(ROOT, suite, sources, executable, target, debug=False)
    with (a.output/'tests.log').open('w') as log:
        result = subprocess.run([str(executable), str(a.output/'input.json'), str(a.output)],
                                cwd=ROOT.parent, stdout=log, stderr=subprocess.STDOUT)
    (a.output/'manifest.json').write_text(json.dumps(hashes, indent=2, sort_keys=True)+'\n')
    print((a.output/'tests.log').read_text())
    assert hashes == {f: hashlib.sha256(Path(f).read_bytes()).hexdigest() for f in hashes}
    result.check_returncode()


if __name__ == '__main__':
    main()
