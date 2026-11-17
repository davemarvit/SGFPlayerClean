#!/usr/bin/env python3
"""Offline ablation of rim-only hold clearance. Never emits clock press evidence."""
import argparse,collections,copy,json,math
from pathlib import Path
from local_quality_lab import digest

class RimClearance:
    def __init__(self,depth=.2,seconds=1.5):
        self.depth=depth;self.seconds=seconds;self.last=None;self.since=None;self.edge=None
    def step(self,row):
        time=row['time'];result=row['result'];edge=result.get('edge');depth=result.get('depth')
        continuous=self.last is not None and 0<time-self.last<=.65 and not row.get('gap',False)
        if not continuous or edge!=self.edge:self.since=None
        self.last=time;self.edge=edge
        eligible=(row['poseClear'] and result.get('obstructed') is True and
                  depth is not None and math.isfinite(depth) and 0<depth<=self.depth)
        if not eligible:self.since=None
        elif self.since is None:self.since=time
        proposal=eligible and time-self.since>=self.seconds
        return {'proposedClear':bool(proposal),'clockAuthority':False,'pressEstimate':None,
                'sourceTimingUnchanged':copy.deepcopy(result.get('estimate')),
                'reason':'rim-only timeout candidate' if proposal else 'retain original result'}

def run(a):
    rows=json.loads(a.replay.read_text());events=[json.loads(l) for l in (a.incident/'static-board/events.jsonl').open()]
    frames={v['frameID']:v for v in events if v['event']=='frame'}
    for v in events:
        if v['event']=='operation finished':
            rows.append({'case':'incident-static','fault':'archived-state','frame':v['frameID'],'time':frames[v['frameID']]['captureUptime'],
                         'truth':'clear','poseClear':v.get('handPose')=={'hands':[],'reliable':True},'result':v['handOutline']})
    decisions=[];summary={}
    for depth,seconds in [(.2,.8),(.2,1.5),(.2,3.0),(.1,1.5)]:
        variant=f'depth-{depth}-wait-{seconds}';states={};stats=collections.defaultdict(collections.Counter)
        for row in rows:
            key=(row['case'],row['fault']);policy=states.setdefault(key,RimClearance(depth,seconds));decision=policy.step(row)
            assert decision['sourceTimingUnchanged']==row['result'].get('estimate')
            group='incident' if row['case']=='incident-static' else 'synthetic' if row['case'].startswith('synthetic') else 'recorded'
            stats[group]['frames']+=1
            if row['result'].get('obstructed') is False and row['truth']=='hand':stats[group]['baselineFalseClear']+=1
            if decision['proposedClear']:
                stats[group]['proposedClear']+=1
                stats[group]['newFalseClear' if row['truth']=='hand' else 'knownClearRelief' if row['truth']=='clear' else 'unlabeledProposal']+=1
            decisions.append({'variant':variant,**row,**decision})
        summary[variant]={'groups':dict(stats),'promote':False,
                          'reason':'Reject: absence of pose plus a shallow stationary component cannot distinguish lingering fingertips from this incident.'}
    a.output.mkdir(parents=True,exist_ok=True)
    (a.output/'hand-decisions.json').write_text(json.dumps(decisions,indent=2)+'\n')
    (a.output/'hand-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    inputs=[a.replay,a.incident/'static-board/events.jsonl',Path(__file__)]
    (a.output/'hand-inputs.json').write_text(json.dumps({str(p):digest(p) for p in inputs},indent=2)+'\n')
    print(json.dumps(summary,indent=2))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--replay',type=Path,required=True);p.add_argument('--incident',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    if a.output.resolve().is_relative_to(Path(__file__).resolve().parents[2]):raise ValueError('Use external output storage')
    run(a)
