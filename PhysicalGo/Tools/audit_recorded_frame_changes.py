#!/usr/bin/env python3
"""Evaluate an explicitly supplied offline change-gate prototype on saved PNGs.

No camera, application, serial or user-state access. Results are scheduling
hints, never fresh clearance, occupancy or calibration/laser admission.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import statistics
import time

import cv2
import numpy as np


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prototype',type=Path,required=True)
    parser.add_argument('--recording',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():raise SystemExit('Refusing to overwrite an earlier report')
    spec=importlib.util.spec_from_file_location('change_gate',args.prototype)
    module=importlib.util.module_from_spec(spec)
    import sys
    sys.modules[spec.name]=module;spec.loader.exec_module(module)
    cv2.setNumThreads(1)
    records=[]
    for path in args.recording.glob('*.json'):
        metadata=json.loads(path.read_text())
        if not isinstance(metadata,dict) or 'frame' not in metadata or 'imageFile' not in metadata:continue
        filename=metadata['imageFile']
        if filename!=Path(filename).name:raise ValueError('Image must be a basename')
        records.append((metadata['frame']['capturedAtUptime'],path,metadata))
    records.sort(key=lambda row:row[0])
    if len(records)<2:raise ValueError('Need at least two saved image manifests')
    anchor=None;rows=[];durations=[];identities=set()
    for _,path,m in records:
        f=m['frame'];identity=(f['streamEpoch'],f['frameID'])
        if identity in identities:raise ValueError('Duplicate saved frame identity')
        identities.add(identity)
        image_path=args.recording/m['imageFile'];image=cv2.imread(str(image_path))
        if image is None or image.shape[:2]!=(m['height'],m['width']):raise ValueError('Missing or mismatched pixels')
        eligible=m.get('alignmentValid') is True and m.get('handObstructed') is False and m.get('currentCalibration') is not None
        row=dict(file=image_path.name,pngSHA256=digest(image_path),metadataSHA256=digest(path),
                 frameID=f['frameID'],recordedClearAligned=eligible)
        if not eligible:
            row.update(reason='recorded_evidence_ineligible',regionsRequested=361)
        else:
            scope=json.dumps([m['cameraID'],m['cameraContext'],f['streamEpoch'],m['width'],m['height']],sort_keys=True)
            began=time.perf_counter()
            current=module.describe(image,m['currentCalibration'],scope)
            result=module.changes(anchor,current)
            elapsed=1000*(time.perf_counter()-began);durations.append(elapsed)
            row.update(reason=result['reason'],regionsRequested=len(result['expanded']),rawRegions=len(result['raw']),milliseconds=elapsed)
            if anchor is None:anchor=current # Fixed first admitted anchor; never adapt to later pixels.
        rows.append(row)
    comparisons=[r['regionsRequested'] for r in rows if r['reason']=='pixel_change']
    report=dict(diagnosticOnly=True,runtimeIntegrated=False,grantsMotion=False,
        limitations=['Archived empty-board noise/geometry only; no new placement/removal sensitivity claim.',
                     'No automatic background update or reused occupancy/clearance evidence.',
                     'Timing includes sampling/descriptor/comparison; image decoding excluded; not native Swift speedup.'],
        prototype=dict(path=str(args.prototype.resolve()),sha256=digest(args.prototype)),
        toolSHA256=digest(Path(__file__)),recording=str(args.recording.resolve()),rows=rows,
        comparisons=len(comparisons),meanRegions=statistics.mean(comparisons) if comparisons else None,
        timing=dict(samples=len(durations),medianMs=statistics.median(durations) if durations else None,
                    p95Ms=float(np.quantile(durations,.95)) if durations else None))
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:report[k] for k in ['comparisons','meanRegions','timing','diagnosticOnly']}))


if __name__=='__main__':main()
