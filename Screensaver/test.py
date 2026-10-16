#!/usr/bin/env python3
import subprocess, sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
files=[root/'SGFPlayerClean/Models'/f for f in ['OGSModels.swift','OGSScoringState.swift','SGFPlayerEngine.swift','ScreensaverConfiguration.swift','StoneJitter.swift']]
files += [root/'Screensaver/Sources'/f for f in ['SaverPlaybackSettings.swift','SaverPlaylist.swift','SaverLayout.swift']]
files += [root/'Screensaver/Tests/PlaylistTests.swift']
binary='/private/tmp/sgf-saver-playlist-tests'
subprocess.run(['xcrun','swiftc','-swift-version','5','-sdk',sdk,'-target','arm64-apple-macos14.0','-O']+list(map(str,files))+['-o',binary],check=True)
subprocess.run(['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',binary]+sys.argv[1:],check=True,timeout=60)
