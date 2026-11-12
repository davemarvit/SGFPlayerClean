"""Build registered tests against one content-addressed, testable app runtime.

The registry and dependency closure remain authoritative. Native test executables
run serially through build.py so they cannot compete for the macOS GUI session.
"""
from pathlib import Path
import hashlib
import json
import subprocess

from scripts.test_suites import Suite
from scripts.build_sources import resolve_sources

MODULE = 'PhysicalGoTestRuntime'


def compile_suite(root, suite, sources, executable, target, debug=False):
    runtime = [p for p in resolve_sources(root, Suite('runtime', 'app', ()).sources(root))
               if p.name != 'TestArtifacts.swift']
    compiler = subprocess.check_output(['xcrun', 'swiftc', '--version'], stderr=subprocess.STDOUT)
    digest = hashlib.sha256(compiler + target.encode() + str(debug).encode())
    for source in runtime:
        digest.update(str(source).encode())
        digest.update(source.read_bytes())
    directory = root / '.build' / 'RegressionModules' / digest.hexdigest()
    directory.mkdir(parents=True, exist_ok=True)
    library = directory / ('lib' + MODULE + '.dylib')
    complete = directory / 'complete'
    common = ['xcrun', 'swiftc', '-swift-version', '5', '-D', 'PHYSICAL_GO', '-target', target]
    if not (complete.exists() and library.exists() and (directory / (MODULE + '.swiftmodule')).exists()):
        print('Building shared regression runtime ' + directory.name[:12], flush=True)
        subprocess.run([*common, '-Onone' if debug else '-O', '-enable-testing',
                        '-emit-library', '-emit-module', '-module-name', MODULE,
                        '-emit-module-path', str(directory / (MODULE + '.swiftmodule')),
                        *map(str, runtime), '-o', str(library)], check=True)
        complete.write_text(directory.name)
    # Preserve source-relative fixture paths when inserting the testable import.
    test_dir = directory / suite.executable
    test_dir.mkdir(exist_ok=True)
    prepared = []
    for index, source in enumerate(p for p in sources if p not in set(runtime)):
        destination = test_dir / (str(index) + '_' + source.name)
        contents = source.read_text().replace('#filePath', json.dumps(str(source)))
        destination.write_text('@testable import ' + MODULE + '\n' + contents)
        prepared.append(destination)
    subprocess.run([*common, '-Onone' if debug or not suite.optimized else '-O',
                    '-I', str(directory), '-L', str(directory), '-l' + MODULE,
                    '-Xlinker', '-rpath', '-Xlinker', str(directory),
                    *map(str, prepared), '-o', str(executable)], check=True)
