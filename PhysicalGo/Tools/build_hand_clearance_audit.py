#!/usr/bin/env python3
"""Compile isolated offline exporter; writes only to an explicit external directory."""
from pathlib import Path
import argparse,json,subprocess,sys
root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root))
from scripts.build_sources import resolve_sources
from local_quality_lab import digest
p=argparse.ArgumentParser();p.add_argument('output',type=Path);args=p.parse_args()
if args.output.resolve().is_relative_to(root.parent):raise ValueError('Use external output storage')
args.output.mkdir(parents=True,exist_ok=True)
sources=[root/'Tools/HandClearanceAudit.swift',root/'Sources/HandOutlineTracker.swift',root/'Sources/HandMotionTiming.swift']
exe=args.output/'HandClearanceAudit'
resolved=resolve_sources(root,sources)
subprocess.run(['xcrun','swiftc','-swift-version','5','-O','-D','PHYSICAL_GO',*map(str,resolved),'-o',str(exe)],check=True)
fixtures=[root/'Tests/Fixtures'/n for n in ['HandOutline','A18HandOutline','A19RemovalHandOutline','ClockCatchUpLoss/Outline']]
with (args.output/'hand-replay.json').open('w') as f:subprocess.run([str(exe),*map(str,fixtures)],stdout=f,check=True)
inputs=[Path(__file__),*resolved,*[folder/name for folder in fixtures for name in ['manifest.json','pixels.u16.gz']]]
(args.output/'hand-native-inputs.json').write_text(json.dumps({str(p):digest(p) for p in inputs},indent=2)+'\n')
