#!/usr/bin/env python3
"""Build an isolated native saver and a host for testing the exact bundle.
Games are copied, never modified. No installation or screen-saver selection here.
"""
import argparse, hashlib, json, plistlib, shutil, subprocess
from pathlib import Path
root = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--games-folder', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--identity', default='-', help='Local codesigning identity, or - for ad hoc')
p.add_argument('--limit', type=int, default=80)
a = p.parse_args()
out=a.output.resolve(); out.mkdir(parents=True,exist_ok=True)
saver=out/'Quiet Go.saver'; host=out/'SGF Screensaver Preview.app'
for bundle in [saver,host]:
    if bundle.exists(): shutil.rmtree(bundle)
    (bundle/'Contents/MacOS').mkdir(parents=True)
    (bundle/'Contents/Resources').mkdir()
sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
common=['xcrun','swiftc','-swift-version','5','-O','-sdk',sdk,'-target','arm64-apple-macos14.0']
core=[root/'SGFPlayerClean/Models'/name for name in ['OGSModels.swift','OGSScoringState.swift','SGFPlayerEngine.swift']]
sources=[root/'Screensaver/Sources'/name for name in ['SaverPlaybackSettings.swift','SaverPlaylist.swift','QuietGoSaverView.swift']]
subprocess.run(common+['-emit-library','-module-name','QuietGoSaver']+list(map(str,core+sources))+['-framework','ScreenSaver','-framework','AppKit','-o',str(saver/'Contents/MacOS/QuietGoSaver')],check=True)
plist=dict(CFBundleExecutable='QuietGoSaver',CFBundleIdentifier='com.davemarvit.SGFPlayer.QuietSaver',CFBundleName='Quiet Go',CFBundleDisplayName='Quiet Go',CFBundlePackageType='BNDL',CFBundleShortVersionString='0.1',CFBundleVersion='1',LSMinimumSystemVersion='14.0',NSPrincipalClass='QuietGoSaverView')
(saver/'Contents/Info.plist').write_bytes(plistlib.dumps(plist))
resources=saver/'Contents/Resources'; games=resources/'Games';games.mkdir()
paths=sorted((f for f in a.games_folder.resolve().rglob('*') if f.is_file() and f.suffix.lower()=='.sgf' and 0<f.stat().st_size<=2_000_000),key=lambda f:f.stat().st_mtime,reverse=True)[:max(1,a.limit)]
if not paths: raise RuntimeError('No SGFs of at most 2 MB in source folder')
manifest=[]
for i, f in enumerate(paths):
    data=f.read_bytes(); dest=games/(f'{i:03d}-'+f.name);dest.write_bytes(data)
    manifest.append(dict(source=str(f),copy=dest.name,sha256=hashlib.sha256(data).hexdigest()))
for name in ['board_kaya.jpg','tatami.jpg','stone_black.png','stone_white.png']: shutil.copy2(root/'SGFPlayerClean/Assets'/name,resources/name)
def sign(bundle):
    subprocess.run(['codesign','--force','--sign',a.identity,'--options','runtime','--timestamp=none',str(bundle)],check=True)
    subprocess.run(['codesign','--verify','--deep','--strict',str(bundle)],check=True)
sign(saver)
plugins=host/'Contents/PlugIns';plugins.mkdir();shutil.copytree(saver,plugins/saver.name)
subprocess.run(common+['-parse-as-library',str(root/'Screensaver/Sources/PreviewHost.swift'),'-framework','ScreenSaver','-o',str(host/'Contents/MacOS/SaverPreview')],check=True)
(host/'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleExecutable='SaverPreview',CFBundleIdentifier='com.davemarvit.SGFPlayer.SaverPreview',CFBundleName='SGF Screensaver Preview',CFBundlePackageType='APPL',CFBundleShortVersionString='0.1',CFBundleVersion='1',LSMinimumSystemVersion='14.0',NSHighResolutionCapable=True)))
sign(host)
(out/'build-info.json').write_text(json.dumps(dict(saver=str(saver),preview=str(host),sourceCommit=subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'],text=True).strip(),games=manifest,architecture='arm64',identity=a.identity),indent=2)+'\n')
print(saver);print(host)
