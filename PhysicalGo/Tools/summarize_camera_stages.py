#!/usr/bin/env python3
"""Read bounded native traces; attribute retained tails without cross-process clocks."""
import argparse
from collections import Counter, defaultdict
import json
import math
from pathlib import Path

STAGES = ('poseSeconds', 'grayExposureSeconds', 'alignmentSeconds',
          'stoneDetectionSeconds', 'handOutlineSeconds', 'lightingSeconds',
          'safetyCallbackSeconds', 'stoneTrackingSeconds', 'stoneAspectSeconds',
          'rectificationSeconds')
EVENTS = {'camera_analysis_stages', 'camera_analysis_applied', 'camera_safety_ready',
          'camera_capture_delivery', 'laser_safety_published', 'laser_frame_published'}


def number(value):
    try:
        return type(value) in (int, float) and math.isfinite(value)
    except OverflowError:
        return False


def load(paths):
    rows, warnings = [], []
    for path in paths:
        path = Path(path)
        if path.stat().st_size > 20 * 1024 * 1024:
            warnings.append(f'{path.name}: exceeds 20 MiB bound')
            continue
        with path.open('rb') as stream:
            for line_number in range(50000):
                raw = stream.readline(32769)
                if not raw:
                    break
                if len(raw) > 32768:
                    warnings.append(f'{path.name}:{line_number + 1}: oversized row; file remainder omitted')
                    break
                try:
                    row = json.loads(raw)
                    if row.get('source') != 'native':
                        continue
                    run = row['runID']
                    if (row.get('schemaVersion') != 1 or not isinstance(run, str) or not run
                            or row['clockDomain'] != 'swift-systemUptime/' + run
                            or not number(row['uptimeSeconds'])
                            or not isinstance(row['event'], str)
                            or not isinstance(row['fields'], dict) or len(row['fields']) > 24
                            or not isinstance(row['metrics'], dict) or len(row['metrics']) > 24
                            or any(not isinstance(k, str) or not isinstance(v, str) for k, v in row['fields'].items())
                            or any(not isinstance(k, str) or not number(v) for k, v in row['metrics'].items())
                            or any(type(row.get(k)) is not int or row[k] < 0 for k in
                                   ('eventSequence', 'droppedEvents', 'writerFailures'))):
                        raise ValueError('invalid native schema')
                    rows.append(row)
                except (ValueError, KeyError, TypeError, AttributeError):
                    warnings.append(f'{path.name}:{line_number + 1}: invalid native trace row')
            else:
                warnings.append(f'{path.name}: row bound reached')
    return rows, warnings


def distribution(values):
    values = sorted(values)
    if not values:
        return {'count': 0}
    def percentile(p):
        index = (len(values) - 1) * p
        lo, hi = math.floor(index), math.ceil(index)
        return values[lo] + (values[hi] - values[lo]) * (index - lo)
    return dict(count=len(values), p50=percentile(.5), p95=percentile(.95),
                p99=percentile(.99), maximum=values[-1])


def summarize(rows, warnings=None):
    warnings = list(warnings or [])
    # Rotated files can overlap. A conflicting sequence is excluded, never
    # silently paired with another process or selected by input-file order.
    unique, conflicts = {}, set()
    for row in rows:
        key = (row['clockDomain'], row['eventSequence'])
        if key in unique and unique[key] != row:
            conflicts.add(key)
        else:
            unique[key] = row
    for key in conflicts:
        del unique[key]
    if conflicts:
        warnings.append(f'{len(conflicts)} conflicting sequence identities excluded')
    domains = defaultdict(list)
    for row in unique.values():
        domains[row['clockDomain']].append(row)
    reports = []
    for domain, events in sorted(domains.items()):
        sequences = {r['eventSequence'] for r in events}
        loss = dict(missingRetainedEvents=max(sequences)-min(sequences)+1-len(sequences),
                    reportedDrops=max(r['droppedEvents'] for r in events),
                    reportedWriterFailures=max(r['writerFailures'] for r in events))
        metrics, workloads, tails = defaultdict(list), defaultdict(list), []
        invalid = 0
        for row in events:
            if row['event'] not in EVENTS:
                continue
            values = row['metrics']
            if row['event'] == 'camera_analysis_stages':
                if (any(not number(values.get(k)) or values[k] < 0 for k in STAGES + ('totalSeconds', 'afterSafetySeconds'))
                        or abs(sum(values[k] for k in STAGES)-values['totalSeconds']) > 1e-6
                        or values['afterSafetySeconds'] > values['totalSeconds'] + 1e-6):
                    invalid += 1
                    continue
                count = values.get('expectedStoneCount')
                workload = ('occupied_expected' if count > 0 else 'empty_expected') if number(count) and count >= 0 and count == int(count) else 'unknown'
                workloads[workload].append(values['totalSeconds'])
                tails.append(dict(eventSequence=row['eventSequence'], frameID=row['fields'].get('frameID'),
                    streamEpoch=row['fields'].get('streamEpoch'), capturedAtUptime=values.get('capturedAtUptime'),
                    expectedStoneCount=count, totalSeconds=values['totalSeconds'],
                    largestStage=max(STAGES, key=lambda k: values[k]),
                    stages={k: values[k] for k in STAGES}))
            for key, value in values.items():
                if key.endswith('Seconds') and number(value) and value >= 0:
                    metrics[row['event'] + '.' + key].append(value)
        reports.append(dict(clockDomain=domain, retainedEvents=len(events), knownLoss=loss,
            eventCounts=dict(Counter(r['event'] for r in events)), invalidStageEvents=invalid,
            timing={k: distribution(v) for k, v in sorted(metrics.items())},
            workerTimeByExpectedOccupancy={k: distribution(v) for k, v in sorted(workloads.items())},
            slowestWorkers=sorted(tails, key=lambda r: r['totalSeconds'], reverse=True)[:10]))
    return dict(schemaVersion=1, warnings=warnings, runs=reports, completeSession=False,
        limitations=[
            'Only retained native events are summarized. Rolling prefixes/tails and final failures may be absent even when known loss is zero.',
            'Expected occupancy is workload context, not a fresh stone or hand-clearance observation. Older traces remain occupancy unknown.',
            'Native stage durations include scheduling. They do not measure host optical registration or CPU/syscall execution.',
            'No cross-process or cross-run subtraction, no command-to-light onset, and no claim that summed phases form an end-to-end critical path.',
            'Missing camera events or stage endpoints remain unknown; counts cannot establish hardware frame loss or sustained gameplay reliability.'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('files', nargs='+', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    rows, warnings = load(args.files)
    output = json.dumps(summarize(rows, warnings), indent=2, allow_nan=False) + '\n'
    if args.output:
        args.output.write_text(output)
    else:
        print(output, end='')


if __name__ == '__main__':
    main()
