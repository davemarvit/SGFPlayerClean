"""PG04 point conversation acceptance and negative controls; fake backend only.

PHYSICAL_GO_GAMEPLAY_HOST_ROOT selects the reviewed read-only host checkout.
No camera, serial, installed app or native compiler is used.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
TOOLS = Path(__file__).resolve().parents[1]/'Tools'
HOST = Path(os.environ.get('PHYSICAL_GO_GAMEPLAY_HOST_ROOT',
    '/Users/Dave/DYNAMIXEL-Go-Pointer-worktrees/feedback-indication-stop'))
FIRMWARE = HOST/'Firmware'
sys.path[:0] = [str(FIRMWARE/'Host tests'), str(FIRMWARE)]
import test_gameplay_fault_contract_review as faults


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


host = module('pg04_host', TOOLS/'paired_contract_host.py')
acceptance = module('pg04_acceptance', TOOLS/'paired_contract_acceptance.py')


class PointConversationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.request = self.root/'swift-point.json'
        shutil.copy(faults.FIXTURES/'swift-point.json', self.request)
        self.report = host.exercise_point_conversation(faults, self.root)
        self.folder = self.root/'PointStatus'

    def validate(self):
        return acceptance.validate_points(self.folder, self.request)

    def manifest(self):
        return json.loads((self.folder/'manifest.json').read_text())

    def save_manifest(self, manifest):
        (self.folder/'manifest.json').write_text(json.dumps(manifest))

    def change_status(self, state, **changes):
        name = f'host-{state}.json'
        path = self.folder/name
        value = json.loads(path.read_text())
        value.update(changes)
        path.write_text(json.dumps(value))
        manifest = self.manifest()
        manifest['files'][name] = hashlib.sha256(path.read_bytes()).hexdigest()
        self.save_manifest(manifest)

    def rejected(self):
        with self.assertRaises(acceptance.AcceptanceError):
            self.validate()

    def test_actual_runtime_conversation_passes(self):
        self.assertEqual(self.validate(), self.report)
        self.assertEqual(len(self.report['files']), 5)
        self.assertEqual(self.report['target'], json.loads(self.request.read_text())['target'])

    def test_missing_dark_approach_cannot_hide_behind_manifest(self):
        name = 'host-approaching-dark.json'
        (self.folder/name).unlink()
        manifest = self.manifest()
        del manifest['files'][name]
        self.save_manifest(manifest)
        self.rejected()

    def test_unknown_light_cannot_be_positive_indication(self):
        self.change_status('approaching-dark', illuminationConfirmed=True)
        self.rejected()

    def test_adequate_requires_positive_feedback(self):
        self.change_status('adequate', illuminationConfirmed=False)
        self.rejected()

    def test_transition_cannot_borrow_old_feedback(self):
        self.change_status('transitioning', illuminationConfirmed=True)
        self.rejected()

    def test_old_revision_cannot_publish_after_cancellation(self):
        self.change_status('off', sequence=self.report['pointSequence'])
        self.rejected()

    def test_full_off_must_release_motor_power(self):
        self.change_status('off', motorBusPowered=True)
        self.rejected()

    def test_point_cannot_invent_dark_evidence(self):
        self.change_status('approaching-lit', darkEvidenceAfter={'frameID':1})
        self.rejected()

    def test_changed_target_is_rejected(self):
        manifest = self.manifest()
        manifest['target']['col'] += 1
        self.save_manifest(manifest)
        self.rejected()

    def test_other_game_scope_is_rejected(self):
        self.change_status('adequate', playSession=dict(source='ai', size=9,
            session='00000000-0000-0000-0000-000000000001'))
        self.rejected()

    def test_missing_late_result_rejection_is_failure(self):
        manifest = self.manifest()
        del manifest['lateFeedbackRejected']
        self.save_manifest(manifest)
        self.rejected()

    def test_source_request_change_is_rejected(self):
        value = json.loads(self.request.read_text())
        value['target']['black'] = not value['target']['black']
        self.request.write_text(json.dumps(value))
        self.rejected()


if __name__ == '__main__':
    unittest.main()
