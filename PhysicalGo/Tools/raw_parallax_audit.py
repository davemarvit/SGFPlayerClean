#!/usr/bin/env python3
"""Raw perspective sensitivity and plotted geometry. No recognition mutations."""
import argparse,json,re
from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from PIL import Image
from parallax_lab import camera_geometry,fit_field,prediction,evaluate
from local_quality_lab import digest

p=argparse.ArgumentParser();p.add_argument('--incident',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
p.add_argument('--native',type=Path);p.add_argument('--photo-inputs',type=Path);a=p.parse_args()
if bool(a.native)!=bool(a.photo_inputs):p.error('--native and --photo-inputs must be supplied together')
if a.output.resolve().is_relative_to(Path(__file__).resolve().parents[2]):raise ValueError('Use external output storage')
a.output.mkdir(parents=True,exist_ok=True)
root=a.incident/'static-board';entries=[json.loads(l) for l in (root/'events.jsonl').open()];frames={e['frameID']:e for e in entries if e['event']=='frame'}
ops=[e for e in entries if e['event']=='operation finished' and e.get('readings')]
session=json.loads((root/'session.json').read_text());before=['empty']*361
for color,xy in re.findall(r';([BW])\[([a-s]{2})\]',session['initialSGF']):before[(ord(xy[1])-97)*19+ord(xy[0])-97]='black' if color=='B' else 'white'
targets=[92,53,41,22,76];records=[]
for op in ops:
 frame=frames[op['frameID']];raw=[[r['occupancy'],r['confidence']] for r in sorted(op['readings'],key=lambda r:r['row']*19+r['col'])];shapes=op.get('footprints',[])+op.get('placementFits',[])
 variants=[]
 for px in [.49,.495,.5,.505,.51]:
  for py in [.49,.495,.5,.505,.51]:
   geometry=camera_geometry(op['calibration'],frame['width'],frame['height'],(px,py))
   result=evaluate(shapes,raw,before,targets,model='raw-camera',geometry=geometry)
   field=result['field']
   variants.append({'principal':[px,py],'geometry':geometry,'field':field,'targets':result['targets'],
                    'effectiveHeightRowPitches':None if field is None else geometry['heightRowPitches']*field['coefficients'][0]/(1+field['coefficients'][0])})
 records.append({'frame':op['frameID'],'variants':variants})
(a.output/'raw-perspective-sensitivity.json').write_text(json.dumps(records,indent=2)+'\n')
# One representative raw frame, with board calibration and the modeled field side by side.
chosen=next((op for op,r in zip(ops,records) if r['variants'][12]['field']),None)
assert chosen is not None
record=next(r for r in records if r['frame']==chosen['frameID']);central=record['variants'][12];geo=central['geometry'];field=central['field'];frame=frames[chosen['frameID']]
fig,(left,right)=plt.subplots(1,2,figsize=(13,6),layout='constrained')
image=Image.open(root/frame['image']);left.imshow(image)
h=chosen['calibration']['h']
def pixel(x,y):
 u,v=x/18,y/18;den=h[6]*u+h[7]*v+1
 return ((h[0]*u+h[1]*v+h[2])/den*(frame['width']-1),(h[3]*u+h[4]*v+h[5])/den*(frame['height']-1))
for i in range(19):
 for pairs in [((i,0),(i,18)),((0,i),(18,i))]:
  xy=np.array([pixel(*q) for q in pairs]);left.plot(xy[:,0],xy[:,1],color='cyan',lw=.45,alpha=.65)
camera=pixel(*geo['cameraGrid']);left.plot(*camera,'rx',ms=10);left.annotate('Camera projection\n(pinhole hypothesis)',camera,xytext=(-100,-65),textcoords='offset points',color='red',arrowprops={'arrowstyle':'->','color':'red'})
left.set_title('Original image: perspective retained');left.set_axis_off()
y,x=np.mgrid[0:19:2,0:19:2];offset=np.array([prediction(field,[cx,cy]) for cx,cy in zip(x.ravel(),y.ravel())])
# User orientation is turn 3: display x=row, y=18-col.
mag=np.linalg.norm(offset,axis=1);dots=right.scatter(y.ravel(),18-x.ravel(),c=mag,cmap='viridis',vmin=0,vmax=.4,s=30)
right.quiver(y.ravel(),18-x.ravel(),offset[:,1],-offset[:,0],angles='xy',scale_units='xy',scale=.2,color='black',width=.003)
right.plot(geo['cameraGrid'][1],18-geo['cameraGrid'][0],'rx',ms=10)
right.set(xlim=(-1,19),ylim=(19,-1),aspect='equal',xticks=range(0,19,2),yticks=range(0,19,2),xticklabels=list('ABCDEFGHJKLMNOPQRST')[::2],yticklabels=list(range(19,0,-1))[::2],title='Predicted displacement across board\nArrows magnified 5×; not a grid correction')
right.grid(alpha=.25);fig.colorbar(dots,ax=right,label='Displacement in grid spacings',shrink=.65)
fig.savefig(a.output/'raw-perspective.png',dpi=140);plt.close(fig)
valid=[v for r in records for v in r['variants'] if v['geometry']];fitted=[v for r in records for v in r['variants'] if v['field']]
summary={'frames':len(records),'hypotheses':len(records)*25,'physicallyAdmissiblePinholeSolutions':len(valid),'fittedHeightSolutions':len(fitted),
 'centralExample':central,'focalRangePixels':[min(v['geometry']['focalPixels'] for v in valid),max(v['geometry']['focalPixels'] for v in valid)],
 'effectiveHeightRangeRowPitches':[min(v['effectiveHeightRowPitches'] for v in fitted),max(v['effectiveHeightRowPitches'] for v in fitted)],
 'limitations':'Principal point ±1% sensitivity only, not a confidence interval. Square pixels, zero skew/distortion, constant effective stone height assumed; physical pitch and lens intrinsics unknown. No clock or recognition authority.'}
summary['staticConsensus']={str(point):sum(all(next(t for t in v['targets'] if t['point']==point)['proposedRelief'] for v in r['variants']) for r in records) for point in targets}
summary['staticAdmissibleConsensus']={str(point):sum(any(v['geometry'] is not None for v in r['variants']) and all(next(t for t in v['targets'] if t['point']==point)['proposedRelief'] for v in r['variants'] if v['geometry'] is not None) for r in records) for point in targets}
# Require a correction under every hypothesis, including abstentions. This is
# a sensitivity check, not a calibrated uncertainty interval or promotion gate.
if a.native:
 sources={v['id']:v for v in json.loads(a.photo_inputs.read_text())};older=[]
 for row in json.loads(a.native.read_text()):
  source=sources[row['id']]
  with Image.open(source['image']) as photo:dimensions=photo.size
  raw=[[r['occupancy'],r['confidence']] for r in row['readings']];variants=[]
  for px in [.49,.495,.5,.505,.51]:
   for py in [.49,.495,.5,.505,.51]:
    geometry=camera_geometry(source['calibration'],*dimensions,(px,py))
    result=evaluate(row['shapes'],raw,row['before'],row['targets'],model='raw-camera',geometry=geometry)
    variants.append({'principal':[px,py],'geometry':geometry,**result})
  older.append({'id':row['id'],'photoLabels':row.get('photoLabels',{}),'variants':variants})
 (a.output/'older-perspective-sensitivity.json').write_text(json.dumps(older,indent=2)+'\n')
 summary['olderPhotos']=[{'id':r['id'],'admissibleGeometry':sum(v['geometry'] is not None for v in r['variants']),
    'fittedFields':sum(v['field'] is not None for v in r['variants']),
    'misplacement39':r['photoLabels'].get('centered39') is False,
    'falseMisplacementRelief':sum(t['proposedRelief'] for v in r['variants'] for t in v['targets'] if t['point']==39 and r['photoLabels'].get('centered39') is False)} for r in older]
(a.output/'raw-perspective-summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps({k:v for k,v in summary.items() if k!='centralExample'},indent=2))
inputs=[Path(__file__),Path(__file__).with_name('parallax_lab.py'),root/'events.jsonl',root/'session.json',root/frame['image']]
if a.native:inputs.extend([a.native,a.photo_inputs])
(a.output/'raw-perspective-inputs.json').write_text(json.dumps({str(p):digest(p) for p in inputs},indent=2)+'\n')
