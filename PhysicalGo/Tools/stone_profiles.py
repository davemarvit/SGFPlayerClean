#!/usr/bin/env python3
"""Measure apparent stone silhouettes and surrounding wood from ordinary diagnostic frames.

Usage: python3 PhysicalGo/Tools/stone_profiles.py NEW_OUTPUT SESSION [SESSION ...]
Supply one session per game. Left/right are in display coordinates. Identify the
camera side from the mount; the measurements do not assume where a stone was placed.
Requires numpy, opencv-python. Measurements are in grid spacings / relative brightness.
"""
import argparse
import csv
import json
from collections import defaultdict
from pathlib import Path

import cv2
import numpy as np

STEP = 1 / 48
AXIS = np.arange(-60, 61, dtype=np.float32) * STEP
X, Y = np.meshgrid(AXIS, AXIS)
SECTORS = 12


def load_image(path):
    image = cv2.imread(str(path))
    if image is None:
        raise ValueError(f"Cannot read {path}")
    return cv2.cvtColor(image, cv2.COLOR_BGR2RGB)


def patch(img, calibration, col, row, turns):
    # X,Y are displayed grid axes. Only the crop is anchored to an intersection.
    # The silhouette, axes, and shadow regions are all measured about the observed stone.
    dc, dr = ((X,Y),(Y,-X),(-X,-Y),(-Y,X))[turns]
    c, r = col+dc, row+dr
    u, v = c/(calibration["size"]-1), r/(calibration["size"]-1)
    h = calibration["h"]
    den = h[6]*u + h[7]*v + 1
    px = (img.shape[1]-1)*(h[0]*u+h[1]*v+h[2])/den
    py = (img.shape[0]-1)*(h[3]*u+h[4]*v+h[5])/den
    pixels = cv2.remap(img,px,py,cv2.INTER_LINEAR).astype(np.float32)/255
    # Exclude ink at predicted rails. Leave extra clearance for lens/calibration error.
    wood = (abs(c-np.rint(c))>.12) & (abs(r-np.rint(r))>.12)
    return pixels, wood


def measure(im, ref, cal, ref_cal, row, col, turns, color, strict_mask=False, preview=False):
    live, wood = patch(im,cal,col,row,turns)
    base, _ = patch(ref,ref_cal,col,row,turns)
    return measure_patch(live,base,wood,color,strict_mask,preview)


def measure_patch(live, base, wood, color, strict_mask=False, preview=False):
    """Measure a board-normalized RGB patch, also used by the retained regression set."""
    # Local exterior normalizes exposure; reference ratios reduce wood-grain bias.
    dist = np.hypot(X,Y)
    outer = wood & (dist>.85) & (dist<1.12)
    lum = live @ np.array([.2126,.7152,.0722],dtype=np.float32)
    wood_lum = np.median(lum[outer])
    chroma = live / np.maximum(.01,live.sum(axis=2,keepdims=True)) - 1/3
    wood_chroma = np.linalg.norm(np.median(chroma[outer],axis=0))
    if color == "black":
        mask = (lum<wood_lum*(.40 if strict_mask else .50)) & (lum<wood_lum-.18)
    else:
        tint = np.linalg.norm(chroma,axis=2)
        mask = ((tint<wood_chroma*(.60 if strict_mask else .70)) & (tint<wood_chroma-.025) & (lum>wood_lum-.08)) | (lum>wood_lum+(.14 if strict_mask else .10))
    mask = cv2.morphologyEx(mask.astype(np.uint8),cv2.MORPH_OPEN,np.ones((3,3),np.uint8))
    contours, _ = cv2.findContours(mask,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
    candidates = []
    for contour in contours:
        bx,by,bw,bh = cv2.boundingRect(contour)
        if bx==0 or by==0 or bx+bw>=mask.shape[1] or by+bh>=mask.shape[0]:
            continue
        m = cv2.moments(contour)
        area = m["m00"] * STEP**2
        if not (.28 <= area <= 1.0):
            continue
        cx = m["m10"]/m["m00"]*STEP + AXIS[0]
        cy = m["m01"]/m["m00"]*STEP + AXIS[0]
        if np.hypot(cx,cy)>.55:
            continue
        width = 4 * np.sqrt(m["mu20"]/m["m00"])*STEP
        height = 4 * np.sqrt(m["mu02"]/m["m00"])*STEP
        if not (.55 < width < 1.2 and .55 < height < 1.2):
            continue
        if abs(area/(np.pi*width*height/4)-1)>.15:
            continue
        candidates.append((contour, cx, cy, width, height, area))
    if len(candidates)!=1:
        return None
    contour,cx,cy,width,height,area = candidates[0]
    disk = np.zeros_like(mask)
    cv2.drawContours(disk,[contour],-1,1,cv2.FILLED)
    edge = cv2.distanceTransform(1-disk,cv2.DIST_L2,5)*STEP
    ref_lum = base @ np.array([.2126,.7152,.0722],dtype=np.float32)
    ratio = lum / np.maximum(.04,ref_lum)
    radius = np.hypot(X-cx,Y-cy)
    background = wood & (radius>.86) & (radius<1.10)
    exterior = wood & (edge>.07) & (edge<.32) & (radius<.90)
    if background.sum()<50 or exterior.sum()<70:
        return None
    darkening = 1-ratio/np.median(ratio[background])
    angle = np.arctan2(Y-cy,X-cx)
    # Equal sector weighting prevents rails removing more pixels on one side from
    # manufacturing a shadow direction. Report the direction of darker wood.
    bins = np.floor((angle+np.pi)*SECTORS/(2*np.pi)).astype(int)%SECTORS
    medians = [np.median(darkening[exterior & (bins==j)]) if (exterior & (bins==j)).sum()>=4 else np.nan for j in range(SECTORS)]
    angles = (np.arange(SECTORS)+.5)*2*np.pi/SECTORS-np.pi
    valid = np.isfinite(medians)
    if valid.sum()<8:
        return None
    design = np.column_stack([np.ones(valid.sum()),np.cos(angles[valid]),np.sin(angles[valid])])
    _, sx, sy = np.linalg.lstsq(design,np.array(medians)[valid],rcond=None)[0]
    if preview:
        rgb=(live*255).clip(0,255).astype(np.uint8)
        shade = exterior & (darkening>.10)
        rgb[shade]=.55*rgb[shade]+.45*np.array([255,140,0])
        cv2.drawContours(rgb,[contour],-1,(0,210,250),1)
        return rgb
    return dict(center_x=float(cx),center_y=float(cy),width=float(width),height=float(height),aspect=float(width/height),area=area,
                dark10=float((darkening[exterior]>.10).mean()),dark08=float((darkening[exterior]>.08).mean()),
                dark12=float((darkening[exterior]>.12).mean()),shadow_x=float(sx),shadow_y=float(sy))


def analyze(folder,strict_mask):
    frames, refs = {}, {}
    tracks = defaultdict(list)
    with (folder/"events.jsonl").open() as f:
        for line in f:
            e=json.loads(line)
            if e.get("event")=="frame":
                frames[e["frameID"]]=e
            if e.get("outcome")!="delivered to recorder":
                continue
            readings=e["readings"]; n=int(len(readings)**.5)
            if sum(v["occupancy"]=="uncertain" for v in readings)>len(readings)*.05:
                continue
            frow=frames[e["frameID"]]; ref=frow.get("referenceImage")
            if not ref or not (folder/frow["image"]).is_file():
                continue
            for i,v in enumerate(readings):
                row,col=divmod(i,n)
                if not (0<row<n-1 and 0<col<n-1 and v["confidence"]>=.85 and v["occupancy"] in ("white","black")):
                    continue
                if any(readings[(row+dr)*n+col+dc]["occupancy"]!="empty" for dr in (-1,0,1) for dc in (-1,0,1) if dc or dr):
                    continue
                key=(i,v["occupancy"])
                if not tracks[key] or frow["captureUptime"]-tracks[key][-1][0]>=1:
                    tracks[key].append((frow["captureUptime"],e["frameID"],e["calibration"]))
    tasks=defaultdict(list)
    for key, views in tracks.items():
        if len(views)<3:
            continue
        for j in np.linspace(0,len(views)-1,min(5,len(views)),dtype=int):
            _,id,cal=views[j]
            tasks[id].append((key,cal))
    hits=defaultdict(list)
    for id,todo in sorted(tasks.items()):
        f=frames[id]; img=load_image(folder/f["image"]); ref=f["referenceImage"]
        if ref not in refs:
            refs[ref]=load_image(folder/ref)
        turns=f["viewQuarterTurns"]%4
        for key,cal in todo:
            i,color=key;n=cal["size"];r,c=divmod(i,n)
            result=measure(img,refs[ref],cal,f["referenceCalibration"],r,c,turns,color,strict_mask)
            if result:
                display_col=(c,n-1-r,n-1-c,r)[turns]
                hits[key].append((display_col,n,result,id))
    result=[]
    for (i,color),views in hits.items():
        if len(views)<3:
            continue
        col,n,_,_=views[0]
        if any((x,y)!=(col,n) for x,y,_,_ in views):
            continue  # View rotated within this placement.
        band="left" if col/(n-1)<1/3 else "right" if col/(n-1)>2/3 else "middle"
        med={k:float(np.median([v[2][k] for v in views])) for k in views[0][2]}
        representative=min(views,key=lambda v:abs(v[2]["width"]-med["width"])+abs(v[2]["height"]-med["height"]))
        result.append(dict(session=folder.name,point=i,color=color,display_col=col,band=band,representative_frame=representative[3],
                           views=len(views),**med))
    return result


def write_examples(folder, rows, output, strict_mask):
    """Show the measured body and the sampled dark wood for representative placements."""
    selected = {}
    for color in ("black", "white"):
        for band in ("left", "right"):
            group = [r for r in rows if r["session"] == folder.name and r["color"] == color and r["band"] == band]
            if group:
                width = np.median([r["width"] for r in group])
                height = np.median([r["height"] for r in group])
                selected[color,band] = min(group, key=lambda r: abs(r["width"]-width)+abs(r["height"]-height))
    ids = {r["representative_frame"] for r in selected.values()}
    frames, grids = {}, {}
    for line in (folder/"events.jsonl").open():
        event = json.loads(line)
        if event.get("frameID") in ids:
            if event.get("event")=="frame":
                frames[event["frameID"]]=event
            if event.get("outcome")=="delivered to recorder":
                grids[event["frameID"]]=event["calibration"]
    sheet = np.full((2*205+35,2*206,3),245,dtype=np.uint8)
    for j,color in enumerate(("black","white")):
        for i,band in enumerate(("left","right")):
            selected_row = selected.get((color,band))
            if not selected_row:
                continue
            id = selected_row["representative_frame"]
            f,cal = frames[id],grids[id]
            row,col = divmod(selected_row["point"],cal["size"])
            turns=f["viewQuarterTurns"]%4
            thumb=measure(load_image(folder/f["image"]),load_image(folder/f["referenceImage"]),
                          cal,f["referenceCalibration"],row,col,turns,color,strict_mask,preview=True)
            x,y=i*206+3,j*205+30
            sheet[y:y+166,x+17:x+183]=cv2.resize(thumb,(166,166))
            cv2.putText(sheet,band.title()+" / "+color,(x+23,y-7),cv2.FONT_HERSHEY_SIMPLEX,.5,(20,20,20),1,cv2.LINE_AA)
    cv2.putText(sheet,"Cyan: silhouette    Orange: darker wood",(10,427),cv2.FONT_HERSHEY_SIMPLEX,.55,(20,20,20),1,cv2.LINE_AA)
    cv2.imwrite(str(output/(folder.name.split()[-1]+"-examples.png")),cv2.cvtColor(sheet,cv2.COLOR_RGB2BGR))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output",type=Path)
    parser.add_argument("sessions",type=Path,nargs="+")
    parser.add_argument("--strict-mask",action="store_true",help="Use stricter silhouette thresholds for a sensitivity check")
    args=parser.parse_args()
    if args.output.exists():parser.error("output already exists")
    rows=[]
    for s in args.sessions:
        measured=analyze(s,args.strict_mask)
        print(s.name,len(measured),"positions",flush=True)
        rows+=measured
    if not rows:
        raise SystemExit("No isolated placements with repeatable measurements")
    args.output.mkdir(parents=True)
    with (args.output/"positions.csv").open("x",newline="") as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
    for folder in args.sessions:
        write_examples(folder, rows, args.output, args.strict_mask)
    summaries=[]
    for name in sorted({r["session"] for r in rows}):
        for color in ("black","white"):
            for band in ("left","middle","right"):
                group=[r for r in rows if r["session"]==name and r["color"]==color and r["band"]==band]
                if group:
                    summaries.append(dict(session=name,color=color,band=band,n=len(group),**{
                        k:float(np.median([r[k] for r in group])) for k in
                        ("aspect","width","height","area","dark08","dark10","dark12","shadow_x","shadow_y")}))
    (args.output/"summary.json").write_text(json.dumps(summaries,indent=2)+"\n")

if __name__=="__main__":main()
