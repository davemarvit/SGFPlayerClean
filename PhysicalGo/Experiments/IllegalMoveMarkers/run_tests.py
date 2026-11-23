#!/usr/bin/env python3
"""Compile and test the isolated diagnostic candidate, never the app or hardware.

All generated Swift, binaries and execution logs go in the ignored PhysicalGo
.build directory. The exact shared engine/models are compiled from this checkout.
"""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess


def main() -> None:
    directory = Path(__file__).resolve().parent
    root = directory.parents[2]
    if shutil.which("xcrun") is None:
        raise SystemExit("This experiment requires macOS with the Xcode command-line tools.")
    build = root / "PhysicalGo/.build/Experiments/IllegalMoveMarkers"
    build.mkdir(parents=True, exist_ok=True)
    # Extract the exact standalone declaration, not a rewritten inference model.
    # A changed source boundary should require review rather than a silent fallback.
    inference_source = root / "PhysicalGo/Sources/PhysicalOnlineBoard.swift"
    original = inference_source.read_text()
    boundary = "/// Compact local history"
    if original.count(boundary) != 1:
        raise SystemExit("PhysicalMoveInference source boundary changed; review extraction.")
    declaration = original.split(boundary, 1)[0]
    if declaration.count("enum PhysicalMoveInference {") != 1:
        raise SystemExit("Expected exactly one authoritative PhysicalMoveInference declaration.")
    extracted = build / "PhysicalMoveInferenceFromSource.swift"
    extracted.write_text(declaration)
    sources = [root / path for path in (
        "SGFPlayerClean/Models/OGSModels.swift",
        "SGFPlayerClean/Models/OGSScoringState.swift",
        "SGFPlayerClean/Models/SGFPlayerEngine.swift",
    )] + [extracted, directory / "PhysicalIllegalMoveWarning.swift",
         directory / "IllegalMoveWarningTests.swift"]
    executable = build / "IllegalMoveWarningTests"
    command = ["xcrun", "swiftc", "-swift-version", "5", "-D", "PHYSICAL_GO", "-Onone",
               *[str(path.relative_to(root)) for path in sources], "-o", str(executable.relative_to(root))]
    compiler = subprocess.run(["xcrun", "swiftc", "--version"], check=True,
                              capture_output=True, text=True).stdout.strip()
    compiled = subprocess.run(command, cwd=root, capture_output=True, text=True)
    (build / "compile.log").write_text(compiled.stdout + compiled.stderr)
    if compiled.returncode:
        print(compiled.stdout + compiled.stderr, end="")
        raise SystemExit(compiled.returncode)
    result = subprocess.run([str(executable)], cwd=root, capture_output=True, text=True)
    (build / "test.log").write_text(result.stdout + result.stderr)
    print(result.stdout + result.stderr, end="")
    if result.returncode:
        raise SystemExit(result.returncode)
    match = re.fullmatch(r"PASS (\d+) illegal-marker candidate checks; actual SGFPlayer rules, "
                         r"no hardware, production unchanged\n", result.stdout)
    if match is None:
        raise SystemExit("Unexpected test completion output; no success record written.")
    recorded_sources = [*sources, inference_source, Path(__file__).resolve()]
    record = {
        "atUtc": datetime.now(timezone.utc).isoformat(),
        "result": "PASS", "checks": int(match.group(1)), "hardware": False,
        "productionEdits": False, "installed": False, "experimental": True,
        "compiler": compiler, "command": command,
        "sha256": {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
                   for path in recorded_sources},
        "inferenceExtraction": "Exact prefix before the Compact local history declaration; no model stubs.",
    }
    (build / "result.json").write_text(json.dumps(record, indent=2) + "\n")
    print("Result: " + str((build / "result.json").relative_to(root)))


if __name__ == "__main__":
    main()
