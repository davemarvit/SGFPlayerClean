"""Offline artifact-only validation; no browser/app, screenshots or runtime imports."""
from pathlib import Path
import ast
import hashlib
import json
import re
import runpy
import subprocess
import xml.etree.ElementTree as ET
from urllib.parse import unquote, urlparse

ROOT=Path(__file__).resolve().parent
NS={'s':'http://www.w3.org/2000/svg'}

def main():
    # Builder definitions only; its main is not run and it imports no app code.
    ast.parse((ROOT/'build_map.py').read_text())
    builder=runpy.run_path(str(ROOT/'build_map.py'),run_name='map_verification')
    snapshot=json.loads((ROOT/'release-snapshot.json').read_text())
    issues=[];nodes_count=0;labels_count=0
    fonts=None
    try:
        from PIL import ImageFont
        f=Path('/System/Library/Fonts/Supplemental')
        fonts={s:ImageFont.truetype(str(f/('Arial Bold.ttf' if s==18 else 'Arial.ttf')),s) for s in (14,15,18)}
    except (ImportError,OSError):pass
    diagrams=sorted(ROOT.glob('*.svg'))
    if len(diagrams)!=7:issues.append('Expected seven SVGs')
    for path in diagrams:
        tree=ET.parse(path);vb=list(map(float,tree.getroot().attrib['viewBox'].split()))
        boxes=[];labels=[]
        for group in tree.findall('.//s:g',NS):
            rect=group.find('s:rect',NS)
            x,y,w,h=[float(rect.attrib[k]) for k in ('x','y','width','height')]
            boxes.append((group.attrib['data-node'],x,y,w,h));nodes_count+=1
            for text in group.findall('s:text',NS):
                if fonts:
                    size=18 if text.attrib.get('class')=='node-title' else 15
                    width=fonts[size].getlength(text.text or '')
                    if float(text.attrib['x'])+width>x+w:issues.append(f'{path.name}: text overflows {group.attrib["data-node"]}')
        for line in tree.findall('.//s:polyline',NS):
            points=[tuple(map(float,p.split(','))) for p in line.attrib['points'].split()]
            for a,b in zip(points,points[1:]):
                for name,x,y,w,h in boxes:
                    vertical=a[0]==b[0] and x<a[0]<x+w and max(min(a[1],b[1]),y)<min(max(a[1],b[1]),y+h)
                    horizontal=a[1]==b[1] and y<a[1]<y+h and max(min(a[0],b[0]),x)<min(max(a[0],b[0]),x+w)
                    if vertical or horizontal:issues.append(f'{path.name}: connector crosses {name}')
        for text in tree.findall('.//s:text',NS):
            if text.attrib.get('class')!='edge-label':continue
            labels_count+=1
            if not fonts:continue
            x,y=float(text.attrib['x']),float(text.attrib['y']);w=fonts[14].getlength(text.text or '')
            box=(x-w/2,y-14,x+w/2,y+3)
            if box[0]<0 or box[2]>vb[2] or box[1]<0 or box[3]>vb[3]:issues.append(f'{path.name}: label outside canvas')
            for name,nx,ny,nw,nh in boxes:
                if box[0]<nx+nw and box[2]>nx and box[1]<ny+nh and box[3]>ny:issues.append(f'{path.name}: label overlaps {name}')
            for old in labels:
                if box[0]<old[2] and box[2]>old[0] and box[1]<old[3] and box[3]>old[1]:issues.append(f'{path.name}: labels overlap')
            labels.append(box)
    html=(ROOT/'index.html').read_text();ids=set(re.findall(r'\bid="([^"]+)"',html))
    for href in re.findall(r'href="([^"]+)"',html):
        parsed=urlparse(href)
        if href.startswith('#'):
            if href[1:] not in ids:issues.append('Missing anchor '+href)
        elif parsed.scheme=='file':
            if not Path(unquote(parsed.path)).exists():issues.append('Missing file '+href)
        elif not parsed.scheme and not (ROOT/unquote(href)).exists():issues.append('Missing relative file '+href)
    sources={}
    for key,(path,desc) in builder['sources'].items():
        if not path.exists():issues.append('Missing source '+str(path));continue
        sources[key]={'path':str(path),'description':desc,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    (ROOT/'source-hashes.json').write_text(json.dumps(sources,indent=2)+'\n')
    actual={}
    for kind in ('native','host'):
        actual[kind]=subprocess.check_output(['git','-C',snapshot[kind+'_source'],'rev-parse','HEAD'],text=True).strip()
    result=dict(date=snapshot['date'],map_state=snapshot['state'],diagrams=len(diagrams),nodes=nodes_count,
        connector_labels=labels_count,issues=issues,font_metrics_checked=fonts is not None,
        source_count=len(sources),source_heads=actual,
        declared_source_heads={k:snapshot[k+'_commit'] for k in ('native','host')},
        source_heads_match={k:actual[k]==snapshot[k+'_commit'] for k in ('native','host')},
        validation_scope='Static SVG/XML, font metrics, connector geometry, links, AST and source hashes; no browser rendering, screenshot, app, camera, hardware or runtime tests.')
    (ROOT/'validation.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))
    if issues:raise SystemExit(1)

if __name__=='__main__':main()
