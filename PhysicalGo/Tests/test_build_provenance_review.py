"""Independent boundary review; temporary files and one tiny Swift path probe, no app/device execution."""
import hashlib
import json
from pathlib import Path
import os
import sys
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts import shared_regressions as shared
from scripts.build_provenance import SourceState


class BuildBoundaryReview(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()

    def artifact(self):
        cache = self.root / "cache"
        cache.mkdir()
        manifest = {"kind": "review", "input": "frozen"}
        def builder(folder):
            (folder / "lib.dylib").write_bytes(b"verified library")
            (folder / "module").write_bytes(b"verified module")
        with shared.build_lock(cache):
            result = shared.publish_artifact(cache, "runtimes", manifest,
                                             ("lib.dylib", "module"), builder)
        return cache, result, manifest, builder

    def test_semantically_malformed_receipt_is_invalid_not_an_uncaught_exception(self):
        _, artifact, manifest, _ = self.artifact()
        receipt = json.loads((artifact / "complete.json").read_text())
        receipt["files"] = ["lib.dylib", "module"]
        (artifact / "complete.json").write_text(json.dumps(receipt))
        self.assertFalse(shared.valid_artifact(artifact, manifest, ("lib.dylib", "module")))

    def test_unrecorded_extra_file_and_missing_file_invalidate_cache(self):
        _, artifact, manifest, _ = self.artifact()
        (artifact / "unexpected.dylib").write_bytes(b"unrecorded")
        self.assertFalse(shared.valid_artifact(artifact, manifest, ("lib.dylib", "module")))
        (artifact / "unexpected.dylib").unlink()
        (artifact / "module").unlink()
        self.assertFalse(shared.valid_artifact(artifact, manifest, ("lib.dylib", "module")))

    def test_receipt_and_output_are_not_visible_after_interrupted_publication(self):
        cache = self.root / "cache"
        cache.mkdir()
        manifest = {"kind": "review"}
        def interrupted(folder):
            (folder / "output").write_bytes(b"partial result")
            raise RuntimeError("injected interruption")
        with shared.build_lock(cache), self.assertRaisesRegex(RuntimeError, "injected"):
            shared.publish_artifact(cache, "runtimes", manifest, ("output",), interrupted)
        self.assertEqual(list((cache / "runtimes").iterdir()), [])
        with shared.build_lock(cache):
            result = shared.publish_artifact(cache, "runtimes", manifest, ("output",),
                                             lambda p: (p / "output").write_bytes(b"complete"))
        self.assertTrue(shared.valid_artifact(result, manifest, ("output",)))

    def test_snapshot_read_cannot_silently_mix_persistent_edit(self):
        source = self.root / "Source.swift"
        source.write_bytes(b"before")
        original = Path.read_bytes
        calls = 0
        def changing(path):
            nonlocal calls
            data = original(path)
            if path == source:
                calls += 1
                if calls == 1:
                    source.write_bytes(b"after")
            return data
        with patch.object(Path, "read_bytes", changing), self.assertRaisesRegex(RuntimeError, "changed while"):
            shared.capture_inputs(self.root, [source])

    def test_replaced_source_cannot_pass_with_equal_bytes_and_restored_mtime(self):
        source = self.root / "Source.swift"
        source.write_bytes(b"unchanged bytes")
        state = SourceState.capture([source])
        previous = source.stat()
        replacement = self.root / "replacement"
        replacement.write_bytes(source.read_bytes())
        os.utime(replacement, ns=(previous.st_atime_ns, previous.st_mtime_ns))
        os.replace(replacement, source)
        with self.assertRaisesRegex(RuntimeError, "refusing to sign"):
            state.assert_unchanged([source])

    def test_real_swift_source_location_preserves_ordinary_unicode_paths(self):
        original = self.root / "Café 源 folder" / "Sample.swift"
        original.parent.mkdir()
        original.write_text("print(#filePath)\n")
        item = shared.Input(original, "Sources/Sample.swift", original.read_bytes())
        source = shared.stage_inputs(self.root / "unicode-staging", [item])[0]
        binary = self.root / "unicode-check"
        subprocess.run(["xcrun", "swiftc", str(source), "-o", str(binary)],
                       check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
        actual = subprocess.check_output([str(binary)], text=True, timeout=5).strip()
        self.assertEqual(actual, str(original))

    def test_staged_test_snapshot_detects_prepared_or_original_mutation(self):
        item = shared.Input(self.root / "Test.swift", "Tests/Test.swift", b"let x = 1\n")
        staging = self.root / "stage"
        prepared = shared.stage_inputs(staging, [item], test=True)
        shared.verify_staged_inputs(staging, [item], test=True)
        for path in [staging / "original/Tests/Test.swift", prepared[0]]:
            before = path.read_bytes()
            path.chmod(0o644)
            path.write_bytes(before + b"// modified\n")
            with self.assertRaisesRegex(RuntimeError, "snapshot was modified"):
                shared.verify_staged_inputs(staging, [item], test=True)
            path.write_bytes(before)


if __name__ == "__main__":
    unittest.main()
