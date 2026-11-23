"""Compile shared regressions from identified, private source snapshots.

Only completed, hash-verified artifacts are published. A worktree-local lock
serializes builders; each caller runs its immutable, identified executable.
Fixtures and runtime resources still live at their original source/build paths.
"""
from contextlib import contextmanager
from dataclasses import dataclass
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from scripts.test_suites import Suite
from scripts.build_sources import resolve_sources

MODULE = 'PhysicalGoTestRuntime'
FORMAT = 2


def file_hash(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def canonical_json(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()


def identity(value):
    return hashlib.sha256(canonical_json(value)).hexdigest()


def toolchain_identity():
    """Record selected executable contents, SDK identity and relevant environment."""
    def query(*args):
        return subprocess.check_output(['xcrun', *args], stderr=subprocess.STDOUT).decode().strip()
    # Preserve argv[0] == swiftc; resolving its symlink changes driver mode.
    compiler = Path(query('--find', 'swiftc')).absolute()
    frontend = compiler.with_name('swift-frontend')
    sdk = Path(query('--sdk', 'macosx', '--show-sdk-path')).resolve()
    settings = next((sdk / name for name in ('SDKSettings.json', 'SDKSettings.plist')
                     if (sdk / name).is_file()), None)
    if not frontend.is_file() or settings is None:
        raise RuntimeError('Cannot identify Swift frontend or macOS SDK settings')
    return {
        'compiler': str(compiler), 'compilerResolved': str(compiler.resolve()),
        'compilerSHA256': file_hash(compiler),
        'frontend': str(frontend), 'frontendSHA256': file_hash(frontend),
        'version': query('swiftc', '--version'),
        'sdk': str(sdk), 'sdkVersion': query('--sdk', 'macosx', '--show-sdk-version'),
        'sdkSettings': str(settings), 'sdkSettingsSHA256': file_hash(settings),
        'environment': {key: os.environ[key] for key in (
            'DEVELOPER_DIR', 'TOOLCHAINS', 'SDKROOT', 'CPATH', 'C_INCLUDE_PATH',
            'CPLUS_INCLUDE_PATH', 'OBJC_INCLUDE_PATH', 'LIBRARY_PATH',
            'MACOSX_DEPLOYMENT_TARGET') if key in os.environ},
    }


@dataclass(frozen=True)
class Input:
    path: Path
    name: str
    contents: bytes

    def prepared(self, test=False):
        # Unlike -file-prefix-map, #sourceLocation preserves #filePath. It also
        # preserves source line numbers without replacing tokens inside strings.
        if self.contents.startswith(b'#!'):
            raise ValueError(f'Shared regression sources cannot contain a script shebang: {self.path}')
        prefix = ('@testable import ' + MODULE + '\n') if test else ''
        prefix += '#sourceLocation(file: ' + json.dumps(str(self.path), ensure_ascii=False) + ', line: 1)\n'
        return prefix.encode() + self.contents

    def record(self, test=False):
        return {'name': self.name, 'originalPath': str(self.path),
                'sha256': hashlib.sha256(self.contents).hexdigest(),
                'preparedSHA256': hashlib.sha256(self.prepared(test)).hexdigest()}


def capture_inputs(repository, paths):
    """Read once, then verify the capture did not overlap a persistent source edit."""
    inputs = []
    for path in paths:
        path = path.resolve()
        name = path.relative_to(repository).as_posix()
        inputs.append(Input(path, name, path.read_bytes()))
    for item in inputs:
        if item.path.read_bytes() != item.contents:
            raise RuntimeError(f'Source changed while taking build snapshot: {item.path}')
    return inputs


@contextmanager
def build_lock(cache):
    cache.mkdir(parents=True, exist_ok=True)
    with (cache / 'build.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


def stage_inputs(directory, inputs, test=False):
    prepared = []
    for index, item in enumerate(inputs):
        raw = directory / 'original' / item.name
        raw.parent.mkdir(parents=True, exist_ok=True)
        raw.write_bytes(item.contents)
        raw.chmod(0o444)
        # A distinct basename avoids Swift #fileID ambiguity with sourceLocation.
        destination = directory / 'prepared' / (str(index) + '_' + item.path.name)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(item.prepared(test))
        destination.chmod(0o444)
        prepared.append(destination)
    return prepared


def verify_staged_inputs(directory, inputs, test=False):
    for index, item in enumerate(inputs):
        paths = ((directory / 'original' / item.name, item.contents),
                 (directory / 'prepared' / (str(index) + '_' + item.path.name), item.prepared(test)))
        for path, expected in paths:
            if path.read_bytes() != expected:
                raise RuntimeError(f'Build snapshot was modified: {path}')


def valid_artifact(directory, manifest, required):
    try:
        receipt = json.loads((directory / 'complete.json').read_bytes())
        if receipt['manifest'] != manifest:
            return False
        recorded = receipt['files']
        if not isinstance(recorded, dict) or not all(
            isinstance(name, str) and isinstance(digest, str) and len(digest) == 64
            and all(c in '0123456789abcdef' for c in digest)
            for name, digest in recorded.items()
        ):
            return False
        if not set(required).issubset(recorded):
            return False
        if any(p.is_symlink() for p in directory.rglob('*')):
            return False
        actual = {p.relative_to(directory).as_posix() for p in directory.rglob('*')
                  if p.is_file() and p.name != 'complete.json'}
        return actual == set(recorded) and all(
            file_hash(directory / name) == digest for name, digest in recorded.items())
    except (OSError, ValueError, KeyError, TypeError):
        return False


def publish_artifact(cache, kind, manifest, required, build):
    """Called under build_lock. A failed compile never creates a complete entry."""
    parent = cache / kind
    parent.mkdir(exist_ok=True)
    destination = parent / identity(manifest)
    if valid_artifact(destination, manifest, required):
        return destination
    if destination.exists():
        shutil.rmtree(destination)
    with tempfile.TemporaryDirectory(prefix='.building-', dir=parent) as temporary:
        staging = Path(temporary)
        build(staging)
        if not all((staging / name).is_file() for name in required):
            raise RuntimeError('Compiler succeeded without all required artifacts')
        files = {p.relative_to(staging).as_posix(): file_hash(p)
                 for p in staging.rglob('*') if p.is_file()}
        (staging / 'complete.json').write_bytes(canonical_json({'manifest': manifest, 'files': files}))
        # Rename into the final namespace only after all outputs and the receipt exist.
        staging.rename(destination)
    return destination


def atomic_copy(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix='.publishing-', dir=destination.parent, delete=False) as f:
        temporary = Path(f.name)
    try:
        shutil.copy2(source, temporary)
        os.replace(temporary, destination)
    finally:
        temporary.unlink(missing_ok=True)


def compile_suite(root, suite, sources, executable, target, debug=False):
    root = root.resolve()
    repository = root.parent
    cache = root / '.build' / 'RegressionModules'
    with build_lock(cache):
        runtime = [p.resolve() for p in resolve_sources(root, Suite('runtime', 'app', ()).sources(root))
                   if p.name != 'TestArtifacts.swift']
        tests = [p.resolve() for p in sources if p.resolve() not in set(runtime)]
        all_inputs = capture_inputs(repository, [*runtime, *tests])
        runtime_inputs, test_inputs = all_inputs[:len(runtime)], all_inputs[len(runtime):]
        # Catch added/removed runtime inputs during capture as well as changed bytes.
        current = [p.resolve() for p in resolve_sources(root, Suite('runtime', 'app', ()).sources(root))
                   if p.name != 'TestArtifacts.swift']
        if current != runtime:
            raise RuntimeError('Runtime source inventory changed while taking build snapshot')
        toolchain = toolchain_identity()
        common = [toolchain['compiler'], '-swift-version', '5', '-D', 'PHYSICAL_GO',
                  '-target', target, '-sdk', toolchain['sdk']]
        configuration = {'format': FORMAT, 'builderSHA256': file_hash(__file__),
                         'toolchain': toolchain, 'commonArguments': common}

        def verify_builder():
            if file_hash(__file__) != configuration['builderSHA256'] or toolchain_identity() != toolchain:
                raise RuntimeError('Build implementation or toolchain changed during compilation')
        runtime_manifest = {**configuration, 'kind': 'runtime', 'module': MODULE,
                            'optimization': '-Onone' if debug else '-O',
                            'inputs': [p.record() for p in runtime_inputs]}
        library_name = 'lib' + MODULE + '.dylib'
        required = (library_name, MODULE + '.swiftmodule')

        def build_runtime(staging):
            print('Building shared regression runtime ' + identity(runtime_manifest)[:12], flush=True)
            prepared = stage_inputs(staging, runtime_inputs)
            subprocess.run([*common, runtime_manifest['optimization'], '-enable-testing',
                            '-emit-library', '-emit-module', '-module-name', MODULE,
                            '-emit-module-path', str(staging / (MODULE + '.swiftmodule')),
                            '-Xlinker', '-install_name', '-Xlinker', '@rpath/' + library_name,
                            *map(str, prepared), '-o', str(staging / library_name)], check=True)
            verify_staged_inputs(staging, runtime_inputs)
            verify_builder()

        runtime_dir = publish_artifact(cache, 'runtimes', runtime_manifest, required, build_runtime)
        runner_manifest = {**configuration, 'kind': 'runner', 'runtime': runtime_dir.name,
                           'runtimeArtifacts': {name: file_hash(runtime_dir / name) for name in required},
                           'executable': suite.executable,
                           'parseAsLibrary': True,
                           'optimization': '-Onone' if debug or not suite.optimized else '-O',
                           'inputs': [p.record(test=True) for p in test_inputs]}

        def build_runner(staging):
            prepared = stage_inputs(staging, test_inputs, test=True)
            subprocess.run([*common, runner_manifest['optimization'], '-parse-as-library',
                            '-I', str(runtime_dir), '-L', str(runtime_dir), '-l' + MODULE,
                            '-Xlinker', '-rpath', '-Xlinker', str(runtime_dir),
                            *map(str, prepared), '-o', str(staging / suite.executable)], check=True)
            verify_staged_inputs(staging, test_inputs, test=True)
            verify_builder()

        runner_dir = publish_artifact(cache, 'runners', runner_manifest,
                                      (suite.executable,), build_runner)
        # Keep executables in .build so Bundle.main still finds prepared resources.
        # The conventional name is retained for manual use; build.py runs the
        # identified name, avoiding a race when another caller publishes a new suite.
        identified = executable.with_name(executable.name + '-' + runner_dir.name)
        atomic_copy(runner_dir / suite.executable, identified)
        pointer = {'schemaVersion': 1, 'runnerReceipt': str(runner_dir / 'complete.json'),
                   'runtimeReceipt': str(runtime_dir / 'complete.json'),
                   'runnerIdentity': runner_dir.name,
                   'executableSHA256': file_hash(identified)}
        with tempfile.NamedTemporaryFile(dir=cache, delete=False) as f:
            pointer_file = Path(f.name)
            f.write(canonical_json(pointer))
        try:
            atomic_copy(pointer_file, identified.with_name(identified.name + '.build.json'))
        finally:
            pointer_file.unlink(missing_ok=True)
        atomic_copy(runner_dir / suite.executable, executable)
        return identified
