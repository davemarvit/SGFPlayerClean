#!/usr/bin/env python3
"""Measure declared diagnostic stones against a frozen centered-anchor model.

Manifest searchCenter only selects a crop; tested intersections are never labels
for fitting a height. This script does not detect moves or update any model.
"""
import argparse
import json
from pathlib import Path
import cv2
import numpy as np
from estimate import rectify,body_measurements,sha


def metadata_for(case):
    if 'metadataFile' in case:
        path=Path(case['metadataFile']);return json.loads(path.read_text()),dict(path=str(path),sha256=sha(path))
    path=Path(case['eventsFile'])
    value=None
    for line in path.open():
        candidate=json.loads(line)
        if candidate.get("event")=="frame" and candidate.get("frameID")==case["frameID"]:
            value=candidate;break
    if value is None:raise ValueError("Retained frame metadata not found")
    return dict(currentCalibration=value['calibration'],cameraID=value['cameraID'],width=value['width'],height=value['height'],frame=dict(frameID=value['frameID']),recordedFrameEvent=value),dict(path=str(path),sha256=sha(path),frameID=case['frameID'])


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('model_report',type=Path);p.add_argument('manifest',type=Path);p.add_argument('output',type=Path)
    args=p.parse_args();cv2.setNumThreads(1)
    report=json.loads(args.model_report.read_text());manifest=json.loads(args.manifest.read_text());results=[]
    if manifest.get('includeForTraining') is not False:raise ValueError('Challenge must explicitly be excluded from training')
    for case in manifest['cases']:
        metadata,provenance=metadata_for(case)
        if metadata['cameraID']!=report['cameraID'] or metadata['currentCalibration']!=report['currentCalibration']:
            raise ValueError('Challenge camera/grid differs from frozen study; require separately reviewed registration')
        image_path=Path(case['image']);image=cv2.imread(str(image_path));center=np.array(case['searchCenter'],float)
        patch,x,y=rectify(image,metadata,center)
        bodies=body_measurements(patch,x,y,report['color'])
        available=[b for b in bodies if 'centerOffset' in b]
        row=dict(caseID=case['id'],image=str(image_path),image_sha256=sha(image_path),metadata=provenance,
                 searchCenter=center.tolist(),declaredContact=case.get('declaredContact'),bodies=bodies,decisions={},
                 measurementOnly=True,modelUpdated=False)
        if len(available)<2:
            row['abstentionReason']='Insufficient body-mask support';results.append(row);continue
        body=center+np.median([b['centerOffset'] for b in available],axis=0)
        row['bodyCenterInNativeGrid']=body.tolist()
        for mode,fit in report['conditionalFits'].items():
            if fit is None:continue
            if mode=='localPrintedGrid':
                row['decisions'][mode]=dict(abstentionReason='A displaced stone occludes different grid arms; no fresh local-ink correction inferred from the old centered frame.')
                continue
            apparent=body.copy()
            if mode=='refinedPrintedGrid':
                grid=json.loads(Path(report['refinedGridAudit']['source']).read_text())
                if sha(Path(report['refinedGridAudit']['source']))!=report['refinedGridAudit']['sha256']:raise ValueError('Refined grid source changed')
                native=np.diag([metadata['width']-1,metadata['height']-1,1])@np.r_[metadata['currentCalibration']['h'],1].reshape(3,3)
                pixel=native@np.r_[body/18,1];pixel=pixel/pixel[2]
                transformed=np.linalg.inv(np.array(grid['board_to_image']))@pixel
                apparent=transformed[:2]/transformed[2]
            k=fit['k'];camera=np.asarray(fit['geometry']['cameraGrid'])
            inferred=(apparent+k*camera)/(1+k)
            candidates=[]
            for point in case['testedIntersections']:
                point=np.array(point,float)
                residual=apparent-point-k*(point-camera)
                candidates.append(dict(point=point.tolist(),apparentResidual=residual.tolist(),apparentResidualNorm=float(np.linalg.norm(residual)),
                                       inferredContactResidual=(inferred-point).tolist(),inferredContactDistance=float(np.linalg.norm(inferred-point))))
            row['decisions'][mode]=dict(conditionalInferredContact=inferred.tolist(),candidateComparisons=candidates,
                                       status='diagnostic comparison, not runtime acceptance or calibrated confidence')
        results.append(row)
    payload=dict(status='offlineChallengeOnly',color=report['color'],manifest=str(args.manifest),manifest_sha256=sha(args.manifest),
                 modelReport=str(args.model_report),model_sha256=sha(args.model_report),evaluator_sha256=sha(Path(__file__)),measurement_source_sha256=sha(Path(__file__).with_name('estimate.py')),
                 cases=results,limits=['No new anchors learned, no height refit, no move or clock authority.',
                                      'Crops are selected by a declared test plan; this is not blind end-to-end stone detection.',
                                      'Repeated frames of one placement are one episode, not independent successes.',
                                      'Uses the frozen setup model; camera ID/grid equality alone is not live registration proof.',
                                      'Existing White pair informed the diagnostic estimator, so its evaluation is a development negative control, not untouched holdout.'])
    with args.output.open('x') as stream:json.dump(payload,stream,indent=2,allow_nan=False);stream.write('\n')
    print(json.dumps([dict(caseID=r['caseID'],body=r.get('bodyCenterInNativeGrid'),decisions=r['decisions']) for r in results],indent=2))

if __name__=='__main__':main()
