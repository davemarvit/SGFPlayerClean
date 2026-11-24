"""Read-only alignment of native safety and captured immutable broker metadata.

The recorder's observedAtUnix precedes its file reads; never treat it as a
post-read validation clock. Publication timestamps also precede manifest IO.
"""
import argparse,bisect,json,statistics
from pathlib import Path


def stats(values):
    a=sorted(values)
    if not a:return None
    return dict(count=len(a),median=statistics.median(a),p95=a[int(.95*(len(a)-1))],maximum=a[-1],minimum=a[0])


def analyze(root):
    timeline=[json.loads(line) for line in (root/'timeline.jsonl').read_text().splitlines()]
    events={}
    for file in root.glob('native-latency*.jsonl'):
        for line in file.read_text().splitlines():
            e=json.loads(line);events[(e.get('runID'),e.get('eventSequence'))]=e
    summary=json.loads((root/'summary.json').read_text())
    begin,end=summary['startUnix'],summary['endUnix']
    events=sorted((e for e in events.values() if begin-1<=e['unixSeconds']<=end+1),key=lambda e:e['unixSeconds'])
    safety=[e for e in events if e['event']=='camera_safety_ready']
    captures=sorted((e['uptimeSeconds']-e['metrics']['captureAgeSeconds'],i) for i,e in enumerate(safety))
    capture_times=[c[0] for c in captures]
    manifests={};mutated=[]
    def add(m):
        if not m or 'frame' not in m:return
        key=(m['frame']['streamEpoch'],m['frame']['frameID'])
        if key in manifests and manifests[key]!=m:mutated.append(key)
        manifests[key]=m
    for row in timeline:add(row.get('frame'))
    for file in (root/'frames').glob('*.json'):add(json.loads(file.read_text()))
    paired=[]
    for key,m in sorted(manifests.items(),key=lambda pair:pair[1]['publishedAtUnix']):
        f=m['frame'];at=bisect.bisect_left(capture_times,f['capturedAtUptime'])
        candidates=captures[max(0,at-1):at+2]
        if not candidates:continue
        nearest,index=min(candidates,key=lambda x:abs(x[0]-f['capturedAtUptime']))
        if abs(nearest-f['capturedAtUptime'])>.002:continue
        e=safety[index];v=e['metrics']
        paired.append(dict(frameID=f['frameID'],capturedAtUnix=f['capturedAtUnix'],publishedAtUnix=m['publishedAtUnix'],
                           safetyAtUnix=e['unixSeconds'],captureToManifest=m['publishedAtUnix']-f['capturedAtUnix'],
                           safetyToManifest=m['publishedAtUnix']-e['unixSeconds'],analysis=v['analysisSeconds'],
                           mainDelivery=v['mainDeliverySeconds'],analysisQueue=v['queueSeconds'],
                           hand=m.get('handObstructed'),aligned=m.get('alignmentValid'),
                           matchError=abs(nearest-f['capturedAtUptime'])))
    transitions=[];last=None
    for row in timeline:
        s=row.get('status') or {};r=row.get('request') or {}
        key=(s.get('state'),s.get('reasonCode'),s.get('sequence'),r.get('action'),r.get('sequence'),r.get('reason'))
        if key!=last:
            transitions.append(dict(recorderLoopStart=row['observedAtUnix'],statusUpdated=s.get('updatedAtUnix'),
                                    state=s.get('state'),statusReason=s.get('reasonCode'),statusSequence=s.get('sequence'),
                                    action=r.get('action'),requestReason=r.get('reason'),requestSequence=r.get('sequence')))
            last=key
    event_metrics={}
    for event in sorted(set(e['event'] for e in events)):
        items=[e for e in events if e['event']==event]
        event_metrics[event]={name:stats([e['metrics'][name] for e in items if name in e.get('metrics',{})])
                              for name in sorted(set().union(*(e.get('metrics',{}) for e in items)))}
    first_fault=next((t['statusUpdated'] for t in transitions if t['statusReason']=='camera_frame_stale'),None)
    first_hand=next((p['capturedAtUnix'] for p in paired if p['hand'] is True),None)
    metric_names=['captureToManifest','safetyToManifest','analysis','mainDelivery','analysisQueue','matchError']
    future_rows=sum(1 for row in timeline if row.get('frame') and row['frame']['publishedAtUnix']>row['observedAtUnix']+.001)
    return dict(recording=str(root),startUnix=begin,endUnix=end,immutableMetadataChanges=mutated,
                timelineRows=len(timeline),uniqueManifests=len(manifests),matchedFrames=len(paired),
                nativeSafetyRangeUnix=[safety[0]['unixSeconds'],safety[-1]['unixSeconds']] if safety else [],
                recorderLoopStartBeforeManifestTimestampRows=future_rows,
                limitations=['Recorder observedAtUnix is before file reads, not a post-read freshness check.',
                             'publishedAtUnix is sampled before manifest encode/write/rename, not actual visibility.',
                             'Sampled recording can omit intermediate publications; gaps are not proof of no publication.',
                             'Native safety-to-manifest interval combines broker wait/encode/pixel IO; installed trace does not split these stages.'],
                eventMetrics=event_metrics,pairedMetrics={name:stats([p[name] for p in paired]) for name in metric_names},
                transitions=transitions,
                largestSafetyToManifest=sorted(paired,key=lambda p:p['safetyToManifest'],reverse=True)[:15],
                firstFaultWindow=[p for p in paired if first_fault is not None and first_fault-1.5<p['capturedAtUnix']<first_fault+1],
                handWindow=[p for p in paired if first_hand is not None and first_hand-.5<p['capturedAtUnix']<first_hand+3])

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('recording',type=Path);parser.add_argument('--output',type=Path)
    args=parser.parse_args();result=analyze(args.recording.resolve());data=json.dumps(result,indent=2)+'\n'
    if args.output:args.output.write_text(data)
    else:print(data)
