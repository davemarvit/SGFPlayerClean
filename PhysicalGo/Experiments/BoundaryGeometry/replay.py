#!/usr/bin/env python3
"""Replay frozen case selection, without calibration/profile/native changes."""
import argparse,hashlib,json,sys
from pathlib import Path
import cv2
import numpy as np
from boundary import measure
sys.path.insert(0,str(Path(__file__).resolve().parent.parent/'StoneSetCalibration'))
from estimate import rectify

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser();p.add_argument('output',type=Path);a=p.parse_args();a.output.mkdir(exist_ok=False,parents=True);cv2.setNumThreads(1)
 manifest=Path(__file__).with_name('cases.json');d=json.loads(manifest.read_text());rows=[];tiles=[]
 for source in d.get('auxiliaryProvenance',[]):
  if sha(Path(source['path']))!=source['sha256']:raise ValueError('Auxiliary source hash mismatch')
 for case in d['cases']:
  for source in ['image','metadata']:
   if sha(Path(case[source]['path']))!=case[source]['sha256']:raise ValueError('Frozen input hash mismatch: '+case['id'])
  im=cv2.imread(case['image']['path']);patch,x,y=rectify(im,{'currentCalibration':case['calibration']},case['seed'])
  evidence=measure(patch,np.array(case['seed']),case['neighborCenters'],case['visibility'],d['policy'],case['compactFit'],dict(caseID=case['id'],imageSHA256=case['image']['sha256'],setup=case['setup'],colorHypothesis=case['colorHypothesis']))
  row=dict(id=case['id'],label=case['label'],evidence=evidence.json());rows.append(row)
  tile=patch.copy();seed=np.array(case['seed'])
  for i in evidence.diagnostics.get('retainedDirections',[]):
   pt=np.array(evidence.diagnostics['edgePoints'][i]);cv2.circle(tile,tuple(np.rint((pt-seed+1.2)*160).astype(int)),2,(0,220,0),-1)
  if evidence.candidateOutline:
   o=evidence.candidateOutline;center=tuple(np.rint((np.array(o.center)-seed+1.2)*160).astype(int));radii=tuple(np.rint(np.array(o.principalRadii)*160).astype(int));cv2.ellipse(tile,center,radii,o.angleDegrees,0,360,(0,200,255),1);cv2.drawMarker(tile,center,(0,0,255),cv2.MARKER_CROSS,10,1)
  cv2.putText(tile,case['id'],(5,18),cv2.FONT_HERSHEY_SIMPLEX,.45,(0,0,0),2);cv2.putText(tile,evidence.status+' '+str(round(evidence.visibleArcCoverage,2)),(5,38),cv2.FONT_HERSHEY_SIMPLEX,.45,(0,0,0),2)
  cv2.imwrite(str(a.output/(case['id']+'.png')),tile);tiles.append(cv2.resize(tile,(256,256)))
 while len(tiles)%5:tiles.append(np.full((256,256,3),255,np.uint8))
 cv2.imwrite(str(a.output/'overview.png'),np.vstack([np.hstack(tiles[i:i+5]) for i in range(0,len(tiles),5)]))
 result=dict(status='offlineDiagnosticOnly',manifestSHA256=sha(manifest),sourceHashes={p.name:sha(p) for p in [Path(__file__),Path(__file__).with_name('boundary.py'),Path(__file__).parent.parent/'StoneSetCalibration/estimate.py']},cases=rows)
 (a.output/'results.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')
 for row in rows:
  e=row['evidence'];print(row['id'],e['status'],round(e['visibleArcCoverage'],3),e['abstentionReasons'])
if __name__=='__main__':main()
