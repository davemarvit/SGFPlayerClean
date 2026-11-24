import sys,json,hashlib
from pathlib import Path
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[3]/'Tools'))
from parallax_lab import camera_geometry,evaluate
# Exact synthetic anisotropic board projected through a pinhole camera.
a,b=.45,.3
Rx=np.array([[1,0,0],[0,np.cos(a),-np.sin(a)],[0,np.sin(a),np.cos(a)]])
Ry=np.array([[np.cos(b),0,np.sin(b)],[0,1,0],[-np.sin(b),0,np.cos(b)]])
R=Rx@Ry;t=np.array([-8.,-9.,30.]);pitch=np.array([1.1,1.])
def project(w,h,f,scale=1.):
 K=np.array([[f,0,(w-1)/2],[0,f,(h-1)/2],[0,0,1.]])
 H=K@np.column_stack([R[:,0]*pitch[0]*18*scale,R[:,1]*pitch[1]*18*scale,t*scale])
 H=np.diag([1/(w-1),1/(h-1),1])@H;H/=H[2,2]
 return dict(h=H.ravel()[:8].tolist(),size=19)
g=camera_geometry(project(1920,1080,1400),1920,1080)
expected=dict(cameraGrid=[-float(R[:,0]@t)/pitch[0],-float(R[:,1]@t)],heightRowPitches=abs(float(R[:,2]@t)),focalPixels=1400.,columnToRowPitch=1.1)
for key,v in expected.items():np.testing.assert_allclose(g[key],v,rtol=1e-11,atol=1e-11)
g2=camera_geometry(project(3839,2159,2800),3839,2159)
for key in ['cameraGrid','heightRowPitches','columnToRowPitch']:np.testing.assert_allclose(g[key],g2[key],rtol=1e-11)
np.testing.assert_allclose(g2['focalPixels'],2*g['focalPixels'],rtol=1e-11)
np.testing.assert_allclose(project(1920,1080,1400)['h'],project(1920,1080,1400,2)['h'],rtol=1e-12)
# Historical unrelated setup: replay its OWN old free radial model, never transfer the new fit.
p=Path('/Users/dave/Documents/SGF PLayer/work/hand-parallax-stage10/geometry-native.json');raw=p.read_bytes();rows=json.loads(raw);negative=[]
for row in rows:
 if row.get('photoLabels',{}).get('centered39') is not False:continue
 rawreadings=[[v['occupancy'],v['confidence']] for v in row['readings']]
 r=evaluate(row['shapes'],rawreadings,row['before'],row['targets'],model='radial')
 negative.append(dict(id=row['id'],field=r['field'],target=next(t for t in r['targets'] if t['point']==39)))
assert len(negative)==2
assert sum(x['target']['proposedRelief'] for x in negative)==1
out=dict(synthetic_geometry='PASS exact camera projection, height in row pitches, anisotropic pitch and focal recovered',double_pixel_resolution='PASS geometry invariant and focal doubles',metric_scale='PASS doubling physical board and camera produces identical homography: metric thickness unidentifiable',geometry=g,historical_negative_source=str(p),historical_negative_sha256=hashlib.sha256(raw).hexdigest(),historical_negatives=negative,note='Historical own-setup model only. New k+b fit was not transferred to another setup or fit on negatives.')
Path(__file__).with_name('geometry-controls.json').write_text(json.dumps(out,indent=2)+'\n')
print(json.dumps(out,indent=2))
