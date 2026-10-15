#!/usr/bin/env python3
"""Check compiled OGS-review defaults and UI with all networking denied."""
import json
import argparse
from pathlib import Path
import plistlib
import subprocess
import struct
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
out = root.parent / 'OGS Review'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('source', nargs='?', default='ReviewUI.swift')
parser.add_argument('--main-build-info', type=Path, help='Link probes to a normal Release build; never launch its main executable.')
args = parser.parse_args()
info = json.loads((args.main_build_info or (out / 'build-info.json')).read_text())
configuration = info.get('configuration', 'Debug')
build = Path(info['buildDirectory']) / 'DerivedData/Build'
objects = list((build / f'Intermediates.noindex/SGFPlayerClean.build/{configuration}/SGFPlayerClean.build/Objects-normal/arm64').glob('*.o'))
objects = [p for p in objects if p.name != 'SGFPlayerCleanApp.o']
folder = Path(tempfile.mkdtemp(prefix='sgf-ogs-ui-'))
if args.main_build_info:
    # Whole-module optimization can place shared helper functions in the app's
    # entry-point object. Keep those helpers, but rename its C entry point in a
    # temporary object copy so only the probe's main runs. The built app is untouched.
    original = build / f'Intermediates.noindex/SGFPlayerClean.build/{configuration}/SGFPlayerClean.build/Objects-normal/arm64/SGFPlayerCleanApp.o'
    data = bytearray(original.read_bytes())
    if struct.unpack_from('<I', data)[0] != 0xFEEDFACF:
        raise RuntimeError('Expected a 64-bit Mach-O object')
    offset = 32
    renamed = False
    for _ in range(struct.unpack_from('<I', data, 16)[0]):
        command, size = struct.unpack_from('<II', data, offset)
        if command == 2:  # LC_SYMTAB
            symbols, count, strings, length = struct.unpack_from('<IIII', data, offset + 8)
            if strings + length != len(data):
                raise RuntimeError('Unexpected object string table layout')
            for index in range(count):
                entry = symbols + index * 16
                name_offset = struct.unpack_from('<I', data, entry)[0]
                start = strings + name_offset
                if data[start:data.index(0, start)] == b'_main':
                    name = b'_sgf_release_main\0'
                    data.extend(name)
                    struct.pack_into('<I', data, entry, length)
                    struct.pack_into('<I', data, offset + 20, length + len(name))
                    renamed = True
                    break
            break
        offset += size
    if not renamed:
        raise RuntimeError('Main entry point not found')
    patched = folder / 'ReleaseEntryHelpers.o'
    patched.write_bytes(data)
    objects.append(patched)
app = folder / 'Probe.app'
binary = app / 'Contents/MacOS/Probe'
binary.parent.mkdir(parents=True)
(app / 'Contents/Resources').symlink_to(Path(info['app']) / 'Contents/Resources')
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'com.davemarvit.SGFPlayerClean.ogs-ui-probe',
    'CFBundleExecutable': 'Probe', 'CFBundlePackageType': 'APPL'}))
profile = folder / 'offline.sb'
profile.write_text((out / 'network-and-file-protection.sb').read_text() + '\n(deny network*)\n')
source = (root / 'Tests/OGSReview' / args.source).resolve()
extras = []
if source.parent.name == 'UI':
    # Exercise the older board/scoring regressions against the current OGS build,
    # with a separate identity and networking still denied. Never rebuild/install
    # the user's offline app just to run these checks.
    content = source.read_text().replace('SGF_Player_Offline_Review', 'SGF_Player_OGS_Review')
    content = content.replace('com.davemarvit.SGFPlayerClean.offline-ui-probe', 'com.davemarvit.SGFPlayerClean.ogs-ui-probe')
    content = content.replace('precondition(', 'reviewRequire(')
    content += '\nprivate func reviewRequire(_ ok: @autoclosure () -> Bool, _ message: String = "Check failed") { if !ok() { fputs("FAIL: \\(message)\\n", stderr); exit(1) } }\n'
    translated = folder / source.name
    translated.write_text(content)
    if source.name == 'ScoringDisplay.swift':
        # The standalone examples are compiled only into the offline app. Include
        # those display fixtures in this probe; the scoring panel remains linked
        # from the current production build.
        scoring = (root / 'SGFPlayerClean/Views/OGSScoringPanel.swift').read_text()
        fixtures = scoring.split('enum OfflineScoringExample:', 1)[1].split('#endif', 1)[0]
        extra = folder / 'ScoringFixtures.swift'
        extra.write_text('import SwiftUI\n@testable import SGF_Player_OGS_Review\nenum OfflineScoringExample:' + fixtures)
        extras = [str(extra)]
    source = translated
if args.main_build_info:
    # Main app objects use their real compilation conditions, but the probe has a
    # disposable bundle ID, fake transports, and the same network/file restrictions.
    for original in [source, *map(Path, extras)]:
        translated = folder / original.name
        translated.write_text(original.read_text().replace('SGF_Player_OGS_Review', info['module']))
        if original == source:
            source = translated
    extras = [str(folder / Path(item).name) for item in extras]
subprocess.run(['swiftc', '-D', 'SGF_OGS_REVIEW', '-target', 'arm64-apple-macosx15.5', '-parse-as-library',
                '-I', str(build / f'Products/{configuration}'), str(source), *extras,
                *map(str, objects), '-o', str(binary)], check=True)
# Each probe starts with its own defaults, independent of earlier UI checks.
# This is the disposable probe domain, never either installed review app's settings.
subprocess.run(['/usr/bin/defaults', 'delete', 'com.davemarvit.SGFPlayerClean.ogs-ui-probe'],
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
subprocess.run(['/usr/bin/sandbox-exec', '-f', str(profile), str(binary)], check=True, timeout=30)
