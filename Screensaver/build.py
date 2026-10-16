#!/usr/bin/env python3
"""Build the native saver and its preview host. Does not install or select it."""
import argparse, hashlib, json, plistlib, re, shutil, subprocess
from pathlib import Path
root = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--identity', default='auto', help='auto prefers an available Developer ID; - uses ad hoc')
a = p.parse_args()
out=a.output.resolve(); out.mkdir(parents=True,exist_ok=True)
identity=a.identity
if identity == 'auto':
    found=subprocess.run(['security','find-identity','-v','-p','codesigning'],capture_output=True,text=True,check=True)
    identities=re.findall(r'"(Developer ID Application: [^"]+)"',found.stdout)
    identity=identities[0] if identities else '-'
saver=out/'Quiet Go.saver'; host=out/'SGF Screensaver Preview.app'
core=[root/'SGFPlayerClean/Models'/name for name in ['OGSModels.swift','OGSScoringState.swift','SGFPlayerEngine.swift','ScreensaverConfiguration.swift']]
sources=[root/'Screensaver/Sources'/name for name in ['SaverPlaybackSettings.swift','SaverPlaylist.swift','QuietGoSaverView.swift']]
preview=root/'Screensaver/Sources/PreviewHost.swift'
assets=[root/'SGFPlayerClean/Assets'/name for name in ['board_kaya.jpg','tatami.jpg','stone_black.png','stone_white.png']]
sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
fingerprint=hashlib.sha256((identity+sdk).encode())
for f in core+sources+[preview,Path(__file__)]+assets: fingerprint.update(f.read_bytes())
digest=fingerprint.hexdigest(); info_path=out/'build-info.json'
if info_path.exists() and json.loads(info_path.read_text()).get('fingerprint') == digest and saver.exists() and host.exists():
    for bundle in [saver,host]: subprocess.run(['codesign','--verify','--deep','--strict',str(bundle)],check=True)
    print('Screensaver build is current'); raise SystemExit(0)
for bundle in [saver,host]:
    if bundle.exists(): shutil.rmtree(bundle)
    (bundle/'Contents/MacOS').mkdir(parents=True)
    (bundle/'Contents/Resources').mkdir()
common=['xcrun','swiftc','-swift-version','5','-O','-sdk',sdk,'-target','arm64-apple-macos14.0']
subprocess.run(common+['-emit-library','-module-name','QuietGoSaver']+list(map(str,core+sources))+['-framework','ScreenSaver','-framework','AppKit','-o',str(saver/'Contents/MacOS/QuietGoSaver')],check=True)
plist=dict(CFBundleExecutable='QuietGoSaver',CFBundleIdentifier='com.davemarvit.SGFPlayer.QuietSaver',CFBundleName='Quiet Go',CFBundleDisplayName='Quiet Go',CFBundlePackageType='BNDL',CFBundleShortVersionString='0.2',CFBundleVersion='2',LSMinimumSystemVersion='14.0',NSPrincipalClass='QuietGoSaverView')
(saver/'Contents/Info.plist').write_bytes(plistlib.dumps(plist))
for f in assets: shutil.copy2(f,saver/'Contents/Resources'/f.name)
def sign(bundle):
    subprocess.run(['codesign','--force','--sign',identity,'--options','runtime','--timestamp=none',str(bundle)],check=True)
    subprocess.run(['codesign','--verify','--deep','--strict',str(bundle)],check=True)
sign(saver)
plugins=host/'Contents/PlugIns';plugins.mkdir();shutil.copytree(saver,plugins/saver.name)
subprocess.run(common+['-parse-as-library',str(preview),'-framework','ScreenSaver','-o',str(host/'Contents/MacOS/SaverPreview')],check=True)
(host/'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleExecutable='SaverPreview',CFBundleIdentifier='com.davemarvit.SGFPlayer.SaverPreview',CFBundleName='SGF Screensaver Preview',CFBundlePackageType='APPL',CFBundleShortVersionString='0.2',CFBundleVersion='2',LSMinimumSystemVersion='14.0',NSHighResolutionCapable=True)))
sign(host)
info_path.write_text(json.dumps(dict(saver=str(saver),preview=str(host),sourceCommit=subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'],text=True).strip(),fingerprint=digest,architecture='arm64',identity=identity),indent=2)+'\n')
print(saver);print(host)
