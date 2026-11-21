#!/usr/bin/env python3
"""Replay the AF660 C16 missed-white incident without touching the saved game.

Replay starts at the visually checked 19-stone position. Only actual saved images
are used within the pixel recording; later observations retain their logged labels.
No missing images or new move decisions are invented. The recording keeps its own
reference and calibration, including when the full camera pipeline is rerun.
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
    p.add_argument('--journal', type=Path, required=True)
    p.add_argument('--pixel-recording', type=Path, required=True)
    p.add_argument('--context-recording', type=Path, action='append', default=[])
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    a.output.mkdir(parents=True, exist_ok=False)
    rows = [json.loads(s) for s in a.journal.read_text().splitlines()]
    start = next(r['uptime'] for r in rows if r['event'] == 'game started')
    analysis, images = {}, {}
    paths = {a.journal, Path(__file__)}
    for folder in [*a.context_recording, a.pixel_recording]:
        events = [json.loads(s) for s in (folder/'events.jsonl').read_text().splitlines()]
        paths.update((folder/'events.jsonl', folder/'session.json'))
        frames = {r['frameID']: r for r in events if r['event'] == 'frame'}
        for r in events:
            if r['event'] == 'automatic analysis' and 'captureUptime' in r:
                analysis[round(r['captureUptime'], 5)] = r
            if r['event'] == 'operation finished' and r.get('readings') and r.get('frameID') in frames:
                analysis[round(frames[r['frameID']]['captureUptime'], 5)] = r
            if r['event'] == 'frame' and folder == a.pixel_recording:
                image, reference = folder/r['image'], folder/r['referenceImage']
                assert image.is_file() and reference.is_file()
                paths.update((image, reference))
                images[round(r['captureUptime'], 5)] = dict(image=str(image), reference=str(reference),
                    calibration=r['calibration'], referenceCalibration=r['referenceCalibration'], threshold=r['threshold'])
    frames = []
    for r in rows:
        if (r.get('event') != 'observation' or not r.get('position') or not r.get('readingConfidence')
                or not start <= r.get('captureUptime', 0) <= start+131):
            continue
        t = r['captureUptime']
        saved = analysis.get(round(t, 5), {})
        states = r.get('interpretedPosition', r['position'])
        frames.append(dict(capturedAt=t, availableAt=r['uptime'], hand=r.get('handObstructed'),
            lightingBlocked=r.get('lightingBlocked', False),
            readings=[dict(row=i//19, col=i % 19, occupancy={'.': 'empty', '?': 'uncertain', 'B': 'black', 'W': 'white'}[c],
                confidence=r['readingConfidence'][i], delta=r['readingDelta'][i]) for i, c in enumerate(states)],
            shapes=saved.get('footprints', []), placements=saved.get('placementFits', []),
            estimate=r.get('clockPressEstimate'), photo=images.get(round(t, 5))))
    controls = [dict(event=r['event'], time=r['uptime'], capturedAt=r.get('captureUptime', r['uptime']),
        estimate=r.get('clockPressEstimate')) for r in rows if r['event'] in
        ('hand obstruction began', 'hand obstruction cleared', 'hand-clear clock boundary') and r.get('uptime', 0) >= start]
    assert sum(f['photo'] is not None for f in frames) >= 25
    (a.output/'input.json').write_text(json.dumps(dict(start=start, frames=frames, controls=controls)))
    suite = Suite('UnlocatedWhiteTurnTests', 'app', ('Tests/UnlocatedWhiteTurnTests.swift',), optimized=False)
    sources = resolve_sources(ROOT, suite.sources(ROOT))
    paths.update(sources)
    hashes = {str(f): hashlib.sha256(f.read_bytes()).hexdigest() for f in paths}
    executable = a.output/suite.executable
    target = subprocess.check_output(['uname', '-m'], text=True).strip()+'-apple-macosx14.0'
    compile_suite(ROOT, suite, sources, executable, target, debug=False)
    with (a.output/'tests.log').open('w') as log:
        result = subprocess.run([str(executable), str(a.output/'input.json'), str(a.output/'results.json')],
            cwd=ROOT.parent, stdout=log, stderr=subprocess.STDOUT)
    (a.output/'manifest.json').write_text(json.dumps(hashes, indent=2, sort_keys=True)+'\n')
    print((a.output/'tests.log').read_text())
    assert hashes == {f: hashlib.sha256(Path(f).read_bytes()).hexdigest() for f in hashes}
    result.check_returncode()


if __name__ == '__main__':
    main()
