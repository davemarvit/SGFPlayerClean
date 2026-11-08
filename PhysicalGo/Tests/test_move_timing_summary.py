import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('summary', Path(__file__).resolve().parents[1] / 'Tools/summarize_move_timings.py')
summary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(summary)


class SummaryTests(unittest.TestCase):
    def test_percentiles_and_bins(self):
        values = [1, 2, 3, 4, None, float('nan')]
        stats = summary.distribution(values)
        self.assertEqual(stats['count'], 4)
        self.assertEqual(stats['mean'], 2.5)
        self.assertEqual(stats['p50'], 2.5)
        self.assertAlmostEqual(stats['p95'], 3.85)
        self.assertEqual([b['count'] for b in summary.histogram(values, [0, 1, 2, 4])], [0, 1, 2, 1])
        self.assertEqual(summary.distribution([]), {'count': 0})

    def test_legacy_manual_missing_ack_and_abandoned_attempts(self):
        def event(attempt, kind, time, **kw):
            return dict(game=42, run='a', attempt=attempt, event=kind, uptime=time,
                        time=time, point=10, size=9, color='black', **kw)
        legacy = event('old', 'move_request_written', 2, recognitionToRequestSeconds=1.2, firstClearAfterSeconds=.2)
        camera = event('camera', 'move_request_written', 5, recognitionToRequestSeconds=2.,
                       firstDetectionEvidence={'confidence': .6},
                       submissionEvidence={'confidence': .9, 'manualCorrection': False},
                       confirmationEvidence={'minimumConfidence': .85, 'manualWitnesses': 0})
        manual = event('manual', 'move_request_written', 8, recognitionToRequestSeconds=3.,
                       submissionEvidence={'confidence': 1., 'manualCorrection': False},
                       confirmationEvidence={'minimumConfidence': .8, 'manualWitnesses': 1})
        rows = [legacy, legacy, camera, manual,
                event('camera', 'server_acknowledged', 5.5, requestToObservationSeconds=.5, elapsedSeconds=2.5),
                event('failed', 'camera_candidate_seen', 9), event('failed', 'stone_removed', 12),
                dict(game=42, run='a', event='server_move_seen', uptime=13, time=13, isPass=True)]
        report = summary.summarize(rows)
        self.assertEqual(report['coverage']['submitted'], 3)
        self.assertEqual(report['coverage']['acknowledged'], 1)
        self.assertEqual(report['coverage']['attempts'], 4)
        self.assertEqual(report['coverage']['attemptOutcomes']['stone_removed'], 1)
        self.assertEqual(report['coverage']['unknownProvenance'], 1)
        self.assertEqual(report['coverage']['manualMoves'], 1)
        self.assertEqual(report['cameraConfidence']['submittedConfidence']['count'], 1)
        self.assertEqual(report['cameraConfidence']['submittedConfidence']['minimum'], .9)
        self.assertIsNone(report['moves'][0]['submittedConfidence'])
        self.assertIsNone(report['moves'][0]['submissionToAcknowledgment'])
        self.assertFalse(report['moves'][1]['geometryAvailable'])
        self.assertEqual(report['moves'][0]['coordinate'], 'B8')
        self.assertIn('Historical scores were not saved', summary.render(report))


if __name__ == '__main__':
    unittest.main()
