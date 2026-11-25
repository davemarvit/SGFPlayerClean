import copy
import unittest
from summarize_ai_worker_latency import summarize


def pair(request='q', worker='w', start='new', retained='false', run='r', duration=8.2):
    fields = dict(workerID=worker, workerRequest=request, workerStart=start,
                  afterIdleRetention=retained, moveNumber='2', boardSize='19')
    row = dict(source='native', runID=run, clockDomain='swift-systemUptime/' + run,
               fields=fields, event='ai_test_worker_started', uptimeSeconds=100.0)
    end = copy.deepcopy(row)
    end.update(event='ai_test_worker_returned', uptimeSeconds=100.0 + duration)
    return [row, end]


class SummaryTests(unittest.TestCase):
    def test_actual_state_not_timing_classifies_worker(self):
        rows = pair(duration=.01) + pair('q2', start='reused', duration=20) + pair('q3', start='reused', retained='true', duration=.2)
        result = summarize(rows)
        self.assertEqual([s['category'] for s in result['samples']],
                         ['new_worker', 'reused_worker', 'reused_after_idle_retention'])
        self.assertFalse(result['completeSession'])

    def test_rotated_duplicate_input_is_counted_once(self):
        rows = pair()
        self.assertEqual(summarize(rows + rows)['groups']['new_worker']['count'], 1)

    def test_cross_run_endpoints_never_join(self):
        rows = [pair()[0], pair(run='other')[1]]
        result = summarize(rows)
        self.assertEqual(result['incompleteRequests'], 2)
        self.assertEqual(result['samples'], [])

    def test_failed_cancelled_request_is_not_success(self):
        rows = pair()
        rows[1]['event'] = 'ai_test_worker_failed'
        result = summarize(rows)
        self.assertEqual(result['failedRequests'], 1)
        self.assertEqual(result['samples'], [])

    def test_obsolete_worker_cannot_pair_with_replacement(self):
        rows = pair()
        rows[1]['fields']['workerID'] = 'replacement'
        self.assertEqual(summarize(rows)['incompleteRequests'], 1)

    def test_incomplete_and_conflicting_endpoints_excluded(self):
        rows = pair()
        conflict = copy.deepcopy(rows[1])
        conflict['uptimeSeconds'] += 1
        self.assertEqual(summarize(rows + [conflict])['incompleteRequests'], 1)
        self.assertEqual(summarize(rows[:1])['incompleteRequests'], 1)

    def test_legacy_events_are_unknown(self):
        result = summarize([dict(event='ai_engine_returned', metrics=dict(durationSeconds=.1))])
        self.assertEqual(result['legacyEngineReturnsWithoutWorkerClassification'], 1)
        self.assertEqual(result['samples'], [])

    def test_invalid_clock_loss_and_nonfinite(self):
        rows = pair()
        rows[1]['uptimeSeconds'] = float('nan')
        rows[0]['writerFailures'] = 1
        result = summarize(rows + [None])
        self.assertEqual(result['samples'], [])
        self.assertEqual(len(result['warnings']), 3)
        rows = pair()
        rows[1]['clockDomain'] = 'python-monotonic/r'
        self.assertEqual(summarize(rows)['samples'], [])

    def test_malformed_event_and_overflow_cannot_crash_report(self):
        self.assertEqual(summarize([{'event': []}])['samples'], [])
        rows = pair()
        rows[0]['uptimeSeconds'] = -1e308
        rows[1]['uptimeSeconds'] = 1e308
        self.assertEqual(summarize(rows)['incompleteRequests'], 1)

    def test_reversed_time_excluded(self):
        self.assertEqual(summarize(pair(duration=-1))['incompleteRequests'], 1)


if __name__ == '__main__':
    unittest.main()
