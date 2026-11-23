"""Cheap failure-path tests; no compiler, native executable or devices."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.dont_write_bytecode=True
SCRIPT=Path(__file__).resolve().parents[1]/'Tools/paired_contract_acceptance.py'
spec=importlib.util.spec_from_file_location('paired_acceptance',SCRIPT)
acceptance=importlib.util.module_from_spec(spec);spec.loader.exec_module(acceptance)


class AcceptanceCommandTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
    def tearDown(self): self.temp.cleanup()

    def stage(self, program, timeout=2):
        return acceptance.run_stage('probe',[sys.executable,'-c',program],self.root,{},timeout,
                                    r'PASS (\d+) coverage',492)

    def test_subprocess_failure_cannot_be_masked_by_pass_output(self):
        with self.assertRaisesRegex(acceptance.AcceptanceError,'exit 3'):
            self.stage('print("PASS 999 coverage");raise SystemExit(3)')

    def test_silent_optional_skip_is_not_acceptance(self):
        with self.assertRaisesRegex(acceptance.AcceptanceError,'mandatory coverage'):
            self.stage('print("PASS 133 coverage")')

    def test_missing_success_marker_is_failure(self):
        with self.assertRaisesRegex(acceptance.AcceptanceError,'mandatory coverage'):
            self.stage('print("finished")')

    def test_bounded_stage_timeout_fails(self):
        with self.assertRaisesRegex(acceptance.AcceptanceError,'could not complete'):
            self.stage('import time;time.sleep(1)',timeout=.02)

    def test_complete_marker_records_check_count_and_log_hash(self):
        result=self.stage('print("PASS 492 coverage")')
        self.assertEqual(result['checks'],492)
        self.assertEqual(result['sha256'],acceptance.digest(Path(result['log'])))

    def test_artifact_path_traversal_is_rejected(self):
        for value in ('../outside.json','/tmp/outside.json',''):
            with self.subTest(value=value),self.assertRaises(acceptance.AcceptanceError):
                acceptance.relative_file(self.root,value)

    def test_missing_requests_cannot_fall_back_to_host_golden_files(self):
        with self.assertRaisesRegex(acceptance.AcceptanceError,'all four'):
            acceptance.validate_requests(self.root)

    def test_baseline_requires_explicit_opt_in(self):
        p={'schemaVersion':1,'kind':'reviewed-existing-baseline'}
        with self.assertRaisesRegex(acceptance.AcceptanceError,'explicit --allow-reviewed-baseline'):
            acceptance.validate_native(self.root,self.root,p)

    def test_changed_native_source_rejects_old_binary(self):
        p={'schemaVersion':1,'kind':'reviewed-existing-baseline','sourceCommit':'abc',
           'validationEvidence':'reviewed','sources':{'source.swift':'old'}}
        with mock.patch.object(acceptance,'native_sources',return_value={'source.swift':'new'}):
            with self.assertRaisesRegex(acceptance.AcceptanceError,'source provenance differs'):
                acceptance.validate_native(self.root,self.root,p,True)

    def test_required_coverage_is_independent_of_manifest(self):
        cases=acceptance.required_fault_cases()
        self.assertEqual(len(cases),68)
        self.assertEqual(cases['bootstrap-hand_obstructed-unconfirmed.json']['reasonCode'],'hand_obstructed')
        self.assertIsNone(cases['recovery-hand_obstructed-new-revision-off.json']['reasonCode'])


if __name__=='__main__': unittest.main()
