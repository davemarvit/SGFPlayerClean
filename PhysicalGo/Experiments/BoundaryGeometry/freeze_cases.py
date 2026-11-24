"""Deterministic pre-evaluation selection; no image analysis or fitting."""
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
OUT=Path(__file__).resolve().parent
CAP=Path('/Users/dave/Documents/SGF PLayer/work/ai-laser-integration/stone-session-20261123/stone-set-calibration')
FIX=ROOT/'PhysicalGo/Tests/Fixtures'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def source(p):return dict(path=str(p),sha256=sha(p))
cases=[]
def add(id,image,meta,cal,point,color,label,setup,neighbors=(),visibility='clear',compact=None):
 cases.append(dict(id=id,image=source(image),metadata=source(meta),calibration=cal,seed=point,colorHypothesis=color,label=label,setup=setup,neighborCenters=list(neighbors),visibility=visibility,compactFit=compact))
points=[[3,3],[9,3],[15,3],[3,9],[15,9],[3,15],[9,15],[15,15]]
for color in ['white','black']:
 folder=CAP/(color+'-01');meta=folder/'frame-00.json';d=json.loads(meta.read_text())
 for p in points:add(f'{color}-centered-{p[0]}-{p[1]}',folder/'frame-00.png',meta,d['currentCalibration'],p,color,'user-confirmed centered outer-star; contact label approximate','nov23-ausdom', [q for q in points if q!=p])
 folder=CAP/(color+'-midpoint-01');meta=folder/'frame-00.json';d=json.loads(meta.read_text())
 add(color+'-fresh-midpoint',folder/'frame-00.png',meta,d['currentCalibration'],[14.5,9],color,'new displaced episode at prior training location, not exact midpoint ground truth','nov23-ausdom',[p for p in points if p!=[15,9]])
meta=ROOT/'PhysicalGo/Experiments/WhiteCentering/frame697/measurements.json';d=json.loads(meta.read_text())
for row in d['measurements']:
 p=[9,9] if row['name']=='legitimate' else [9,14.5]
 add('nov23-'+row['name'],Path(d['image']),meta,d['calibration'],p,'white','existing development centered/midway pair','nov23-ausdom',compact=row['productionFit'])
for name in ['centered','nudged']:
 meta=FIX/'HalfwayNudge'/(name+'.json');d=json.loads(meta.read_text())
 add('old-black-'+name,meta.with_suffix('.png'),meta,d['calibration'],[9,9 if name=='centered' else 9.5],'black','historical labeled Black '+name,'nov12-iphone',[[3,3],[15,15]])
meta=FIX/'CrowdedWhiteAdjustment/metadata.json';rows=json.loads(meta.read_text());native=json.loads(Path('/Users/dave/Documents/SGF PLayer/work/hand-parallax-stage10/geometry-native.json').read_text())
for name in ['frame-816','frame-950']:
 d=next(x for x in rows if x['name']==name);n=next(x for x in native if x['id']=='crowded-'+name)
 neighbors=[[i%19,i//19] for i,c in enumerate(d['signature']) if c in 'BW?' and i!=39]
 fit=next(s for s in n['shapes'] if s['row']*19+s['col']==39)
 add('crowded-'+name,FIX/'CrowdedWhiteAdjustment'/(name+'.png'),meta,d['calibration'],[1,1.7],'white','known real misplacement; frame950 preserves earlier false relief .36 to .221','nov05-crowded',neighbors,compact=fit)
 if name=='frame-950':
  add('hand-covered-950-95',FIX/'CrowdedWhiteAdjustment/frame-950.png',meta,d['calibration'],[0,5],'white','independent photo-label occluded95; supplied gate, not hand-detection validation','nov05-crowded',neighbors,visibility='occluded')
for name in ['10','75','150']:
 meta=FIX/'ShadedCross'/(name+'.json');d=json.loads(meta.read_text());neighbors=[[x['col'],x['row']] for x in d['readings'] if x['occupancy'] in ['black','white']]
 add('shaded-empty-'+name,meta.with_suffix('.png'),meta,d['calibration'],[12,15],'white','test fixture: shaded empty crossing','nov04-shaded',neighbors)
meta=CAP/'black-01/frame-00.json';d=json.loads(meta.read_text());add('empty-center-current',meta.with_suffix('.png'),meta,d['currentCalibration'],[9,9],'white','user-confirmed eight outer stones, center empty','nov23-ausdom',points)
policy={'version':'radial-rgb-edge-v1','samplingAngles':72,'radiusSearch':[.22,.80],'edgeHalfWidth':.025,'minimumRGBStep':18.,'minimumRadiality':.65,'minimumArcFraction':.70,'maximumMissingArcDegrees':90,'ellipseRadiusBounds':[.32,.62],'maximumCenterShift':.30,'maximumEllipseResidual':.045,'maximumContestedFraction':.15,'neighborOwnershipMargin':.08,'geometryOnly':True,'thresholdStatus':'engineering assumptions frozen before replay, not calibrated'}
payload={'selection':'fixed before first boundary replay; first frame per episode, all eight centered anchors, predefined historical controls','cases':cases,'policy':policy,'excluded':'No later frame selection, model fitting, threshold tuning, physical contact inference or live use.'}
with (OUT/'cases.json').open('x') as f:json.dump(payload,f,indent=2);f.write('\n')
print(len(cases),'cases frozen')
