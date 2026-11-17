#!/usr/bin/env python3
"""Development ablation of sampling geometry; no live recognition or timing code.

Uses current-frame outlines only. The 85-game is now development evidence,
not a held-out validation set for this experiment. No thresholds are searched.
"""
import argparse
from collections import defaultdict
import json
from pathlib import Path

import numpy as np

from evaluate_unavailable_shadow import point_scores
from local_quality_lab import digest, read_image
from placement_competition_lab import appearance_features
from recognition_parameter_search import write_json
from unchanged_baseline_lab import Observation, Sampler, features
from unavailable_shadow_lab import measured_contrast


def eligible(shapes):
    result = []
    for s in shapes:
        values = [s['quality'], s['center']['x'], s['center']['y'], s['radiusCol'], s['radiusRow']]
        if (all(np.isfinite(values)) and s['quality'] >= .8 and
                .25 <= s['radiusCol'] <= .75 and .25 <= s['radiusRow'] <= .75 and
                max(abs(s['center']['x']-s['col']), abs(s['center']['y']-s['row'])) <= .5):
            result.append(s)
    return result


def geometry(shape, shapes):
    y, x = np.mgrid[:shape[0], :shape[1]]
    x, y = x/24-1.5, y/24-1.5
    excluded = np.zeros(shape, dtype=bool)
    for s in shapes:
        excluded |= ((x-s['center']['x'])/(s['radiusCol']+.08))**2 + ((y-s['center']['y'])/(s['radiusRow']+.08))**2 <= 1
    return x, y, excluded.ravel()


def run(prepared, labels_evidence, output, case):
    if output.resolve().is_relative_to(Path(__file__).resolve().parents[2]):
        raise ValueError('Use external output storage')
    output.mkdir(parents=True, exist_ok=False)
    write_json(output/'plan.json', {
        'status': 'OFFLINE DEVELOPMENT ABLATION; no promotion',
        'variants': ['original', 'outline_mask', 'outline_center_and_mask'],
        'qualityMinimum': .8, 'maximumAxisOffset': .5, 'radiusRange': [.25, .75], 'maskPadding': .08,
        'coreRadius': .32, 'wood': 'Original grid exclusion/ring, additionally exclude eligible current-frame ellipses.',
        'scope': 'Feature-only ablation using unchanged frozen support thresholds; no clock/capture/temporal decoder.',
        'truth': 'Existing visually reviewed point labels only. Original 85-game frozen failure retained.'})
    evidence = {r['frame']: r for r in map(json.loads, (prepared/'evidence.jsonl').open())}
    rows = [r for r in json.loads(labels_evidence.read_text()) if r['case'] == case]
    by_frame = defaultdict(list)
    for row in rows:
        by_frame[row['frame']].append(row)
    variants = {'original': rows, 'outline_mask': [], 'outline_center_and_mask': []}
    details, references, frame_metadata, inputs = [], {}, {}, {prepared/'evidence.jsonl', labels_evidence, Path(__file__)}
    for frame, batch in sorted(by_frame.items()):
        e = evidence[frame]
        op = e['recordedOperation']
        path, ref = Path(e['image']), Path(e['referenceImage'])
        # Reference calibration is stored in the original camera frame metadata,
        # not the analyzed-operation calibration. Read from the source manifest.
        inputs.update((path, ref))
        current = read_image(path, op['calibration'])
        reference_calibration = e.get('referenceCalibration')
        if reference_calibration is None:
            events = path.parent.parent/'events.jsonl'
            if events not in frame_metadata:
                frame_metadata[events] = {}
                for line in events.open():
                    item = json.loads(line)
                    if item['event'] == 'frame' and item['frameID'] in by_frame:
                        frame_metadata[events][item['frameID']] = item['referenceCalibration']
            if frame not in frame_metadata[events]:
                raise ValueError('Missing original reference calibration')
            reference_calibration = frame_metadata[events][frame]
            inputs.add(events)
        ref_key = (str(ref), json.dumps(reference_calibration, sort_keys=True))
        if ref_key not in references:
            references[ref_key] = read_image(ref, reference_calibration)
        old = references[ref_key]
        flat = np.where(current[1], current[0], np.nan).ravel()
        old_flat = np.where(old[1], old[0], np.nan).ravel()
        sampler = Sampler(current[0].shape)
        shapes = eligible(op.get('footprints', [])+op.get('placementFits', []))
        x, y, excluded = geometry(current[0].shape, shapes)
        for row in batch:
            p = row['point']
            matches = [s for s in shapes if s['row']*19+s['col'] == p]
            target = max(matches, key=lambda s: s['quality']) if matches else None
            core, wood = sampler.core[p], sampler.wood[p]
            masked_wood = wood[~excluded[wood]]
            diagnostic = {'frame': frame, 'point': p, 'kind': row['kind'], 'truth': row['truth'],
                          'outline': target, 'originalWoodPixels': len(wood), 'maskedWoodPixels': len(masked_wood),
                          'excludedWoodFraction': 1-len(masked_wood)/len(wood) if len(wood) else None,
                          'original': row['appearance']}
            for variant in ('outline_mask', 'outline_center_and_mask'):
                index = core
                if variant == 'outline_center_and_mask' and target:
                    index = np.flatnonzero((x-target['center']['x'])**2+(y-target['center']['y'])**2 <= .32**2)
                metric = features([flat[index]], [flat[masked_wood]], [old_flat[index]], [old_flat[masked_wood]])
                obs = Observation(frame, e['capturedAt'], False, False, [], [flat[index]], metric)
                appearance = appearance_features(obs, [old_flat[index]])[0]
                appearance['measuredCoreDelta'] = measured_contrast(flat[index], old_flat[index], appearance)
                variants[variant].append({**row, 'appearance': appearance})
                diagnostic[variant] = appearance
            details.append(diagnostic)
    scores = {variant: point_scores(values) for variant, values in variants.items()}
    write_json(output/'scores.json', scores)
    write_json(output/'geometry-evidence.json', details)
    summary = {variant: {policy: {k: v for k, v in result.items() if k != 'rows'}
                         for policy, result in policies.items()} for variant, policies in scores.items()}
    write_json(output/'summary.json', summary)
    write_json(output/'manifest.json', {'inputs': {str(p): digest(p) for p in sorted(inputs)}, 'clockAuthority': False})
    print(json.dumps({v: {p: {k: r[k] for k in ('afterPlacementStrong', 'strongWrong')}
                          for p, r in policies.items()} for v, policies in summary.items()}, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('prepared', 'labels-evidence', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--case', required=True)
    args = parser.parse_args()
    run(args.prepared, args.labels_evidence, args.output, args.case)
