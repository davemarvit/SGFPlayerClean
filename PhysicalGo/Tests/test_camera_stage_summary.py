import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('summary', Path(__file__).parents[1] / 'Tools/summarize_camera_stages.py')
summary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(summary)


def event(sequence=1, run='run-a', count=4):
    metrics = {name: .01 for name in summary.STAGES}
    metrics.update(totalSeconds=.1, afterSafetySeconds=.03, capturedAtUptime=200)
    if count is not None:
        metrics['expectedStoneCount'] = count
    return dict(schemaVersion=1, source='native', runID=run, clockDomain='swift-systemUptime/' + run,
                event='camera_analysis_stages', eventSequence=sequence, uptimeSeconds=201,
                droppedEvents=0, writerFailures=0, fields={'frameID': '1', 'streamEpoch': 'epoch-a'}, metrics=metrics)


class CameraStageSummaryTests(unittest.TestCase):
    def test_workload_is_context_and_unknown_is_retained(self):
        result = summary.summarize([event(1, count=0), event(2), event(3, count=None)])
        groups = result['runs'][0]['workerTimeByExpectedOccupancy']
        self.assertEqual({k: v['count'] for k, v in groups.items()},
                         {'empty_expected': 1, 'occupied_expected': 1, 'unknown': 1})
        self.assertFalse(result['completeSession'])

    def test_runs_never_join_on_reused_frame_identity(self):
        second = event(run='run-b')
        second['uptimeSeconds'] = 100000
        runs = summary.summarize([event(), second])['runs']
        self.assertEqual(len(runs), 2)
        self.assertEqual([r['timing']['camera_analysis_stages.totalSeconds']['p50'] for r in runs], [.1, .1])

    def test_duplicate_rotations_do_not_double_count(self):
        result = summary.summarize([event(), copy.deepcopy(event())])['runs'][0]
        self.assertEqual(result['retainedEvents'], 1)

    def test_conflicting_identity_is_excluded(self):
        other = event()
        other['metrics']['capturedAtUptime'] = 5
        result = summary.summarize([event(), other])
        self.assertEqual(result['runs'], [])
        self.assertIn('conflicting', result['warnings'][0])

    def test_loss_counts_and_non_camera_events(self):
        row = event(4)
        row.update(event='request_published', droppedEvents=2, writerFailures=1)
        run = summary.summarize([event(), row])['runs'][0]
        self.assertEqual(run['knownLoss'], dict(missingRetainedEvents=2, reportedDrops=2, reportedWriterFailures=1))
        self.assertEqual(run['retainedEvents'], 2)

    def test_malformed_partition_negative_and_missing_stage_excluded(self):
        for key, value in [('poseSeconds', -1), ('totalSeconds', .2), ('afterSafetySeconds', 1)]:
            row = event()
            row['metrics'][key] = value
            run = summary.summarize([row])['runs'][0]
            self.assertEqual(run['invalidStageEvents'], 1)
            self.assertEqual(run['timing'], {})
        row = event()
        del row['metrics']['poseSeconds']
        self.assertEqual(summary.summarize([row])['runs'][0]['invalidStageEvents'], 1)

    def test_main_delay_separate_from_worker(self):
        row = event(2)
        row.update(event='camera_analysis_applied', metrics={'workerSeconds': .1, 'mainDeliverySeconds': .7})
        timing = summary.summarize([event(), row])['runs'][0]['timing']
        self.assertEqual(timing['camera_analysis_applied.mainDeliverySeconds']['maximum'], .7)
        self.assertEqual(timing['camera_analysis_stages.totalSeconds']['maximum'], .1)

    def test_largest_stage_retains_frame_identity(self):
        row = event()
        row['metrics'].update(rectificationSeconds=.5, totalSeconds=.59, afterSafetySeconds=.52)
        tail = summary.summarize([row])['runs'][0]['slowestWorkers'][0]
        self.assertEqual(tail['largestStage'], 'rectificationSeconds')
        self.assertEqual((tail['frameID'], tail['streamEpoch']), ('1', 'epoch-a'))

    def test_loader_rejects_wrong_clock_and_nonfinite_without_host_comparison(self):
        wrong_clock = event(2)
        wrong_clock['clockDomain'] = 'python-monotonic/run-a'
        nonfinite = event(3)
        nonfinite['metrics']['totalSeconds'] = float('nan')
        host = dict(event(), source='host', clockDomain='python-monotonic/run-a')
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'native.jsonl'
            path.write_text('\n'.join(json.dumps(r) for r in [event(), wrong_clock, nonfinite, host]) + '\n[]\n')
            rows, warnings = summary.load([path])
        self.assertEqual(len(rows), 1)
        self.assertEqual(len(warnings), 3)

    def test_oversize_row_never_parses_fragments(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'native.jsonl'
            path.write_bytes(b' ' * 32769 + b'\n' + json.dumps(event()).encode() + b'\n')
            rows, warnings = summary.load([path])
        self.assertEqual(rows, [])
        self.assertIn('remainder omitted', warnings[0])


if __name__ == '__main__':
    unittest.main()
