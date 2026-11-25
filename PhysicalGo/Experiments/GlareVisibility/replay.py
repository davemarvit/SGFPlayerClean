#!/usr/bin/env python3
"""Read retained camera evidence; write diagnostics to a new output directory."""
import argparse
import hashlib
import json
from pathlib import Path
import cv2
from probe import analyze, calibration_h

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--evidence-root', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=True)
passive = a.evidence_root / 'work/feedback-play-release-20261124/freshness-investigation/passive-motion'
occupied = a.evidence_root / 'work/ai-laser-integration/laser-position-recovery-20261123/calibration-acceptance-redesign/geometry-source/Camera checks/App bridge 2026-11-21/occupied move88 reference'
fixtures = Path(__file__).resolve().parents[2] / 'Tests/Fixtures/AIWhiteD7Glare'
samples = [(f'passive-{name}', passive / f'{name}-broker.png', json.loads((passive / f'{name}-metadata.json').read_text())) for name in ['anchor', 'worst']]
samples.append(('occupied-move88', occupied / 'view.png', json.loads((occupied / 'setup.json').read_text())))
samples += [(f'd7-{s["image"][:-4]}', fixtures / s['image'], s) for s in json.loads((fixtures / 'cases.json').read_text())]
summary = []
for name, image_path, metadata in samples:
    image = cv2.imread(str(image_path))
    h = calibration_h(metadata, image.shape[1], image.shape[0])
    result, overlay, clipped = analyze(image, h)
    result['source'] = {'image': str(image_path), 'sha256': hashlib.sha256(image_path.read_bytes()).hexdigest(), 'metadata': metadata}
    folder = a.output / name
    folder.mkdir(exist_ok=True)
    (folder / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    cv2.imwrite(str(folder / 'diagnostic.png'), overlay)
    cv2.imwrite(str(folder / 'clipped-pixels.png'), clipped * 255)
    summary.append({'name': name, **{k: result.get(k) for k in ['geometrySupported', 'supportedRailCounts', 'clippedFraction', 'p95PriorDisplacementGridUnits', 'maxPriorDisplacementGridUnits']}, 'imageSha256': result['source']['sha256']})
receipt = {'nativeBase': 'c53ac0502e920fda5a3ac5b50cba1ec330fdc051', 'opencv': cv2.__version__, 'probeSha256': hashlib.sha256(Path(__file__).with_name('probe.py').read_bytes()).hexdigest(), 'diagnosticOnly': True, 'samples': summary}
(a.output / 'summary.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps(receipt, indent=2))
