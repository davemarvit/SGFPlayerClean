#!/usr/bin/env python3
"""Build and verify the regular app without installing it or opening user data."""
import argparse
import json
from pathlib import Path
import plistlib
import subprocess

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
with (out / 'release-build.log').open('w') as log:
    subprocess.run([
        'xcodebuild', '-project', str(root / 'SGFPlayerClean/SGFPlayerClean.xcodeproj'),
        '-scheme', 'SGFPlayerClean', '-configuration', 'Release',
        '-derivedDataPath', str(out / 'DerivedData'),
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS=', 'ENABLE_DEBUG_DYLIB=NO',
        # Retain internal symbols so the offline probes can link this exact build.
        'ENABLE_TESTABILITY=YES', 'CODE_SIGN_IDENTITY=-', 'CODE_SIGNING_ALLOWED=YES',
        'build'], check=True, stdout=log, stderr=subprocess.STDOUT)
app = out / 'DerivedData/Build/Products/Release/SGFPlayerClean.app'
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
if info['CFBundleIdentifier'] != 'com.davemarvit.SGFPlayerClean':
    raise RuntimeError('Unexpected main app identity')
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
(out / 'build-info.json').write_text(json.dumps({
    'app': str(app), 'buildDirectory': str(out), 'configuration': 'Release',
    'module': 'SGFPlayerClean', 'bundleIdentifier': info['CFBundleIdentifier'],
    'sourceCommit': subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip(),
    'includesUncommittedChanges': bool(subprocess.check_output(['git', '-C', str(root), 'status', '--porcelain'], text=True).strip()),
    'installed': False,
}, indent=2) + '\n')
print(app)
