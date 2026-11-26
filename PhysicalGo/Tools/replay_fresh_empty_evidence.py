#!/usr/bin/env python3
"""Offline producer/eligibility experiment using a verified immutable runtime.

Compiles only the edited observation/detector, unchanged appearance detector and
diagnostic runner. It does not build, install, launch or operate the application.
The original delayed R16 pixels/checkpoint are unavailable; this is a later photo.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime', required=True, type=Path)
    parser.add_argument('--baseline', default='fb4697c4ef314d83a253bd0aa219de1bb6b3d61f')
    parser.add_argument('--metadata', required=True, type=Path)
    parser.add_argument('--frame', required=True, type=Path)
    parser.add_argument('--reference', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    runtime = args.runtime.resolve()
    receipt = json.loads((runtime / 'complete.json').read_text())
    for item in receipt['manifest']['inputs']:
        original = subprocess.check_output(['git', 'show', args.baseline + ':' + item['name']], cwd=root)
        if sha(original) != item['sha256']:
            raise SystemExit('Baseline source mismatch: ' + item['name'])
    for name, expected in receipt['files'].items():
        if sha((runtime / name).read_bytes()) != expected:
            raise SystemExit('Immutable artifact mismatch: ' + name)
    source = root / 'PhysicalGo/Sources/BoardVision.swift'
    appearance = root / 'PhysicalGo/Sources/BoardAppearanceDetector.swift'
    # The experiment changes only BoardObservation/BoardDetector. Keep the
    # supporting appearance classifier exactly equal to the runtime baseline.
    if appearance.read_bytes() != subprocess.check_output(
            ['git', 'show', args.baseline + ':PhysicalGo/Sources/BoardAppearanceDetector.swift'], cwd=root):
        raise SystemExit('Appearance detector differs from verified baseline')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    body = source.read_text()
    extracted = body[body.index('/// Positive, current-pixel support'):body.index('struct ObservationStability {')]
    detector = output / 'ReceiptDetector.swift'
    detector.write_text('@testable import PhysicalGoTestRuntime\nimport Foundation\n' + extracted)
    local_appearance = output / 'ReceiptAppearance.swift'
    local_appearance.write_text('@testable import PhysicalGoTestRuntime\n' + appearance.read_text())
    runner = root / 'PhysicalGo/Tools/InspectFreshEmptyEvidence.swift'
    command = receipt['manifest']['commonArguments'] + [
        '-Onone', '-parse-as-library', '-I', str(runtime), '-L', str(runtime),
        '-lPhysicalGoTestRuntime', '-Xlinker', '-rpath', '-Xlinker', str(runtime),
        str(detector), str(local_appearance), str(runner), '-o', str(output / 'replay')]
    provenance = {
        'baseline': args.baseline, 'runtime': str(runtime), 'command': command,
        'verifiedInputs': len(receipt['manifest']['inputs']), 'verifiedArtifacts': len(receipt['files']),
        'inputHashes': {str(p.resolve()): sha(p.read_bytes()) for p in [source, appearance, runner, args.metadata, args.frame, args.reference]},
        'limitations': ['Later photograph; original delayed R16 pixels and tracker checkpoint missing.',
                        'Prior position is explicitly synthesized from the later photo minus target41.',
                        'Pure spatial eligibility, not real controller temporal acceptance or measured delay.']}
    (output / 'provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
    subprocess.run(command, cwd=root, check=True)
    with (output / 'result.log').open('w') as log:
        result = subprocess.run([str(output / 'replay'), str(args.metadata.resolve()),
                                 str(args.frame.resolve()), str(args.reference.resolve())],
                                cwd=root, stdout=log, stderr=subprocess.STDOUT)
    print((output / 'result.log').read_text())
    raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()
