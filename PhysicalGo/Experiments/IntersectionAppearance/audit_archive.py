#!/usr/bin/env python3
"""Offline coverage and spatial holdout audit of confirmed appearance features.

No images are analyzed, no app is imported, and no classifier is activated.
Uses stored features from StoneCalibrationArchive, not detector-derived labels.
"""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
import math
from pathlib import Path

LABELS = ('empty', 'black', 'white')
FLOORS = (.045, .035, .025, .025, .045)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def quantile(values, q):
    # Swift .rounded() for nonnegative indices: ties away from zero.
    values = sorted(values)
    return values[int(math.floor((len(values) - 1) * q + .5))]


def context_group(context):
    if context.get('unknown', 8):
        return 'unknown'
    black, white = context.get('black', 0), context.get('white', 0)
    if black and white:
        return 'mixed'
    if black:
        return 'one black' if black == 1 else 'several black'
    if white:
        return 'one white' if white == 1 else 'several white'
    return 'open'


def fit(rows):
    """Same pooled descriptive ranges as StoneAppearanceModel; no probability."""
    result = {}
    for label in LABELS:
        samples = [r['features']['values'] for r in rows if r['label'] == label]
        if len(samples) < 3:
            return None
        center, radius = [], []
        for index, floor in enumerate(FLOORS):
            values = [row[index] for row in samples]
            median = quantile(values, .5)
            span = max(abs(quantile(values, .1) - median), abs(quantile(values, .9) - median))
            center.append(median)
            radius.append(max(floor, span * 1.25))
        result[label] = dict(center=center, radius=radius)
    return result


def predict(model, features):
    if model is None:
        return 'unknown'
    distances = sorted((math.sqrt(sum(((value - center) / radius) ** 2
                                      for value, center, radius in zip(features, d['center'], d['radius'])) / 5), label)
                       for label, d in model.items())
    if distances[0][0] > 1.25 or distances[1][0] - distances[0][0] < .65:
        return 'unknown'
    return distances[0][1]


def load_archive(folder):
    profile_path = folder / 'profile.json'
    profile = json.loads(profile_path.read_text())
    captures = []
    for capture_id in profile['captures']:
        path = folder / capture_id / 'capture.json'
        data = json.loads(path.read_text())
        if data.get('labelSource') != 'user-confirmed calibration diagram and frozen photo':
            raise ValueError('Require explicit user-confirmed calibration provenance')
        if data.get('id') != capture_id or data.get('session') != folder.name:
            raise ValueError('Capture/profile identity mismatch')
        captures.append((path, data))
    captures.sort(key=lambda pair: pair[1]['stage'])
    if [d['stage'] for _, d in captures] != [0, 1, 2]:
        raise ValueError('Require exactly one confirmed capture at each stage')
    dimensions = {(d['size'], d['width'], d['height']) for _, d in captures}
    cameras = {d['cameraID'] for _, d in captures if d.get('cameraID')}
    if len(dimensions) != 1 or len(cameras) != 1:
        raise ValueError('Mixed/unknown camera or board dimensions; do not pool')
    size = captures[0][1]['size']
    # Archive examples are written in stage order, with ascending point order.
    # Verify the labels against every capture before attributing features to it.
    expected = [(d['stage'], item['point'], item['occupancy'])
                for _, d in captures for item in sorted(d['labels'], key=lambda x: x['point'])]
    examples = profile['examples']
    if len(examples) != len(expected):
        raise ValueError('Incomplete feature archive: cannot infer stage association')
    rows = []
    for sample, (stage, point, label) in zip(examples, expected):
        values = sample['features']['values']
        if sample['point'] != point or sample['label'] != label or label not in LABELS:
            raise ValueError('Example and confirmed capture label mismatch')
        if not 0 <= point < size * size or len(values) != 5 or not all(math.isfinite(x) for x in values):
            raise ValueError('Invalid features or intersection')
        rows.append({**sample, 'stage': stage})
    sources = []
    for path, data in captures:
        image = path.parent / data['image']
        sources.append({key: data.get(key) for key in ('id', 'stage', 'cameraID', 'capturedAt', 'appVersion', 'labelSource', 'calibration')}
                       | dict(metadata=str(path), metadata_sha256=digest(path), image=str(image), image_sha256=digest(image)))
    return rows, size, dict(profile=str(profile_path), profile_sha256=digest(profile_path), captures=sources)


def audit(folder):
    rows, size, provenance = load_archive(folder)
    by_point = defaultdict(set)
    for row in rows:
        by_point[row['point']].add(row['label'])
    # Withhold ALL appearances at an intersection, not random adjacent frames.
    # This is an internal spatial sanity check, NOT episode/setup validation.
    holdout = []
    for point in sorted(by_point):
        training = [r for r in rows if r['point'] != point]
        model = fit(training)
        for row in rows:
            if row['point'] == point:
                call = predict(model, row['features']['values'])
                holdout.append(dict(point=point, stage=row['stage'], truth=row['label'], call=call,
                                    outcome='correct' if call == row['label'] else 'unknown' if call == 'unknown' else 'wrong'))
    all_model = fit(rows)
    stored = json.loads((folder / 'profile.json').read_text())['model']['distributions']
    if any(abs(a - b) > 1e-10 for d in stored for field in ('center', 'radius')
           for a, b in zip(d[field], all_model[d['label']][field])):
        raise ValueError('Pooled audit model does not reproduce stored Swift ranges')
    summaries = {}
    for label in LABELS:
        selected = [r for r in rows if r['label'] == label]
        summaries[label] = dict(examples=len(selected), unique_points=len({r['point'] for r in selected}),
                               brightness_relative_to_wood=dict(min=min(r['features']['values'][0] for r in selected),
                                                                median=quantile([r['features']['values'][0] for r in selected], .5),
                                                                max=max(r['features']['values'][0] for r in selected)),
                               internal_spatial_holdout=dict(Counter(r['outcome'] for r in holdout if r['truth'] == label)))
    return dict(schema=1, purpose='Offline coverage / existing feature model sanity check; no live activation',
                provenance=provenance, board_size=size, samples=len(rows), classes=summaries,
                coverage=dict(sampled_intersections=len(by_point), all_three_classes=sum(len(labels) == 3 for labels in by_point.values()),
                              no_explicit_labels=size * size - len(by_point),
                              neighborhoods=dict(Counter(context_group(r.get('context', {})) for r in rows))),
                pooled_ranges_match_archived_swift_model=True,
                per_intersection={str(point): sorted(labels) for point, labels in sorted(by_point.items())},
                spatial_holdout_rows=holdout,
                limitations=[
                    'One Nov4 calibration setup. No independent setup/episode holdout; no accuracy claim.',
                    'Spatial holdout shares frames, lighting and camera with training; points are correlated.',
                    'Legacy empty stage lacks camera ID; associated by confirmed archive, not asserted current-camera identity.',
                    'Only explicit calibration sample labels count; omitted positions are not ground truth empties.',
                    'Stored features are not recomputed here; image, metadata and feature-profile hashes preserve provenance.',
                    'Pooled feature model only; does not test neighbor-conditioned, new template or live production detector.',
                    'No hand, glare, severe-shadow or occupied-reference challenge labels in these confirmed captures.',
                    'Nov4 camera-port ID differs from Nov21-23; this profile is not applied to those setups.',
                    'Compatibility is correlated with existing pixel/shape evidence and is not an independent probability.',
                ])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    result = audit(args.archive.resolve())
    # Refuse to overwrite a prior report or any source artifact.
    with args.output.open('x') as stream:
        json.dump(result, stream, indent=2, allow_nan=False)
        stream.write('\n')
    print(json.dumps({key: result[key] for key in ('samples', 'classes', 'coverage')}, indent=2))
