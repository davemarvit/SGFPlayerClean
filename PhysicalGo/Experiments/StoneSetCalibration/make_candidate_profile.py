#!/usr/bin/env python3
"""Emit a standalone offline StoneSetProfile; never installs/selects a profile."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import uuid


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('white_report',type=Path);p.add_argument('black_report',type=Path);p.add_argument('output',type=Path)
    p.add_argument('--name',default='November 23 calibration set (offline)')
    args=p.parse_args()
    reports={color:json.loads(path.read_text()) for color,path in [('white',args.white_report),('black',args.black_report)]}
    if reports['white']['color']!='white' or reports['black']['color']!='black':raise ValueError('Color/report mismatch')
    white,black=reports['white'],reports['black']
    if (white['cameraID'],white['streamEpoch'],white['currentCalibration'])!=(black['cameraID'],black['streamEpoch'],black['currentCalibration']):
        raise ValueError('Different setup hypotheses must not silently become one profile')
    geometry_hash=hashlib.sha256(json.dumps(white['currentCalibration'],sort_keys=True).encode()).hexdigest()
    identity=uuid.uuid5(uuid.NAMESPACE_URL,white['samples_sha256']+'/'+black['samples_sha256'])
    date=datetime.fromtimestamp(max(s['frame']['capturedAtUnix'] for report in reports.values() for s in report['sources']),timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    profile=dict(schemaVersion=1,stoneSetID=str(identity),name=args.name,createdAt=date,updatedAt=date)
    for color,path in [('white',args.white_report),('black',args.black_report)]:
        report=reports[color];candidates=[]
        report_ref=str(path.resolve())+'#sha256='+digest(path)
        for mode,fit in report['conditionalFits'].items():
            if fit is None or fit['atConstraintBoundary'] or fit['effectiveHeightRowPitches']<=0:continue
            heights=[v['effectiveHeightRowPitches'] for v in fit['principalPointSensitivity'] if v['effectiveHeightRowPitches'] is not None]
            if len(fit['fitPoints'])<6 or len(fit['heldOut'])!=2 or len(heights)!=25:raise ValueError('Missing fit/heldout/sensitivity provenance')
            candidate=dict(candidateID=str(uuid.uuid5(identity,color+'/'+mode)),status='offlineCandidate',
                           value=fit['effectiveHeightRowPitches'],units='rowPitch',referenceBoardPitchID='unmeasured-board-spacing-'+geometry_hash[:16],
                           metricConversion=None,metricScaleSource=None,
                           measurementModelID='isolated-'+color+'-body-contour',measurementModelVersion='exploratory-v1',
                           setupModelID=report['cameraID']+'/'+report['streamEpoch']+'/'+geometry_hash[:16],
                           geometryHypothesisID=mode,
                           geometryAssumptions=['Pinhole model, square pixels, zero skew/distortion; principal point assumed near image center.',
                                                'Printed row/column axes orthogonal; board spacing in millimetres unknown.',
                                                'User confirmed these anchors centered; physical centering error remains unmeasured.',
                                                'Visible-body effective height depends on color-specific contour/rim/shadow estimator; not physical thickness.',
                                                'Geometry mode '+mode+' is preserved separately, not selected by best outcome.'],
                           confidence=dict(calibrationStatus='uncalibrated',sampleCount=len(fit['fitPoints']),
                                           description=f"Six fitted anchors; two held-out anchors; eight repeated frames in one static episode. Median fit residual {fit['medianResidual']:.4f} cells; maximum {fit['maxResidual']:.4f}. No calibrated correctness probability."),
                           uncertainty=dict(kind='sensitivityRange',lower=min(heights),upper=max(heights),
                                            description='Principal point +/-1% only across25 conditional hypotheses. Not a confidence interval; excludes contour bias, grid-choice differences, placement error and physical-thickness variation.'),
                           compatibility=dict(description='Same original board spacing and compatible contour/camera assumptions only. Physical pitch unknown: do not transfer rowPitch values to a different board without its spacing. Revalidate after camera/lighting/estimator changes.',
                                              independentSetupValidation='notPerformed',validationReportID=None),
                           heldOutReportID=report_ref,
                           captures=[dict(captureID=s['frame']['streamEpoch']+'/'+str(s['frame']['frameID']),imageSHA256=s['image_sha256'],metadataSHA256=s['metadata_sha256']) for s in report['sources']],
                           sourceCodeSHA256={'estimate.py':report['estimator_sha256'],'parallax_lab.py':report['parallax_lab_sha256'],'make_candidate_profile.py':digest(Path(__file__))})
            if not candidate['uncertainty']['lower']<=candidate['value']<=candidate['uncertainty']['upper']:raise ValueError('Sensitivity range omits central hypothesis')
            candidates.append(candidate)
        profile[color]=dict(physicalThicknessMm=None,opticalHeightCandidates=candidates)
    with args.output.open('x') as f:json.dump(profile,f,indent=2,allow_nan=False);f.write('\n')
    print(json.dumps(dict(profile=str(args.output),status='standalone offline candidate; not installed',candidates={c:len(profile[c]['opticalHeightCandidates']) for c in ['black','white']}),indent=2))

if __name__=='__main__':main()
