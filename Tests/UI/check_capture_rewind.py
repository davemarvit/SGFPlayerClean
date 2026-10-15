#!/usr/bin/env python3
"""Run the real app model and hosted views from the last offline review build.
Uses a separate test bundle/preferences and the review's network-deny sandbox.
"""
import json
import plistlib
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
out = root.parent / 'Offline Review'
info = json.loads((out / 'build-info.json').read_text())
build = Path(info['buildDirectory']) / 'DerivedData/Build'
objects = list((build / 'Intermediates.noindex/SGFPlayerClean.build/Debug/SGFPlayerClean.build/Objects-normal/arm64').glob('*.o'))
objects = [p for p in objects if p.name != 'SGFPlayerCleanApp.o']
folder = Path(tempfile.mkdtemp(prefix='sgf-ui-rewind-'))
app = folder / 'Probe.app'
binary = app / 'Contents/MacOS/Probe'
binary.parent.mkdir(parents=True)
(app / 'Contents/Resources').symlink_to(out / 'SGF Player Offline Review.app/Contents/Resources')
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'com.davemarvit.SGFPlayerClean.offline-ui-probe',
    'CFBundleExecutable': 'Probe', 'CFBundlePackageType': 'APPL'}))
subprocess.run(['swiftc', '-target', 'arm64-apple-macosx15.5', '-parse-as-library', '-I', str(build / 'Products/Debug'),
                str(root / 'Tests/UI/CaptureRewind.swift'), *map(str, objects), '-o', str(binary)], check=True)
subprocess.run(['/usr/bin/sandbox-exec', '-f', str(out / 'network-and-file-protection.sb'), str(binary)], check=True, timeout=40)
