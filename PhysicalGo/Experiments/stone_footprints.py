"""Offline footprint experiment; does not alter the app's classifications.
Requires numpy, OpenCV, matplotlib. Uses accepted stones as seeds, then fits
an elliptical color-region boundary in grid coordinates for visual inspection.
"""
from pathlib import Path
import argparse, json
import cv2
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Ellipse

parser=argparse.ArgumentParser()
parser.add_argument('sample',type=Path)
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args()
meta=json.loads((args.sample/'sample.json').read_text())
pitch=80
margin=0.8
n=meta['boardSize']
side=round((n-1+2*margin)*pitch)
y,x=np.mgrid[:side,:side].astype(np.float32)
col=x/pitch-margin
row=y/pitch-margin

def rectify(name,calibration):
    im=cv2.imread(str(args.sample/name))
    if im is None: raise ValueError(f'Cannot read {name}')
    h=calibration['h'];u=col/(n-1);v=row/(n-1)
    d=h[6]*u+h[7]*v+1
    mx=((h[0]*u+h[1]*v+h[2])/d*(im.shape[1]-1)).astype(np.float32)
    my=((h[3]*u+h[4]*v+h[5])/d*(im.shape[0]-1)).astype(np.float32)
    return cv2.remap(im,mx,my,cv2.INTER_LINEAR).astype(np.float32)[...,::-1]/255

frame=rectify('frame.png',meta['calibration'])
reference=rectify('empty-reference.png',meta.get('referenceCalibration') or meta['calibration'])
level=frame.mean(axis=2);base=reference.mean(axis=2)
chroma=frame/np.maximum(frame.sum(axis=2,keepdims=True),.05)-1/3
basechroma=reference/np.maximum(reference.sum(axis=2,keepdims=True),.05)-1/3
saturation=np.linalg.norm(chroma,axis=2);basesaturation=np.linalg.norm(basechroma,axis=2)
masks={
 'black':((level<base-.20)&(level<base*.65)).astype(np.float32),
 'white':(((basesaturation-saturation>.035)&(saturation<basesaturation*.65)&(level>base-.06))|(level>base+.12)).astype(np.float32)
}
aspect=22/23.6 if meta.get('rectifiedLongAxisRows',True) else 23.6/22
fits=[]
for color,mask in masks.items():
    seeds=[p for p in meta['readings'] if p['occupancy']==color]
    best=[None]*len(seeds)
    for radius in np.arange(.32,.551,.01):
        reach=int(np.ceil((radius+.16)*max(1,aspect)*pitch))
        ky,kx=np.mgrid[-reach:reach+1,-reach:reach+1]/pitch
        distance=np.hypot(kx,ky/aspect)
        inside=(distance<radius).astype(np.float32)
        ring=((distance>radius+.06)&(distance<radius+.15)).astype(np.float32)
        kernel=inside/inside.sum()-.7*ring/ring.sum()
        scores=cv2.filter2D(mask,-1,kernel)
        for i,seed in enumerate(seeds):
            cx=round((seed['col']+margin)*pitch);cy=round((seed['row']+margin)*pitch)
            reach_search=round(.45*pitch)
            left=max(0,cx-reach_search);right=min(side,cx+reach_search+1)
            top=max(0,cy-reach_search);bottom=min(side,cy+reach_search+1)
            patch=scores[top:bottom,left:right]
            iy,ix=np.unravel_index(patch.argmax(),patch.shape)
            score=float(patch[iy,ix])
            if best[i] is None or score>best[i]['score']:
                best[i]=dict(row=seed['row'],col=seed['col'],color=color,
                             center_col=(left+int(ix))/pitch-margin,
                             center_row=(top+int(iy))/pitch-margin,
                             radius_col=float(radius),radius_row=float(radius*aspect),score=score)
    fits.extend(best)

uncertain=[]
for point in meta['readings']:
    if point['occupancy']!='uncertain':continue
    xx,yy=np.meshgrid(np.linspace(-.3,.3,31),np.linspace(-.3,.3,31))
    patch=xx*xx+yy*yy<=.3**2
    covered=np.zeros_like(patch)
    neighbors=[]
    for stone in fits:
        if abs(stone['col']-point['col'])>1 or abs(stone['row']-point['row'])>1:continue
        inside=((point['col']+xx-stone['center_col'])/stone['radius_col'])**2+((point['row']+yy-stone['center_row'])/stone['radius_row'])**2<=1
        overlap=float((inside&patch).sum()/patch.sum())
        covered |= inside
        if overlap>0:neighbors.append({'row':stone['row'],'col':stone['col'],'overlap':round(overlap,3)})
    uncertain.append(dict(row=point['row'],col=point['col'],footprint_overlap=round(float((covered&patch).sum()/patch.sum()),3),neighbors=neighbors))
args.output.mkdir(parents=True,exist_ok=True)
report=dict(note='Exploratory fits, not verified outlines or app classifications. Overlap is with a radius-0.3 sampling region, not the intersection itself.',fits=fits,uncertain=uncertain)
(args.output/'footprints.json').write_text(json.dumps(report,indent=2))
fig,ax=plt.subplots(figsize=(11,11))
ax.imshow(frame,extent=(-margin,n-1+margin,n-1+margin,-margin))
for stone in fits:
    ax.add_patch(Ellipse((stone['center_col'],stone['center_row']),2*stone['radius_col'],2*stone['radius_row'],fill=False,edgecolor='#00d8ff',lw=1.3))
    ax.plot(stone['center_col'],stone['center_row'],'+',color='#00d8ff',ms=5)
for point in uncertain:
    ax.plot(point['col'],point['row'],'o',mfc='none',mec='#ff8c00',ms=10,mew=1.5)
    ax.annotate(f"{round(point['footprint_overlap']*100)}%",(point['col'],point['row']),xytext=(7,-12),textcoords='offset points',color='#dd5700',fontsize=8)
ax.set_title('Experimental stone outlines and uncertain points\nCyan: fitted body and center · orange: uncertain · %: estimated sampling-region overlap')
ax.set_xticks(range(n));ax.set_yticks(range(n));ax.set_xlabel('Raw camera grid column (zero-based)');ax.set_ylabel('Raw camera grid row (zero-based)')
fig.tight_layout();fig.savefig(args.output/'footprints.png',dpi=150);plt.close(fig)
print(json.dumps({'stones':len(fits),'fit_score_range':[min(s['score'] for s in fits),max(s['score'] for s in fits)],'uncertain':uncertain},indent=2))
# Compact detail panels make the crowded regions easier to review alongside chat.
fig,axes=plt.subplots(1,2,figsize=(12,6))
for ax,bounds,title in zip(axes,[(.7,9.9,13.6,18.1),(14.1,18.6,10.4,17.4)],['Lower-left group','Right-hand group']):
    ax.imshow(frame,extent=(-margin,n-1+margin,n-1+margin,-margin))
    for stone in fits:
        ax.add_patch(Ellipse((stone['center_col'],stone['center_row']),2*stone['radius_col'],2*stone['radius_row'],fill=False,edgecolor='#00d8ff',lw=1.4))
        ax.plot(stone['center_col'],stone['center_row'],'+',color='#00d8ff',ms=5)
    for point in uncertain:
        ax.plot(point['col'],point['row'],'o',mfc='none',mec='#ff8c00',ms=10,mew=1.8)
    ax.set_xlim(bounds[0],bounds[1]);ax.set_ylim(bounds[3],bounds[2]);ax.set_title(title)
    ax.set_xlabel('Column');ax.set_ylabel('Row')
fig.suptitle('Offline experiment: cyan outlines/centers · orange uncertain intersections')
fig.tight_layout();fig.savefig(args.output/'details.png',dpi=150);plt.close(fig)
