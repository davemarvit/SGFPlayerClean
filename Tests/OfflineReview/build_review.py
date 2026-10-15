#!/usr/bin/env python3
"""Build a separately identified offline or OGS observation review app.

No original checkout, app, preference domain, cookies, or AI cache is changed.
The output is deliberately outside the checkout; no Xcode project settings change.
"""
import argparse
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
# Bundled examples and engine resources must not live in a TCC-protected folder.
# Reports and exported samples can remain beside the checkout.
INSTALL_DIRECTORY = HOME_DIRECTORY / 'Applications'


def run(args, **kwargs):
    subprocess.run([str(a) for a in args], check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ogs-observer', action='store_true',
                        help='Build a separate network-enabled, observation-only review app.')
    args = parser.parse_args()
    online = args.ogs_observer
    output = ROOT.parent / ('OGS Review' if online else 'Offline Review')
    name = 'SGF Player OGS Review' if online else NAME
    identifier = 'com.davemarvit.SGFPlayerClean.ogs-review' if online else IDENTIFIER
    flag = 'SGF_OGS_REVIEW' if online else 'SGF_OFFLINE_REVIEW'
    guard_source = 'OGSReview/ReviewGuard.c' if online else 'OfflineReview/OfflineGuard.c'
    instructions = 'OGSReview/START HERE.txt' if online else 'OfflineReview/START HERE.txt'
    output.mkdir(exist_ok=True)
    shutil.copy2(ROOT / 'Tests' / instructions, output / 'START HERE.txt')
    work = Path(tempfile.mkdtemp(prefix='sgf-ogs-build-' if online else 'sgf-offline-build-'))
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
    if online:
        # The existing offline app and its data are protected too.
        protected += [INSTALL_DIRECTORY / f'{NAME}.app', OUTPUT / f'{NAME}.app',
                      HOME_DIRECTORY / f'Library/Preferences/{IDENTIFIER}.plist',
                      HOME_DIRECTORY / f'Library/Caches/{IDENTIFIER}']
    write_probe = work / 'protected-write-probe'
    write_probe.write_text('Must remain unchanged.\n')
    protected.append(write_probe)
    profile = '(version 1)\n(allow default)\n'
    if not online:
        profile += '(deny network*)\n'
    for path in protected:
        profile += f'(deny file-write* (subpath {json.dumps(str(path.resolve()))}))\n'
    header = 'static const char *review_profile = ' + json.dumps(profile) + ';\n'
    header += 'static const char *review_write_probe = ' + json.dumps(str(write_probe)) + ';\n'
    (work / 'ReviewProfile.h').write_text(header)
    (output / 'network-and-file-protection.sb').write_text(profile)
    guard = work / 'OfflineGuard.o'
    run(['xcrun', 'clang', '-c', ROOT / 'Tests' / guard_source, '-I', work,
         '-Wno-deprecated-declarations', '-mmacosx-version-min=13.0', '-o', guard])
    with (output / 'build.log').open('w') as log:
        run(['xcodebuild', '-project', ROOT / 'SGFPlayerClean/SGFPlayerClean.xcodeproj',
             '-scheme', 'SGFPlayerClean', '-configuration', 'Debug',
             '-derivedDataPath', work / 'DerivedData',
             f'PRODUCT_BUNDLE_IDENTIFIER={identifier}', f'PRODUCT_NAME={name}',
             f'SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG {flag}',
             f'OTHER_LDFLAGS=$(inherited) {guard} -framework CoreFoundation',
             'ENABLE_DEBUG_DYLIB=NO', 'CODE_SIGN_IDENTITY=-',
             'CODE_SIGNING_ALLOWED=YES', 'build'], stdout=log, stderr=subprocess.STDOUT)
    built = work / 'DerivedData/Build/Products/Debug' / f'{name}.app'
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
    for filename, sgf in examples.items():
        (games / filename).write_text(sgf + '\n')
    info_path = built / 'Contents/Info.plist'
    with info_path.open('rb') as file:
        info = plistlib.load(file)
    assert info['CFBundleIdentifier'] == identifier
    info['CFBundleDisplayName'] = name
    info['CFBundleName'] = name
    with info_path.open('wb') as file:
        plistlib.dump(info, file)
    run(['codesign', '--force', '--sign', '-', built])
    run(['codesign', '--verify', '--deep', '--strict', built])
    INSTALL_DIRECTORY.mkdir(exist_ok=True)
    target = INSTALL_DIRECTORY / f'{name}.app'
    if target.exists():
        # Preserve a previous review package rather than replacing anything running in place.
        previous = work / 'previous-review.app'
        target.rename(previous)
    shutil.copytree(built, target, symlinks=True)
    samples = output / 'Sample Games'
    samples.mkdir(exist_ok=True)
    for file in games.iterdir():
        shutil.copy2(file, samples / file.name)
    (output / 'build-info.json').write_text(json.dumps({
        'app': str(target), 'bundleIdentifier': identifier,
        'sourceCommit': subprocess.check_output(['git', '-C', ROOT, 'rev-parse', 'HEAD'], text=True).strip(),
        'includesUncommittedChanges': bool(subprocess.check_output(['git', '-C', ROOT, 'status', '--porcelain'], text=True).strip()),
        'buildDirectory': str(work),
        'preferences': f'~/Library/Preferences/{identifier}.plist',
        'aiCache': f'~/Library/Caches/{identifier}/AICache',
        'network': ('Enabled for login and observation; review client blocks game mutations.' if online else
                    'All socket networking denied before AppModel is constructed; children inherit the restriction.'),
    }, indent=2) + '\n')
    with (output / 'isolation-check.log').open('w') as log:
        run([target / 'Contents/MacOS' / info['CFBundleExecutable']],
            env={**os.environ, 'SGF_REVIEW_CHECK': '1'}, stdout=log, stderr=subprocess.STDOUT, timeout=30)
    print(target, flush=True)


if __name__ == '__main__':
    main()
