#!/usr/bin/env python3
"""Prepare old positive/negative photos; baseline position is supplied, never inferred from tested pixels."""
import argparse,json,subprocess,sys,re
from pathlib import Path
root=Path(__file__).resolve().parents[1];sys.path.insert(0,str(root))
from scripts.build_sources import resolve_sources
from local_quality_lab import digest
from parallax_lab import camera_geometry
from PIL import Image
from fresh_game_confidence import positions
p=argparse.ArgumentParser();p.add_argument('output',type=Path);a=p.parse_args()
if a.output.resolve().is_relative_to(root.parent):raise ValueError('Use external output storage')
a.output.mkdir(parents=True,exist_ok=True);inputs=[];hashes={}
fixture=root/'Tests/Fixtures/HalfwayNudge'
before=['empty']*361;before[60]='black';before[300]='white'
for name in ['centered','nudged']:
 hashes[str(fixture/(name+'.json'))]=digest(fixture/(name+'.json'))
 m=json.loads((fixture/(name+'.json')).read_text())
 inputs.append(dict(id='halfway-'+name,image=str(fixture/(name+'.png')),reference=str(fixture/'empty-reference.png'),calibration=m['calibration'],referenceCalibration=m['referenceCalibration'],threshold=m['threshold'],before=before,targets=[180,199]))
fixture=root/'Tests/Fixtures/CrowdedWhiteAdjustment';metadata=json.loads((fixture/'metadata.json').read_text());labels=json.loads((fixture/'photo-labels.json').read_text())
for name in ['metadata.json','photo-labels.json','initial.sgf']:hashes[str(fixture/name)]=digest(fixture/name)
moves=[('black' if c=='B' else 'white',(ord(xy[1])-97)*19+ord(xy[0])-97) for c,xy in re.findall(r';([BW])\[([a-s]{2})\]',(fixture/'initial.sgf').read_text())]
before=positions(moves)[0][-1]
for m in metadata:
 name=m['name']
 if name not in labels and m.get('expectedClear') is None:continue
 targets=list(labels.get(name,{}).get('empty',[]))
 if m.get('expectedClear') is not None:targets.append(39)
 inputs.append(dict(id='crowded-'+name,image=str(fixture/(name+'.png')),reference=str(fixture/'reference.png'),calibration=m['calibration'],referenceCalibration=m['referenceCalibration'],threshold=m['threshold'],before=before,targets=targets))
for f in inputs:
 for key in ['image','reference']:hashes[f[key]]=digest(Path(f[key]))
manifest=a.output/'geometry-inputs.json';manifest.write_text(json.dumps(inputs,indent=2)+'\n')
exe=a.output/'ParallaxGeometryAudit';sources=[root/'Tools/ParallaxGeometryAudit.swift',root/'Sources/BoardVision.swift',root/'Sources/StoneGeometry.swift',root/'Sources/BoardAppearanceDetector.swift',root.parent/'SGFPlayerClean/Models/OGSModels.swift',root.parent/'SGFPlayerClean/Models/OGSScoringState.swift']
resolved=resolve_sources(root,sources)
subprocess.run(['xcrun','swiftc','-swift-version','5','-O','-D','PHYSICAL_GO',*map(str,resolved),'-o',str(exe)],check=True)
with (a.output/'geometry-native.json').open('w') as f:subprocess.run([str(exe),str(manifest)],stdout=f,check=True)
native=json.loads((a.output/'geometry-native.json').read_text())
for row,source in zip(native,inputs):
    with Image.open(source['image']) as image:row['cameraGeometry']=camera_geometry(source['calibration'],*image.size)
    if row['id'].startswith('crowded-'):
        name=row['id'].removeprefix('crowded-');m=next(v for v in metadata if v['name']==name)
        row['photoLabels']={'empty':labels.get(name,{}).get('empty',[]),'occluded':labels.get(name,{}).get('occluded',[]),'centered39':m.get('expectedClear')}
    elif row['id']=='halfway-nudged':row['photoLabels']={'ambiguous':[180,199]}
(a.output/'geometry-native.json').write_text(json.dumps(native)+'\n')
hashes.update({str(p):digest(p) for p in [*resolved,Path(__file__),Path(__file__).with_name('parallax_lab.py'),manifest]});(a.output/'geometry-input-hashes.json').write_text(json.dumps(hashes,indent=2)+'\n')
