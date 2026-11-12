"""Verify source coverage and aggregate CLI behavior without invoking Swift."""
import contextlib
import io
from pathlib import Path
import re
import runpy
import subprocess
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.test_suites import SUITES
from scripts.build_sources import resolve_sources


class BuildTests(unittest.TestCase):
    def test_every_suite_has_unique_existing_sources(self):
        executables = set()
        for name, suite in SUITES.items():
            with self.subTest(suite=name):
                sources = resolve_sources(ROOT, suite.sources(ROOT))
                self.assertEqual(len(sources), len(set(sources)))
                self.assertNotIn(suite.executable, executables)
                executables.add(suite.executable)
                self.assertEqual(1, sum(bool(re.search(r'@main\b', p.read_text())) for p in sources))

    def test_all_regression_entry_points_are_registered(self):
        registered = {ROOT / name for suite in SUITES.values() for name in suite.tests}
        tools = {'InspectSample.swift', 'KokoroVoiceTests.swift', 'Preview.swift'}
        for path in (ROOT / 'Tests').glob('*.swift'):
            if re.search(r'@main\b', path.read_text()) and path.name not in tools:
                self.assertIn(path, registered, f'Unregistered regression: {path.name}')

    def invoke(self, arguments, failed_flag=None):
        calls = []
        self.environments = []
        def run(command, **kwargs):
            calls.append(command)
            self.environments.append(kwargs.get("env", {}))
            return subprocess.CompletedProcess(command, 1 if failed_flag in command else 0)
        output = io.StringIO()
        with patch.object(sys, 'argv', [str(ROOT / 'build.py'), *arguments]), \
             patch('subprocess.run', side_effect=run), \
             contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            with self.assertRaises(SystemExit) as result:
                runpy.run_path(str(ROOT / 'build.py'), run_name='__main__')
        return result.exception.code, calls, output.getvalue()

    def test_multiple_flags_run_every_suite_and_report_failure(self):
        code, calls, output = self.invoke(['--camera-test', '--test', '--debug-tests'], '--camera-test')
        self.assertEqual(1, code)
        self.assertEqual(2, len(calls))
        self.assertTrue(all('--debug-tests' in call for call in calls))
        self.assertIn('--test', calls[-1])
        self.assertIn('1/2 suites passed', output)

    def test_all_tests_includes_registry_checks_and_all_suites(self):
        code, calls, _ = self.invoke(['--all-tests'])
        self.assertEqual(0, code)
        self.assertEqual(len(SUITES) + 1, len(calls))
        self.assertEqual(str(ROOT / 'Tests/test_build.py'), calls[0][1])
        self.assertEqual({'--' + name for name in SUITES}, {call[2] for call in calls[1:]})

    def test_aggregate_uses_tracked_shared_runtime(self):
        code, calls, _ = self.invoke(['--all-tests'])
        self.assertEqual(0, code)
        self.assertTrue(all(env.get('PHYSICAL_GO_SHARED_REGRESSIONS') == '1'
                            for env in self.environments[1:]))

    def test_invalid_tool_combinations_do_not_build(self):
        for arguments in [ ['--test', '--preview'], ['--test', '--camera-test', '--saved-observations'] ]:
            code, calls, _ = self.invoke(arguments)
            self.assertEqual(2, code)
            self.assertFalse(calls)

    def test_listing_does_not_build(self):
        code, calls, output = self.invoke(['--list-tests'])
        self.assertEqual(0, code)
        self.assertFalse(calls)
        self.assertEqual({'--' + name for name in SUITES}, set(output.splitlines()))


if __name__ == '__main__':
    unittest.main()
