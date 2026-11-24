#!/usr/bin/env python3
"""Compile the small real rules engine and write only a NEW artifact directory."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess

here = Path(__file__).resolve().parent
repo = here.parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('destination', type=Path)
args = parser.parse_args()
destination = args.destination.expanduser().resolve()
if destination.exists():
    parser.error('Destination already exists; refuse overwriting fixtures or game data.')
# Prevent an accidentally supplied live application-support path, including
# alternate user homes. No activation/install mode is provided.
if 'Application Support' in destination.parts or 'Library' in destination.parts:
    parser.error('Artifact output cannot be inside a Library/application-support directory.')
build = repo / 'PhysicalGo/.build/capture-kit'
build.mkdir(parents=True, exist_ok=True)
sources = [repo / name for name in [
    'SGFPlayerClean/Models/OGSModels.swift',
    'SGFPlayerClean/Models/OGSScoringState.swift',
    'SGFPlayerClean/Models/SGFPlayerEngine.swift',
    'PhysicalGo/Sources/PhysicalAITiming.swift',
    'PhysicalGo/Experiments/AttendedCaptureKit/Generate.swift',
]]
executable = build / 'GenerateCaptureKit'
command = ['xcrun', 'swiftc', '-Onone', '-D', 'PHYSICAL_GO', *map(str, sources), '-o', str(executable)]
subprocess.run(command, check=True)
subprocess.run([str(executable), str(destination)], check=True)
manifest = destination / 'manifest.json'
data = json.loads(manifest.read_text())
data['sourceWorkingTreeDirty'] = bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=repo, text=True).strip())
data['sourceCommit'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip()
data['sourceSHA256'] = {str(p.relative_to(repo)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
data['fixtureSHA256'] = {str(p.relative_to(destination)): hashlib.sha256(p.read_bytes()).hexdigest()
                         for p in sorted(destination.rglob('*')) if p.is_file() and p != manifest}
manifest.write_text(json.dumps(data, indent=2, sort_keys=True) + '\n')
print('Artifact manifest records source and fixture hashes. No app activation performed.')
