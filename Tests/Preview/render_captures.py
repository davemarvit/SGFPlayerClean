#!/usr/bin/env python3
"""Offscreen rendering of production SceneKit lids. No application launch or OGS connection."""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
subprocess.run(['swift', 'build'], cwd=root, check=True, capture_output=True)
build = Path(subprocess.check_output(['swift', 'build', '--show-bin-path'], cwd=root, text=True).strip())
objects = list((build / 'SGFPlayerNetworking.build').glob('*.swift.o'))
output = Path(sys.argv[1] if len(sys.argv) > 1 else '/private/tmp/sgfplayer-captures.png').resolve()
with tempfile.TemporaryDirectory(prefix='sgf-capture-preview-') as directory:
    binary = Path(directory) / 'preview'
    subprocess.run(['swiftc', '-parse-as-library', '-I', str(build / 'Modules'),
                    str(root / 'Tests/Preview/CapturePreview.swift'), *map(str, objects), '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(root / 'SGFPlayerClean/Assets'), str(output), *sys.argv[2:]], check=True)
print(output)
