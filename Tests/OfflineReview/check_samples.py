#!/usr/bin/env python3
"""Check the actual packaged SGFs using the production parser and rule engine."""
from pathlib import Path
import json
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
subprocess.run(['swift', 'build'], cwd=root, check=True, capture_output=True)
build = Path(subprocess.check_output(['swift', 'build', '--show-bin-path'], cwd=root, text=True).strip())
info = json.loads((root.parent / 'Offline Review/build-info.json').read_text())
games = Path(info['app']) / 'Contents/Resources/Review Games'
with tempfile.TemporaryDirectory(prefix='sgf-review-samples-') as folder:
    binary = Path(folder) / 'check-samples'
    subprocess.run(['swiftc', '-parse-as-library', '-I', str(build / 'Modules'),
                    str(root / 'Tests/OfflineReview/CheckSamples.swift'),
                    *map(str, (build / 'SGFPlayerNetworking.build').glob('*.swift.o')),
                    '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(games)], check=True)
