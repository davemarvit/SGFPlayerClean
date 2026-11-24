#!/usr/bin/env python3
"""Bounded same-view diagnostic for the two Nov23 moved-stone episodes.

Frozen estimator and coefficients are read, never changed. This is not a runtime
registration gate or blind stone detector. Current metadata remains untouched.
"""
import argparse,json
from pathlib import Path
import cv2
import numpy as np
from estimate import POINTS,rectify,body_measurements,grid_evidence,sha


def pixel_matrix(calibration,width=1920,height=1080):
    return np.diag([width-1,height-1,1])@np.r_[calibration['h'],1].reshape(3,3)@np.diag([1/18,1/18,1])


def mapped(matrix,point):
    value=matrix@np.r_[point,1.]
    return value[:2]/value[2]


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('calibration_root',type=Path);parser.add_argument('output',type=Path)
    args=parser.parse_args();cv2.setNumThreads(1);base=args.calibration_root
    reference_path=base/'offline-body-study-02/black/results.json';reference=json.loads(reference_path.read_text())
    frozen_h=pixel_matrix(reference['currentCalibration']);results=[]
    for color in ['black','white']:
        capture=base/(color+'-midpoint-01');samples_path=capture/'samples.json';samples=json.loads(samples_path.read_text())
        model_path=base/'offline-body-study-02'/color/'results.json';model=json.loads(model_path.read_text())
        if model['currentCalibration']!=reference['currentCalibration']:raise ValueError('Training grids differ')
        rows=[];registrations=[];movement=[]
        for index,sample in enumerate(samples['samples']):
            image_path=capture/sample['image'];metadata_path=capture/sample['metadata'];metadata=json.loads(metadata_path.read_text())
            if sha(image_path)!=sample['sha256']:raise ValueError('Image hash mismatch')
            if (metadata['cameraID']!=reference['cameraID'] or metadata['frame']['streamEpoch']!=reference['streamEpoch']
                or metadata['width']!=1920 or metadata['height']!=1080 or metadata.get('handObstructed') is not False or metadata.get('alignmentValid') is not True):
                raise ValueError('Incompatible or inadmissible capture')
            image=cv2.imread(str(image_path));current_h=pixel_matrix(metadata['currentCalibration'])
            # Seven unchanged printed crossings independently check this view;
            # exclude the experimentally moved point and do not fit a new field.
            if index in [0,len(samples['samples'])-1]:
                differences=[]
                for point in POINTS:
                    if point==(15,9):continue
                    patch,x,y=rectify(image,metadata,point);ink=grid_evidence(patch,x,y)
                    if not all(axis['usable'] for axis in ink):raise ValueError('Cannot establish seven-crossing compatibility')
                    old=next(a for a in reference['aggregated'] if a['point']==list(point))
                    fresh_pixel=mapped(current_h,np.array(point)+[axis['offset'] for axis in ink])
                    old_pixel=mapped(frozen_h,np.array(point)+old['printedGridOffset'])
                    differences.append(dict(point=list(point),freshMinusPriorPixels=(fresh_pixel-old_pixel).tolist()))
                delta=np.array([d['freshMinusPriorPixels'] for d in differences]);translation=np.median(delta,axis=0)
                registrations.append(dict(frameID=metadata['frame']['frameID'],crossings=differences,medianShiftPixels=translation.tolist(),
                                          maximumDisplacementPixels=float(max(np.linalg.norm(delta,axis=1))),
                                          maximumResidualAfterMedianShiftPixels=float(max(np.linalg.norm(delta-translation,axis=1)))))
            if color=='black' and index==0:
                for point in POINTS:
                    patch,x,y=rectify(image,metadata,point);bodies=body_measurements(patch,x,y,'black')
                    centers=[b['centerOffset'] for b in bodies if 'centerOffset' in b]
                    if not centers:raise ValueError('Cannot verify which Black moved')
                    center=np.array(point)+np.median(centers,axis=0)
                    frozen=mapped(np.linalg.inv(frozen_h),mapped(current_h,center))
                    old=next(a for a in reference['aggregated'] if a['point']==list(point))
                    movement.append(dict(point=list(point),bodyInFrozenGrid=frozen.tolist(),changeFromCenteredPass=(frozen-np.array(point)-old['bodyCenterOffset']).tolist()))
            search=np.array([14.5,9.]);patch,x,y=rectify(image,metadata,search);bodies=body_measurements(patch,x,y,color)
            available=[b for b in bodies if 'centerOffset' in b]
            if len(available)<2:raise ValueError('Frozen masks cannot support this body; no tuning permitted')
            body=search+np.median([b['centerOffset'] for b in available],axis=0)
            body_pixel=mapped(current_h,body)
            frozen=mapped(np.linalg.inv(frozen_h),body_pixel)
            comparisons={}
            for mode in ['currentGrid','refinedPrintedGrid']:
                fit=model['conditionalFits'][mode];apparent=frozen
                if mode=='refinedPrintedGrid':
                    path=Path(model['refinedGridAudit']['source'])
                    if sha(path)!=model['refinedGridAudit']['sha256']:raise ValueError('Refined G changed')
                    apparent=mapped(np.linalg.inv(np.array(json.loads(path.read_text())['board_to_image'])),body_pixel)
                k=fit['k'];camera=np.array(fit['geometry']['cameraGrid']);inferred=(apparent+k*camera)/(1+k)
                comparisons[mode]=dict(kFrozen=k,conditionalContact=inferred.tolist(),distancesToCol14And15=[float(np.linalg.norm(inferred-point)) for point in [np.array([14.,9.]),np.array([15.,9.])]])
            rows.append(dict(frameID=metadata['frame']['frameID'],image=str(image_path),imageSHA256=sha(image_path),metadata=str(metadata_path),metadataSHA256=sha(metadata_path),
                             currentCalibration=metadata['currentCalibration'],bodySamples=bodies,bodyPixel=body_pixel.tolist(),bodyInCurrentGrid=body.tolist(),bodyInFrozenGrid=frozen.tolist(),
                             calibrationDeltaPixelsAtTarget=(mapped(current_h,search)-mapped(frozen_h,search)).tolist(),comparisons=comparisons))
        # Descriptive summaries; repeated images are one episode, not eight tests.
        summaries={}
        for mode in ['currentGrid','refinedPrintedGrid']:
            contact=np.array([r['comparisons'][mode]['conditionalContact'] for r in rows]);distance=np.array([r['comparisons'][mode]['distancesToCol14And15'] for r in rows])
            summaries[mode]=dict(medianContact=np.median(contact,axis=0).tolist(),coordinateRange=np.c_[contact.min(axis=0),contact.max(axis=0)].tolist(),
                                 medianDistancesToCol14And15=np.median(distance,axis=0).tolist(),distanceRanges=np.c_[distance.min(axis=0),distance.max(axis=0)].tolist())
        results.append(dict(color=color,modelReport=str(model_path),modelSHA256=sha(model_path),sampleManifest=str(samples_path),sampleManifestSHA256=sha(samples_path),
                            registration=registrations,verifiedBlackMovement=movement,frames=rows,summary=summaries))
    output=dict(status='offlineSameViewDiagnosticOnly',cases=results,sourceSHA256=sha(Path(__file__)),frozenMeasurementSourceSHA256=sha(Path(__file__).with_name('estimate.py')),
                limitations=['Actual moved point is(15,9), toward col14; original front-middle instruction was ambiguous. Original raw metadata is preserved.',
                             'These are new negative placement episodes at a prior training location, not held-out locations or independent setups.',
                             'Seven exposed crossings on first/last frames establish subpixel same-view consistency; no live registration gate or new grid is activated.',
                             'No translation is applied to body pixels. The measured common image shift and residual are retained as uncertainty.',
                             'Body pixels are mapped explicitly from current H through raw image coordinates into frozen H/G; model coefficients are unchanged.',
                             'Approximate nominal midpoint is not asserted as measured physical ground truth; conditional optical estimates and actual movement are reported.',
                             'Original evaluator exact-grid guard remains intact; this explicit diagnostic does not change or bypass runtime admission.',
                             'No score threshold tuning, contour-mask tuning, new height fitting, learning, profile activation, camera or hardware operations.'])
    with args.output.open('x') as stream:json.dump(output,stream,indent=2,allow_nan=False);stream.write('\n')
    print(json.dumps([{k:c[k] for k in ['color','summary']} for c in results],indent=2))

if __name__=='__main__':main()
