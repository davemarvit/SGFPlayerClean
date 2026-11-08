#!/usr/bin/env python3
"""Replay retained camera pixels; keep sequence agreement separate from ground truth.
Never write into source archives or count seeded prior moves as recognized moves.
"""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import subprocess


def write(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def inventory(captures):
    rows=[]
    for area in ['Diagnostics','DiagnosticEvidence']:
        for manifest in sorted((captures/area).glob('*/session.json')):
            folder=manifest.parent; meta=json.loads(manifest.read_text())
            frames={}; delivered=[]; last_decision={}; sgf=meta.get('initialSGF'); starts=False; edits=[]
            for line in (folder/'events.jsonl').open():
                event=json.loads(line)
                if event.get('event')=='frame': frames[event['frameID']]=event
                if event.get('outcome')=='delivered to recorder': delivered.append(event['frameID'])
                if event.get('event')=='recorder':
                    d=event['decision']; last_decision=d
                    sgf=d.get('sgf',sgf)
                    if d.get('event')=='start': starts=True
                    if d.get('event') in ['manual move','restored saved game']: edits.append(d['event'])
            available=[i for i in delivered if (folder/frames[i]['image']).is_file()]
            initial=meta['recorder']
            sequence=(len(available)==len(delivered) and initial['pendingMoves']==0 and not edits and
                      (initial['moveCount']>0 or initial['state']!='idle' or starts))
            rows.append(dict(session=folder.name.split()[-1],archive=str(folder.resolve()),
                manifest_sha256=hashlib.sha256(manifest.read_bytes()).hexdigest(),
                events_sha256=hashlib.sha256((folder/'events.jsonl').read_bytes()).hexdigest(),
                initial_moves=initial['moveCount'],initial_pending=initial['pendingMoves'],
                analyzed_frames=len(delivered),available_frames=len(available),missing_frames=len(delivered)-len(available),
                mode='continuous pixel-to-recorder replay' if sequence else 'retained pixel classifications only',
                expected_sgf=sgf,expected_pending=last_decision.get('tentativeSequences',[]),ids=available))
    return rows


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output',type=Path)
    parser.add_argument('--captures',type=Path,default=Path('PhysicalGo/Captures'))
    parser.add_argument('--sequence-engine',type=Path,required=True)
    parser.add_argument('--pixel-engine',type=Path,required=True)
    parser.add_argument('--workers',type=int,default=3)
    args=parser.parse_args()
    args.output.mkdir(parents=True,exist_ok=False)
    rows=inventory(args.captures)
    write(args.output/'inventory.json',rows)
    initial_references=[]
    for row in rows:
        meta=json.loads((Path(row['archive'])/'session.json').read_text())
        if meta.get('initialSGF'):
            reference=args.output/(row['session']+'-initial-reference.sgf')
            reference.write_text(meta['initialSGF'])
            points=json.loads(subprocess.check_output([str(args.pixel_engine.resolve()),'moves',str(reference)]))
            initial_references.append(dict(session=row['session'],points=points))
    write(args.output/'initial-references.json',initial_references)
    write(args.output/'engines.json',{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [args.sequence_engine,args.pixel_engine]})
    def job(row):
        key=row['session']; log=args.output/(key+'.log')
        result={k:v for k,v in row.items() if k not in ['expected_sgf','expected_pending','ids']}
        try:
            if row['mode']=='continuous pixel-to-recorder replay':
                target=args.output/key
                with log.open('w') as f:
                    subprocess.run([str(args.sequence_engine.resolve()),row['archive'],str(target.resolve())],stdout=f,stderr=subprocess.STDOUT,check=True)
                replay=json.loads((target/'summary.json').read_text())
                result['replay']=replay
                if row['expected_sgf']:
                    ref=target/'archived-reference.sgf';ref.write_text(row['expected_sgf'])
                    expected=json.loads(subprocess.check_output([str(args.pixel_engine.resolve()),'moves',str(ref)]))
                    pending=row['expected_pending']
                    if len(pending)==1: expected+=pending[0]
                    elif len(pending)>1: result['ambiguous_archived_tail']=True
                    initial=row['initial_moves']
                    actual=replay['savedPoints']+replay['pendingPoints']
                    pairs=[dict(move=i+1,reference=expected[i],current=actual[i] if i<len(actual) else None,
                                state='saved' if i<replay['moves'] else 'pending' if i<len(actual) else 'not retained') for i in range(initial,len(expected))]
                    write(target/'move-comparison.json',pairs)
                    result['reference_kind']='previous recognizer SGF plus unique archived pending sequence; not independent ground truth'
                    result['new_reference_moves']=len(pairs)
                    result['matching_saved']=sum(p['reference']==p['current'] and p['state']=='saved' for p in pairs)
                    result['matching_pending']=sum(p['reference']==p['current'] and p['state']=='pending' for p in pairs)
                    result['not_retained']=sum(p['state']=='not retained' for p in pairs)
                    result['disagreements']=[p for p in pairs if p['state']!='not retained' and p['reference']!=p['current']]
                    result['additional_current_moves']=actual[len(expected):]
            else:
                target=args.output/(key+'-pixels.json')
                with target.open('w') as f,log.open('w') as err:
                    subprocess.run([str(args.pixel_engine.resolve()),'frames',row['archive'],','.join(map(str,row['ids']))],stdout=f,stderr=err,check=True)
                predictions=json.loads(target.read_text())
                counts={'old':{},'new':{}}
                for side in counts:
                    for frame in predictions:
                        for r in frame[side]:counts[side][r['occupancy']]=counts[side].get(r['occupancy'],0)+1
                result['classification_counts_not_accuracy']=counts
                result['changed_calls']=sum(a['occupancy']!=b['occupancy'] for f in predictions for a,b in zip(f['old'],f['new']))
            result['completed']=True
        except Exception as e:
            result['completed']=False;result['error']=str(e)
        write(args.output/(key+'-result.json'),result)
        print(key, 'OK' if result['completed'] else 'FAILED', row['mode'],row['available_frames'],'images',flush=True)
        return result
    results=[]
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        for result in pool.map(job,rows):results.append(result)
    write(args.output/'results.json',results)
    print('Complete:',sum(r['completed'] for r in results),'/',len(results),flush=True)
    if not all(r['completed'] for r in results):raise SystemExit(1)

if __name__=='__main__':main()
