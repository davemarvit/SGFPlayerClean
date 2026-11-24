from pathlib import Path
import hashlib,json,numpy as np
W=Path(__file__).resolve().parents[3]
T=Path('/Users/dave/Documents/SGF PLayer/work/ai-laser-integration/stone-session-20261123/stone-set-calibration/native-white-votes-01')
m=json.loads((T/'manifest.json').read_text());sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert all(sha(Path(p))==s for p,s in m['sources'].items())
assert sha(W/'PhysicalGo/Sources/StoneGeometry.swift')==m['originalStoneGeometrySHA256']
assert sha(W/'PhysicalGo/Experiments/WhiteVoteDiagnostic/run.py')==m['generator_sha256']
rec=Path(m['recording']);assert sha(rec/'events.jsonl')==m['events_sha256'];assert sha(rec/'frames/000697.png')==m['image_sha256']
events=[json.loads(l) for l in (rec/'events.jsonl').read_text().splitlines()]
original=[e for e in events if e.get('frameID')==697 and e.get('event')=='operation finished'][-1]
r=json.loads((T/'native-replay.json').read_text());assert original['footprints']==r['savedFootprints']==r['replayedFootprints'];assert len(r['savedFootprints'])==4
bodies=json.loads((W/'PhysicalGo/Experiments/WhiteCentering/frame697/measurements.json').read_text())
results=[]
for p in sorted(T.glob('point-*-call-*.json')):
 d=json.loads(p.read_text());a=np.array(d['cells']);cur=a[:,9:12];wood=a[:,12:15]
 cm=np.linalg.norm(cur,axis=1);wm=np.linalg.norm(wood,axis=1)
 np.testing.assert_allclose(cm,a[:,7],atol=1e-15);np.testing.assert_allclose(wm,a[:,8],atol=1e-15)
 neutral=(wm-cm>.035)&(cm<wm*.65)
 cool=(cm<.075)&(cm<wm*.90)&(wood[:,0]-cur[:,0]>.035)&(cur[:,2]-wood[:,2]>.035)
 rawcolor=neutral|cool
 floor=a[:,3]*.75 if d['shadedWhite'] else a[:,3]-.06
 color=rawcolor&(a[:,2]-d['correction']>floor)
 bright=a[:,2]-d['correction']>a[:,3]+.12
 assert np.array_equal(color,a[:,4]);assert np.array_equal(bright,a[:,5]);assert np.array_equal(color|bright,a[:,6])
 body=next(x for x in bodies['measurements'] if x['point']==d['point'])['thresholdSweep'][1];center=np.array(body['bodyCentroidGrid'])
 rel=a[:,:2]-center;core=(rel[:,0]/.38)**2+(rel[:,1]/.40)**2<=1
 assert not rawcolor[core].any()
 # All native candidates, vectorized independent direct disk sums; retain native order/ties.
 votes=a[:,6].reshape(65,65);best=(-1.,None)
 dx,dy=np.meshgrid(np.arange(-d['searchSteps'],d['searchSteps']+1),np.arange(-d['searchSteps'],d['searchSteps']+1))
 xx=32+dx.ravel();yy=32+dy.ravel()
 def total(rx,aspect):
  ry=rx*aspect;offset=[]
  for y in range(-int(ry/.04),int(ry/.04)+1):
   extent=int(rx/.04*np.sqrt(max(0.,1-(y*.04/ry)**2)))
   offset.extend((x,y) for x in range(-extent,extent+1))
  off=np.array(offset);return votes[yy[:,None]+off[:,1],xx[:,None]+off[:,0]].sum(axis=1),len(off)
 for i in range(15):
  rx=.32+i*.02
  if rx>.54:continue
  for aspect in [.94,1.06]:
   bv,n=total(rx,aspect);iv,ni=total(rx+.06,aspect);ov,no=total(rx+.15,aspect)
   score=bv/n-.7*(ov-iv)/(no-ni);j=int(np.argmax(score))
   if score[j]>best[0]:best=(float(score[j]),(rx,rx*aspect,int(dx.ravel()[j]),int(dy.ravel()[j])))
 chosen=d['best'];rx,ry,x,y=best[1]
 np.testing.assert_allclose([best[0],rx,ry,chosen['col']+x*.04,chosen['row']+y*.04],[chosen['quality'],chosen['radiusCol'],chosen['radiusRow'],chosen['center']['x'],chosen['center']['y']],atol=1e-12,rtol=0)
 results.append(dict(point=d['point'],all4225_votes_match=True,raw_color_support_in_core=int(rawcolor[core].sum()),full_discrete_search_matches=True,best=best,native_minus_body_row=chosen['center']['y']-center[1]))
out=dict(source_hashes_verified=len(m['sources']),archived_footprints_exactly_reproduced=4,cases=results)
Path(__file__).with_name('independent-review-results.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out,indent=2))
