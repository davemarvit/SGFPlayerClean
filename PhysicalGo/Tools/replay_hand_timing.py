#!/usr/bin/env python3
"""Build and run the offline evaluator against a lab capture folder."""
from pathlib import Path
import subprocess, sys

root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root))
from scripts.build_sources import resolve_sources

if len(sys.argv) not in (2,3) or (len(sys.argv)==3 and sys.argv[2]!='--outline'):
    raise SystemExit('Usage: python3 Tools/replay_hand_timing.py CAPTURE_FOLDER [--outline]')
sources=[root/'Tools/HandTimingLab/Replay.swift',root/'Tools/HandTimingLab/Capture.swift',
         root/'Sources/CameraFrameTimestamp.swift',root/'Sources/BoardHandDetector.swift',
         root/'Sources/HandOutlineSampling.swift',
         root/'Sources/BoardVision.swift',root/'Sources/StoneGeometry.swift',
         root.parent/'SGFPlayerClean/Models/OGSModels.swift',root.parent/'SGFPlayerClean/Models/OGSScoringState.swift']
executable=root/'.build/HandTimingReplay'
subprocess.run(['xcrun','swiftc','-swift-version','5','-O','-D','PHYSICAL_GO',
    '-target',subprocess.check_output(['uname','-m'],text=True).strip()+'-apple-macosx14.0',
    *map(str,resolve_sources(root,sources)),'-o',str(executable)],check=True)
subprocess.run([str(executable),str(Path(sys.argv[1]).resolve()),*sys.argv[2:]],check=True)
