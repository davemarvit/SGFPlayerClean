#!/usr/bin/env python3
"""Replay saved app-broker images with unchanged native BoardDetector sources.

An archived frame verifies native replay correspondence before fresh outputs are
interpreted. This does not replay the temporal tracker or PhysicalAI controller.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('recording', type=Path)
    parser.add_argument('samples', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--reference-state', type=Path, required=True,
                        help='Saved EmptyBoardReference.plist snapshot; must contain identical reference PNG bytes')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    root = Path(__file__).resolve().parents[2]
    sys.path.insert(0, str(root))
    from scripts.build_sources import resolve_sources
    events_path = args.recording / 'events.jsonl'
    event = archived = None
    for line in events_path.open():
        row = json.loads(line)
        if row.get('frameID') != 697:
            continue
        if row.get('event') == 'frame':
            event = row
        if row.get('event') == 'operation finished':
            archived = row
    if event is None or archived is None:
        raise ValueError('Required archived frame697 control is missing')
    reference = (args.recording / event['referenceImage']).resolve()
    reference_state = plistlib.loads(args.reference_state.read_bytes())
    if (reference_state['png'] != reference.read_bytes()
            or reference_state['cameraID'] != event['cameraID']
            or reference_state['referenceCalibration'] != event['referenceCalibration']):
        raise ValueError('Persisted reference snapshot differs from archived control reference')
    image = (args.recording / event['image']).resolve()
    rows = [dict(id='archived-697-control', image=str(image), referenceImage=str(reference),
                 calibration=event['calibration'], referenceCalibration=event['referenceCalibration'],
                 threshold=event['threshold'])]
    evidence = {str(events_path.resolve()): sha(events_path), str(reference): sha(reference), str(image): sha(image)}
    evidence[str(args.reference_state.resolve())] = sha(args.reference_state)
    sample_sets = ['black-01', 'white-01', 'black-midpoint-01', 'white-midpoint-01']
    frames = []
    seen = set()
    for name in sample_sets:
        folder = args.samples / name
        manifest_path = folder / 'samples.json'
        manifest = json.loads(manifest_path.read_text())
        evidence[str(manifest_path.resolve())] = sha(manifest_path)
        if len(manifest['samples']) != 8:
            raise ValueError('Each named capture must contain exactly eight samples')
        for sample in manifest['samples']:
            image = (folder / sample['image']).resolve()
            metadata_path = folder / sample['metadata']
            metadata = json.loads(metadata_path.read_text())
            if sha(image) != sample['sha256'] or metadata['frame'] != sample['frame']:
                raise ValueError('Sample image hash or frame identity changed')
            if metadata['cameraID'] != event['cameraID'] or metadata['referenceCalibration'] != event['referenceCalibration']:
                raise ValueError('Reference/camera mismatch; do not reuse archived reference')
            if metadata['handObstructed'] is not False or metadata['alignmentValid'] is not True:
                raise ValueError('Capture did not have clear/aligned evidence')
            identity = (metadata['frame']['streamEpoch'], metadata['frame']['frameID'])
            if identity in seen:
                raise ValueError('Duplicate captured frame')
            seen.add(identity)
            evidence[str(image)] = sha(image)
            evidence[str(metadata_path.resolve())] = sha(metadata_path)
            case_id = name + '/' + sample['image']
            rows.append(dict(id=case_id, image=str(image), referenceImage=str(reference),
                             calibration=metadata['currentCalibration'],
                             referenceCalibration=metadata['referenceCalibration'], threshold=event['threshold']))
            frames.append(dict(id=case_id, frame=metadata['frame'], cameraID=metadata['cameraID']))
    input_path = args.output / 'inputs.json'
    input_path.write_text(json.dumps(rows, indent=2) + '\n')
    sources = [root.parent / 'SGFPlayerClean/Models' / name for name in ['OGSModels.swift', 'OGSScoringState.swift']]
    sources += [root / 'Sources' / name for name in ['BoardVision.swift', 'StoneGeometry.swift', 'BoardAppearanceDetector.swift']]
    sources = resolve_sources(root, sources)
    sources.append(Path(__file__).with_name('Replay.swift'))
    source_hashes = {str(path): sha(path) for path in sources}
    executable = args.output / 'Replay'
    command = ['xcrun', 'swiftc', '-swift-version', '5', '-D', 'PHYSICAL_GO', '-O',
               *map(str, sources), '-o', str(executable)]
    provenance = dict(purpose='Stateless native detector replay; no game/move authority',
                      buildCommand=command, sourceHashes=source_hashes, inputHashes=evidence,
                      inputsSHA256=sha(input_path), driverSHA256=sha(Path(__file__)), frames=frames,
                      thresholdSource='Archived control frame697: not a current preference read',
                      referenceEvidence='Archived PNG exactly matches supplied persisted reference snapshot; not an in-memory frame receipt',
                      temporalTrackerReplayed=False, controllerReplayed=False)
    (args.output / 'provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
    with (args.output / 'build.log').open('w') as log:
        subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
    if {str(path): sha(path) for path in sources} != source_hashes:
        raise ValueError('Build sources changed during compilation')
    raw = subprocess.check_output([str(executable), str(input_path)])
    (args.output / 'native-results.json').write_bytes(raw)
    output = json.loads(raw)
    if (output[0]['footprints'] != archived['footprints']
            or output[0]['placementFits'] != archived['placementFits']):
        raise ValueError('Archived footprint replay mismatch; fresh output is not validated')
    if sha(input_path) != provenance['inputsSHA256']:
        raise ValueError('Generated replay input changed during execution')
    if {key: sha(Path(key)) for key in evidence} != evidence:
        raise ValueError('Input evidence changed during replay')
    summary = dict(archivedFootprintsExactlyReproduced=True,
                   executableSHA256=sha(executable), sourceHashesUnchanged=True,
                   inputHashesUnchanged=True, cases=[])
    for row in output:
        if row['id'] == 'archived-697-control':
            continue
        # Retain all source outputs; these compact views focus on the moved side-middle.
        readings = [r for r in row['readings'] if 8 <= r['row'] <= 10 and 13 <= r['col'] <= 16]
        fits = [f for f in row['footprints'] + row['placementFits'] if 8 <= f['row'] <= 10 and 13 <= f['col'] <= 16]
        summary['cases'].append(dict(id=row['id'], localReadings=readings, localFits=fits,
                                     manualPoints=row['manualPoints'], lightingBlocked=row['lightingBlocked']))
    summary['limitations'] = [
        'Archived control establishes source/image replay correspondence for that example.',
        'Fresh broker metadata does not include threshold; archived0.13 is explicit, not claimed as a fresh preference read.',
        'Reference PNG matches persisted snapshot exactly; broker metadata does not attest in-memory reference bytes per frame.',
        'Saved camera flags describe capture only. This does not replay temporal hand/tracking state.',
        'Classification and fits do not prove full-controller acceptance, hint activation, or clock behavior.',
        'No profile correction, fitting, training, runtime changes, app start, or hardware commands.',
    ]
    (args.output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print('PASS: archived footprints exactly reproduced; ' + str(len(rows)-1) + ' captured frames replayed; inputs/sources unchanged')


if __name__ == '__main__':
    main()
