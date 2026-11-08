#!/usr/bin/env python3
"""Package the generated master artwork into a full macOS icon family."""
from pathlib import Path
import subprocess
import tempfile


def build_icon(master: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="physical-go-icon-") as temporary:
        iconset = Path(temporary) / "PhysicalGo.iconset"
        iconset.mkdir()
        for points in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                pixels = points * scale
                name = f"icon_{points}x{points}" + ("@2x" if scale == 2 else "") + ".png"
                subprocess.run(["sips", "-z", str(pixels), str(pixels), str(master),
                                "--out", str(iconset / name)], check=True, stdout=subprocess.DEVNULL)
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(destination)], check=True)


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    build_icon(root / "Resources/AppIcon/PhysicalGo.png", root / "Resources/PhysicalGo.icns")
