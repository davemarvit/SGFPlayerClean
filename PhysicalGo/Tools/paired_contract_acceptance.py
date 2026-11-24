#!/usr/bin/env python3
"""Mandatory offline Swift -> Python -> Swift contract acceptance.

No compiler, installed app, camera, serial port or hardware backend is invoked.
Native executables must have reviewed, hash-pinned provenance matching this tree.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import uuid

sys.dont_write_bytecode = True
APP = Path(__file__).resolve().parents[2]
HARD = {'controller_fault', 'laser_transport_fault', 'laser_setup_fault',
        'laser_optical_fault', 'laser_operation_fault'}
CAMERA = {'hand_obstructed', 'camera_evidence_unavailable', 'camera_frame_stale'}
TRANSIENT = CAMERA | {'request_lease_expired'}
REQUESTS = {'swift-standby-clear.json', 'swift-standby-hand.json',
            'swift-point.json', 'swift-off.json'}
NATIVE = {'standby': 'PhysicalLaserStandbyTests',
          'continuity': 'PhysicalAIGuidanceContinuityTests'}


class AcceptanceError(RuntimeError):
    pass


def require(value, message):
    if not value:
        raise AcceptanceError(message)


def digest(path):
    require(path.is_file(), f'Missing required file: {path}')
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError) as error:
        raise AcceptanceError(f'Cannot read required JSON {path}: {error}') from error


def relative_file(root, name):
    require(isinstance(name, str) and name and not Path(name).is_absolute(),
            f'Expected a nonempty relative path: {name!r}')
    path = (root / name).resolve()
    require(path.is_relative_to(root.resolve()), f'Path escapes its artifact directory: {name}')
    return path


def native_sources(app):
    # Read the existing dependency closure; do not maintain a second build registry.
    sys.path.insert(0, str(app / 'PhysicalGo'))
    try:
        from scripts.build_sources import resolve_sources
        from scripts.test_suites import Suite
        paths = resolve_sources(app/'PhysicalGo', Suite('contract', 'app', (
            'Tests/PhysicalLaserStandbyTests.swift',
            'Tests/PhysicalAIGuidanceContinuityTests.swift')).sources(app/'PhysicalGo'))
    finally:
        sys.path.pop(0)
    paths += [app/'PhysicalGo/scripts/build_sources.py', app/'PhysicalGo/scripts/test_suites.py',
              app/'PhysicalGo/scripts/shared_regressions.py']
    return {str(path.resolve().relative_to(app.resolve())): digest(path) for path in paths}


def validate_native(app, native_root, provenance, allow_baseline=False):
    require(provenance.get('schemaVersion') == 1, 'Unsupported native provenance schema')
    require(provenance.get('kind') == 'reviewed-existing-baseline',
            'Legacy provenance supports only reviewed-existing-baseline; fresh builds require build pointers')
    require(provenance['kind'] != 'reviewed-existing-baseline' or allow_baseline,
            'Baseline artifact reuse requires explicit --allow-reviewed-baseline; it is not a fresh build')
    require(provenance.get('sourceCommit') and provenance.get('validationEvidence'),
            'Native provenance lacks source commit or validation evidence')
    require(provenance.get('sources') == native_sources(app),
            'Native source provenance differs from this worktree. Build/review matching native '
            'artifacts and update provenance; an old executable cannot certify new source.')
    executables = provenance.get('executables', {})
    require(set(executables) == set(NATIVE), 'Both mandatory native consumers need executable provenance')
    artifacts = provenance.get('artifacts', {})
    require(bool(artifacts), 'Missing native runtime artifact provenance')
    paths = {}
    for role, expected_name in NATIVE.items():
        item = executables[role]
        require(item.get('file') == expected_name, f'Unexpected executable for {role}')
        path = relative_file(native_root, item['file'])
        require(digest(path) == item.get('sha256'), f'Native executable hash mismatch: {path}')
        paths[role] = path
    for name, expected in artifacts.items():
        require(digest(relative_file(native_root, name)) == expected,
                f'Native runtime artifact hash mismatch: {name}')
    # A pinned executable must load the pinned library, not an unrecorded dylib.
    for path in paths.values():
        try:
            linked = subprocess.check_output(['otool', '-L', str(path)], text=True)
        except (OSError, subprocess.CalledProcessError) as error:
            raise AcceptanceError(f'Cannot inspect native dependencies: {error}') from error
        dependencies = [line.strip().split(' (', 1)[0] for line in linked.splitlines()[1:]]
        local = [Path(name).resolve() for name in dependencies
                 if not name.startswith(('/System/', '/usr/lib/'))]
        require(local and all(p.is_file() and any(p.samefile(relative_file(native_root, name))
                                                 for name in artifacts) for p in local),
                f'Unpinned/nonlocal runtime dependency in {path}')
    return paths


def validate_requests(folder):
    require({p.name for p in folder.glob('swift-*.json')} == REQUESTS,
            'Swift exporter did not produce all four required request fixtures')
    payloads = {name: read_json(folder/name) for name in REQUESTS}
    expected = {'swift-standby-clear.json': ('standby', False),
                'swift-standby-hand.json': ('standby', True),
                'swift-point.json': ('point', None), 'swift-off.json': ('off', None)}
    for name, (action, retain) in expected.items():
        p = payloads[name]
        require(p.get('schemaVersion') == 2 and p.get('action') == action,
                f'Wrong exported action/schema: {name}')
        require(p.get('retainOnly') is retain, f'Wrong retain-only permission: {name}')
        require(p.get('producer') and p.get('playSession') and p.get('streamEpoch') and p.get('cameraContext'),
                f'Incomplete exported scope: {name}')
    return {name: digest(folder/name) for name in sorted(REQUESTS)}


def required_fault_cases():
    cases = {}
    routes = [(route,code) for code in HARD | CAMERA for route in ('worker','supervisor','confirmation')]
    routes += [('write-guard','hand_obstructed'),('write-transport','laser_transport_fault'),
               ('coordinator','request_lease_expired'),('coordinator','obsolete_cancel')]
    routes += [('bootstrap',code) for code in TRANSIENT]
    for route,code in routes:
        for stage in ('unconfirmed','confirmed-off'):
            cases[f'{route}-{code}-{stage}.json'] = dict(route=route,stage=stage,
                reasonCode=None if code=='obsolete_cancel' else code)
    for code in TRANSIENT:
        cases[f'recovery-{code}-new-revision-off.json'] = dict(route='recovery',stage='new-revision-off',
            reasonCode=code if code in {'camera_frame_stale','request_lease_expired'} else None)
    return cases


def required_fault_names():
    return set(required_fault_cases())


def validate_status_shape(status, name):
    require(status.get('schemaVersion')==2 and status.get('mode')=='hardware', f'Unexpected host wire version/mode: {name}')
    require(type(status.get('sequence')) is int and status['sequence']>=0, f'Invalid revision: {name}')
    require(type(status.get('updatedAtUnix')) in (int,float) and math.isfinite(status['updatedAtUnix']),
            f'Invalid publication time: {name}')
    require(type(status.get('laserOn')) is bool and type(status.get('requiresNewRevision')) is bool,
            f'Missing output/revision certainty: {name}')
    play=status.get('playSession', {})
    require(isinstance(play,dict) and play.get('source') in {'ai','online'} and play.get('size') in {9,13,19},
            f'Missing active game scope: {name}')
    try:
        for value in (status.get('producer'),status.get('streamEpoch'),play.get('session')): uuid.UUID(value)
    except (TypeError,ValueError,AttributeError) as error:
        raise AcceptanceError(f'Invalid UUID scope in {name}') from error
    require(bool(status.get('cameraContext')) and bool(status.get('setupId')), f'Missing camera/setup scope: {name}')
    if status.get('state')=='off':
        since=status.get('offSinceUnix')
        require(status['laserOn'] is False and status.get('motorsHeld') is False and
                status.get('motorBusPowered') is False and type(since) in (int,float) and
                math.isfinite(since) and since<=status['updatedAtUnix'], f'Invalid full-OFF receipt: {name}')


def validate_faults(folder, firmware):
    manifest = read_json(folder/'manifest.json')
    require(manifest.get('generator') == 'Firmware/Host tests/test_gameplay_fault_contract_review.py',
            'Unrecognized host fault fixture generator')
    sources = manifest.get('sources', {})
    required_sources = {'bridge_runtime.py', 'bridge_errors.py', 'bridge_frames.py', 'bridge_thermal.py',
                        'bridge_lease.py', 'Host tests/test_gameplay_fault_contract_review.py',
                        'Host tests/test_gameplay_runtime.py'}
    require(required_sources <= set(sources), 'Missing host generator source provenance')
    for name, expected in sources.items():
        require(digest(relative_file(firmware, name)) == expected, f'Host source hash mismatch: {name}')
    entries = manifest.get('fixtures', [])
    names = [entry.get('file') for entry in entries]
    require(len(names) == len(set(names)) and set(names) == required_fault_names(),
            'Required 68-status fault coverage is missing, duplicated, or unknown')
    require({p.name for p in folder.glob('*.json')} == set(names) | {'manifest.json'},
            'Fault directory contains missing or unlisted JSON payloads')
    for entry in entries:
        path = relative_file(folder, entry['file'])
        require(digest(path) == entry.get('sha256'), f'Host fixture hash mismatch: {path.name}')
        status = read_json(path)
        validate_status_shape(status, path.name)
        code = status.get('reasonCode')
        case = required_fault_cases()[path.name]
        require(all(entry.get(key)==expected for key,expected in case.items()) and code==case['reasonCode'],
                f'Fixture filename/route/stage has wrong reason semantics: {path.name}')
        require(status.get('state') in {'fault', 'off', 'transitioning'},
                f'Unknown fault-fixture status state: {path.name}')
        require(code is None or code in HARD | TRANSIENT, f'Unknown reason code: {code}')
        require(entry.get('reasonCode') == code and type(entry.get('expectedAutoPause')) is bool and
                entry['expectedAutoPause'] == (code in HARD), f'Incorrect severity contract: {path.name}')
        expected_state = ('off' if case['stage']!='unconfirmed' else
                          'transitioning' if case['reasonCode'] is None else 'fault')
        require(status['state']==expected_state, f'Wrong state for required fixture stage: {path.name}')
        if expected_state=='transitioning':
            require(status['laserOn'] is True and status.get('illuminationConfirmed') is False and
                    'darkMotorStandbyV1' in status.get('capabilities', []) and
                    all(status.get(key) is None for key in
                        ('offSinceUnix','evidenceAfter','beamOffSinceUnix','darkEvidenceAfter')),
                    f'Transition fabricates light confirmation or darkness: {path.name}')
        require(status['requiresNewRevision'] == (case['stage']!='new-revision-off' and
                                                  'obsolete_cancel' not in path.name),
                f'Wrong admission rejection semantics: {path.name}')
    chains = manifest.get('recoverySequences', [])
    require(len(chains) == 4 and {c.get('reasonCode') for c in chains} == TRANSIENT,
            'All four ordered transient recovery chains are mandatory')
    for chain in chains:
        code = chain['reasonCode']
        require(chain == dict(reasonCode=code, faultFile=f'bootstrap-{code}-unconfirmed.json',
                              confirmedOffFile=f'bootstrap-{code}-confirmed-off.json',
                              healthyOffFile=f'recovery-{code}-new-revision-off.json'),
                f'Unexpected recovery-chain mapping for {code}')
        failed, rejected, healthy = (read_json(folder/chain[k]) for k in
                                     ('faultFile', 'confirmedOffFile', 'healthyOffFile'))
        require(failed['sequence'] == rejected['sequence'] < healthy['sequence'],
                f'Recovery chain has no genuine new revision: {code}')
        require(failed['requiresNewRevision'] is True and rejected['requiresNewRevision'] is True and
                healthy['requiresNewRevision'] is False and healthy['state'] == 'off' and
                healthy['laserOn'] is False, f'Invalid rejected/healthy OFF transition: {code}')
    return manifest


def run_stage(name, command, folder, env, timeout, expected_pattern=None, minimum=None):
    print(f'Running {name}', flush=True)
    log = folder/(name+'.log')
    try:
        with log.open('w') as output:
            result = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT,
                                    env=env, timeout=timeout, cwd=folder)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise AcceptanceError(f'{name} could not complete: {error}; log: {log}') from error
    require(result.returncode == 0, f'{name} failed (exit {result.returncode}); log: {log}')
    text = log.read_text()
    if expected_pattern:
        match = re.search(expected_pattern, text)
        require(match is not None and int(match.group(1)) >= minimum,
                f'{name} did not report mandatory coverage (minimum {minimum}); log: {log}')
        return dict(log=str(log), checks=int(match.group(1)), sha256=digest(log))
    return dict(log=str(log), sha256=digest(log))


def host_source_changes(host):
    changed = subprocess.check_output(['git', '-C', str(host), 'diff', '--name-only', 'HEAD', '--', 'Firmware'], text=True).splitlines()
    untracked = subprocess.check_output(['git', '-C', str(host), 'ls-files', '--others', '--exclude-standard', '--', 'Firmware'], text=True).splitlines()
    return [name for name in changed+untracked if name.endswith('.py')]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app-root', type=Path, default=APP, help='Exact app source tree represented by the native build receipts')
    parser.add_argument('--host-root', type=Path, required=True, help='Read-only laser repository')
    parser.add_argument('--standby-build-pointer', type=Path, help='Immutable standby executable .build.json from shared builder')
    parser.add_argument('--continuity-build-pointer', type=Path, help='Immutable continuity executable .build.json from shared builder')
    parser.add_argument('--native-root', type=Path, help='Legacy baseline binary directory (explicit opt-in only)')
    parser.add_argument('--native-provenance', type=Path, help='Legacy reviewed baseline provenance')
    parser.add_argument('--expected-host-commit', required=True, help='Reviewed full Git revision for host source')
    parser.add_argument('--allow-reviewed-baseline', action='store_true',
                        help='Explicitly permit reviewed existing binaries when their complete source manifest matches')
    parser.add_argument('--timeout', type=float, default=120, help='Maximum seconds for each offline stage')
    args = parser.parse_args(argv)
    folder = Path(tempfile.mkdtemp(prefix='physical-go-paired-contract-'))
    report = {'schemaVersion': 1, 'contractVersion': 1, 'result': 'failed', 'stages': {},
              'artifactDirectory': str(folder),
              'scope': 'Composed actual encoders/parser/runtime/publisher/native consumers; fake hardware. '
                       'Native recovery rebases scope, clock origins and watermarks; legacy recovery cases '
                       'also rebase schema2 snapshots to schema1. Not concurrent whole-process or physical validation.'}
    try:
        require(args.timeout > 0 and args.timeout <= 600, '--timeout must be in (0,600]')
        app=args.app_root.resolve()
        host = args.host_root.resolve(); firmware = host/'Firmware'
        commit = subprocess.check_output(['git', '-C', str(host), 'rev-parse', 'HEAD'], text=True).strip()
        require(commit == args.expected_host_commit, 'Host commit does not match the explicitly reviewed baseline')
        require(not host_source_changes(host),
                'Host Python source differs from its reviewed commit (tracked or untracked source changes)')
        pointers = None
        if args.standby_build_pointer or args.continuity_build_pointer:
            require(args.standby_build_pointer and args.continuity_build_pointer and
                    not args.native_root and not args.native_provenance and not args.allow_reviewed_baseline,
                    'Supply both build pointers; do not mix fresh build receipts and legacy baseline options')
            from paired_contract_provenance import validate_build_pointers
            pointers = dict(standby=args.standby_build_pointer, continuity=args.continuity_build_pointer)
            executables = validate_build_pointers(app, pointers, native_sources(app))
            provenance = dict(kind='shared-builder-format2', pointers={k:str(v.resolve()) for k,v in pointers.items()},
                              pointerSHA256={k:digest(v) for k,v in pointers.items()})
            provenance['receipts']={role:dict(pointer=read_json(path),
                runner=read_json(Path(read_json(path)['runnerReceipt'])),
                runtime=read_json(Path(read_json(path)['runtimeReceipt']))) for role,path in pointers.items()}
        else:
            require(args.native_root and args.native_provenance,
                    'Mandatory native provenance missing: provide both build pointers or explicit baseline options')
            provenance = read_json(args.native_provenance)
            executables = validate_native(app, args.native_root.resolve(), provenance, args.allow_reviewed_baseline)
        tracked = subprocess.check_output(['git', '-C', str(host), 'ls-files', '-z', '--', 'Firmware'], text=True).split('\0')
        host_sources = {name: digest(relative_file(host, name)) for name in tracked if name.endswith('.py')}
        require(host_sources, 'Host snapshot contains no tracked Python sources')
        report['nativeProvenance'] = provenance
        report['appRoot'] = str(app)
        report['hostCommit'] = commit
        report['hostPythonSources'] = host_sources
        tool_paths=[Path(__file__),Path(__file__).with_name('paired_contract_host.py'),
                    Path(__file__).with_name('paired_contract_provenance.py')]
        report['toolSources']={path.name:digest(path) for path in tool_paths}
        env = {k: v for k, v in os.environ.items()
               if not k.startswith(('PHYSICAL_GO_', 'DYLD_'))}
        env['PYTHONDONTWRITEBYTECODE'] = '1'
        env.pop('PYTHONPATH',None);env.pop('PYTHONHOME',None)
        env['PHYSICAL_GO_TEST_OUTPUT'] = str(folder/'NativeArtifacts')
        swift = folder/'SwiftRequests'; swift.mkdir()
        export_env = dict(env, PHYSICAL_GO_STANDBY_FIXTURES=str(swift))
        report['stages']['swift-export'] = run_stage('swift-export', [str(executables['standby'])],
            folder, export_env, args.timeout, r'PASS (\d+) monitored standby checks', 143)
        request_hashes = validate_requests(swift)
        request_provenance = dict(generator='PhysicalGo/Tests/PhysicalLaserStandbyTests.swift',
            generatorExecutableSHA256=digest(executables['standby']), files=request_hashes)
        (swift/'provenance.json').write_text(json.dumps(request_provenance, indent=2)+'\n')
        report['swiftRequests'] = request_provenance
        report['stages']['host-contract'] = run_stage('host-contract', [sys.executable, '-B',
            str(Path(__file__).with_name('paired_contract_host.py')), str(firmware), str(swift)],
            folder, env, args.timeout)
        report['hostStage'] = read_json(swift/'host-stage.json')
        require(report['hostStage'].get('tests')==16 and report['hostStage'].get('expiryAdapter'),
                'Host stage did not record its full test coverage and explicit expiry adapter')
        fault_manifest = validate_faults(swift/'FaultStatus', firmware)
        exported_scope=read_json(swift/'swift-standby-clear.json')
        for entry in fault_manifest['fixtures']:
            status=read_json(swift/'FaultStatus'/entry['file'])
            require(all(status.get(k)==exported_scope.get(k) for k in
                        ('producer','playSession','cameraContext','streamEpoch')),
                    f'Host status did not originate from the fresh Swift request scope: {entry["file"]}')
        basic = swift/'HostStatus'
        require({p.name for p in basic.glob('*.json')} == {f'host-{s}.json' for s in ('off', 'arming', 'holding', 'cooling')},
                'Required actual startup/holding/cooling/OFF statuses are missing')
        for path in basic.glob('*.json'):
            payload=read_json(path);validate_status_shape(payload,path.name)
            require(all(payload.get(k)==exported_scope.get(k) for k in
                        ('producer','playSession','cameraContext','streamEpoch')),
                    f'Basic host status borrowed a different request scope: {path.name}')
            require(payload.get('state') == path.stem.removeprefix('host-'),
                    f'Wrong basic state fixture: {path}')
        report['faultManifest'] = fault_manifest
        report['basicStatusHashes'] = {p.name: digest(p) for p in sorted(basic.glob('*.json'))}
        report['stages']['native-status-control'] = run_stage('native-status-control', [str(executables['standby'])],
            folder, env, args.timeout, r'PASS (\d+) monitored standby checks', 1)
        report['stages']['native-status'] = run_stage('native-status', [str(executables['standby'])],
            folder, dict(env, PHYSICAL_GO_HOST_STATUS_FIXTURES=str(basic)), args.timeout,
            r'PASS (\d+) monitored standby checks', 241)
        require(report['stages']['native-status']['checks']-report['stages']['native-status-control']['checks']>=16,
                'Native normal-status fixture block did not add its mandatory16 checks')
        report['stages']['native-recovery-control'] = run_stage('native-recovery-control', [str(executables['continuity'])],
            folder, env, args.timeout, r'PASS (\d+) automatic guidance-fault continuity checks', 1)
        report['stages']['native-recovery'] = run_stage('native-recovery', [str(executables['continuity'])],
            folder, dict(env, PHYSICAL_GO_HOST_FAULT_STATUS_FIXTURES=str(swift/'FaultStatus')), args.timeout,
            r'PASS (\d+) automatic guidance-fault continuity checks', 492)
        require(report['stages']['native-recovery']['checks']-report['stages']['native-recovery-control']['checks']>=359,
                'Native ordered recovery fixture block did not add its mandatory359 checks')
        # Close the read/use interval: inputs/artifacts changing mid-run invalidate the run.
        if pointers:
            validate_build_pointers(app, pointers, native_sources(app))
            require(all(digest(v)==provenance['pointerSHA256'][k] for k,v in pointers.items()),
                    'Native build pointer changed during acceptance')
        else:
            validate_native(app, args.native_root.resolve(), provenance, args.allow_reviewed_baseline)
        validate_faults(swift/'FaultStatus', firmware)
        require({p.name:digest(p) for p in basic.glob('*.json')}==report['basicStatusHashes'],
                'Basic host statuses changed during acceptance')
        require(validate_requests(swift) == request_hashes, 'Swift request fixtures changed during acceptance')
        require(all(digest(path)==report['toolSources'][path.name] for path in tool_paths),
                'Acceptance implementation changed during the run')
        require(all(digest(relative_file(host, name)) == expected for name, expected in host_sources.items()),
                'Host Python source changed during acceptance')
        require(not host_source_changes(host) and subprocess.check_output(
            ['git', '-C', str(host), 'rev-parse', 'HEAD'], text=True).strip() == commit,
            'Host source snapshot changed during acceptance')
        report['result'] = 'passed'
        print('PASS paired contract acceptance: mandatory producer, host and native recovery stages', flush=True)
        return 0
    except (RuntimeError, OSError, subprocess.CalledProcessError, ValueError, KeyError, TypeError) as error:
        report['error'] = str(error)
        print(f'FAIL paired contract acceptance: {error}', file=sys.stderr)
        return 1
    finally:
        path = folder/'acceptance.json'
        path.write_text(json.dumps(report, indent=2)+'\n')
        print(f'Acceptance report: {path}', flush=True)


if __name__ == '__main__':
    raise SystemExit(main())
