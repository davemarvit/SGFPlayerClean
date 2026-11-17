#!/usr/bin/env python3
"""Run offline placement-geometry comparisons; prior positions are supplied contexts."""
import argparse,collections,gzip,json,re
from pathlib import Path
import numpy as np
from parallax_lab import evaluate,camera_geometry
from local_quality_lab import digest

def write(p,v):p.write_text(json.dumps(v,indent=2,sort_keys=True)+'\n')

def main(a):
    if a.output.resolve().is_relative_to(Path(__file__).resolve().parents[2]):raise ValueError('Use external output storage')
    a.output.mkdir(parents=True,exist_ok=True)
    inputs={Path(__file__),Path(__file__).with_name('parallax_lab.py')};details=[]
    source=a.incident/'static-board/events.jsonl';inputs.add(source)
    entries=[json.loads(l) for l in source.open()]
    frames={v['frameID']:v for v in entries if v['event']=='frame'}
    session=json.loads((a.incident/'static-board/session.json').read_text());inputs.add(a.incident/'static-board/session.json')
    before=['empty']*361
    for color,xy in re.findall(r';([BW])\[([a-s]{2})\]',session['initialSGF']):before[(ord(xy[1])-97)*19+ord(xy[0])-97]='black' if color=='B' else 'white'
    targets=[92,53,41,22,76];names={92:'E17',53:'C16',41:'C4',22:'B4',76:'E1'}
    for op in entries:
        if op['event']!='operation finished' or not op.get('readings'):continue
        raw=[[r['occupancy'],r['confidence']] for r in sorted(op['readings'],key=lambda r:r['row']*19+r['col'])]
        shapes=op.get('footprints',[])+op.get('placementFits',[])
        for model in ['translation','radial','raw-camera']:
            frame=frames[op['frameID']]
            result=evaluate(shapes,raw,before,targets,model=model,geometry=camera_geometry(op['calibration'],frame['width'],frame['height']))
            details.append({'case':'incident-static','frame':op['frameID'],'model':model,'handBlocked':op['handOutline'].get('obstructed'),
                            'scope':'Static diagnostic only; field uses later established stones, not a causal replay of moves 4/6/12.',**result})
    for game in ['game65-cache','game85-cache']:
        folder=a.previous/game;contexts=json.loads((folder/'contexts.json').read_text());inputs.update([folder/'contexts.json',folder/'observations.jsonl.gz'])
        by_frame=collections.defaultdict(list)
        for c in contexts:by_frame[c['reviewedEndpoint']].append(c)
        plan=json.loads((folder/'plan.json').read_text());events_path=Path(plan['snapshot'])/'capture/events.jsonl'
        inputs.update([folder/'plan.json',events_path]);geometries={};dimensions={}
        for l in events_path.open():
            v=json.loads(l);fid=v.get('frameID')
            if fid not in by_frame:continue
            if v['event']=='frame':dimensions[fid]=(v['width'],v['height'])
            elif v['event']=='operation finished' and v.get('calibration') and fid in dimensions:
                geometries[fid]=camera_geometry(v['calibration'],*dimensions[fid])
        with gzip.open(folder/'observations.jsonl.gz','rt') as f:
            for line in f:
                row=json.loads(line)
                for c in by_frame.get(row['frame'],[]):
                    targets=[c['expected']] if c['expected'] is not None else c['reviewedEmpty']
                    for model in ['translation','radial','raw-camera']:
                        result=evaluate(row['shapes'],row['raw'],c['before'],targets,model=model,geometry=geometries.get(row['frame']))
                        details.append({'case':game,'id':c['id'],'frame':row['frame'],'model':model,'expected':c['expected'],
                                        'truth':c['color'] if c['expected'] is not None else 'empty','capture':c.get('capture'),
                                        'handBlocked':row['hand'],'lightingBlocked':row['lightingBlocked'],
                                        'recordedTiming':row['recordedTiming'],'scope':'Reviewed endpoint geometry only; supplied prior position, no chronology or clock replay.',**result})
    if a.native:
        native=json.loads(a.native.read_text());inputs.add(a.native)
        from parallax_lab import assignment_offsets
        for frame in native:
            raw=[[r['occupancy'],r['confidence']] for r in frame['readings']]
            original=assignment_offsets(frame['shapes'],raw,frame['before'])
            assert original.keys()=={int(k) for k in frame['assignmentOffsets']},frame['id']
            assert all(abs(v-frame['assignmentOffsets'][str(k)])<1e-9 for k,v in original.items()),frame['id']
            for model in ['translation','radial','raw-camera']:
                result=evaluate(frame['shapes'],raw,frame['before'],frame['targets'],model=model,geometry=frame.get('cameraGeometry'))
                details.append({'case':'older-photos','id':frame['id'],'frame':0,'model':model,'photoLabels':frame.get('photoLabels',{}),'scope':'Independent static photograph; no timestamps.',**result})
    summary={}
    for case in sorted({r['case'] for r in details}):
        summary[case]={}
        for model in ['translation','radial','raw-camera']:
            subset=[r for r in details if r['case']==case and r['model']==model]
            points=[t for r in subset for t in r['targets']]
            summary[case][model]={'contexts':len(subset),'fieldsFitted':sum(r['field'] is not None for r in subset),
                                 'pointEvaluations':len(points),'originallyFlagged':sum(t['originalOffset'] is not None and t['originalOffset']>=.3 for t in points),
                                 'relieved':sum(t['proposedRelief'] for t in points),'newlyFlagged':sum((t['originalOffset'] is None or t['originalOffset']<.3) and t['proposedOffset'] is not None and t['proposedOffset']>=.3 for t in points)}
            if case=='older-photos':
                negatives=[r for r in subset if r['photoLabels'].get('centered39') is False]
                summary[case][model].update(
                    labeledMisplacementFrames=len(negatives),
                    misplacementFramesWithField=sum(r['field'] is not None for r in negatives),
                    falseMisplacementRelief=sum(t['proposedRelief'] for r in negatives for t in r['targets'] if t['point']==39))
    static={}
    for p,name in names.items():
        static[name]={}
        for model in ['translation','radial','raw-camera']:
            matches=[t for r in details if r['case']=='incident-static' and r['model']==model for t in r['targets'] if t['point']==p]
            static[name][model]={'frames':len(matches),'relieved':sum(t['proposedRelief'] for t in matches),'occupancy':dict(collections.Counter(t['occupancy'] for t in matches)),
                               'originallyFlagged':sum(t['originalOffset'] is not None and t['originalOffset']>=.3 for t in matches),
                               'medianOriginal':float(np.median([t['originalOffset'] for t in matches if t['originalOffset'] is not None])) if any(t['originalOffset'] is not None for t in matches) else None,
                               'medianProposed':float(np.median([t['proposedOffset'] for t in matches if t['proposedOffset'] is not None])) if any(t['proposedOffset'] is not None for t in matches) else None}
    write(a.output/'parallax-decisions.json',details);write(a.output/'parallax-summary.json',{'comparisons':summary,'staticPoints':static,'promotion':False,'clockAuthority':False,
        'scope':'Assignment evidence only; no changes to occupancies, hand gates, time evidence, sequence inference, or Go capture handling.'})
    write(a.output/'parallax-inputs.json',{str(p):digest(p) for p in sorted(inputs)})
    print(json.dumps(summary,indent=2));print(json.dumps(static,indent=2))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--incident',type=Path,required=True);p.add_argument('--previous',type=Path,required=True);p.add_argument('--native',type=Path);p.add_argument('--output',type=Path,required=True);main(p.parse_args())
