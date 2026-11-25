"""Bounded offline stone-center measurement collector; never runtime authority."""
import argparse
from collections import defaultdict
import hashlib
import json
import math
from pathlib import Path
import statistics

from audit import field_fit, prediction, residual

MAX_BYTES = 8 * 1024 * 1024
MAX_FRAMES = 10000
CONTEXT = ('setupID', 'cameraEpoch', 'calibrationSHA256', 'stoneSetID',
           'color', 'estimatorVersion', 'labelKind')
QUALITY = ('handClear', 'laserDark', 'gridStable', 'fullBoundary',
           'noGlare', 'noTouching')
SPLITS = ('train', 'heldOut', 'misplacedControl')


def text(value):
    return isinstance(value, str) and 0 < len(value) <= 512


def digest(value):
    return isinstance(value, str) and len(value) == 64 and all(c in '0123456789abcdef' for c in value)


def pair(value):
    return (isinstance(value, list) and len(value) == 2
            and all(type(v) in (int, float) and math.isfinite(v) for v in value))


def bounded_json(path):
    with path.open('rb') as source:
        raw = source.read(MAX_BYTES + 1)
    if len(raw) > MAX_BYTES:
        raise ValueError('JSON input exceeds 8 MiB')
    return json.loads(raw), hashlib.sha256(raw).hexdigest()


def collect(doc):
    """Validate all records before quality filtering; median each placement once."""
    if doc.get('schemaVersion') != 1 or doc.get('units') != 'gridCells':
        raise ValueError('Expected schemaVersion 1 and gridCells units')
    rows = doc.get('frames')
    sources = doc.get('sources')
    if not isinstance(rows, list) or len(rows) > MAX_FRAMES:
        raise ValueError('Expected at most 10000 frames')
    if not isinstance(sources, list) or len(sources) > MAX_FRAMES:
        raise ValueError('Expected bounded source list')
    source_ids = set()
    for source in sources:
        if not all(text(source.get(k)) for k in ('id', 'path')) or not digest(source.get('sha256')):
            raise ValueError('Every measurement source needs ID/path/SHA256')
        if source['id'] in source_ids:
            raise ValueError('Duplicate source ID')
        source_ids.add(source['id'])
    placements, identities, seen, rejected = defaultdict(list), {}, set(), []
    move_placements = {}
    for index, row in enumerate(rows):
        if not all(text(row.get(k)) for k in CONTEXT + ('placementID', 'frameID', 'sourceID', 'recordID', 'gameID')):
            raise ValueError('Missing placement/frame/context provenance')
        if type(row.get('moveIndex')) is not int or row['moveIndex'] < 0:
            raise ValueError('Move index must be a nonnegative integer')
        if not digest(row['calibrationSHA256']) or row['sourceID'] not in source_ids:
            raise ValueError('Invalid calibration or missing measurement source')
        if row['color'] not in ('black', 'white') or row['labelKind'] not in ('acceptedTentative', 'explicitlyCentered'):
            raise ValueError('Color/label kind must be explicit; pending targets are not labels')
        if row.get('split') not in SPLITS or not pair(row.get('point')) or not pair(row.get('offset')):
            raise ValueError('Invalid split or finite two-dimensional cell measurement')
        if any(v < 0 or v > 18 for v in row['point']):
            raise ValueError('Point outside zero-indexed 19x19 board')
        context = tuple(row[k] for k in CONTEXT)
        # A placement identity may never be relabelled, repartitioned or pooled across setups.
        identity = (context, row['gameID'], row['moveIndex'], tuple(row['point']), row['split'])
        pid = row['placementID']
        move_key = (context, row['gameID'], row['moveIndex'])
        if move_key in move_placements and move_placements[move_key] != pid:
            raise ValueError('Same game move has multiple placement IDs')
        move_placements[move_key] = pid
        if pid in identities and identities[pid] != identity:
            raise ValueError('Placement crosses split, context or intended point')
        identities[pid] = identity
        frame_key = (pid, row['frameID'])
        if frame_key in seen:
            raise ValueError('Duplicate frame within placement')
        seen.add(frame_key)
        quality = row.get('quality', {})
        failures = [key for key in QUALITY if quality.get(key) is not True]
        if failures:
            rejected.append({'index': index, 'placementID': pid, 'reasons': failures})
            continue
        placements[pid].append(row)
    result = []
    for pid, frames in sorted(placements.items()):
        first = frames[0]
        result.append({**{k: first[k] for k in CONTEXT}, 'placementID': pid,
                       'point': first['point'], 'split': first['split'],
                       'gameID': first['gameID'], 'moveIndex': first['moveIndex'],
                       'frameCount': len(frames), 'sourceIDs': sorted({r['sourceID'] for r in frames}),
                       'frameIDs': [r['frameID'] for r in frames],
                       'measurementRecords': [{'sourceID': r['sourceID'], 'recordID': r['recordID']} for r in frames],
                       'offset': [statistics.median(r['offset'][j] for r in frames) for j in (0, 1)]})
    return result, rejected


def region(point):
    return tuple(min(2, int(v // (19 / 3))) for v in point)


def support(points):
    """Conservative diagnostic gate, not a claim of universal sample sufficiency."""
    if len(points) < 6:
        return 'fewerThanSixIndependentPlacements'
    means = [statistics.mean(p[j] for p in points) for j in (0, 1)]
    a, b = [sum((p[j] - means[j]) ** 2 for p in points) for j in (0, 1)]
    c = sum((p[0] - means[0]) * (p[1] - means[1]) for p in points)
    if min(max(p[j] for p in points) - min(p[j] for p in points) for j in (0, 1)) < 4:
        return 'narrowSpatialSupport'
    if a * b - c * c <= 0.01 * (a + b) ** 2:
        return 'nearlyCollinearSupport'
    return None


def evaluate(doc, *, hold_out_regions=False):
    placements, rejected = collect(doc)
    groups = defaultdict(list)
    for row in placements:
        groups[tuple(row[k] for k in CONTEXT)].append(row)
    results = []
    for context, rows in sorted(groups.items()):
        train = [r for r in rows if r['split'] == 'train']
        held = [r for r in rows if r['split'] == 'heldOut']
        if hold_out_regions and ({region(r['point']) for r in train} & {region(r['point']) for r in held}):
            raise ValueError('Training and held-out board regions overlap')
        result = {'context': dict(zip(CONTEXT, context)),
                  'trainingPlacementIDs': [r['placementID'] for r in train],
                  'trainingFrames': sum(r['frameCount'] for r in train), 'evaluation': []}
        reason = support([r['point'] for r in train])
        if reason:
            result['abstention'] = reason
        else:
            fit = field_fit([r['point'] for r in train], [r['offset'] for r in train])
            result['diagnosticOpticalField'] = fit
            for row in rows:
                if row['split'] == 'train':
                    continue
                result['evaluation'].append({'placementID': row['placementID'], 'split': row['split'],
                    'point': row['point'], 'uncorrectedErrorCells': residual(row['offset'], [0, 0]),
                    'meanOnlyErrorCells': residual(row['offset'], fit['meanOffset']),
                    'fieldErrorCells': residual(row['offset'], prediction(fit, row['point']))})
            if not held:
                result['validationGap'] = 'No held-out placements; fit alone is not validation'
        results.append(result)
    return {'schemaVersion': 1, 'status': 'offlineDiagnosticOnly',
            'physicalThicknessIdentified': False, 'grantsMotion': False, 'changesRecognition': False,
            'placementCount': len(placements), 'rejectedFrames': rejected,
            'placements': placements, 'groups': results,
            'holdOutRegionsRequired': hold_out_regions,
            'limitations': ['Input quality and accepted labels are recorded claims, not independently verified truth.',
                'Accepted ordinary-play labels remain tentative and selection-biased.',
                'OLS optical field cannot separate placement bias, estimator bias, grid error or thickness.',
                'Misplaced controls are scored but never trained; no automatic correction is promoted.']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--hold-out-regions', action='store_true')
    args = parser.parse_args()
    doc, sha = bounded_json(args.manifest)
    # Verify bounded measurement JSON provenance; never load/acquire camera images.
    sources = doc.get('sources', [])
    if not isinstance(sources, list) or len(sources) > MAX_FRAMES:
        raise ValueError('Invalid sources')
    # Validate first so malformed identities cannot trigger arbitrary source reads.
    report = evaluate(doc, hold_out_regions=args.hold_out_regions)
    total = 0
    for source in sources:
        path = args.manifest.parent / source['path']
        total += path.stat().st_size
        if total > MAX_BYTES:
            raise ValueError('Combined measurement sources exceed 8 MiB')
        _, actual = bounded_json(path)
        if actual != source['sha256']:
            raise ValueError('Measurement source hash mismatch: ' + source['id'])
    report['manifest'] = {'path': str(args.manifest), 'sha256': sha}
    report['verifiedMeasurementSources'] = sources
    with args.output.open('x') as output:
        json.dump(report, output, indent=2, allow_nan=False)
        output.write('\n')
    print(f"{report['placementCount']} placements; {len(report['rejectedFrames'])} rejected frames; offline only")


if __name__ == '__main__':
    main()
