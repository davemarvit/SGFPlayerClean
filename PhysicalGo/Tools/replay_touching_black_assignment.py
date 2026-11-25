#!/usr/bin/env python3
"""Inspect one saved frame and a placement-only hypothesis using a verified cache.

This never opens a camera/app/device or changes a runtime/cache. The candidate is
an offline experiment, not a production patch or installation command.
"""
import argparse
import hashlib
import json
import plistlib
from pathlib import Path
import subprocess


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime', required=True, type=Path)
    parser.add_argument('--metadata', required=True, type=Path)
    parser.add_argument('--frame', required=True, type=Path)
    parser.add_argument('--reference-plist', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    source_root = Path(__file__).resolve().parents[2]
    runtime = args.runtime.resolve()
    receipt = json.loads((runtime / 'complete.json').read_text())
    for item in receipt['manifest']['inputs']:
        path = source_root / item['name']
        data = path.read_bytes() if path.is_file() else subprocess.check_output(
            ['git', 'show', 'HEAD:' + item['name']], cwd=source_root)
        if digest(data) != item['sha256']:
            raise SystemExit('Runtime source differs: ' + item['name'])
    for name, expected in receipt['files'].items():
        if digest((runtime / name).read_bytes()) != expected:
            raise SystemExit('Runtime artifact differs: ' + name)
    meta = json.loads(args.metadata.read_text())
    reference_bytes = args.reference_plist.read_bytes()
    reference = plistlib.loads(reference_bytes)
    if reference['calibration'] != meta['currentCalibration'] or reference['referenceCalibration'] != meta['referenceCalibration']:
        raise SystemExit('Reference/current calibration identity mismatch')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    (output / 'reference-archive.plist').write_bytes(reference_bytes)
    reference_png = output / 'empty-reference.png'
    reference_png.write_bytes(reference['png'])
    geometry = (source_root / 'PhysicalGo/Sources/StoneGeometry.swift').read_text()
    geometry = geometry[geometry.index('enum StoneGeometry {'):].replace('StoneGeometry', 'CandidateStoneGeometry')
    old = 'if reading.occupancy == .white {\n                for neighbor in result where neighbor.occupancy == .white && neighbor.confidence>=0.9'
    if old not in geometry:
        raise SystemExit('Expected placement-only White-mask boundary changed')
    geometry = geometry.replace(old, 'if reading.occupancy.stone != nil {\n                for neighbor in result where neighbor.occupancy == reading.occupancy && neighbor.confidence>=0.9')
    geometry = geometry.replace('if neighbors.count >= (reading.occupancy == .white ? 1 : 2), refined.quality >= 0.90 {', 'if neighbors.count >= 1, refined.quality >= 0.90 {')
    gate = '        guard let best,best.quality>=minimumQuality,best.radiusCol>0.32,best.radiusCol<maximumRadius else { return nil }'
    geometry = geometry.replace(gate, '''        if reading.row*19+reading.col==41 || reading.row*19+reading.col==60 {
            print("FIT",reading.row*19+reading.col,"color",reading.occupancy,"minimum",minimumQuality,"masks",masking.count,"best",String(describing:best))
        }
''' + gate)
    detector = (source_root / 'PhysicalGo/Sources/BoardVision.swift').read_text()
    detector = detector[detector.index('enum BoardDetector {'):detector.index('struct ObservationStability {')]
    detector = detector.replace('BoardDetector', 'CandidateBoardDetector').replace('StoneGeometry', 'CandidateStoneGeometry')
    generated = []
    for name, contents in [('CandidateStoneGeometry.swift', geometry), ('CandidateBoardDetector.swift', detector)]:
        path = output / name
        path.write_text('@testable import PhysicalGoTestRuntime\nimport Foundation\n' + contents)
        generated.append(str(path))
    main_source = source_root / 'PhysicalGo/Tools/InspectPlacementAssignment.swift'
    common = receipt['manifest']['commonArguments'] + ['-Onone', '-parse-as-library', '-I', str(runtime), '-L', str(runtime), '-lPhysicalGoTestRuntime', '-Xlinker', '-rpath', '-Xlinker', str(runtime)]
    commands = []
    for candidate in (False, True):
        name = 'candidate' if candidate else 'baseline'
        executable = output / name
        command = common + (['-D', 'TOUCHING_BLACK_CANDIDATE'] + generated if candidate else []) + [str(main_source), '-o', str(executable)]
        commands.append(command)
        subprocess.run(command, check=True)
        result = subprocess.run([str(executable), str(args.metadata.resolve()), str(args.frame.resolve()), str(reference_png), str(output / (name + '.json'))], check=True, capture_output=True, text=True)
        (output / (name + '.log')).write_text(result.stdout)
        print(result.stdout, end='')
    baseline = json.loads((output / 'baseline.json').read_text())
    candidate = json.loads((output / 'candidate.json').read_text())
    report = {'runtime': str(runtime), 'sourceCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=source_root, text=True).strip(), 'verifiedInputs': len(receipt['manifest']['inputs']), 'verifiedArtifacts': len(receipt['files']), 'commands': commands, 'inputHashes': {str(path): digest(path.read_bytes()) for path in [args.metadata, args.frame, args.reference_plist]}, 'referenceSavedAt': reference['savedAt'].isoformat(), 'readingsExactlyEqual': baseline['readings'] == candidate['readings'], 'point41CandidateFits': [s for s in candidate['footprints'] + candidate['placementFits'] if s['row'] * 19 + s['col'] == 41], 'limitation': 'Later saved frame; not exact delayed frames or historical tracker checkpoint. Threshold0.13 and current reference calibration; no placement acceptance claim.'}
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('Readings exactly equal:', report['readingsExactlyEqual'], 'point41 candidate fits:', report['point41CandidateFits'])


if __name__ == '__main__':
    main()
