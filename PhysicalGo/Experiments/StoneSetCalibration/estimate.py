#!/usr/bin/env python3
"""Offline confirmed-anchor optical-height study. No app/laser/runtime writes."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import cv2
import numpy as np

TOOLS = Path(__file__).resolve().parents[2] / 'Tools'
sys.path.insert(0, str(TOOLS))
from parallax_lab import camera_geometry

POINTS = [(3,3),(9,3),(15,3),(3,9),(15,9),(3,15),(9,15),(15,15)]
HELD_OUT = {(9,3),(9,15)}
SCALE = 160
EXTENT = 1.2


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rectify(image, metadata, point):
    axis = np.arange(int(2*EXTENT*SCALE))/SCALE-EXTENT
    y,x = np.meshgrid(axis,axis,indexing='ij')
    h = np.r_[metadata['currentCalibration']['h'],1].reshape(3,3)
    grid = np.array([((x+point[0])/18).ravel(),((y+point[1])/18).ravel(),np.ones(x.size)])
    p = h@grid
    p = p[:2]/p[2]
    patch = cv2.remap(image,(p[0]*(image.shape[1]-1)).reshape(x.shape).astype('float32'),
                      (p[1]*(image.shape[0]-1)).reshape(x.shape).astype('float32'),cv2.INTER_LINEAR)
    return patch,x,y


def grid_evidence(patch,x,y):
    gray = cv2.cvtColor(patch,cv2.COLOR_BGR2GRAY).astype(float)/255
    axes=[]
    for axis in [0,1]:
        variable = x if axis==0 else y
        other = y if axis==0 else x
        side_estimates=[]
        for side in [-1,1]:
            offsets=np.arange(-24,25)/SCALE
            values=[]
            for offset in offsets:
                mask=(abs(variable-offset)<.003)&(side*other>.72)&(side*other<1.12)
                values.append(float(np.median(gray[mask])))
            values=np.array(values)
            smooth=np.convolve(np.pad(values,2,mode='edge'),np.ones(5)/5,mode='valid')
            index=int(np.argmin(smooth))
            contrast=float(np.median(smooth)-smooth[index])
            side_estimates.append(dict(offset=float(offsets[index]),contrast=contrast))
        offsets=[s['offset'] for s in side_estimates]
        axes.append(dict(offset=float(np.mean(offsets)),sideAgreement=abs(offsets[0]-offsets[1]),sides=side_estimates,
                         usable=min(s['contrast'] for s in side_estimates)>.025 and abs(offsets[0]-offsets[1])<.075))
    return axes


def body_measurements(patch,x,y,color):
    b,g,r=cv2.split(patch.astype('float32'))
    gray=cv2.cvtColor(patch,cv2.COLOR_BGR2GRAY).astype(float)
    wood=float(np.median(gray[(x*x+y*y>.85**2)&(x*x+y*y<1.1**2)]))
    rows=[]
    parameters=[15,20,25,30] if color=='white' else [.35,.4,.45,.5]
    for threshold in parameters:
        if color=='white':
            mask=((b-r>threshold)&(b>145)&(g-r>10)).astype('uint8')
        else:
            mask=(gray<wood*threshold).astype('uint8')
            # Remove thin printed rails before taking an external body contour.
            kernel=cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(13,13))
            mask=cv2.morphologyEx(mask,cv2.MORPH_OPEN,kernel)
        contours,_=cv2.findContours(mask,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_NONE)
        candidates=[]
        for contour in contours:
            area=cv2.contourArea(contour)/SCALE**2
            if len(contour)<5 or not .3<area<1.1:continue
            moment=cv2.moments(contour)
            center=np.array([moment['m10']/moment['m00'],moment['m01']/moment['m00']])/SCALE-EXTENT
            if max(abs(center))>.55:continue
            ellipse=cv2.fitEllipse(contour)
            hull=cv2.convexHull(contour)
            if cv2.contourArea(hull)<=0:continue
            solidity=cv2.contourArea(contour)/cv2.contourArea(hull)
            radii=np.asarray(ellipse[1])/(2*SCALE)
            candidates.append(dict(parameter=threshold,centerOffset=center.tolist(),ellipseCenterOffset=(np.array(ellipse[0])/SCALE-EXTENT).tolist(),
                                   principalRadii=radii.tolist(),area=area,solidity=float(solidity)))
        rows.append(max(candidates,key=lambda c:c['area']) if candidates else dict(parameter=threshold,unavailable='no bounded visible-body component'))
    return rows


def fit_confirmed(points,centers,geometry):
    """Explicit labeled-anchor adapter; no fake native confidences/footprints.

    Reuses the old constrained scalar relation and robust weights. Centers are
    diagnostic body contours, so this is a different measurement provenance.
    """
    if len(points)<6:return None
    p=np.asarray(points,float);a=np.asarray(centers,float)
    if np.any(np.ptp(p,axis=0)<4) or np.linalg.svd(p-p.mean(axis=0),compute_uv=False)[-1]<2:return None
    direction=p-geometry['cameraGrid'];delta=a-p;weights=np.ones(len(p));k=0.
    for _ in range(8):
        denominator=float(np.sum(weights[:,None]*direction**2))
        if denominator<=0:return None
        unconstrained=float(np.sum(weights[:,None]*direction*delta)/denominator)
        k=float(np.clip(unconstrained,0,.04))
        residual=delta-k*direction
        weights=np.minimum(1,.1/np.maximum(np.linalg.norm(residual,axis=1),1e-8))
    return dict(k=k,unconstrainedK=unconstrained,effectiveHeightRowPitches=float(geometry['heightRowPitches']*k/(1+k)),
                medianResidual=float(np.median(np.linalg.norm(residual,axis=1))),maxResidual=float(np.max(np.linalg.norm(residual,axis=1))),
                residualVectors=residual.tolist(),fitPoints=[list(p) for p in points],atConstraintBoundary=k in (0.,.04))


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('capture',type=Path);parser.add_argument('output',type=Path);parser.add_argument('--refined-setup',type=Path)
    args=parser.parse_args();cv2.setNumThreads(1)
    args.output.mkdir(parents=True,exist_ok=False)
    samples=json.loads((args.capture/'samples.json').read_text());color=samples['color']
    if samples.get('userConfirmedCentered') is not True or samples['expectedColRow']!=[list(p) for p in POINTS] or color not in ('white','black'):
        raise ValueError('Require exactly the user-confirmed eight-point pattern')
    measurements=[];sources=[];context=None;first_patches={};metadata0=None
    for sample in samples['samples']:
        image_path=args.capture/sample['image'];metadata_path=args.capture/sample['metadata']
        if sha(image_path)!=sample['sha256']:raise ValueError('Capture hash mismatch')
        metadata=json.loads(metadata_path.read_text());image=cv2.imread(str(image_path))
        signature=(metadata['cameraID'],metadata['frame']['streamEpoch'],metadata['width'],metadata['height'],json.dumps(metadata['currentCalibration'],sort_keys=True))
        if context is not None and signature!=context:raise ValueError('Mixed camera/geometry/epoch; do not pool')
        if metadata.get('handObstructed') is not False or metadata.get('alignmentValid') is not True:raise ValueError('Capture admission flags not clear')
        context=signature;metadata0=metadata0 or metadata
        sources.append(dict(image=str(image_path),image_sha256=sha(image_path),metadata=str(metadata_path),metadata_sha256=sha(metadata_path),frame=metadata['frame']))
        for point in POINTS:
            patch,x,y=rectify(image,metadata,point)
            bodies=body_measurements(patch,x,y,color)
            grid=grid_evidence(patch,x,y)
            measurements.append(dict(frameID=metadata['frame']['frameID'],point=list(point),bodies=bodies,grid=grid))
            if point not in first_patches:first_patches[point]=patch
    aggregated=[]
    for point in POINTS:
        selected=[m for m in measurements if m['point']==list(point)]
        body=[b['centerOffset'] for m in selected for b in m['bodies'] if 'centerOffset' in b]
        grid=[ [axis['offset'] for axis in m['grid']] for m in selected if all(axis['usable'] for axis in m['grid'])]
        if not body or not grid:
            aggregated.append(dict(point=list(point),supported=False,reason='body or exposed-grid evidence unavailable'));continue
        body=np.array(body);grid=np.array(grid);center=np.median(body,axis=0);ink=np.median(grid,axis=0)
        span=np.ptp(body,axis=0)
        complete_parameters=[parameter for parameter in [b['parameter'] for b in selected[0]['bodies']]
                             if all(any(b['parameter']==parameter and 'centerOffset' in b for b in m['bodies']) for m in selected)]
        aggregate=dict(point=list(point),supported=len(complete_parameters)>=2 and max(span)<.10 and len(grid)==len(selected),
                       completeMaskParameters=complete_parameters,allMaskParametersSupported=len(body)==len(selected)*4,
                       bodyObservations=len(body),gridObservations=len(grid),bodyCenterOffset=center.tolist(),bodyOffsetRange=np.c_[body.min(axis=0),body.max(axis=0)].tolist(),
                       bodyRangeAcrossFramesAndThresholds=span.tolist(),printedGridOffset=ink.tolist(),bodyMinusLocalPrintedGrid=(center-ink).tolist(),
                       heldOut=point in HELD_OUT)
        aggregated.append(aggregate)
        overlay=first_patches[point].copy();o=int(EXTENT*SCALE)
        cv2.line(overlay,(0,o),(overlay.shape[1]-1,o),(0,0,255),1);cv2.line(overlay,(o,0),(o,overlay.shape[0]-1),(0,0,255),1)
        for offset,bgr in [(ink,(0,255,255)),(center,(255,0,0))]:cv2.drawMarker(overlay,tuple(np.rint((offset+EXTENT)*SCALE).astype(int)),bgr,cv2.MARKER_CROSS,14,2)
        cv2.putText(overlay,f'{color} {point}',(8,20),cv2.FONT_HERSHEY_SIMPLEX,.45,(255,255,255),1)
        first_patches[point]=overlay
    tiles=[first_patches[p] for p in POINTS]
    cv2.imwrite(str(args.output/'anchors.png'),np.vstack([np.hstack(tiles[:4]),np.hstack(tiles[4:])]))
    geometry=camera_geometry(metadata0['currentCalibration'],metadata0['width'],metadata0['height'])
    if any("bodyCenterOffset" not in a or "printedGridOffset" not in a for a in aggregated):
        raise ValueError("Incomplete body/printed-grid evidence; preserve captures and inspect before fitting")
    fits={}; refined_report=None
    all_points=np.array([a['point'] for a in aggregated],float)
    modes={}
    for mode in ['currentGrid','localPrintedGrid']:
        centers=np.array([np.array(a['point'])+np.array(a['bodyCenterOffset'] if mode=='currentGrid' else a['bodyMinusLocalPrintedGrid']) for a in aggregated])
        modes[mode]=(centers,metadata0['currentCalibration'])
    if args.refined_setup:
        setup=json.loads(args.refined_setup.read_text())
        if setup['camera_id']!=metadata0['cameraID'] or setup['stream_epoch']!=metadata0['frame']['streamEpoch'] or setup['image_size']!=[metadata0['width'],metadata0['height']]:
            raise ValueError('Refined setup camera/epoch/dimensions mismatch')
        G=np.array(setup['board_to_image'],float)
        native=np.diag([metadata0['width']-1,metadata0['height']-1,1])@np.r_[metadata0['currentCalibration']['h'],1].reshape(3,3)@np.diag([1/18,1/18,1])
        def mapped(matrix,points):
            q=matrix@np.c_[points,np.ones(len(points))].T
            return (q[:2]/q[2]).T
        apparent_pixels=mapped(native,modes['currentGrid'][0])
        refined_centers=mapped(np.linalg.inv(G),apparent_pixels)
        local_ink=all_points+np.array([a['printedGridOffset'] for a in aggregated])
        ink_pixels=mapped(native,local_ink)
        disagreement=ink_pixels-mapped(G,all_points)
        translation=np.median(disagreement,axis=0)
        residuals=np.linalg.norm(disagreement-translation,axis=1)
        H=np.diag([1/(metadata0['width']-1),1/(metadata0['height']-1),1])@G@np.diag([18,18,1]);H=H/H[2,2]
        refined_calibration=dict(size=19,h=H.ravel()[:8].tolist())
        modes['refinedPrintedGrid']=(refined_centers,refined_calibration)
        refined_report=dict(source=str(args.refined_setup),sha256=sha(args.refined_setup),sourceID=setup['id'],
                            currentExposedInkMinusRefinedGridPixels=disagreement.tolist(),medianTranslationPixels=translation.tolist(),
                            residualAfterMedianTranslation=dict(median=float(np.median(residuals)),maximum=float(max(residuals))),
                            note='Diagnostic comparison of eight exposed-rail crossings; no live registration qualification or grid replacement. Refined G is NOT translated for height fitting.',
                            calibration=refined_calibration)
    for mode,(centers,calibration) in modes.items():
        geo=camera_geometry(calibration,metadata0['width'],metadata0['height'])
        train=[i for i,a in enumerate(aggregated) if a['supported'] and not a['heldOut']]
        fit=fit_confirmed(all_points[train].tolist(),centers[train],geo) if geo else None
        if fit:
            held=[]
            for i,a in enumerate(aggregated):
                if not a.get('supported') or not a['heldOut']:continue
                offset=centers[i]-all_points[i]
                predicted=fit['k']*(all_points[i]-geo['cameraGrid']);residual=offset-predicted
                held.append(dict(point=a['point'],observedOffset=offset.tolist(),predictedOffset=predicted.tolist(),residual=residual.tolist(),residualNorm=float(np.linalg.norm(residual)),beforeNorm=float(np.linalg.norm(offset))))
            fit['heldOut']=held;fit['geometry']=geo
            sensitivity=[]
            for cx in [.49,.495,.5,.505,.51]:
                for cy in [.49,.495,.5,.505,.51]:
                    variant_geo=camera_geometry(calibration,metadata0['width'],metadata0['height'],(cx,cy))
                    variant=fit_confirmed(all_points[train].tolist(),centers[train],variant_geo) if variant_geo else None
                    sensitivity.append(dict(principalFraction=[cx,cy],effectiveHeightRowPitches=None if variant is None else variant['effectiveHeightRowPitches'],medianResidual=None if variant is None else variant['medianResidual']))
            fit['principalPointSensitivity']=sensitivity
            fit['sensitivityMeaning']='Conditional principal-point perturbation only, not a statistical interval; estimator/grid/placement error remains separate.'
        fits[mode]=fit
    report=dict(status='offlineDiagnosticOnly',color=color,source=str(args.capture),sources=sources,samples_sha256=sha(args.capture/'samples.json'),
                estimator_sha256=sha(Path(__file__)),parallax_lab_sha256=sha(TOOLS/'parallax_lab.py'),
                currentCalibration=metadata0['currentCalibration'],cameraID=metadata0['cameraID'],streamEpoch=metadata0['frame']['streamEpoch'],
                geometryHypothesis=geometry,refinedGridAudit=refined_report,aggregated=aggregated,conditionalFits=fits,measurements=measurements,
                limits=['Eight frames are one static episode, not eight independent calibrations.','Mask/rail thresholds are exploratory scene-specific diagnostics; no statistical confidence claim.',
                        'Local-rail offsets diagnose printed-grid mismatch; they do not rewrite homography or identify hidden contact centers.',
                        'Effective height includes optical-estimator bias and assumed camera intrinsics; not physical thickness in millimeters.',
                        'Two-point spatial holdout shares setup/frame/stone set; independent setup validation and misplacement negatives remain required.',
                        'No runtime profile or binding is created or activated.'])
    (args.output/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(dict(color=color,aggregated=aggregated,conditionalFits=fits),indent=2))

if __name__=='__main__':main()
