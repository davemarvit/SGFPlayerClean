#!/usr/bin/env python3
"""Build the separate camera lab; it is never bundled in Physical Go."""
import os, plistlib, re, subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
app = root / '.build/Hand Timing Lab.app'
(app / 'Contents/MacOS').mkdir(parents=True, exist_ok=True)
bundle_id = 'com.davemarvit.PhysicalGo.HandTimingLab'
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps(dict(
    CFBundleIdentifier=bundle_id, CFBundleName='Hand Timing Lab',
    CFBundleExecutable='HandTimingLab', CFBundlePackageType='APPL',
    CFBundleShortVersionString='1.0', CFBundleVersion='1', LSMinimumSystemVersion='14.0',
    NSCameraUsageDescription='The developer timing lab records short high-rate Go-board frame sequences for measuring hand-clear timing accuracy.',
    NSCameraUseContinuityCameraDeviceType=True)))
subprocess.run(['xcrun','swiftc','-swift-version','5','-O','-target',
    subprocess.check_output(['uname','-m'],text=True).strip()+'-apple-macosx14.0',
    str(root/'Tools/HandTimingLab/App.swift'),str(root/'Tools/HandTimingLab/Capture.swift'),
    str(root/'Sources/CameraFrameTimestamp.swift'),'-o',str(app/'Contents/MacOS/HandTimingLab')],check=True)
identity = os.environ.get('PHYSICAL_GO_SIGN_IDENTITY')
if not identity:
    listing = subprocess.check_output(['security','find-identity','-v','-p','codesigning'],text=True)
    identities = re.findall(r'\b([0-9A-F]{40}) "([^"]+)"',listing)
    for prefix in ['Developer ID Application:', 'Apple Development:']:
        matches = [fingerprint for fingerprint,name in identities if name.startswith(prefix)]
        if len(matches)==1:
            identity=matches[0]
            break
if not identity:
    raise SystemExit('Set PHYSICAL_GO_SIGN_IDENTITY to a signing certificate.')
subprocess.run(['codesign','--force','--sign',identity,'--timestamp=none','--identifier',bundle_id,str(app)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
print(app)
