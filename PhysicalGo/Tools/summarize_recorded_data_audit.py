#!/usr/bin/env python3
"""Summarize replay agreement, explicitly not independent recognition accuracy."""
import argparse
import html
import json
from pathlib import Path


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('results',type=Path)
    args=parser.parse_args();root=args.results
    results=json.loads((root/'results.json').read_text())
    later=json.loads((root/'initial-references.json').read_text())
    rows=[];details=[]
    for r in results:
        if 'replay' not in r:continue
        replay=r['replay'];initial=r['initial_moves']
        actual=replay['savedPoints']+replay['pendingPoints']
        comparisons=json.loads((root/r['session']/'move-comparison.json').read_text())
        extended_by=None
        if r['additional_current_moves']:
            witnesses=[ref for ref in later if len(ref['points'])>=len(actual) and ref['points'][:len(actual)]==actual]
            if witnesses:
                ref=min(witnesses,key=lambda q:len(q['points']));extended_by=ref['session']
                first=initial+len(comparisons)
                comparisons += [dict(move=i+1,reference=ref['points'][i],current=actual[i],state='saved' if i<replay['moves'] else 'pending',reference_source='later initial SGF '+ref['session']) for i in range(first,len(actual))]
        row=dict(session=r['session'],initial_moves_excluded=initial,reference_moves=len(comparisons),
            matching_saved=sum(p['reference']==p['current'] and p['state']=='saved' for p in comparisons),
            matching_pending=sum(p['reference']==p['current'] and p['state']=='pending' for p in comparisons),
            not_retained=sum(p['state']=='not retained' for p in comparisons),
            disagreements=sum(p['state']!='not retained' and p['reference']!=p['current'] for p in comparisons),
            extension_reference=extended_by)
        rows.append(row)
        details.extend(dict(session=r['session'],**p) for p in comparisons)
    totals={k:sum(r[k] for r in rows) for k in ['reference_moves','matching_saved','matching_pending','not_retained','disagreements']}
    assert totals['reference_moves']==sum(totals[k] for k in ['matching_saved','matching_pending','not_retained','disagreements'])
    summary=dict(archives=len(results),analyzed_frames=sum(r['analyzed_frames'] for r in results),
        available_frames_reprocessed=sum(r['available_frames'] for r in results),missing_frames=sum(r['missing_frames'] for r in results),
        continuous_archives=len(rows),totals=totals,sessions=rows,
        limitations=[
            'Sequence agreement with earlier recognizer SGFs/pending histories; not independent annotation of every physical placement.',
            'Initial seeded moves excluded. Continuous clips cover disjoint move ranges within their games; retained photo-only archives are not pooled as additional moves.',
            'Fourteen additional current moves match later archived initial SGFs. Other omitted or unlogged physical moves are not automatically included in the denominator.',
            'Reference endings need review, particularly D228C8EC and A6AF9918. Visible later additions/capture removals are not fully represented by the archived move histories.',
            'Saved alignment, thresholds and control events are replayed. Grid discovery and camera scheduling are not rerun.',
            'No recorded manual classifications or simulated centering are supplied to continuous pixel replay.',
            'Per-frame classification counts on unlabeled photos are not accuracy estimates.'
        ])
    (root/'comparison-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    (root/'compared-moves.json').write_text(json.dumps(details,indent=2)+'\n')
    table=''.join('<tr>'+''.join('<td>'+html.escape(str(r[k]))+'</td>' for k in ['session','reference_moves','matching_saved','matching_pending','not_retained','disagreements'])+'</tr>' for r in rows)
    page='''<!doctype html><meta charset="utf-8"><title>Current algorithm replay audit</title>
<style>body{font:17px system-ui;max-width:1050px;margin:40px auto;padding:0 24px;line-height:1.5;color:#20252b}table{border-collapse:collapse;width:100%}td,th{padding:9px;text-align:right;border-bottom:1px solid #ddd}td:first-child,th:first-child{text-align:left}.note{background:#f2f4f6;padding:18px;border-radius:8px}a{color:#145a9d}</style>
<h1>Current algorithm replay audit — Physical Go 0.75</h1>'''
    page+=f'<p>Reprocessed <strong>{summary["available_frames_reprocessed"]:,} camera images</strong> across {len(results)} archives. {summary["missing_frames"]:,} older analyzed frames are no longer available. {len(rows)} complete clips support continuous pixel-to-recorder replay.</p>'
    page+='<p class="note"><strong>These are reference-agreement results, not a ground-truth accuracy claim.</strong> Earlier recognizer histories can contain mistakes or omit physical moves. No user training labels were changed.</p>'
    page+='<table><tr><th>Clip</th><th>Reference moves</th><th>Matching saved</th><th>Matching pending</th><th>Not retained</th><th>Disputed pending</th></tr>'+table
    page+='<tr><th>Total</th>'+''.join('<th>'+str(totals[k])+'</th>' for k in ['reference_moves','matching_saved','matching_pending','not_retained','disagreements'])+'</tr></table>'
    n=totals['reference_moves']
    if n:
        page+=f"<p>{totals['matching_saved']}/{n} ({totals['matching_saved']/n:.1%}) automatically recorded in agreement; {totals['matching_pending']}/{n} ({totals['matching_pending']/n:.1%}) agree but remain pending. {totals['not_retained']} are not retained; {totals['disagreements']} differ from the old reference.</p>"
    notes=root/'review-notes.json'
    if notes.exists():
        page+='<h2>Review findings</h2><ul>'+''.join('<li>'+html.escape(x)+'</li>' for x in json.loads(notes.read_text()))+'</ul>'
    page+='<h2>Limits</h2><ul>'+''.join('<li>'+html.escape(x)+'</li>' for x in summary['limitations'])+'</ul>'
    page+='<p>Detailed machine-readable records: comparison-summary.json, compared-moves.json, inventory.json, engines.json and per-session logs/replays in this folder.</p>'
    (root/'report.html').write_text(page)
    print(json.dumps(summary,indent=2))

if __name__=='__main__':main()
