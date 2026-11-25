#!/usr/bin/env python3
"""Offline controls for a supplied native ReplayAlignment executable.

This script opens only explicit saved files. It does not build, acquire camera
frames, contact the app/broker, or grant live alignment authority.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import time

from PIL import Image, ImageDraw, ImageEnhance


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("baseline", "candidate", "anchor_image", "current_image",
                 "anchor_calibration", "previous_calibration", "output"):
        parser.add_argument("--" + name.replace("_", "-"), required=True, type=Path)
    args = parser.parse_args()
    source = Image.open(args.current_image).convert("RGB")
    calibration = json.loads(args.previous_calibration.read_text())
    h = calibration["h"]
    n = calibration["size"] - 1

    def point(col, row):
        u, v = col / n, row / n
        d = h[6] * u + h[7] * v + 1
        return ((h[0] * u + h[1] * v + h[2]) / d * (source.width - 1),
                (h[3] * u + h[4] * v + h[5]) / d * (source.height - 1))

    def variants():
        yield "unmodified", source, "accept", {}
        for distance in (.5, 1, 2, 5, 10, 20, 30):
            for direction, dx, dy in (("right", distance, 0), ("left", -distance, 0),
                                      ("down", 0, distance), ("up", 0, -distance)):
                image = source.transform(source.size, Image.Transform.AFFINE,
                                         (1, 0, -dx, 0, 1, -dy),
                                         resample=Image.Resampling.BILINEAR,
                                         fillcolor=(180, 180, 180))
                # Small motions are measured, not assigned an arbitrary rejection
                # requirement: the tracker deliberately tolerates/refits jitter.
                expected = "reject" if distance >= 20 else "measure"
                yield f"translate_{direction}_{distance:g}px", image, expected, {"dx": dx, "dy": dy}
        for factor in (.7, .85, 1.15, 1.3):
            yield f"brightness_{factor:g}", ImageEnhance.Brightness(source).enhance(factor), "measure", {"factor": factor}
        for name, start, end in (("top", (0, 0), (n, 0)), ("bottom", (0, n), (n, n)),
                                 ("left", (0, 0), (0, n)), ("right", (n, 0), (n, n))):
            image = source.copy()
            draw = ImageDraw.Draw(image)
            draw.line([point(*start), point(*end)], fill=(180, 180, 180), width=32)
            yield "covered_" + name, image, "reject", {"stripe_width_px": 32}
        yield "blank", Image.new("RGB", source.size, (180, 180, 180)), "reject", {}

    report = {
        "diagnostic_only": True,
        "grants_live_authority": False,
        "provenance": "Saved rejected camera pixels; reconstructed anchor, not exact live tracker checkpoint. Synthetic controls are not camera acquisitions.",
        "inputs": {name: {"path": str(getattr(args, name)), "sha256": sha256(getattr(args, name))}
                   for name in ("baseline", "candidate", "anchor_image", "current_image", "anchor_calibration", "previous_calibration")},
        "cases": [],
    }
    failures = []
    with tempfile.TemporaryDirectory(prefix="pg31-controls-") as temporary:
        control_path = Path(temporary) / "control.png"
        for name, image, expected, transform in variants():
            image.save(control_path)
            case = {"name": name, "expected": expected, "transform": transform, "png_sha256": sha256(control_path)}
            for version in ("baseline", "candidate"):
                start = time.monotonic()
                run = subprocess.run([str(getattr(args, version)), str(args.anchor_image), str(control_path),
                                      str(args.anchor_calibration), str(args.previous_calibration)],
                                     capture_output=True, text=True, timeout=45, check=True)
                result = json.loads(run.stdout)
                case[version] = {"elapsed_seconds": time.monotonic() - start, "result": result}
            accepted = case["candidate"]["result"]["alignmentAccepted"]
            if (expected == "accept" and not accepted) or (expected == "reject" and accepted):
                failures.append(name)
            report["cases"].append(case)
            print(name, "baseline=", case["baseline"]["result"]["alignmentAccepted"],
                  "candidate=", accepted, "expected=", expected, flush=True)
    report["failed_expectations"] = failures
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    raise SystemExit(bool(failures))


if __name__ == "__main__":
    main()
