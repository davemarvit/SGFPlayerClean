#!/usr/bin/env python3
"""Re-run the bright-wood false-stone regression through the native detector."""
import argparse,json,subprocess,hashlib
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--engine',type=Path,required=True);a=p.parse_args()
root=Path(__file__).resolve().parent/'Fixtures/ResumeGlare/v1'
for name,expected in json.loads((root/'checksums.json').read_text()).items():
 assert hashlib.sha256((root/name).read_bytes()).hexdigest()==expected,name
manifest=json.loads((root/'manifest.json').read_text())
frames=json.loads(subprocess.check_output([str(a.engine.resolve()),'corpus',str(root)]))
assert {x['frame'] for x in frames}=={x['frame'] for x in manifest['cases']}
checks=0
for frame in frames:
 for point in manifest['emptyPoints']:
  assert frame['readings'][point]['occupancy'] in ['empty','uncertain'],(frame['frame'],point,'false stone');checks+=1
 for point in manifest['whitePoints']:
  assert frame['readings'][point]['occupancy']=='white',(frame['frame'],point,'lost white stone');checks+=1
print(f'PASS: {checks} photographed glare checks, {len(frames)} frames; no false stones, visible white stones retained.')
