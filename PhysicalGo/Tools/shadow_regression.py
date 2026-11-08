#!/usr/bin/env python3
"""Compare offline silhouette/shadow rules on the frozen photographic regression set."""
import argparse
import csv
import gzip
import hashlib
import json
import math
import subprocess
from collections import Counter, defaultdict
from functools import lru_cache
from pathlib import Path
from statistics import mean, median

import cv2
import numpy as np

import stone_profiles as profiles

FIXTURE = Path(__file__).resolve().parents[1]/"Tests/Fixtures/ShadowRegression/v1"
MODES = ("baseline", "pooled_outline", "outline", "shadow")


def table(file):
    with file.open(newline="") as f:
        return list(csv.DictReader(f))


def write_table(path, rows):
    with path.open("x",newline="") as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)


def display_column(point, size, turns):
    row,col=divmod(point,size)
    return (col,size-1-row,size-1-col,row)[turns]


def training_views(root, manifest, targets):
    result=defaultdict(list)
    for e in manifest["exemplars"]:
        if (e["session"],e["point"]) in targets:
            raise ValueError("An evaluation location was also used to learn the profile")
        pair=profiles.load_image(root/e["patch"])/255.
        live,base=np.hsplit(pair,2)
        # Grid lines are rotation invariant at an integer-centered, quarter-turned crop.
        wood=(abs(profiles.X-np.rint(profiles.X))>.12)&(abs(profiles.Y-np.rint(profiles.Y))>.12)
        value=profiles.measure_patch(live,base,wood,e["color"])
        if value is not None:
            result[e["session"],e["color"],e["point"]].append((e,value))
    return result


def local_profile(views, case, point, color, pooled=False):
    size=case["calibration"]["size"]
    target=display_column(point,size,case["turns"])
    positions=[]
    for (key,col,location),samples in views.items():
        if (key,col)!=(case["session"],color):
            continue
        prior=[v for e,v in samples if e["capture_time"]<case["capture_time"] and e["turns"]==case["turns"] and
               e["size"]==size and e["source_reference"]==case["source_reference"]]
        if len(prior)<3:
            continue
        distance=abs(display_column(location,size,case["turns"])-target)
        if pooled or distance<=6:
            positions.append((distance,location,{k:median([v[k] for v in prior]) for k in prior[0]}))
    if len(positions)<2:
        return None
    nearest=positions if pooled else sorted(positions)[:4]
    return {k:median([v[k] for _,_,v in nearest]) for k in nearest[0][2]}


def surviving_cross(live, base):
    # Test both printed rails against adjacent wood on both sides. An unobserved
    # stone outline by itself is never treated as evidence of an empty point.
    luma=np.array([.2126,.7152,.0722])
    a,b=live@luma,base@luma
    def pixel(image,x,y):
        return image[60+round(y/profiles.STEP),60+round(x/profiles.STEP)]
    def contrast(image,x,y,vertical):
        dx,dy=(.14,0) if vertical else (0,.14)
        return min(pixel(image,x+dx,y+dy),pixel(image,x-dx,y-dy))-pixel(image,x,y)
    radius=np.hypot(profiles.X,profiles.Y)
    wood=(abs(profiles.X-np.rint(profiles.X))>.12)&(abs(profiles.Y-np.rint(profiles.Y))>.12)
    ratio=a/np.maximum(.04,b)
    background=np.median(ratio[wood & (radius>.86) & (radius<1.10)])
    shade=1-np.median(ratio[wood & (radius<.35)])/max(.01,background)
    if not .06<=shade<=.30:
        return False
    for vertical in [False,True]:
        votes=0
        for along in [-.24,-.16,.16,.24]:
            centers=[(off,along) if vertical else (along,off) for off in [-.06,-.03,0,.03,.06]]
            x,y=max(centers,key=lambda xy:contrast(b,*xy,vertical))
            ink=contrast(b,x,y,vertical)
            if ink>.035 and contrast(a,x,y,vertical)>=max(.03,.60*ink):
                votes+=1
        if votes<3:
            return False
    return True


def evaluate(root, base, labels, manifest):
    views=training_views(root,manifest,{(r["session"],int(r["point"])) for r in labels})
    case_map={(c["session"],c["frame"]):c for c in manifest["cases"]}
    base_map={(c["session"],c["frame"]):c for c in base}
    @lru_cache(maxsize=5)
    def image(relative):
        return profiles.load_image(root/relative)
    @lru_cache(maxsize=512)
    def data(key,id,point,color):
        case=case_map[key,id];n=case["calibration"]["size"];row,col=divmod(point,n)
        live,wood=profiles.patch(image(case["image"]),case["calibration"],col,row,case["turns"])
        ref,_=profiles.patch(image(case["reference"]),case["reference_calibration"],col,row,case["turns"])
        body=profiles.measure_patch(live,ref,wood,color)
        return body,live,ref
    if len(base_map)!=len(base) or set(base_map)!=set(case_map):
        raise ValueError("Baseline frames do not match the frozen corpus")
    if len({(r["session"],r["frame"],r["point"]) for r in labels})!=len(labels):
        raise ValueError("Duplicate test label")
    if {(r["session"],int(r["frame"])) for r in labels}!=set(case_map):
        raise ValueError("Label frames do not match the frozen corpus")
    results=[]
    for r in labels:
        key,id,point=r["session"],int(r["frame"]),int(r["point"])
        case=case_map[key,id];base_case=base_map[key,id];n=case["calibration"]["size"]
        reading=base_case["readings"][point];old=reading["occupancy"]
        if reading["row"]*n+reading["col"]!=point:
            raise ValueError("Baseline point order does not match labels")
        result=dict(r, baseline=old, baseline_score=reading["confidence"],pooled_outline=old,outline=old,shadow=old,
                    profiles=0, matching_bodies=0, shadow_supported=False, shadow_explained_empty=False)
        for color in ("white","black"):
            result[color+"_outline_margin"]=None
            result[color+"_shadow_margin"]=None
        bodies=[]
        pooled_bodies=[]
        for color in ("white","black"):
            profile=local_profile(views,case,point,color)
            pooled=local_profile(views,case,point,color,pooled=True)
            result["profiles"]+=int(profile is not None)
            if pooled is None:
                continue
            body,_,_=data(key,id,point,color)
            if body is None or math.hypot(body["center_x"],body["center_y"])>.40:
                continue
            if all(abs(body[k]-pooled[k])<=limit for k,limit in (("width",.16),("height",.16),("area",.20))):
                pooled_bodies.append(color)
            if profile is None:
                continue
            outline_margin=1-max(abs(body[k]-profile[k])/limit for k,limit in
                                 (("width",.16),("height",.16),("area",.20)))
            shadow_margin=1-max(abs(body["dark10"]-profile["dark10"])/.18,
                                math.hypot(body["shadow_x"]-profile["shadow_x"],body["shadow_y"]-profile["shadow_y"])/.075)
            result[color+"_outline_margin"]=outline_margin
            result[color+"_shadow_margin"]=shadow_margin
            if outline_margin<0:
                continue
            shadow_match=shadow_margin>=0
            bodies.append((color,shadow_match))
        if len(pooled_bodies)==1 and old in ("uncertain","empty"):
            result["pooled_outline"]=pooled_bodies[0]
        result["matching_bodies"]=len(bodies)
        if len(bodies)==1 and old in ("uncertain","empty"):
            color,match=bodies[0]
            result["outline"]=color
            result["shadow_supported"]=match
            if match:
                result["shadow"]=color
        # Does an independently measured neighbor explain an apparently dark piece
        # of exposed wood? Only change uncertain/black, and require visible rails.
        if not bodies and old in ("uncertain","black"):
            row,col=divmod(point,n)
            _,live,ref=data(key,id,point,"black")
            if 0<col<n-1 and 0<row<n-1 and surviving_cross(live,ref):
                for f in base_case["shapes"]:
                    other=f["row"]*n+f["col"];c=base_case["readings"][other]["occupancy"]
                    if other==point or c not in ("black","white") or f["quality"]<.86:
                        continue
                    dc,dr=col-f["center"]["x"],row-f["center"]["y"]
                    gap=math.hypot(dc/f["radiusCol"],dr/f["radiusRow"])
                    if not 1.05<=gap<=1.65:
                        continue
                    profile=local_profile(views,case,other,c)
                    if profile is None:
                        continue
                    dx,dy=((dc,dr),(-dr,dc),(-dc,-dr),(dr,-dc))[case["turns"]]
                    projected=(dx*profile["shadow_x"]+dy*profile["shadow_y"])/math.hypot(dx,dy)
                    if projected>.03 and profile["dark10"]>.08:
                        result["shadow"]="empty"
                        result["shadow_explained_empty"]=True
                        break
        results.append(result)
    return results


def summarize(rows):
    output={}
    for split in sorted({r["split"] for r in rows}):
        selected=[r for r in rows if r["split"]==split]
        clear=[r for r in selected if r["truth"]!="occluded"]
        groups=defaultdict(list)
        for r in clear:
            groups[r["session"],r["point"],r["episode"]].append(r)
        report=dict(labeled=len(clear),occluded=len(selected)-len(clear),episodes=len(groups),
                    with_profiles=sum(r["profiles"]>0 for r in clear), modes={})
        for mode in MODES:
            counts=Counter("correct" if r[mode]==r["truth"] else "uncertain" if r[mode]=="uncertain" else "wrong" for r in clear)
            report["modes"][mode]=dict(counts=counts,wrong_color_or_phantom=sum(r[mode] in ("black","white") and r[mode]!=r["truth"] for r in clear),
                episode_mean_accuracy=mean(mean(r[mode]==r["truth"] for r in g) for g in groups.values()),
                improved=sum(r["baseline"]!=r["truth"]==r[mode] for r in clear),
                regressed=sum(r["baseline"]==r["truth"]!=r[mode] for r in clear),
                occluded_stone_calls=sum(r["truth"]=="occluded" and r[mode] in ("black","white") for r in selected))
        output[split]=report
    return output


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("output",type=Path,help="new report directory")
    ap.add_argument("--corpus",type=Path,default=FIXTURE)
    ap.add_argument("--engine",type=Path,help="recompute the baseline with a compiled ConfidenceReplay")
    args=ap.parse_args()
    if args.output.exists():
        ap.error("Report already exists")
    root=args.corpus
    sums=json.loads((root/"checksums.json").read_text())
    for name,expected in sums.items():
        if hashlib.sha256((root/name).read_bytes()).hexdigest()!=expected:
            raise ValueError(f"Fixture failed integrity check: {name}")
    manifest=json.loads((root/"manifest.json").read_text());labels=table(root/"labels.csv")
    base=(json.loads(subprocess.check_output([args.engine.resolve(),"corpus",root.resolve()])) if args.engine else
          json.loads(gzip.decompress((root/"baseline-0.50.json.gz").read_bytes())))
    rows=evaluate(root,base,labels,manifest)
    args.output.mkdir(parents=True)
    write_table(args.output/"paired.csv",rows)
    report=summarize(rows)
    (args.output/"summary.json").write_text(json.dumps(report,indent=2)+"\n")
    provenance=dict(corpus_sha256=hashlib.sha256((root/"checksums.json").read_bytes()).hexdigest(),
                    implementation_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                    profiles_sha256=hashlib.sha256(Path(profiles.__file__).read_bytes()).hexdigest(),
                    baseline="frozen 0.50" if not args.engine else hashlib.sha256(args.engine.read_bytes()).hexdigest())
    (args.output/"run.json").write_text(json.dumps(provenance,indent=2)+"\n")
    print(json.dumps(report,indent=2))


if __name__=="__main__":main()
