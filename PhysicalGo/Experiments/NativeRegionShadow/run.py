"""Compile a focused native replay, with timing hooks in a generated source copy.

No app entry point, camera API, controller, storage/game mutation or UI is run.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixtures', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--prepare-only', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    folder = Path(__file__).resolve().parent
    args.output.mkdir(parents=True, exist_ok=True)
    sys.path.insert(0, str(root))
    from scripts.build_sources import resolve_sources
    sources = resolve_sources(root, [folder/'Replay.swift', folder/'ShadowScheduler.swift',
        root/'Sources/BoardVision.swift', root/'Sources/StoneGeometry.swift',
        root.parent/'SGFPlayerClean/Models/OGSModels.swift',
        root.parent/'SGFPlayerClean/Models/OGSScoringState.swift'])
    original = root/'Sources/BoardVision.swift'
    source = original.read_text()
    start = '        for row in 0..<calibration.size { for col in 0..<calibration.size {\n            // Estimate illumination from nearby cell centers, not from the stone.'
    end = '            centers.append(center)\n        } }'
    if source.count(start) != 1 or source.count(end) != 1:
        raise ValueError('Classification-loop instrumentation boundary changed')
    source = source.replace(start, start.replace('\n            //', '\n            let shadowCellStarted=DispatchTime.now().uptimeNanoseconds\n            //'))
    source = source.replace(end, '            centers.append(center)\n            NativeShadowCost.record(row*calibration.size+col,shadowCellStarted)\n        } }')
    generated = args.output/'BoardVision.swift'
    generated.write_text(source)
    inputs = {str(path):digest(path) for path in sources}
    compiled = [generated if path == original else path for path in sources]
    command = ['xcrun','swiftc','-swift-version','5','-O','-D','PHYSICAL_GO',*map(str,compiled),'-o',str(args.output/'replay')]
    metadata = json.loads((args.fixtures/'metadata.json').read_text())
    used = ['metadata.json','photo-labels.json','provenance.json','reference.png','frame-950.png']
    used += [row['name']+'.png' for row in metadata if row.get('time') is not None]
    provenance = dict(nativeBase='1f6fb91cac57616791d47c2fea4cc4eca0426a28', sourceHashes=inputs,
                      generatedTimingSourceSHA256=digest(generated), command=command,
                      fixtureHashes={name:digest(args.fixtures/name) for name in used},
                      runnerSHA256=digest(Path(__file__)), noRuntimeSourceMutation=True)
    (args.output/'provenance.json').write_text(json.dumps(provenance, indent=2)+'\n')
    if args.prepare_only:
        print(f'Prepared {len(compiled)} sources; no compiler launched.')
        return
    with (args.output/'build.log').open('w') as log:
        subprocess.run(command, check=True, stdout=log, stderr=subprocess.STDOUT)
    with (args.output/'run.log').open('w') as log:
        subprocess.run([str(args.output/'replay'),str(args.fixtures),str(args.output/'result.json')],
                       check=True, stdout=log, stderr=subprocess.STDOUT, timeout=180)
    print((args.output/'run.log').read_text())


if __name__ == '__main__':
    main()
