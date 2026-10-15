#!/usr/bin/env python3
"""Check compiled OGS-review defaults and UI with all networking denied."""
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
out = root.parent / 'OGS Review'
info = json.loads((out / 'build-info.json').read_text())
build = Path(info['buildDirectory']) / 'DerivedData/Build'
objects = list((build / 'Intermediates.noindex/SGFPlayerClean.build/Debug/SGFPlayerClean.build/Objects-normal/arm64').glob('*.o'))
objects = [p for p in objects if p.name != 'SGFPlayerCleanApp.o']
folder = Path(tempfile.mkdtemp(prefix='sgf-ogs-ui-'))
app = folder / 'Probe.app'
binary = app / 'Contents/MacOS/Probe'
binary.parent.mkdir(parents=True)
(app / 'Contents/Resources').symlink_to(Path(info['app']) / 'Contents/Resources')
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'com.davemarvit.SGFPlayerClean.ogs-ui-probe',
    'CFBundleExecutable': 'Probe', 'CFBundlePackageType': 'APPL'}))
profile = folder / 'offline.sb'
profile.write_text((out / 'network-and-file-protection.sb').read_text() + '\n(deny network*)\n')
source = (root / 'Tests/OGSReview' / (sys.argv[1] if len(sys.argv) > 1 else 'ReviewUI.swift')).resolve()
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
subprocess.run(['swiftc', '-D', 'SGF_OGS_REVIEW', '-target', 'arm64-apple-macosx15.5', '-parse-as-library',
                '-I', str(build / 'Products/Debug'), str(source), *extras,
                *map(str, objects), '-o', str(binary)], check=True)
# Each probe starts with its own defaults, independent of earlier UI checks.
# This is the disposable probe domain, never either installed review app's settings.
subprocess.run(['/usr/bin/defaults', 'delete', 'com.davemarvit.SGFPlayerClean.ogs-ui-probe'],
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
subprocess.run(['/usr/bin/sandbox-exec', '-f', str(profile), str(binary)], check=True, timeout=30)
