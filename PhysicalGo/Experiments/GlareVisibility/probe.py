#!/usr/bin/env python3
"""Offline diagnostic only: retained-grid rail recovery, never occupancy/clearance."""
import argparse
import hashlib
import json
from pathlib import Path
import cv2
import numpy as np

PITCH = 40
MARGIN = 20
SIDE = 18 * PITCH + 2 * MARGIN + 1

def project(h, points):
    return cv2.perspectiveTransform(np.asarray(points, np.float64).reshape(-1, 1, 2), h).reshape(-1, 2)

def calibration_h(metadata, width, height):
    if 'board_to_image' in metadata:
        return np.asarray(metadata['board_to_image'], np.float64)
    cal = metadata.get('currentCalibration', metadata.get('calibration', metadata))
    if cal['size'] != 19:
        raise ValueError('This bounded prototype handles 19x19 only')
    h = np.asarray(cal['h'] + [1], np.float64).reshape(3, 3)
    return np.diag([width - 1, height - 1, 1]) @ h @ np.diag([1 / 18, 1 / 18, 1])

def robust_line(points):
    """Deterministic RANSAC, then least squares; along -> transverse."""
    p = np.asarray(points, np.float64)
    if len(p) < 24:
        return None
    best = None
    for i in range(0, len(p), 3):
        for j in range(i + 12, len(p), 3):
            if abs(p[j, 0] - p[i, 0]) < 6 * PITCH:
                continue
            slope = (p[j, 1] - p[i, 1]) / (p[j, 0] - p[i, 0])
            intercept = p[i, 1] - slope * p[i, 0]
            mask = np.abs(p[:, 1] - slope * p[:, 0] - intercept) < 1.5
            score = int(mask.sum())
            if best is None or score > best[0]:
                best = score, mask
    if best is None:
        return None
    clean = p[best[1]]
    if len(clean) < 24 or np.ptp(clean[:, 0]) < 9 * PITCH:
        return None
    slope, intercept = np.polyfit(clean[:, 0], clean[:, 1], 1)
    residual = np.abs(clean[:, 1] - slope * clean[:, 0] - intercept)
    return {'slope': float(slope), 'intercept': float(intercept),
            'count': len(clean), 'span': [float(clean[:, 0].min()), float(clean[:, 0].max())],
            'p95ResidualRectifiedPx': float(np.quantile(residual, .95))}

def analyze(image, h):
    rect = np.array([[PITCH, 0, MARGIN], [0, PITCH, MARGIN], [0, 0, 1]], np.float64)
    warp = cv2.warpPerspective(image, rect @ np.linalg.inv(h), (SIDE, SIDE))
    gray = cv2.cvtColor(warp, cv2.COLOR_BGR2GRAY).astype(float)
    clipped = (warp.min(axis=2) >= 250).astype(np.uint8)
    lines = [[], []]
    points = [[], []]
    # Along-rail probes stay between intersections. A narrow dark ridge must
    # have brighter flanks on BOTH sides; white/dark interiors are not rails.
    for axis in [0, 1]:
        view = gray if axis == 0 else gray.T
        for rail in range(19):
            nominal = MARGIN + rail * PITCH
            samples = []
            for segment in range(18):
                for fraction in [.25, .5, .75]:
                    along = int(MARGIN + (segment + fraction) * PITCH)
                    candidates = np.arange(nominal - 6, nominal + 7)
                    center = view[candidates, along]
                    flank = np.minimum(view[candidates - 6, along], view[candidates + 6, along])
                    contrast = flank - center
                    idx = int(contrast.argmax())
                    if contrast[idx] >= max(8, flank[idx] * .055):
                        samples.append([along, int(candidates[idx])])
            lines[axis].append(robust_line(samples))
            points[axis].append(samples)
    known, observed = [], []
    for row, horizontal in enumerate(lines[0]):
        if horizontal is None:
            continue
        for col, vertical in enumerate(lines[1]):
            if vertical is None:
                continue
            x = (vertical['intercept'] + vertical['slope'] * horizontal['intercept']) / (1 - vertical['slope'] * horizontal['slope'])
            y = horizontal['intercept'] + horizontal['slope'] * x
            known.append([col, row]); observed.append([x, y])
    counts = [sum(v is not None for v in family) for family in lines]
    diagnostic_h = None
    spans = [max((i for i, v in enumerate(family) if v is not None), default=0) - min((i for i, v in enumerate(family) if v is not None), default=0) for family in lines]
    if min(counts) >= 10 and min(spans) >= 14:
        diagnostic_h, inliers = cv2.findHomography(np.asarray(known, float), np.asarray(observed, float), cv2.RANSAC, 2)
    grid = np.array([[c, r] for r in range(19) for c in range(19)], float)
    cells = []
    for col, row in grid.astype(int):
        x, y = MARGIN + col * PITCH, MARGIN + row * PITCH
        patch = clipped[y - 10:y + 11, x - 10:x + 11]
        support = []
        for axis, rail, along in [(0, row, x), (1, col, y)]:
            nearby = [p for p in points[axis][rail] if abs(p[0] - along) <= 30]
            support.append(len(nearby))
        cells.append({'row': int(row), 'col': int(col), 'clippedFraction': float(patch.mean()),
                      'nearbyRailProbeCounts': support, 'stoneState': 'unknown',
                      'freshClearance': False})
    result = {'diagnosticOnly': True, 'stoneClassificationImplemented': False,
              'geometrySupported': diagnostic_h is not None, 'supportedRailCounts': counts,
              'clippedFraction': float(clipped.mean()), 'supportedRailSpans': spans,
              'lines': lines, 'intersections': cells,
              'notes': ['Clipping is a pixel annotation, not a frame veto or a glare classifier.',
                        'No interpolated geometry is observed ink or fresh empty/stone/hand evidence.',
                        'Retained calibration seeds line identity; no independent acquisition.']}
    overlay = warp.copy()
    overlay[clipped != 0] = [180, 0, 180]
    if diagnostic_h is not None:
        mapped = project(diagnostic_h, grid)
        delta = np.linalg.norm(mapped - project(rect, grid), axis=1)
        result['p95PriorDisplacementGridUnits'] = float(np.quantile(delta, .95) / PITCH)
        result['maxPriorDisplacementGridUnits'] = float(delta.max() / PITCH)
        result['diagnosticBoardToImage'] = (h @ np.linalg.inv(rect) @ diagnostic_h).tolist()
        for (col, row), (x, y) in zip(grid.astype(int), mapped):
            horizontal, vertical = lines[0][row], lines[1][col]
            supported = horizontal is not None and vertical is not None
            internal = supported and horizontal['span'][0] <= x <= horizontal['span'][1] and vertical['span'][0] <= y <= vertical['span'][1]
            result['intersections'][row * 19 + col]['geometryMode'] = 'interpolated' if internal else 'extrapolated'
            cv2.circle(overlay, (round(x), round(y)), 3, (0, 180, 0) if internal else (0, 130, 255), 1)
    return result, overlay, clipped

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image', type=Path, required=True)
    parser.add_argument('--metadata', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    image = cv2.imread(str(args.image))
    if image is None:
        raise ValueError('Cannot read input image')
    metadata = json.loads(args.metadata.read_text())
    h = calibration_h(metadata, image.shape[1], image.shape[0])
    result, overlay, clipped = analyze(image, h)
    result['source'] = {'image': str(args.image), 'metadata': str(args.metadata),
                        'imageSha256': hashlib.sha256(args.image.read_bytes()).hexdigest(),
                        'metadataSha256': hashlib.sha256(args.metadata.read_bytes()).hexdigest()}
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    cv2.imwrite(str(args.output / 'diagnostic.png'), overlay)
    cv2.imwrite(str(args.output / 'clipped-pixels.png'), clipped * 255)
    print(json.dumps({k: v for k, v in result.items() if k not in ['lines', 'intersections', 'source']}))

if __name__ == '__main__':
    main()
