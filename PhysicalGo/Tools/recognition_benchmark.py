#!/usr/bin/env python3
"""Replay saved observations and run clock/capture guards; never launch the app."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SUITES = {
    'historical-correction-test': 'false saved placement removal, copies, clocks, captures and correction UI',
    'candidate-history-test': 'per-candidate histories and differential replay against stage 1',
    'observation-replay-test': 'rapid reply, exact observations, clock arithmetic, missing-evidence control',
    'shadow-recognition-test': 'shadow bursts, retrospective revisions, review-gap continuation',
    'adaptive-turn-timing-test': 'confidence timing, isolated flashes, timeout boundaries',
    'placement-timing-test': 'candidate timing and placement aliases',
    'provisional-play-test': 'provisional turns and recovery',
    'transient-clock-pause-test': 'recorded B19 phantom and genuine missing turns',
    'faint-capture-test': 'recorded capture photographs',
    'go-club-visibility-test': 'recorded long visibility gap',
    'missing-provisional-review-test': 'review/resume with missing candidate',
    'clock-awaiting-turn-test': 'clock review and resume',
    'review-flicker-test': 'review stability',
    'camera-preview-test': 'real camera pipeline freshness and alignment UI',
    'workflow-ui-test': 'camera continuity, local chronology, game preservation',
    'capture-clock-test': 'capture removal, clock pause/resume and arithmetic',
    'hand-clock-test': 'hand timing and catch-up',
    'view-orientation-test': 'in-game orientation and setup controls',
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True, help='New report folder outside the source tree')
    args = parser.parse_args()
    output = args.output.expanduser().resolve()
    if output.exists() or output.is_relative_to(ROOT):
        parser.error('Choose a new report folder outside PhysicalGo')
    output.mkdir(parents=True)
    sources = sorted((ROOT / 'Sources').glob('*.swift'))
    source_hash = hashlib.sha256(b''.join(p.read_bytes() for p in sources)).hexdigest()
    fixture = ROOT / 'Tests/Fixtures/RapidReplyShadow/sequence.json'
    metadata = {'schemaVersion': 1, 'sourceHash': source_hash,
                'gitCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                'workingTreeStatus': subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True),
                'fixtureSHA256': hashlib.sha256(fixture.read_bytes()).hexdigest(), 'suites': SUITES,
                'scope': 'Rapid-reply replay uses saved classifier outputs and recorded hand gates, not rerun pixels. '
                         'Other suites cover captured photos and constructed clock/capture cases. Physical placement times are estimates, not ground truth.'}
    (output / 'manifest.json').write_text(json.dumps(metadata, indent=2) + '\n')
    env = {**os.environ, 'PHYSICAL_GO_REPLAY_REPORT': str(output / 'replay.json'),
           'PHYSICAL_GO_CANDIDATE_REPORT': str(output / 'candidates.json')}
    with (output / 'validation.log').open('w') as log:
        registry = subprocess.run([sys.executable, str(ROOT / 'Tests/test_build.py')], cwd=ROOT.parent, stdout=log, stderr=subprocess.STDOUT)
        checks = subprocess.run([sys.executable, str(ROOT / 'build.py'), *('--' + name for name in SUITES)],
                                cwd=ROOT.parent, env=env, stdout=log, stderr=subprocess.STDOUT)
    summary = {'passed': registry.returncode == checks.returncode == 0,
               'buildRegistryExitCode': registry.returncode, 'regressionExitCode': checks.returncode,
               'regressionSuites': len(SUITES), 'scope': metadata['scope']}
    if (output / 'replay.json').exists():
        summary['sequences'] = [{k: v for k, v in row.items() if k != 'states'} for row in json.loads((output / 'replay.json').read_text())]
    if (output / 'candidates.json').exists():
        summary['candidateComparison'] = json.loads((output / 'candidates.json').read_text())
    (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(('PASS' if summary['passed'] else 'FAIL') + ': ' + str(output), flush=True)
    return 0 if summary['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
