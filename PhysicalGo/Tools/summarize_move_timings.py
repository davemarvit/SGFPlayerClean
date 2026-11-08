#!/usr/bin/env python3
"""Summarize persistent online journals (schemas 2/3), never infer absent confidence.

Usage: python3 PhysicalGo/Tools/summarize_move_timings.py --game 92223085 --output /path/report
"""
import argparse
import collections
import csv
import html
import json
import math
from pathlib import Path


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def distribution(values):
    values = sorted(v for v in values if number(v))
    if not values:
        return {"count": 0}

    def percentile(p):
        index = (len(values) - 1) * p
        lo = math.floor(index)
        hi = math.ceil(index)
        return values[lo] + (values[hi] - values[lo]) * (index - lo)

    return dict(count=len(values), mean=sum(values) / len(values), minimum=values[0],
                p50=percentile(.50), p90=percentile(.90), p95=percentile(.95),
                p99=percentile(.99), maximum=values[-1])


def histogram(values, edges):
    values = [v for v in values if number(v)]
    bins = []
    for low, high in zip(edges, edges[1:] + [None]):
        count = sum(v >= low and (high is None or v < high) for v in values)
        bins.append(dict(low=low, high=high, count=count,
                         percent=count * 100 / len(values) if values else None))
    return bins


def coordinate(point, size):
    if isinstance(point, int) and 0 <= point < size * size:
        return 'ABCDEFGHJKLMNOPQRST'[point % size] + str(size - point // size)
    return None


def summarize(rows):
    # Repeated input files/events do not double count moves. UUID + run + game
    # keep successive games/restarts and separate attempts at one point distinct.
    attempts = collections.defaultdict(list)
    for row in rows:
        if row.get('attempt'):
            attempts[(row['game'], row['run'], row['attempt'])].append(row)
    moves = []
    outcomes = collections.Counter()
    for key, events in attempts.items():
        events.sort(key=lambda r: r['uptime'])
        send = next((r for r in events if r['event'] == 'move_request_written'), None)
        ack = next((r for r in events if r['event'] == 'server_acknowledged'), None)
        outcomes['submitted' if send else events[-1]['event']] += 1
        if send is None:
            continue
        first = send.get('firstDetectionEvidence') or {}
        final = send.get('submissionEvidence') or {}
        window = send.get('confirmationEvidence') or {}
        total = send.get('recognitionToRequestSeconds')
        clear = send.get('firstClearAfterSeconds')
        moves.append(dict(game=key[0], run=key[1], attempt=key[2], request=send.get('requestID'),
            point=send['point'], coordinate=coordinate(send['point'], send['size']), color=send['color'],
            submittedAt=send['time'], acknowledged=ack is not None,
            firstSeenToSubmission=total, firstSeenToFirstClear=clear,
            firstClearToSubmission=max(0, total-clear) if number(total) and number(clear) else None,
            submissionToAcknowledgment=ack.get('requestToObservationSeconds') if ack else None,
            firstSeenToAcknowledgment=ack.get('elapsedSeconds') if ack else None,
            finalConfirmationSpan=window.get('spanSeconds'),
            firstConfidence=first.get('confidence'), submittedConfidence=final.get('confidence'),
            minimumConfirmationConfidence=window.get('minimumConfidence'),
            assignmentOffset=final.get('assignmentOffset'), placementOffset=final.get('placementOffset'),
            geometryAvailable=number(final.get('assignmentOffset')),
            manualCorrection=(final.get('manualCorrection') is True or window.get('manualWitnesses', 0) > 0)
                if final or window else None,
            clearWitnesses=window.get('clearWitnesses'), scoredWitnesses=window.get('scoredWitnesses'),
            uncertainElsewhereAtSubmission=send.get('uncertainIntersectionsAtSubmission'),
            maxObservationGap=send.get('maxObservationGapSeconds'),
            appVersion=send.get('appVersion'), sourceHash=send.get('sourceHash'),
            evidenceCaptureFolders=sorted({r['evidenceCaptureFolder'] for r in events if r.get('evidenceCaptureFolder')}),
            alignmentFailureCounts=send.get('alignmentFailureCounts', {}),
            blockers=send.get('blockers', {})))
    moves.sort(key=lambda r: r['submittedAt'])
    durations = ['firstSeenToSubmission', 'firstSeenToFirstClear', 'firstClearToSubmission',
                 'submissionToAcknowledgment', 'firstSeenToAcknowledgment', 'finalConfirmationSpan']
    scores = ['firstConfidence', 'submittedConfidence', 'minimumConfirmationConfidence']
    # Keep manual/unknown provenance out of the camera-only confidence distribution.
    camera_moves = [m for m in moves if m['manualCorrection'] is False]
    return dict(schema=1, games=sorted({r['game'] for r in rows}),
        coverage=dict(submitted=len(moves), acknowledged=sum(m['acknowledged'] for m in moves),
                      attempts=len(attempts), attemptOutcomes=dict(outcomes),
                      movesWithConfidence=sum(number(m['submittedConfidence']) for m in moves),
                      manualMoves=sum(m['manualCorrection'] is True for m in moves),
                      unknownProvenance=sum(m['manualCorrection'] is None for m in moves)),
        timing={field: distribution([m[field] for m in moves]) for field in durations},
        timingHistogram=histogram([m['firstSeenToSubmission'] for m in moves], [0, 1, 1.5, 2, 3, 5, 10]),
        cameraConfidence={field: distribution([m[field] for m in camera_moves]) for field in scores},
        confidenceHistogram=histogram([m['submittedConfidence'] for m in camera_moves], [0, .8, .85, .9, .95, 1]),
        moves=moves,
        limitations=[
            'First seen is the first uniquely classified added stone of the expected color in that attempt; it is not physical placement time. Detection failures before this point are not measured.',
            'Candidate replacements/removals start new attempts. Successful-attempt timing can understate a physical move delayed by earlier failed attempts; these are counted separately.',
            'Server acknowledgment is when this app observes the updated server board, including polling and client processing, not pure network latency.',
            'Confidence is a heuristic score, not a probability of correctness. Missing historical scores/geometry remain unknown, never zero.',
            'Confidence summaries exclude moves with manual confirmation evidence and unknown provenance. Timing includes all submitted moves; unsent attempts and missing acknowledgments are reported separately.',
            'Percentiles use linear interpolation between sorted samples. Histogram lower edges are inclusive, upper edges exclusive.'])


def render(report):
    def fmt(v):
        return f'{v:.3f}' if number(v) else '—'

    def table(headers, rows):
        return '<table><thead><tr>' + ''.join(f'<th>{html.escape(str(h))}</th>' for h in headers) + '</tr></thead><tbody>' + ''.join(
            '<tr>' + ''.join(f'<td>{html.escape(str(c))}</td>' for c in row) + '</tr>' for row in rows) + '</tbody></table>'

    labels = dict(firstSeenToSubmission='First detection → submission', firstSeenToFirstClear='First detection → first clear evidence',
                  firstClearToSubmission='First clear evidence → submission', submissionToAcknowledgment='Submission → server observed',
                  firstSeenToAcknowledgment='First detection → server observed', finalConfirmationSpan='Final confirmation window')
    stats = table(['Seconds', 'Moves', 'Mean', 'Median', 'P90', 'P95', 'P99', 'Max'],
                  [[labels[k], v['count']] + [fmt(v.get(f)) for f in ['mean', 'p50', 'p90', 'p95', 'p99', 'maximum']]
                   for k, v in report['timing'].items()])
    hist = table(['Detection → submission (seconds)', 'Moves', 'Percent'],
                 [[f"{b['low']:g}–{b['high']:g}" if b['high'] is not None else f"≥{b['low']:g}",
                   b['count'], fmt(b['percent'])] for b in report['timingHistogram']])
    scores = table(['Camera-only heuristic score', 'Moves', 'Min', 'Mean', 'Median', 'P90', 'Max'],
                   [[k, v['count']] + [fmt(v.get(f)) for f in ['minimum', 'mean', 'p50', 'p90', 'maximum']]
                    for k, v in report['cameraConfidence'].items()])
    score_hist = table(['Submitted camera score', 'Moves', 'Percent'],
                      [[f"{b['low']:g}–{b['high']:g}" if b['high'] is not None else f"≥{b['low']:g}",
                        b['count'], fmt(b['percent'])] for b in report['confidenceHistogram']])
    moves = table(['Game', 'Move point', 'Detection → send (s)', 'Send → server (s)', 'First score', 'Send score', 'Lowest final-window score', 'Manual'],
                  [[m['game'], m['coordinate'], fmt(m['firstSeenToSubmission']), fmt(m['submissionToAcknowledgment']),
                    fmt(m['firstConfidence']), fmt(m['submittedConfidence']), fmt(m['minimumConfirmationConfidence']),
                    m['manualCorrection'] if m['manualCorrection'] is not None else 'unknown'] for m in report['moves']])
    coverage = html.escape(json.dumps(report['coverage'], indent=2))
    notes = ''.join(f'<li>{html.escape(note)}</li>' for note in report['limitations'])
    return f'''<!doctype html><html lang="en"><meta charset="utf-8"><title>Physical Go move evidence</title>
<style>body{{font:16px system-ui;max-width:1150px;margin:40px auto;padding:0 24px;color:#222}}table{{border-collapse:collapse;margin:20px 0;width:100%}}th,td{{padding:8px;text-align:right;border-bottom:1px solid #ddd}}th:first-child,td:first-child{{text-align:left}}th{{background:#eee}}li{{margin:10px 0}}pre{{background:#f4f4f4;padding:16px}}</style>
<h1>Physical Go: move timing and evidence</h1><p>Games: {html.escape(str(report['games']))}. Durations describe client observations.</p>
<h2>Coverage</h2><pre>{coverage}</pre><h2>Timing</h2>{stats}<h2>Detection-to-submission distribution</h2>{hist}
<h2>Confidence</h2><p>These scores are not probabilities of correctness. Historical scores were not saved.</p>{scores}{score_hist}
<h2>Interpretation limits</h2><ul>{notes}</ul><h2>Every submitted move, in time order</h2>{moves}</html>'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, default=Path.home() / 'Library/Application Support/Physical Go/Online Bridge/Move Timing')
    parser.add_argument('--game', type=int)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    rows, unreadable = [], []
    files = sorted(args.input.glob('game-*.jsonl')) if args.input.is_dir() else [args.input]
    for file in files:
        for index, line in enumerate(file.read_text().splitlines(), 1):
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                unreadable.append(f'{file.name}:{index}')
                continue
            if args.game is None or row.get('game') == args.game:
                rows.append(row)
    if not rows:
        parser.error('No matching timing events found.')
    report = summarize(rows)
    report['unreadableLines'] = unreadable
    if unreadable:
        report['limitations'].append(f'{len(unreadable)} unreadable lines were skipped; see summary.json for locations.')
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / 'summary.json').write_text(json.dumps(report, indent=2, allow_nan=False) + '\n')
    (args.output / 'report.html').write_text(render(report))
    if report['moves']:
        with (args.output / 'moves.csv').open('w', newline='') as file:
            writer = csv.DictWriter(file, fieldnames=report['moves'][0].keys())
            writer.writeheader()
            writer.writerows(report['moves'])
    print(json.dumps(dict(coverage=report['coverage'], timing=report['timing']), indent=2))
    print(args.output / 'report.html')


if __name__ == '__main__':
    main()
