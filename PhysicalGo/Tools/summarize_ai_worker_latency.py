#!/usr/bin/env python3
"""Summarize opt-in TestWorker traces without opening the app or engine."""
import argparse
import json
import math
from pathlib import Path
import statistics

PREFIX = 'ai_test_worker_'
IDENTITY = ('workerID', 'workerRequest', 'workerStart', 'afterIdleRetention', 'moveNumber', 'boardSize')


def summarize(rows):
    requests, warnings, seen = {}, set(), set()
    legacy_returns = 0
    for row in rows:
        if not isinstance(row, dict):
            warnings.add('Non-object trace row ignored.')
            continue
        if row.get('droppedEvents', 0) or row.get('writerFailures', 0):
            warnings.add('Trace reports dropped events or writer failures; completeness is unknown.')
        event = row.get('event', '')
        if not isinstance(event, str):
            warnings.add('Invalid event name ignored.')
            continue
        signature = json.dumps(row, sort_keys=True)
        if signature in seen:
            continue
        seen.add(signature)
        if event == 'ai_engine_returned':
            legacy_returns += 1
        if event not in {PREFIX + stage for stage in ('started', 'returned', 'failed')}:
            continue
        fields = row.get('fields')
        stamp = row.get('uptimeSeconds')
        if (row.get('source') != 'native' or not isinstance(fields, dict)
                or any(not isinstance(fields.get(k), str) or not fields[k] for k in IDENTITY)
                or not isinstance(row.get('runID'), str) or not row['runID']
                or row.get('clockDomain') != 'swift-systemUptime/' + row['runID']
                or isinstance(stamp, bool) or not isinstance(stamp, (int, float)) or not math.isfinite(stamp)
                or fields['workerStart'] not in ('new', 'reused')
                or fields['afterIdleRetention'] not in ('true', 'false')
                or fields['workerStart'] == 'new' and fields['afterIdleRetention'] != 'false'):
            warnings.add('Invalid worker trace row ignored.')
            continue
        key = (row['runID'], row['clockDomain'], fields['workerRequest'])
        requests.setdefault(key, []).append(row)
    samples, incomplete, failed = [], 0, 0
    for key, events in sorted(requests.items()):
        starts = [e for e in events if e['event'] == PREFIX + 'started']
        ends = [e for e in events if e['event'] in (PREFIX + 'returned', PREFIX + 'failed')]
        if len(starts) != 1 or len(ends) != 1:
            incomplete += 1
            continue
        start, end = starts[0], ends[0]
        fields = start['fields']
        duration = end['uptimeSeconds'] - start['uptimeSeconds']
        if not math.isfinite(duration) or duration < 0 or any(fields[k] != end['fields'][k] for k in IDENTITY):
            incomplete += 1
            warnings.add('Mismatched or reversed request endpoints excluded.')
            continue
        if end['event'] == PREFIX + 'failed':
            failed += 1
            continue
        category = ('new_worker' if fields['workerStart'] == 'new' else
                    'reused_after_idle_retention' if fields['afterIdleRetention'] == 'true' else 'reused_worker')
        samples.append({'runID': key[0], **{k: fields[k] for k in IDENTITY},
                        'category': category, 'durationSeconds': duration})
    groups = {}
    for category in ('new_worker', 'reused_worker', 'reused_after_idle_retention'):
        values = [s['durationSeconds'] for s in samples if s['category'] == category]
        groups[category] = {'count': len(values), 'medianSeconds': statistics.median(values) if values else None,
                            'maxSeconds': max(values) if values else None}
    return {'schemaVersion': 1, 'scope': 'fast-test worker call, not physical move-to-reply or move-to-light',
            'completeSession': False, 'groups': groups, 'samples': samples,
            'failedRequests': failed, 'incompleteRequests': incomplete,
            'legacyEngineReturnsWithoutWorkerClassification': legacy_returns,
            'warnings': sorted(warnings), 'limits': [
                'New worker includes process/model startup; operating-system caches may already be warm.',
                'Idle retention includes pause, resume and camera freeze; it does not identify which operation occurred.',
                'Durations use paired timestamps within one native run and clock domain only.',
                'Rolling traces may omit requests; failed, mismatched and incomplete requests are excluded from timing statistics.',
                'Old engine events cannot establish cold/warm state and are not classified by elapsed time.']}


def read_rows(paths):
    total = 0
    for path in paths:
        with path.open('rb') as stream:
            while True:
                line = stream.readline(32769)
                if not line:
                    break
                total += len(line)
                if len(line) > 32768 or total > 64 * 1024 * 1024:
                    raise ValueError('Trace exceeds 32 KiB row or 64 MiB total input limit.')
                try:
                    yield json.loads(line)
                except (ValueError, UnicodeDecodeError):
                    yield None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('traces', nargs='+', type=Path)
    args = parser.parse_args()
    try:
        result = summarize(read_rows(args.traces))
    except (OSError, ValueError) as error:
        parser.error(str(error))
    print(json.dumps(result, indent=2, allow_nan=False))


if __name__ == '__main__':
    main()
