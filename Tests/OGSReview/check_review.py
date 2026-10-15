#!/usr/bin/env python3
"""Check compiled OGS-review defaults and UI with all networking denied."""
import json
from pathlib import Path
import plistlib
import subprocess
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
subprocess.run(['swiftc', '-target', 'arm64-apple-macosx15.5', '-parse-as-library',
                '-I', str(build / 'Products/Debug'), str(root / 'Tests/OGSReview/ReviewUI.swift'),
                *map(str, objects), '-o', str(binary)], check=True)
subprocess.run(['/usr/bin/sandbox-exec', '-f', str(profile), str(binary)], check=True, timeout=30)
