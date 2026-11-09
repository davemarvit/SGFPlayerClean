#!/usr/bin/env python3
"""Build an independent app, referencing authoritative Go models without copying them."""
from pathlib import Path
import argparse, hashlib, os, plistlib, re, subprocess, shutil, sys
from scripts.test_suites import SUITES
from scripts.build_sources import resolve_sources
root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--stone-appearance-audit', type=Path)
parser.add_argument('--voice-assets', action='store_true')
parser.add_argument('--replay-session', nargs=2, type=Path, metavar=('SESSION','NEW_OUTPUT_FOLDER'))
parser.add_argument('--saved-observations', action='store_true')
parser.add_argument('--replay-diagnostic', nargs=2, metavar=('SESSION','FRAME'))
parser.add_argument('--replay-recording', nargs=3, type=Path, metavar=('SGF','JOURNAL','OUTPUT'))
parser.add_argument('--preview', action='store_true')
parser.add_argument('--inspect-sample', type=Path)
for flag in SUITES:
    parser.add_argument('--' + flag, action='store_true')
parser.add_argument('--all-tests', action='store_true', help='Run every registered regression suite; summarize all failures')
parser.add_argument('--list-tests', action='store_true', help='List regression suites without building')
parser.add_argument('--debug-tests', action='store_true', help='Compile tests without optimization for faster iteration')
args = parser.parse_args()
if args.list_tests:
    print('\n'.join('--' + name for name in SUITES))
    raise SystemExit(0)
selected = list(SUITES) if args.all_tests else [name for name in SUITES if getattr(args, name.replace('-', '_'))]
tools_selected = [name for name in ('voice_assets', 'stone_appearance_audit', 'replay_session', 'replay_diagnostic', 'replay_recording', 'inspect_sample', 'preview') if getattr(args, name)]
if len(tools_selected) > 1 or (selected and tools_selected):
    parser.error('Choose regression suites or one tool action, not both.')
if args.saved_observations and not args.replay_session:
    parser.error("--saved-observations requires --replay-session")
if args.all_tests or len(selected) > 1:
    failures = []
    total = len(selected)
    if args.all_tests:
        total += 1
        result = subprocess.run([sys.executable, str(root / 'Tests/test_build.py')])
        if result.returncode:
            failures.append('build registry')
    for name in selected:
        print(f'\nRunning --{name}', flush=True)
        result = subprocess.run([sys.executable, str(Path(__file__).resolve()), '--' + name, *(['--debug-tests'] if args.debug_tests else [])])
        if result.returncode:
            failures.append(name)
    print(f'\n{total - len(failures)}/{total} suites passed', flush=True)
    if failures:
        print('Failed: ' + ', '.join(failures))
    raise SystemExit(1 if failures else 0)
selected_suite = SUITES[selected[0]] if selected else None
build = root / '.build'
build.mkdir(exist_ok=True)
shared = [root.parent / 'SGFPlayerClean/Models' / f for f in ['OGSModels.swift', 'OGSScoringState.swift']]
if selected_suite:
    executable = build / selected_suite.executable
    sources = selected_suite.sources(root)
elif args.voice_assets:
    executable = build / 'KokoroVoiceTests'
    sources = [root / 'Sources/KokoroSpeech.swift', root / 'Tests/KokoroVoiceTests.swift']
elif args.stone_appearance_audit:
    executable = build / 'StoneAppearanceAudit'
    sources = shared + [root / 'Sources' / f for f in ['BoardVision.swift', 'StoneGeometry.swift', 'BoardAppearanceDetector.swift', 'StoneAppearanceModel.swift']] + [root / 'Tools/StoneAppearanceAudit.swift']
elif args.replay_session:
    executable = build / 'ReplayDiagnosticSession'
    sources = shared + [root.parent / 'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [root / 'Sources' / f for f in ['BoardVision.swift', 'StoneGeometry.swift', 'BoardAppearanceDetector.swift', 'LocalMoveEvidence.swift', 'MoveObservationHistory.swift', 'RecordingWarningMonitor.swift', 'GameRecorder.swift']] + [root / 'Tools/ReplayDiagnosticSession.swift']
elif args.replay_diagnostic:
    executable = build / 'ReplayDiagnostic'
    sources = shared + [root / 'Sources/BoardVision.swift', root / 'Sources/StoneGeometry.swift', root / 'Sources/BoardAppearanceDetector.swift', root / 'Sources/AutoGridDetector.swift', root / 'Tools/ReplayDiagnostic.swift']
elif args.replay_recording:
    executable = build / 'ReplayRecording'
    sources = shared + [root.parent / 'SGFPlayerClean/Models/SGFPlayerEngine.swift', root / 'Sources/BoardVision.swift', root / 'Sources/StoneGeometry.swift', root / 'Sources/LocalMoveEvidence.swift', root / 'Sources/MoveObservationHistory.swift', root / 'Sources/RecordingWarningMonitor.swift', root / 'Sources/GameRecorder.swift', root / 'Tools/ReplayRecording.swift']
elif args.inspect_sample:
    executable = build / 'InspectSample'
    sources = shared + [root / 'Sources/BoardVision.swift', root / 'Sources/StoneGeometry.swift', root / 'Sources/BoardAppearanceDetector.swift', root / 'Tests/InspectSample.swift']
elif args.preview:
    executable = build / 'PhysicalGoPreview'
    sources = shared + [root.parent / 'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [p for p in sorted((root / 'Sources').glob('*.swift')) if p.name != 'PhysicalGoApp.swift'] + [root / 'Tests/Preview.swift']
else:
    app = build / 'Physical Go.app'
    (app / 'Contents/MacOS').mkdir(parents=True, exist_ok=True)
    (app / 'Contents/Resources').mkdir(exist_ok=True)
    executable = app / 'Contents/MacOS/PhysicalGo'
    sources = shared + [root.parent / 'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + sorted((root / 'Sources').glob('*.swift'))
    plist = dict(CFBundleIdentifier='com.davemarvit.PhysicalGo', CFBundleName='Physical Go', CFBundleDisplayName='Physical Go', CFBundleExecutable='PhysicalGo', CFBundlePackageType='APPL', CFBundleIconFile='PhysicalGo.icns', CFBundleShortVersionString='0.126', CFBundleVersion='127', LSMinimumSystemVersion='14.0', NSHighResolutionCapable=True, NSCameraUsageDescription='Physical Go uses your camera to recognize stones on your Go board. Images are processed on this Mac.', NSCameraUseContinuityCameraDeviceType=True, PhysicalGoCaptureDirectory=str(root / 'Captures'), PhysicalGoSourceHash=hashlib.sha256(b''.join((p.read_bytes() for p in sources))).hexdigest())
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(plist))
sources = resolve_sources(root, sources)
if executable.name == 'PhysicalGo':
    icon_master=root/'Resources/AppIcon/PhysicalGo.png'
    icon_file=root/'Resources/PhysicalGo.icns'
    icon_builder=root/'scripts/build_icon.py'
    if not icon_file.exists() or icon_file.stat().st_mtime < max(icon_master.stat().st_mtime,icon_builder.stat().st_mtime):
        subprocess.run(['python3',str(icon_builder)],check=True)
    shutil.copy2(icon_file,app/'Contents/Resources/PhysicalGo.icns')
    for name in ['analysis.cfg','kata1-b18.bin.gz']:
        shutil.copy2(root.parent/'SGFPlayerClean/Resources'/name,app/'Contents/Resources'/name)
    plist['PhysicalGoSourceHash']=hashlib.sha256(b''.join(p.read_bytes() for p in sources)).hexdigest()
    (app/'Contents/Info.plist').write_bytes(plistlib.dumps(plist))
if root/'Sources/KokoroSpeech.swift' in sources:
    subprocess.run(['python3',str(root/'scripts/prepare_kokoro.py')],check=True)
    resource_destination=app/'Contents/Resources' if executable.name=='PhysicalGo' else build
    for name in ['Kokoro','KokoroResources.bundle']:
        shutil.copytree(root/'Resources'/name,resource_destination/name,dirs_exist_ok=True)
    if executable.name=='PhysicalGo':
        if not (root/'Resources/Kokoro/audio/manifest.json').exists():
            raise SystemExit('Generate bundled countdowns first: python3 PhysicalGo/build.py --voice-assets')
        plist['PhysicalGoSourceHash']=hashlib.sha256(b''.join(p.read_bytes() for p in sources)).hexdigest()
        (app/'Contents/Info.plist').write_bytes(plistlib.dumps(plist))
subprocess.run(['xcrun','swiftc','-swift-version','5','-D','PHYSICAL_GO','-Onone' if selected_suite and (args.debug_tests or not selected_suite.optimized) else '-O','-target',subprocess.check_output(['uname','-m'],text=True).strip()+'-apple-macosx14.0', *map(str,sources), '-o',str(executable)],check=True)
if args.voice_assets:
    subprocess.run([str(executable),str(root/"Resources/Kokoro")],check=True,cwd=root.parent)
    raise SystemExit(0)
if selected_suite:
    subprocess.run([str(executable)],check=True,cwd=root.parent)
    raise SystemExit(0)
if args.replay_session:
    subprocess.run([str(executable),*map(lambda p:str(p.resolve()),args.replay_session),*(['--saved-observations'] if args.saved_observations else [])],check=True,cwd=root.parent)
elif args.replay_diagnostic:
    subprocess.run([str(executable),str(Path(args.replay_diagnostic[0]).resolve()),args.replay_diagnostic[1]],check=True,cwd=root.parent)
elif args.replay_recording:
    subprocess.run([str(executable),*map(lambda p:str(p.resolve()),args.replay_recording)],check=True,cwd=root.parent)
elif args.inspect_sample:
    subprocess.run([str(executable), str(args.inspect_sample.resolve())], check=True, cwd=root.parent)
elif args.stone_appearance_audit:
    subprocess.run([str(executable),str(args.stone_appearance_audit.resolve())],check=True,cwd=root.parent)
elif args.preview:
    subprocess.run([str(executable)],check=True,cwd=root.parent)
else:
    # TCC camera grants identify the signed app across updates. Ad-hoc signatures
    # use a per-build hash, so do not silently fall back to them for installed apps.
    identity = os.environ.get('PHYSICAL_GO_SIGN_IDENTITY')
    if not identity:
        listing = subprocess.check_output(['security','find-identity','-v','-p','codesigning'],text=True)
        identities = re.findall(r'\b([0-9A-F]{40}) "([^"]+)"',listing)
        for prefix in ['Developer ID Application:', 'Apple Development:']:
            matches = [fingerprint for fingerprint,name in identities if name.startswith(prefix)]
            if len(matches) == 1:
                identity = matches[0]
                break
            if len(matches) > 1:
                raise SystemExit('Multiple signing identities found. Set PHYSICAL_GO_SIGN_IDENTITY to the intended certificate name or fingerprint.')
    if not identity:
        raise SystemExit('A code-signing certificate is required to preserve camera permission across updates. Set PHYSICAL_GO_SIGN_IDENTITY; use "-" only for an intentional ad-hoc test build.')
    if identity == '-':
        print('Warning: explicit ad-hoc build; camera permission may be requested again after updates.')
    subprocess.run(['codesign','--force','--sign',identity,'--timestamp=none','--identifier','com.davemarvit.PhysicalGo',str(app)],check=True)
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
    print(app)
