#!/usr/bin/env python3
"""Explain exact native votes; counterfactual scores do not change production."""
import argparse,hashlib,json,math
from pathlib import Path
import cv2
import numpy as np


def disk_offsets(rx,ry,step=.04):
    result=[]
    for y in range(-int(ry/step),int(ry/step)+1):
        x=int(rx/step*math.sqrt(max(0,1-(y*step/ry)**2)))
        result.extend((xx,y) for xx in range(-x,x+1))
    return np.array(result,int)


def score(votes,center,rx,aspect):
    def total(radius):
        offsets=disk_offsets(radius,radius*aspect)+center
        return float(votes[offsets[:,1],offsets[:,0]].sum()),len(offsets)
    body,count=total(rx);inner,inner_count=total(rx+.06);outer,outer_count=total(rx+.15)
    inside=body/count;ring=(outer-inner)/(outer_count-inner_count)
    return dict(score=inside-.7*ring,insideFraction=inside,ringFraction=ring,bodySamples=count)


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('trace',type=Path);p.add_argument('body_measurements',type=Path);args=p.parse_args();cv2.setNumThreads(1)
    replay=json.loads((args.trace/'native-replay.json').read_text())
    assert replay['savedFootprints']==replay['replayedFootprints'],'Native trace changed or failed to reproduce saved fits'
    bodies=json.loads(args.body_measurements.read_text());summaries=[]
    for path in sorted(args.trace.glob('point-*-call-*.json')):
        data=json.loads(path.read_text());cells=np.array(data['cells']);votes=cells[:,6].reshape(65,65)
        assert len(cells)==4225 and not data['maskingCount'] and not data['occlusionCount']
        body=next(b for b in bodies['measurements'] if b['point']==data['point'])['thresholdSweep'][1]
        body_center=np.array(body['bodyCentroidGrid']);best=data['best'];nominal=np.array([best['col'],best['row']])
        fit_center=np.array([best['center']['x'],best['center']['y']]);index=np.rint((fit_center-nominal)/.04).astype(int)+32
        native_score=score(votes,index,best['radiusCol'],best['radiusRow']/best['radiusCol'])
        assert abs(native_score['score']-best['quality'])<1e-12
        quantized_body=np.rint((body_center-nominal)/.04).astype(int)+32
        small_recentered=score(votes,quantized_body,best['radiusCol'],best['radiusRow']/best['radiusCol'])
        full_body=score(votes,quantized_body,.46,1.06)
        # Conservative visible-body interior; excludes the uncertain rim.
        relative=cells[:,:2]-body_center
        core=(relative[:,0]/.38)**2+(relative[:,1]/.40)**2<=1
        halves={}
        for name,select in [('upper',core&(relative[:,1]<0)),('lower',core&(relative[:,1]>=0))]:
            rows=cells[select]
            halves[name]=dict(samples=len(rows),whiteVoteFraction=float(rows[:,6].mean()),
                              colorCriterionVotes=int(rows[:,4].sum()),brightnessCriterionVotes=int(rows[:,5].sum()),
                              medianCorrectedBrightnessDifference=float(np.median(rows[:,2]-rows[:,3]-data['correction'])),
                              medianCurrentColorMagnitude=float(np.median(rows[:,7])),medianExpectedWoodColorMagnitude=float(np.median(rows[:,8])))
        mask=cv2.cvtColor((votes*180).astype('uint8'),cv2.COLOR_GRAY2BGR)
        for select,bgr in [(core&(relative[:,1]<0),(0,160,0)),(core&(relative[:,1]>=0),(160,0,0))]:
            mask.reshape(-1,3)[select]+=np.array(bgr,dtype='uint8')//3
        mask=cv2.resize(mask,(520,520),interpolation=cv2.INTER_NEAREST)
        # Native lattice cell center maps to corresponding enlarged pixel center.
        def location(grid):return tuple(np.rint((((grid-nominal)/.04+32)+.5)*8).astype(int))
        cv2.drawMarker(mask,location(nominal),(0,0,255),cv2.MARKER_CROSS,18,1)
        cv2.circle(mask,location(fit_center),5,(0,255,0),-1)
        cv2.drawMarker(mask,location(body_center),(255,255,0),cv2.MARKER_CROSS,18,2)
        image_name=path.stem+'-diagnostic.png';cv2.imwrite(str(args.trace/image_name),mask)
        summaries.append(dict(point=data['point'],trace=str(path),trace_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                              nativeFit=best,bodyCenter=body_center.tolist(),nativeScore=native_score,
                              sameSmallDiskAtBodyCenter=small_recentered,largerBodyDiskAtBodyCenter=full_body,
                              visibleCore=halves,diagnosticImage=str(args.trace/image_name)))
    output=dict(nativeArchivedFootprintsExactlyReproduced=True,objectiveScoresExactlyReproduced=True,
                bodyMeasurementSource=str(args.body_measurements),bodyMeasurementSHA256=hashlib.sha256(args.body_measurements.read_bytes()).hexdigest(),
                analysisSourceSHA256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),cases=summaries,
                limits=['Two White stones in one frame; no general classifier validation.',
                        'Upper/lower masks use a conservative ellipse around the independently measured visible-body center, not a board-contact estimate.',
                        'Larger-body score uses radius.46/aspect1.06 as a diagnostic counterfactual, not an optimized replacement.',
                        'No threshold, live model, camera, laser, grid or game state changed.'])
    (args.trace/'explanation.json').write_text(json.dumps(output,indent=2,allow_nan=False)+'\n')
    print(json.dumps(output,indent=2))

if __name__=='__main__':main()
