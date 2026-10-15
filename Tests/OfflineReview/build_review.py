#!/usr/bin/env python3
"""Build a local, separately identified app with a mandatory network sandbox.

No original checkout, app, preference domain, cookies, or AI cache is changed.
The output is deliberately outside the checkout; no Xcode project settings change.
"""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT.parent / 'Offline Review'
NAME = 'SGF Player Offline Review'
IDENTIFIER = 'com.davemarvit.SGFPlayerClean.offline-review'
HOME_DIRECTORY = Path.home()


def run(args, **kwargs):
    subprocess.run([str(a) for a in args], check=True, **kwargs)


def main():
    OUTPUT.mkdir(exist_ok=True)
    shutil.copy2(ROOT / 'Tests/OfflineReview/START HERE.txt', OUTPUT / 'START HERE.txt')
    work = Path(tempfile.mkdtemp(prefix='sgf-offline-build-'))
    # The binary embeds these protections, so Finder and Terminal launches both apply them.
    protected = [
        HOME_DIRECTORY / 'SGFPlayerClean',
        Path('/Applications/SGFPlayerClean.app'),
        HOME_DIRECTORY / 'Applications/SGFPlayerClean.app',
        HOME_DIRECTORY / 'Library/Caches/SGFPlayerClean',
        HOME_DIRECTORY / 'Library/Caches/com.davemarvit.SGFPlayerClean',
        HOME_DIRECTORY / 'Library/Preferences/com.davemarvit.SGFPlayerClean.plist',
        HOME_DIRECTORY / 'Library/Cookies/com.davemarvit.SGFPlayerClean.binarycookies',
        HOME_DIRECTORY / 'Library/HTTPStorages/com.davemarvit.SGFPlayerClean',
        HOME_DIRECTORY / 'Library/HTTPStorages/com.davemarvit.SGFPlayerClean.binarycookies',
        HOME_DIRECTORY / 'Library/Saved Application State/com.davemarvit.SGFPlayerClean.savedState',
        HOME_DIRECTORY / '.katago',
    ]
    profile = '(version 1)\n(allow default)\n(deny network*)\n'
    for path in protected:
        profile += f'(deny file-write* (subpath {json.dumps(str(path.resolve()))}))\n'
    (work / 'ReviewProfile.h').write_text('static const char *review_profile = ' + json.dumps(profile) + ';\n')
    (OUTPUT / 'network-and-file-protection.sb').write_text(profile)
    guard = work / 'OfflineGuard.o'
    run(['xcrun', 'clang', '-c', ROOT / 'Tests/OfflineReview/OfflineGuard.c', '-I', work,
         '-Wno-deprecated-declarations', '-mmacosx-version-min=13.0', '-o', guard])
    with (OUTPUT / 'build.log').open('w') as log:
        run(['xcodebuild', '-project', ROOT / 'SGFPlayerClean/SGFPlayerClean.xcodeproj',
             '-scheme', 'SGFPlayerClean', '-configuration', 'Debug',
             '-derivedDataPath', work / 'DerivedData',
             f'PRODUCT_BUNDLE_IDENTIFIER={IDENTIFIER}', f'PRODUCT_NAME={NAME}',
             'SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG SGF_OFFLINE_REVIEW',
             f'OTHER_LDFLAGS=$(inherited) {guard} -framework CoreFoundation',
             'ENABLE_DEBUG_DYLIB=NO', 'CODE_SIGN_IDENTITY=-',
             'CODE_SIGNING_ALLOWED=YES', 'build'], stdout=log, stderr=subprocess.STDOUT)
    built = work / 'DerivedData/Build/Products/Debug' / f'{NAME}.app'
    games = built / 'Contents/Resources/Review Games'
    games.mkdir()
    examples = {
        '01 Ko and one capture.sgf': '(;GM[1]FF[4]SZ[9]RU[Japanese]KM[6.5]PB[Ko example]PW[White]AB[ba][ab][bc]AW[bb][ca][db][cc];B[cb])',
        '02 Two stone handicap.sgf': '(;GM[1]FF[4]SZ[9]RU[Chinese-OGS]KM[0.5]HA[2]PL[W]PB[Handicap example]PW[White]AB[cg][gc];W[cc];B[gg];W[ee])',
        '03 Japanese self capture.sgf': '(;GM[1]FF[4]SZ[9]RU[Japanese]KM[6.5]PB[Japanese suicide check]PW[White]AB[aa]AW[ab][bb][ca])',
        '04 New Zealand self capture.sgf': '(;GM[1]FF[4]SZ[9]RU[New Zealand]KM[7]PB[NZ suicide check]PW[White]AB[aa]AW[ab][bb][ca])',
        '05 Japanese scoring.sgf': '(;GM[1]FF[4]SZ[9]RU[Japanese]KM[6.5]PB[Dave]PW[Alice]AB[da][db][dc][dd][de][df][dg][dh][di][ba][bb][bc][cc][ad]AW[fa][fb][fc][fd][fe][ff][fg][fh][fi][aa][ab])',
        '06 New Zealand scoring.sgf': '(;GM[1]FF[4]SZ[9]RU[New Zealand]KM[7]PB[Dave]PW[Alice]AB[da][db][dc][dd][de][df][dg][dh][di][ba][bb][bc][cc][ad]AW[fa][fb][fc][fd][fe][ff][fg][fh][fi][aa][ab])',
    }
    for name, sgf in examples.items():
        (games / name).write_text(sgf + '\n')
    info_path = built / 'Contents/Info.plist'
    with info_path.open('rb') as file:
        info = plistlib.load(file)
    assert info['CFBundleIdentifier'] == IDENTIFIER
    info['CFBundleDisplayName'] = NAME
    info['CFBundleName'] = NAME
    with info_path.open('wb') as file:
        plistlib.dump(info, file)
    run(['codesign', '--force', '--sign', '-', built])
    run(['codesign', '--verify', '--deep', '--strict', built])
    target = OUTPUT / f'{NAME}.app'
    if target.exists():
        # Preserve a previous review package rather than replacing anything running in place.
        previous = OUTPUT / f'{NAME}.previous.app'
        if previous.exists():
            raise SystemExit(f'Previous review already exists: {previous}; move it before rebuilding.')
        target.rename(previous)
    shutil.copytree(built, target, symlinks=True)
    samples = OUTPUT / 'Sample Games'
    samples.mkdir(exist_ok=True)
    for file in games.iterdir():
        shutil.copy2(file, samples / file.name)
    (OUTPUT / 'build-info.json').write_text(json.dumps({
        'app': str(target), 'bundleIdentifier': IDENTIFIER,
        'sourceCommit': subprocess.check_output(['git', '-C', ROOT, 'rev-parse', 'HEAD'], text=True).strip(),
        'includesUncommittedChanges': bool(subprocess.check_output(['git', '-C', ROOT, 'status', '--porcelain'], text=True).strip()),
        'buildDirectory': str(work),
        'preferences': f'~/Library/Preferences/{IDENTIFIER}.plist',
        'aiCache': f'~/Library/Caches/{IDENTIFIER}/AICache',
        'network': 'All socket networking denied before AppModel is constructed; children inherit the restriction.',
    }, indent=2) + '\n')
    with (OUTPUT / 'isolation-check.log').open('w') as log:
        run([target / 'Contents/MacOS' / info['CFBundleExecutable']],
            env={**os.environ, 'SGF_REVIEW_CHECK': '1'}, stdout=log, stderr=subprocess.STDOUT, timeout=30)
    print(target, flush=True)


if __name__ == '__main__':
    main()
