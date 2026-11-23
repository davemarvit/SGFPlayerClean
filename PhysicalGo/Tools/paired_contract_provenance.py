"""Read-only adapter for shared_regressions format2 build receipts.

The builder owns artifact creation and the manifest schema. This adapter verifies
its receipts; it neither compiles nor manufactures build attestations.
"""
import hashlib
import json
from pathlib import Path
import re
import subprocess


class ProvenanceError(RuntimeError):
    pass


def need(value, message):
    if not value: raise ProvenanceError(message)


def sha(path):
    need(path.is_file(), f'Missing build artifact: {path}')
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    try: value=json.loads(path.read_text())
    except (OSError, ValueError) as error: raise ProvenanceError(f'Unreadable build receipt {path}: {error}') from error
    need(isinstance(value,dict), f'Build receipt must be an object: {path}')
    return value


def inside(root, name):
    need(isinstance(name,str) and name and not Path(name).is_absolute(), f'Invalid receipt file name: {name!r}')
    path=(root/name).resolve()
    need(path.is_relative_to(root.resolve()), f'Receipt artifact escapes its directory: {name}')
    return path


def identity(manifest):
    return hashlib.sha256(json.dumps(manifest,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()


def load_receipt(path, kind, app):
    receipt=read(path)
    manifest=receipt.get('manifest', {})
    need(isinstance(manifest,dict), f'Invalid manifest object: {path}')
    need(manifest.get('format')==2 and manifest.get('kind')==kind, f'Wrong format/kind in {path}')
    need(manifest.get('builderSHA256')==sha(app/'PhysicalGo/scripts/shared_regressions.py'),
         'Build receipt does not match the requested shared builder')
    need(isinstance(manifest.get('toolchain'),dict) and manifest['toolchain'] and
         isinstance(manifest.get('commonArguments'),list) and manifest['commonArguments'] and
         all(isinstance(v,str) for v in manifest['commonArguments']), 'Build receipt lacks toolchain/arguments')
    files=receipt.get('files', {})
    need(isinstance(files,dict) and files, f'Empty/invalid build artifact manifest: {path}')
    for name, expected in files.items():
        need(sha(inside(path.parent,name))==expected, f'Changed build artifact: {name}')
    inputs=manifest.get('inputs', [])
    need(isinstance(inputs,list) and inputs and all(isinstance(p,dict) and isinstance(p.get('name'),str) for p in inputs),
         'Missing/invalid build source inputs')
    need(len({p['name'] for p in inputs})==len(inputs), 'Duplicate build source inputs')
    for item in inputs:
        name=item['name']
        current=inside(app,name)
        need(sha(current)==item.get('sha256'), f'Compiled source differs from requested source: {name}')
        original_path=item.get('originalPath')
        need(isinstance(original_path,str) and Path(original_path).is_absolute() and
             Path(original_path)==Path(original_path).resolve() and
             Path(original_path).is_file() and Path(original_path).samefile(current) and
             Path(original_path).parent.resolve().samefile(current.parent.resolve()) and
             Path(original_path).name==current.name,
             f'Original source/resource path differs from requested tree: {name}')
        original='original/'+name
        need(files.get(original)==item['sha256'], f'Missing original source snapshot: {name}')
        prepared=item.get('preparedSHA256')
        need(prepared and any(n.startswith('prepared/') and h==prepared for n,h in files.items()),
             f'Missing prepared source snapshot: {name}')
    return receipt, identity(manifest)


def linked_paths(executable):
    try:
        dependencies=subprocess.check_output(['otool','-L',str(executable)],text=True)
        commands=subprocess.check_output(['otool','-l',str(executable)],text=True)
    except (OSError,subprocess.CalledProcessError) as error:
        raise ProvenanceError(f'Cannot inspect native linkage: {error}') from error
    rpaths=re.findall(r'cmd LC_RPATH\s+cmdsize \d+\s+path (.+?) \(offset',commands)
    def expand(value):
        for marker in ('@loader_path','@executable_path'):
            if value==marker or value.startswith(marker+'/'):
                return executable.parent/value.removeprefix(marker).lstrip('/')
        return Path(value)
    result=[]
    for line in dependencies.splitlines()[1:]:
        name=line.strip().split(' (',1)[0]
        if name.startswith(('/System/','/usr/lib/')): continue
        if name.startswith('@rpath/'):
            candidates=[expand(p)/name.removeprefix('@rpath/') for p in rpaths]
            path=next((p for p in candidates if p.is_file()),None)
            need(path is not None, f'Unresolved native runtime: {name}')
        else: path=expand(name)
        need(path.is_absolute() and path.is_file(), f'Unresolved native dependency: {name}')
        result.append(path.resolve())
    return result


def validate_build_pointers(app, pointers, expected_sources):
    """Return immutable binaries only when runner/runtime/source/linkage match."""
    expected_names={'standby':'PhysicalLaserStandbyTests','continuity':'PhysicalAIGuidanceContinuityTests'}
    need(set(pointers)==set(expected_names), 'Both native build pointers are mandatory')
    executables={}; observed_sources={}; runtimes=set()
    expected_swift={n:h for n,h in expected_sources.items() if n.endswith('.swift')}
    for role, pointer_path in pointers.items():
        pointer_path=Path(pointer_path).resolve(); pointer=read(pointer_path)
        need(pointer.get('schemaVersion')==1, 'Unsupported build-pointer schema')
        need(isinstance(pointer.get('runnerReceipt'),str) and isinstance(pointer.get('runtimeReceipt'),str),
             'Build pointer has invalid receipt paths')
        runner_path=Path(pointer['runnerReceipt'])
        runtime_path=Path(pointer['runtimeReceipt'])
        need(runner_path.is_absolute() and runtime_path.is_absolute(), 'Build receipt pointers must be absolute')
        runner, runner_id=load_receipt(runner_path,'runner',app)
        runtime, runtime_id=load_receipt(runtime_path,'runtime',app)
        need(pointer.get('runnerIdentity')==runner_id and runner['manifest'].get('runtime')==runtime_id,
             'Runner/runtime manifest identity mismatch')
        need(runner['manifest'].get('executable')==expected_names[role], 'Wrong native suite in build receipt')
        need(runtime['manifest'].get('module')=='PhysicalGoTestRuntime', 'Wrong shared runtime module')
        need(runner['manifest']['toolchain']==runtime['manifest']['toolchain'], 'Runner and runtime toolchains differ')
        runtime_outputs={name:runtime['files'].get(name) for name in
                         ('libPhysicalGoTestRuntime.dylib','PhysicalGoTestRuntime.swiftmodule')}
        need(all(runtime_outputs.values()) and runner['manifest'].get('runtimeArtifacts')==runtime_outputs,
             'Runner does not pin the exact runtime library/module outputs it compiled against')
        need(pointer_path.name.endswith('.build.json'), 'Expected identified executable build pointer')
        executable=Path(str(pointer_path).removesuffix('.build.json'))
        file_hash=sha(executable)
        need(file_hash==pointer.get('executableSHA256'), 'Identified native executable hash mismatch')
        need(runner['files'].get(expected_names[role])==file_hash,
             'Identified executable is absent from its runner receipt')
        libraries=[inside(runtime_path.parent,n) for n in runtime['files'] if n.endswith('.dylib')]
        need(len(libraries)==1, 'Expected exactly one attested shared runtime library')
        links=linked_paths(executable)
        need(len(links)==1 and links[0].samefile(libraries[0]), 'Native executable loads an unattested runtime')
        for receipt in (runner,runtime):
            for item in receipt['manifest']['inputs']:
                previous=observed_sources.setdefault(item['name'],item['sha256'])
                need(previous==item['sha256'], 'Runner/runtime source snapshots disagree')
        runtimes.add(runtime_id);executables[role]=executable
    need(len(runtimes)==1, 'Mandatory native suites use different runtime snapshots')
    need(observed_sources==expected_swift, 'Build receipts omit or add source inputs relative to requested native suites')
    return executables
