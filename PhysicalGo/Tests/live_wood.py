#!/usr/bin/env python3
"""Photographed live-grid regression; these labels were visually reviewed."""
import argparse,json,subprocess,hashlib
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--engine',type=Path,required=True);a=p.parse_args()
r=Path(__file__).resolve().parent/'Fixtures/LiveWood/v1'
for name,expected in json.loads((r/'checksums.json').read_text()).items():
 assert hashlib.sha256((r/name).read_bytes()).hexdigest()==expected,name
m=json.loads((r/'manifest.json').read_text());frames=json.loads(subprocess.check_output([str(a.engine.resolve()),'corpus',str(r)]));checks=0
for k,f in enumerate(frames):
 for point in m['emptyPoints']:
  assert f['readings'][point]['occupancy'] in ['empty','uncertain'],(k,point,'false stone');checks+=1
 for color,key in [('black','blackPoints'),('white','whitePoints')]:
  for point in m[key]+(m['lastFrame'+key[0].upper()+key[1:]] if k==len(frames)-1 else []):
   assert f['readings'][point]['occupancy']==color,(k,point,'missed stone');checks+=1
print(f'PASS: {checks} live-wood checks across {len(frames)} photographed positions.')
