"""Read-only fixtures + synthetic controls. No live camera, hardware or app IO."""
import argparse,json,time,statistics,gzip
from pathlib import Path
import cv2,numpy as np
from change_gate import describe,describe_rectified,changes

ROOT=Path(__file__).resolve().parents[2]/'Tests/Fixtures'

def photo(folder,name):
    result=cv2.imread(str(ROOT/folder/name));assert result is not None
    return result

def meta(folder,name='sample.json'):
    return json.loads((ROOT/folder/name).read_text())

def summarize(name,result,required=None):
    return dict(name=name,rawCount=len(result['raw']),expandedCount=len(result['expanded']),
                skippedFraction=1-len(result['expanded'])/361,
                required=required,requiredFound=None if required is None else all(p in result['expanded'] for p in required),
                **{k:v for k,v in result.items() if k not in ('raw','expanded')})

def run():
    cv2.setNumThreads(1);rng=np.random.default_rng(12024);rows=[];times=[]
    calibration=meta('A18HandOutline')['calibration'];base=photo('A18HandOutline','before.png')
    anchor=describe(base,calibration,'fixed')
    # These are clearly labelled constructed controls, not additional recordings.
    controls={
        'same_pixels':base,
        'sensor_noise_sigma2':np.clip(base.astype(float)+rng.normal(0,2,base.shape),0,255).astype(np.uint8),
        'uniform_5percent_dimmer':(base*.95).astype(np.uint8),
    }
    y,x=np.mgrid[:base.shape[0],:base.shape[1]]
    shade=1-.08*np.exp(-((x-base.shape[1]/2)**2+(y-base.shape[0]/2)**2)/(2*350**2))
    controls['smooth_8percent_shadow']=np.clip(base*shade[:,:,None],0,255).astype(np.uint8)
    controls['camera_translation_2px']=cv2.warpAffine(base,np.float32([[1,0,2],[0,1,0]]),(base.shape[1],base.shape[0]))
    for name,image in controls.items():
        rows.append(summarize('synthetic/'+name,changes(anchor,describe(image,calibration,'fixed'))))
    for _ in range(40):
        began=time.perf_counter();current=describe(base,calibration,'fixed');changes(anchor,current)
        times.append((time.perf_counter()-began)*1000)
    # Captured stone insertion/removal through substantial glare.
    cases=meta('KnownPositionGlare','cases.json')
    descriptions=[describe(photo('KnownPositionGlare',c['image']),c['calibration'],'glare') for c in cases]
    for a,b in [(0,1),(1,2),(0,2)]:
        rows.append(summarize(f'recorded/glare-{cases[a]["image"]}-to-{cases[b]["image"]}',changes(descriptions[a],descriptions[b]),[185] if b==1 or a==1 else None))
    for folder,a,b,required in [('A18HandOutline','before.png','after.png',[17]),('A18HandOutline','before.png','hand.png',None),('C1HandOutline','before.png','after.png',[322])]:
        c=meta(folder)['calibration']
        rows.append(summarize(f'recorded/{folder}/{a}-to-{b}',changes(describe(photo(folder,a),c,folder),describe(photo(folder,b),c,folder)),required))
    c=meta('CoveredBorder','metadata.json')['calibration']
    a=describe(photo('CoveredBorder','000001.png'),c,'border')
    for name in ['000009.png','000010.png','000011.png']:
        rows.append(summarize(f'recorded/covered-border-{name}',changes(a,describe(photo('CoveredBorder',name),c,'border'))))
    # Real successive no-hand frames around White A18. RGB reconstructed from
    # the native quantized chroma/light samples, not fabricated camera frames.
    sequence=meta('A18HandOutline','manifest.json')
    packed=np.frombuffer(gzip.decompress((ROOT/'A18HandOutline/pixels.u16.gz').read_bytes()),dtype='<u2')
    packed=packed.reshape(len(sequence['frames']),sequence['width'],sequence['width'],3)
    seq={}
    for info,pixels in zip(sequence['frames'],packed):
        v=pixels.astype(np.float32)/sequence['scale']
        red,green,light=v[:,:,0],v[:,:,1],v[:,:,2]
        bgr=np.stack((1-red-green,green,red),axis=2)*(3*light[:,:,None])*255
        bgr=np.clip(bgr,0,255).astype(np.uint8)
        axis=((np.arange(380,dtype=np.float32)+.5)/20-.5+2)*10
        xx,yy=np.meshgrid(axis,axis)
        bgr=cv2.remap(bgr,xx,yy,cv2.INTER_LINEAR)
        seq[info['index']]=describe_rectified(bgr,np.ones((380,380),bool),19,'A18-grid')
    temporal=[]
    for start,end in [(230,245),(256,280)]:
        for i in sorted(seq):
            if start<i<=end:
                outcome=changes(seq[start],seq[i])
                temporal.append(summarize(f'recorded/grid-A18-{start}-to-{i}',outcome))
    rows.extend(temporal)
    # Synthetic sub-cell changes supplement actual photographs. They make no
    # claim about physical optical sensitivity. White has modest contrast on wood.
    wood=np.zeros((380,380,3),np.uint8);wood[:]=[140,170,190]
    def stone(col,row,color,shift=0):
        high=cv2.resize(wood,(1520,1520),interpolation=cv2.INTER_NEAREST)
        center=(round((col+.5+shift)*80),round((row+.5)*80))
        cv2.circle(high,center,32,color,-1,lineType=cv2.LINE_AA)
        return cv2.resize(high,(380,380),interpolation=cv2.INTER_AREA)
    def desc(rect):return describe_rectified(rect,np.ones((380,380),bool),19,'synthetic-stone')
    for color_name,color in [('black',(30,30,30)),('white',(193,199,203))]:
        for col,row in [(0,0),(18,18),(9,9)]:
            absent=desc(wood);present=desc(stone(col,row,color))
            rows.append(summarize(f'synthetic/{color_name}-placement-{row*19+col}',changes(absent,present),[row*19+col]))
            rows.append(summarize(f'synthetic/{color_name}-removal-{row*19+col}',changes(present,absent),[row*19+col]))
            for shift in [.025,.05,.1]:
                moved=desc(stone(col,row,color,shift))
                rows.append(summarize(f'synthetic/{color_name}-shift-{shift}-{row*19+col}',changes(present,moved),[row*19+col]))
    # The fresh sampling grid changes context: geometry/stream/lighting/target
    # boundaries invalidate hints, even when pixels happen to be identical.
    rows.append(summarize('scope_reset',changes(anchor,describe(base,calibration,'new-stream'))))
    return dict(diagnosticOnly=True,runtimeIntegrated=False,
                timing=dict(samples=len(times),medianMs=statistics.median(times),p95Ms=float(np.quantile(times,.95)),maxMs=max(times),includes='rectification, descriptor and region comparison; image decode excluded',opencv=cv2.__version__),cases=rows)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path);a=p.parse_args();result=run()
    text=json.dumps(result,indent=2)
    if a.output:a.output.write_text(text+'\n')
    print(text)
