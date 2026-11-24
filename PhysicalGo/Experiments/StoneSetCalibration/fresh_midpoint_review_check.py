"""Independent retained-data checks; no hardware and no writes to captured evidence."""
from pathlib import Path
import hashlib,json,subprocess,sys,tempfile
import numpy as np
import cv2
HERE=Path(__file__).resolve().parent
BASE=Path('/Users/dave/Documents/SGF PLayer/work/ai-laser-integration/stone-session-20261123/stone-set-calibration')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
summary=json.loads((HERE/'results-summary.json').read_text());rpath=Path(summary['freshMidpoints']['path'])
assert sha(rpath)==summary['freshMidpoints']['sha256'];r=json.loads(rpath.read_text())
assert sha(HERE/'fresh_midpoint_audit.py')==r['sourceSHA256'];assert sha(HERE/'estimate.py')==r['frozenMeasurementSourceSHA256']
# Independently implement scalar normalized-H projection and its two-equation inverse.
def pixels(cal,p):
 h=cal['h'];u,v=np.array(p)/18;d=h[6]*u+h[7]*v+1
 return np.array([(h[0]*u+h[1]*v+h[2])/d*1919,(h[3]*u+h[4]*v+h[5])/d*1079])
def grid(cal,p):
 x,y=np.array(p)/[1919,1079];h=cal['h']
 return 18*np.linalg.solve([[h[0]-x*h[6],h[1]-x*h[7]],[h[3]-y*h[6],h[4]-y*h[7]]],[x-h[2],y-h[5]])
minimum=float('inf');max_roundtrip=0.;cases=[]
for case in r['cases']:
 mp=Path(case['modelReport']);sp=Path(case['sampleManifest']);assert sha(mp)==case['modelSHA256'];assert sha(sp)==case['sampleManifestSHA256']
 model=json.loads(mp.read_text());samples=json.loads(sp.read_text());assert samples['includeForTraining'] is False and samples['preselectedHeldOutLocation'] is False
 assert samples['userConfirmedReady'] and samples['freshNegativeEpisode'];assert len(samples['samples'])==len(case['frames'])==8
 assert [15,9] in model['conditionalFits']['currentGrid']['fitPoints'];assert [9,3] not in model['conditionalFits']['currentGrid']['fitPoints']
 old=json.loads((BASE/'offline-body-study-01'/case['color']/'results.json').read_text());assert old['conditionalFits']==model['conditionalFits']
 gp=Path(model['refinedGridAudit']['source']);assert sha(gp)==model['refinedGridAudit']['sha256'];G=np.array(json.loads(gp.read_text())['board_to_image'])
 distances=[]
 for f,s in zip(case['frames'],samples['samples']):
  ip=Path(f['image']);meta=Path(f['metadata']);assert sha(ip)==f['imageSHA256']==s['sha256'];assert sha(meta)==f['metadataSHA256']
  m=json.loads(meta.read_text());assert m['frame']==s['frame'];assert m['frame']['frameID']==f['frameID'];assert m['cameraID']==model['cameraID'];assert m['frame']['streamEpoch']==model['streamEpoch']
  assert m['currentCalibration']==f['currentCalibration'];assert m['currentCalibration']['size']==19;assert cv2.imread(str(ip)).shape[:2]==(1080,1920)
  assert m['alignmentValid'] is True and m['handObstructed'] is False
  px=pixels(f['currentCalibration'],f['bodyInCurrentGrid']);np.testing.assert_allclose(px,f['bodyPixel'],atol=1e-9,rtol=0)
  frozen=grid(model['currentCalibration'],px);np.testing.assert_allclose(frozen,f['bodyInFrozenGrid'],atol=1e-12,rtol=0)
  error=np.linalg.norm(pixels(model['currentCalibration'],frozen)-px);max_roundtrip=max(max_roundtrip,error)
  for mode,v in f['comparisons'].items():
   fit=model['conditionalFits'][mode];assert v['kFrozen']==fit['k'];q=np.array(v['conditionalContact']);apparent=(1+fit['k'])*q-fit['k']*np.array(fit['geometry']['cameraGrid'])
   if mode=='currentGrid':np.testing.assert_allclose(apparent,frozen,atol=1e-12,rtol=0)
   else:
    z=G@np.r_[apparent,1];np.testing.assert_allclose(z[:2]/z[2],px,atol=1e-9,rtol=0)
   ds=[float(np.linalg.norm(q-point)) for point in [[14,9],[15,9]]];np.testing.assert_allclose(ds,v['distancesToCol14And15'],atol=1e-12,rtol=0);minimum=min(minimum,*ds);distances.append(ds)
 for reg in case['registration']:
  assert len(reg['crossings'])==7 and all(p['point']!=[15,9] for p in reg['crossings']);d=np.array([p['freshMinusPriorPixels'] for p in reg['crossings']]);med=np.median(d,axis=0)
  np.testing.assert_allclose(med,reg['medianShiftPixels'],atol=1e-12);assert abs(np.linalg.norm(d,axis=1).max()-reg['maximumDisplacementPixels'])<1e-12
  assert abs(np.linalg.norm(d-med,axis=1).max()-reg['maximumResidualAfterMedianShiftPixels'])<1e-12
 cases.append(dict(color=case['color'],frames=8,allSourceAndIdentityChecks=True,coefficientsEqualStudy01=True,minimumNeighborDistance=min(min(x) for x in distances)))
# Two fail-closed input controls use isolated metadata/manifests and symlinks to read-only archives.
negative=[]
for fault in ['changed_epoch','changed_image_hash']:
 with tempfile.TemporaryDirectory(prefix='midpoint-review-negative-') as tmp:
  b=Path(tmp);(b/'offline-body-study-02').symlink_to(BASE/'offline-body-study-02',target_is_directory=True)
  capture=b/'black-midpoint-01';capture.mkdir();source=BASE/'black-midpoint-01';s=json.loads((source/'samples.json').read_text())
  for p in source.iterdir():
   if p.name!='samples.json':(capture/p.name).symlink_to(p)
  if fault=='changed_epoch':
   p=capture/s['samples'][0]['metadata'];p.unlink();m=json.loads((source/p.name).read_text());m['frame']['streamEpoch']='independent-invalid-epoch';p.write_text(json.dumps(m))
  else:s['samples'][0]['sha256']='0'*64
  (capture/'samples.json').write_text(json.dumps(s));out=b/'result.json'
  run=subprocess.run([sys.executable,str(HERE/'fresh_midpoint_audit.py'),str(b),str(out)],capture_output=True,text=True)
  assert run.returncode!=0 and not out.exists();expected='Incompatible or inadmissible capture' if fault=='changed_epoch' else 'Image hash mismatch';assert expected in run.stderr;negative.append(dict(fault=fault,rejectedBeforeResult=True))
report=dict(status='independent offline review only',artifactSHA256=sha(rpath),cases=cases,minimumNeighborDistance=minimum,maximumNativeGridRoundtripPixels=max_roundtrip,negativeControls=negative)
(HERE/'fresh-midpoint-review-results.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
