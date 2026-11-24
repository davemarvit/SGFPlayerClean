#!/usr/bin/env python3
"""One-frame optical-center diagnostic, never a gameplay classifier.

The cyan mask is selected for these two visible White stones. It is not a
transferable white detector, clearance check, or estimate of board-contact center.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path
import cv2
import numpy as np


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('recording', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    cv2.setNumThreads(1)
    records = [json.loads(line) for line in (args.recording / 'events.jsonl').open()]
    frame = next(row for row in records if row.get('event') == 'frame' and row.get('frameID') == 697)
    analysis = next(row for row in records if row.get('event') == 'operation finished' and row.get('frameID') == 697)
    image_path = args.recording / frame['image']
    image = cv2.imread(str(image_path))
    height, width = image.shape[:2]
    transform = np.r_[frame['calibration']['h'], 1].reshape(3, 3)
    size = frame['boardSize']

    def project(grid):
        points = np.c_[np.asarray(grid) / (size-1), np.ones(len(grid))]
        projected = (transform @ points.T).T
        # Match GrayFrame's normalized point -> image-pixel convention.
        return projected[:, :2] / projected[:, 2:] * [width-1, height-1]

    report = dict(cameraID=frame['cameraID'], frameID=697, captureUptime=frame['captureUptime'],
                  image=str(image_path), image_sha256=digest(image_path),
                  events=str(args.recording/'events.jsonl'), events_sha256=digest(args.recording/'events.jsonl'),
                  calibration=frame['calibration'], script_sha256=digest(Path(__file__)),
                  opencv=cv2.__version__, numpy=np.__version__, measurements=[])
    for name, row in [('legitimate', 9), ('midway', 14)]:
        col = 9
        fit = next(f for f in analysis['footprints'] if f['col'] == col and f['row'] == row)
        fit_center = np.array([fit['center']['x'], fit['center']['y']])
        y, x = np.mgrid[:400, :400] / 200 - 1
        grid = np.stack([x+col, y+row], axis=-1)
        pixels = project(grid.reshape(-1, 2)).reshape(400, 400, 2).astype('float32')
        patch = cv2.remap(image, pixels[:, :, 0], pixels[:, :, 1], cv2.INTER_LINEAR)
        cv2.imwrite(str(args.output/(name+'-raw.png')), patch)
        b, g, r = cv2.split(patch.astype('float32'))
        rows = []
        for threshold in [15, 20, 25, 30]:
            mask = ((b-r > threshold) & (b > 145) & (g-r > 10)).astype('uint8')
            contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
            contour = max(contours, key=cv2.contourArea)
            moments = cv2.moments(contour)
            centroid = np.array([moments['m10']/moments['m00'], moments['m01']/moments['m00']])/200-1+[col,row]
            ellipse = cv2.fitEllipse(contour)
            ellipse_center = np.asarray(ellipse[0])/200-1+[col,row]
            rows.append(dict(blueMinusRedThreshold=threshold, bodyCentroidGrid=centroid.tolist(),
                             bodyCentroidPixel=project([centroid])[0].tolist(),
                             ellipseCenterGrid=ellipse_center.tolist(), ellipsePrincipalRadiiGrid=(np.asarray(ellipse[1])/400).tolist(),
                             fittedMinusBodyCenterGrid=(fit_center-centroid).tolist(),
                             fittedMinusBodyCenterPixel=(project([fit_center])[0]-project([centroid])[0]).tolist()))
        selected = rows[1]
        overlay = patch.copy()
        for offset in [-1, 0, 1]:
            cv2.line(overlay,(0,int((offset+1)*200)),(399,int((offset+1)*200)),(0,0,255),1)
        cv2.line(overlay,(200,0),(200,399),(0,0,255),1)
        fit_patch = np.rint((fit_center-[col,row]+1)*200).astype(int)
        body_patch = np.rint((np.asarray(selected['bodyCentroidGrid'])-[col,row]+1)*200).astype(int)
        cv2.circle(overlay,tuple(fit_patch),5,(0,255,0),-1)
        cv2.drawMarker(overlay,tuple(body_patch),(255,0,0),cv2.MARKER_CROSS,14,2)
        cv2.imwrite(str(args.output/(name+'-overlay.png')),overlay)
        report['measurements'].append(dict(name=name, point=row*size+col, productionFit=fit,
                                          productionFitPixel=project([fit_center])[0].tolist(), thresholdSweep=rows))
    tools_folder = Path(__file__).resolve().parents[2] / 'Tools'
    sys.path.insert(0, str(tools_folder))
    from parallax_lab import camera_geometry
    hypotheses = [dict(principalFraction=[cx, cy], geometry=camera_geometry(frame['calibration'], width, height, (cx, cy)))
                  for cx in [.49, .495, .5, .505, .51] for cy in [.49, .495, .5, .505, .51]]
    camera_report = dict(purpose='Reuse prior camera_geometry without fitting a height field or changing assignment',
                         parallax_lab_sha256=digest(tools_folder/'parallax_lab.py'), image_sha256=digest(image_path),
                         hypotheses=hypotheses, admissible=sum(h['geometry'] is not None for h in hypotheses),
                         heightFieldFit=None, reason='Four visible stones; evaluated candidate must be excluded; existing fit needs six well-spread established anchors.')
    (args.output/'camera-hypotheses.json').write_text(json.dumps(camera_report, indent=2)+'\n')
    report['limits'] = [
        'Single retained frame; diagnostic thresholds selected after viewing these pixels, not an independently validated estimator.',
        'Measures visible cyan/white body, not physical board-contact center or true stone placement.',
        'Contour threshold sweep estimates sensitivity to this mask only, not a statistical confidence interval.',
        'Exact native White-vote mask and disk objective not replayed here; mechanism attribution remains partial.',
        'Red cross is nominal assigned grid point; green dot is saved production fit; blue cross is contour centroid at threshold20.',
        'Current grid and source image are retained, not recalibrated or fitted to these stone centers.',
    ]
    (args.output/'measurements.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps([{k:v for k,v in row.items() if k!='thresholdSweep'} | {'threshold20':row['thresholdSweep'][1]}
                      for row in report['measurements']],indent=2))

if __name__ == '__main__':
    main()
