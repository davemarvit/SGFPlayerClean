#!/usr/bin/env python3
"""Build the offline production-tracker replay in external evidence storage."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root/'scripts'))
from build_sources import resolve_sources

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('output',type=Path)
a=p.parse_args()
out=a.output.resolve()
if out.is_relative_to(root.parent):raise ValueError('Use external output storage')
out.mkdir(parents=True,exist_ok=True)
sources=resolve_sources(root,[root/'Tools/HandRimAudit.swift',root/'Sources/HandOutlineSampling.swift',
    root/'Sources/BoardHandDetector.swift',root/'Sources/StoneGeometry.swift',
    root.parent/'SGFPlayerClean/Models/OGSModels.swift',root.parent/'SGFPlayerClean/Models/OGSScoringState.swift'])
subprocess.run(['xcrun','swiftc','-swift-version','5','-O','-D','PHYSICAL_GO',
                *map(str,sources),'-o',str(out/'HandRimAudit')],check=True)
(out/'rim-audit-source-hashes.json').write_text(json.dumps(
    {str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in [Path(__file__),*sources]},indent=2)+'\n')
print(out/'HandRimAudit')
