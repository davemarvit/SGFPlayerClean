"""Source/publication races without compiling the application or operating hardware."""
import hashlib
import json
import multiprocessing
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts import shared_regressions as shared
from scripts.build_provenance import SourceState, acquire_release_lock
from scripts.test_suites import Suite


def fixture(repository):
    root = repository / 'PhysicalGo'
    (root / 'Sources').mkdir(parents=True, exist_ok=True)
    (root / 'Tests').mkdir(exist_ok=True)
    runtime = root / 'Sources/Runtime.swift'
    test = root / 'Tests/Checks.swift'
    if not runtime.exists():
        runtime.write_text('struct Value { static let number = 1 }\n')
        test.write_text('import Foundation\n@main struct Checks { static func main() {} }\n')
    return root, runtime, test


def fake_toolchain():
    return {'compiler': '/fake/swiftc', 'sdk': '/fake/sdk', 'version': 'test',
            'compilerSHA256': 'compiler-a', 'frontendSHA256': 'frontend-a'}


def fake_compile(command, check=True):
    output = Path(command[command.index('-o') + 1])
    texts = [Path(p).read_text() for p in command if p.endswith('.swift')]
    output.write_text(json.dumps({'compiled': texts}))
    output.chmod(0o755)
    if '-emit-module-path' in command:
        Path(command[command.index('-emit-module-path') + 1]).write_bytes(b'module')
    return subprocess.CompletedProcess(command, 0)


def concurrent_builder(repository, start, results):
    root, runtime, test = fixture(Path(repository))
    def compile_and_log(command, check=True):
        with (root / 'compiler-calls.jsonl').open('a') as stream:
            stream.write(json.dumps({'pid': os.getpid(), 'runtime': '-emit-library' in command}) + '\n')
        time.sleep(.04)
        return fake_compile(command, check)
    try:
        start.wait(5)
        with patch.object(shared, 'resolve_sources', return_value=[runtime]), \
             patch.object(shared, 'toolchain_identity', side_effect=fake_toolchain), \
             patch.object(shared.subprocess, 'run', side_effect=compile_and_log):
            result = shared.compile_suite(root, Suite('Checks', 'standalone', ()),
                                          [runtime, test], root / '.build/Checks', 'fake-target')
        results.put(('ok', str(result)))
    except BaseException as error:
        results.put(('error', repr(error)))


def release_lock_worker(build, results):
    lock = acquire_release_lock(Path(build))
    results.put('acquired')
    lock.close()


class SharedBuildTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repository = Path(self.temp.name)
        self.root, self.runtime, self.test = fixture(self.repository)
        self.cache = self.root / '.build/RegressionModules'
        self.suite = Suite('Checks', 'standalone', (), optimized=False)
        self.calls = []
        self.action = None
        self.toolchain = fake_toolchain()
        self.stack = []
        for mock in [patch.object(shared, 'resolve_sources', return_value=[self.runtime]),
                     patch.object(shared, 'toolchain_identity', side_effect=lambda: dict(self.toolchain)),
                     patch.object(shared.subprocess, 'run', side_effect=self.compile)]:
            self.stack.append(mock.start())
            self.addCleanup(mock.stop)

    def compile(self, command, check=True):
        self.calls.append(command)
        if self.action:
            self.action(command)
        return fake_compile(command, check)

    def build(self, debug=False, target='fake-target'):
        return shared.compile_suite(self.root, self.suite, [self.runtime, self.test],
                                    self.root / '.build/Checks', target, debug)

    def receipt(self, executable):
        pointer = json.loads(Path(str(executable) + '.build.json').read_text())
        return pointer, json.loads(Path(pointer['runnerReceipt']).read_text())

    def test_compiles_only_staged_bytes_and_caches_both_runtime_and_runner(self):
        result = self.build()
        self.assertEqual(len(self.calls), 2)
        self.assertEqual(self.build(), result)
        self.assertEqual(len(self.calls), 2)
        for command in self.calls:
            for source in (p for p in command if p.endswith('.swift')):
                self.assertIn('/.building-', source)
                self.assertNotIn(source, [str(self.runtime), str(self.test)])
        pointer, receipt = self.receipt(result)
        self.assertEqual(pointer['executableSHA256'], shared.file_hash(result))
        self.assertEqual(receipt['manifest']['runtime'], Path(pointer['runtimeReceipt']).parent.name)
        self.assertTrue(result.name.endswith(pointer['runnerIdentity']))
        self.assertEqual(result.parent, self.root / '.build')
        self.assertIn('@rpath/libPhysicalGoTestRuntime.dylib', self.calls[0])

    def test_live_edits_after_capture_do_not_relabel_or_change_compiled_inputs(self):
        original_runtime = self.runtime.read_text()
        original_test = self.test.read_text()
        def mutate(command):
            if '-emit-library' in command:
                self.runtime.write_text('struct Value { static let number = 2 }\n')
                self.test.write_text('import Foundation\n@main struct NewChecks { static func main() {} }\n')
        self.action = mutate
        first = self.build()
        pointer, runner = self.receipt(first)
        runtime = json.loads(Path(pointer['runtimeReceipt']).read_text())
        self.assertEqual(runtime['manifest']['inputs'][0]['sha256'], hashlib.sha256(original_runtime.encode()).hexdigest())
        self.assertEqual(runner['manifest']['inputs'][0]['sha256'], hashlib.sha256(original_test.encode()).hexdigest())
        self.assertIn(original_test, json.loads(first.read_text())['compiled'][0])
        self.action = None
        self.assertNotEqual(first, self.build())
        self.assertEqual(len(self.calls), 4)
        self.assertIn(original_test, json.loads(first.read_text())['compiled'][0])

    def test_test_only_edit_reuses_runtime_and_has_distinct_runner(self):
        first = self.build()
        self.test.write_text(self.test.read_text() + '// later test\n')
        second = self.build()
        self.assertNotEqual(first, second)
        self.assertEqual(sum('-emit-library' in call for call in self.calls), 1)
        self.assertEqual(len(self.calls), 3)

    def test_configuration_and_compiler_identity_invalidate_cache(self):
        first = self.build()
        debug = self.build(debug=True)
        self.assertNotEqual(first, debug)
        self.assertNotEqual(debug, self.build(debug=True, target='other-target'))
        self.toolchain['compilerSHA256'] = 'compiler-b-same-version'
        self.assertNotEqual(first, self.build())
        self.assertEqual(len(self.calls), 8)

    def test_failed_compile_never_publishes_complete_artifact(self):
        def fail(command):
            raise subprocess.CalledProcessError(1, command)
        self.action = fail
        with self.assertRaises(subprocess.CalledProcessError):
            self.build()
        self.assertEqual(list(self.cache.rglob('complete.json')), [])
        self.assertEqual(list(self.cache.rglob('.building-*')), [])
        self.action = None
        self.build()
        self.assertEqual(len(list(self.cache.rglob('complete.json'))), 2)

    def test_failed_runner_preserves_good_runtime_and_previous_executable(self):
        previous = self.build()
        self.test.write_text(self.test.read_text() + '// next candidate\n')
        def fail_runner(command):
            if '-emit-library' not in command:
                raise subprocess.CalledProcessError(1, command)
        self.action = fail_runner
        with self.assertRaises(subprocess.CalledProcessError):
            self.build()
        self.assertEqual((self.root / '.build/Checks').read_bytes(), previous.read_bytes())
        self.assertEqual(len(list((self.cache / 'runtimes').iterdir())), 1)

    def test_corrupt_outputs_are_rebuilt_instead_of_reused(self):
        result = self.build()
        pointer, _ = self.receipt(result)
        runtime_dir = Path(pointer['runtimeReceipt']).parent
        (runtime_dir / ('lib' + shared.MODULE + '.dylib')).write_bytes(b'corrupt')
        self.build()
        self.assertEqual(sum('-emit-library' in call for call in self.calls), 2)
        runner_dir = Path(pointer['runnerReceipt']).parent
        (runner_dir / 'Checks').write_bytes(b'corrupt')
        self.build()
        self.assertEqual(len(self.calls), 4)

    def test_snapshot_modification_by_compiler_is_rejected(self):
        def mutate_snapshot(command):
            path = next(Path(p) for p in command if p.endswith('.swift'))
            path.chmod(0o644)
            path.write_text('// altered compiler input\n')
        self.action = mutate_snapshot
        with self.assertRaisesRegex(RuntimeError, 'snapshot was modified'):
            self.build()
        self.assertEqual(list(self.cache.rglob('complete.json')), [])

    def test_rebuilt_same_input_runtime_outputs_require_a_new_runner(self):
        def changing_outputs(command, check=True):
            self.calls.append(command)
            result = fake_compile(command, check)
            if '-emit-library' in command:
                output = Path(command[command.index('-o') + 1])
                output.write_text(output.read_text() + '\nUUID-' + str(len(self.calls)))
            return result
        with patch.object(shared.subprocess, 'run', side_effect=changing_outputs):
            first = self.build()
            first_pointer, first_runner = self.receipt(first)
            runtime_dir = Path(first_pointer['runtimeReceipt']).parent
            library = runtime_dir / ('lib' + shared.MODULE + '.dylib')
            library.write_bytes(b'corrupt runtime requires a rebuild')
            second = self.build()
        second_pointer, second_runner = self.receipt(second)
        self.assertEqual(first_pointer['runtimeReceipt'], second_pointer['runtimeReceipt'])
        self.assertNotEqual(first, second)
        self.assertNotEqual(first_runner['manifest']['runtimeArtifacts'], second_runner['manifest']['runtimeArtifacts'])
        self.assertEqual(second_runner['manifest']['runtimeArtifacts'][library.name], shared.file_hash(library))
        self.assertEqual(set(second_runner['manifest']['runtimeArtifacts']),
                         {library.name, shared.MODULE + '.swiftmodule'})
        self.assertEqual(len(self.calls), 4)

    def test_toolchain_change_mid_compile_is_rejected(self):
        self.action = lambda command: self.toolchain.update(compilerSHA256='changed')
        with self.assertRaisesRegex(RuntimeError, 'toolchain changed'):
            self.build()
        self.assertEqual(list(self.cache.rglob('complete.json')), [])

    def test_source_location_preserves_tokens_inside_strings_and_existing_directives(self):
        text = '#sourceLocation(file: "custom.swift", line: 12)\nlet literal = #"#filePath"#\nlet location = #filePath\n'
        item = shared.Input(self.runtime, 'PhysicalGo/Sources/Runtime.swift', text.encode())
        prepared = item.prepared(test=True).decode()
        self.assertTrue(prepared.endswith(text))
        self.assertIn(str(self.runtime), prepared)
        self.assertEqual(prepared.count('@testable import ' + shared.MODULE), 1)
        with self.assertRaisesRegex(ValueError, 'shebang'):
            shared.Input(self.runtime, 'script.swift', b'#!/usr/bin/swift\n').prepared()

    def test_incomplete_success_and_malformed_receipt_cannot_be_cached(self):
        with patch.object(shared.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)):
            with self.assertRaisesRegex(RuntimeError, 'required artifacts'):
                self.build()
        self.build()
        receipt = next((self.cache / 'runtimes').glob('*/complete.json'))
        receipt.write_text('{')
        self.build()
        self.assertEqual(sum('-emit-library' in call for call in self.calls), 2)

    def test_changed_inventory_during_capture_is_rejected_before_compile(self):
        with patch.object(shared, 'resolve_sources', side_effect=[[self.runtime], [self.runtime, self.test]]):
            with self.assertRaisesRegex(RuntimeError, 'inventory changed'):
                self.build()
        self.assertEqual(self.calls, [])

    def test_changed_bytes_while_snapshot_is_read_are_rejected(self):
        original_read = Path.read_bytes
        count = 0
        def changing_read(path):
            nonlocal count
            contents = original_read(path)
            if path.resolve() == self.runtime.resolve():
                count += 1
                if count == 1:
                    path.write_text('// changed during capture\n')
            return contents
        with patch.object(Path, 'read_bytes', changing_read):
            with self.assertRaisesRegex(RuntimeError, 'while taking build snapshot'):
                self.build()
        self.assertEqual(self.calls, [])


class SourceStateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.first = self.root / 'First.swift'
        self.second = self.root / 'Second.swift'
        self.first.write_text('first')
        self.second.write_text('second')
        self.paths = [self.first, self.second]
        self.state = SourceState.capture(self.paths)

    def test_unchanged_snapshot_and_exact_content_hash(self):
        self.state.assert_unchanged(self.paths)
        self.assertEqual(self.state.content_hash, hashlib.sha256(b'firstsecond').hexdigest())

    def test_changed_content_and_restored_content_are_detected(self):
        self.first.write_text('edited')
        with self.assertRaisesRegex(RuntimeError, 'refusing to sign'):
            self.state.assert_unchanged(self.paths)
        self.first.write_text('first')
        with self.assertRaisesRegex(RuntimeError, 'refusing to sign'):
            self.state.assert_unchanged(self.paths)

    def test_added_removed_reordered_and_missing_inputs_are_detected(self):
        for paths in [self.paths[::-1], self.paths[:1], self.paths + [self.root / 'New.swift']]:
            with self.assertRaisesRegex(RuntimeError, 'inventory/order changed'):
                self.state.assert_unchanged(paths)
        self.first.unlink()
        with self.assertRaisesRegex(RuntimeError, 'unavailable'):
            self.state.assert_unchanged(self.paths)


class ProcessOwnershipTests(unittest.TestCase):
    def test_competing_builders_publish_once_and_receive_same_identified_result(self):
        with tempfile.TemporaryDirectory() as folder:
            root, _, _ = fixture(Path(folder))
            ctx = multiprocessing.get_context('spawn')
            start, results = ctx.Event(), ctx.Queue()
            workers = [ctx.Process(target=concurrent_builder, args=(folder, start, results)) for _ in range(2)]
            for worker in workers:
                worker.start()
            start.set()
            received = [results.get(timeout=15) for _ in workers]
            for worker in workers:
                worker.join(timeout=15)
                self.assertEqual(worker.exitcode, 0)
            self.assertTrue(all(kind == 'ok' for kind, _ in received), received)
            self.assertEqual(received[0][1], received[1][1])
            calls = [json.loads(line) for line in (root / 'compiler-calls.jsonl').read_text().splitlines()]
            self.assertEqual(len(calls), 2)
            self.assertEqual(len({call['pid'] for call in calls}), 1)

    def test_release_output_lock_serializes_separate_processes(self):
        with tempfile.TemporaryDirectory() as folder:
            ctx = multiprocessing.get_context('spawn')
            results = ctx.Queue()
            lock = acquire_release_lock(Path(folder))
            worker = ctx.Process(target=release_lock_worker, args=(folder, results))
            worker.start()
            time.sleep(.2)
            self.assertTrue(results.empty())
            lock.close()
            self.assertEqual(results.get(timeout=10), 'acquired')
            worker.join(timeout=10)
            self.assertEqual(worker.exitcode, 0)


@unittest.skipUnless(os.environ.get('PHYSICAL_GO_PROVENANCE_SWIFT_SMOKE') == '1',
                     'Set PHYSICAL_GO_PROVENANCE_SWIFT_SMOKE=1 for a tiny real Swift module/runner')
class RealSwiftSmokeTests(unittest.TestCase):
    def test_staged_module_runner_load_after_temporary_directory_is_gone(self):
        # This intentionally compiles only two tiny files, never the application.
        with tempfile.TemporaryDirectory() as folder:
            root, runtime, test = fixture(Path(folder))
            runtime.write_text('import Foundation\nstruct Probe {\n'
                               'static let number = 41\nstatic let literal = #"#filePath"#\n'
                               'static let location = #filePath\n}\n')
            test.write_text('import Foundation\n@testable import PhysicalGoTestRuntime\n'
                            '@main struct Checks { static func main() {\n'
                            'precondition(Probe.number == 41)\nprecondition(Probe.literal == "#filePath")\n'
                            'precondition(Probe.location == CommandLine.arguments[1])\n'
                            'print("real snapshot smoke passed")\n}}\n')
            target = subprocess.check_output(['uname', '-m'], text=True).strip() + '-apple-macosx14.0'
            with patch.object(shared, 'resolve_sources', return_value=[runtime]):
                executable = shared.compile_suite(root, Suite('Checks', 'standalone', ()),
                                                  [runtime, test], root / '.build/Checks', target, debug=True)
            self.assertEqual(list((root / '.build/RegressionModules').rglob('.building-*')), [])
            result = subprocess.run([str(executable), str(runtime.resolve())], check=True,
                                    text=True, capture_output=True)
            self.assertIn('real snapshot smoke passed', result.stdout)


if __name__ == '__main__':
    unittest.main()
