#!/usr/bin/env python3
"""Render the actual SwiftUI scoring panel using offline sample state. No app launch or OGS traffic."""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
output = Path(sys.argv[1] if len(sys.argv) > 1 else "/private/tmp/sgfplayer-scoring-preview.png").resolve()
with tempfile.TemporaryDirectory(prefix="sgf-scoring-preview-") as directory:
    binary = Path(directory) / "preview"
    sources = [
        root / "SGFPlayerClean/Models/OGSModels.swift",
        root / "SGFPlayerClean/Models/OGSScoringState.swift",
        root / "SGFPlayerClean/Views/OGSScoringPanel.swift",
        root / "Tests/Preview/ScoringPreview.swift",
    ]
    subprocess.run(["swiftc", "-parse-as-library", *map(str, sources), "-o", str(binary)], check=True)
    subprocess.run([str(binary), str(output)], check=True)
print(output)
