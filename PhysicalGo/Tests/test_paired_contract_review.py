"""Independent adversarial review of mandatory paired acceptance; no device IO."""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("paired_contract_review_subject", ROOT / "Tools/paired_contract_acceptance.py")
subject = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(subject)
FIRMWARE = Path("/Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware")
BASE = FIRMWARE / "Host tests/Fixtures/GameplayContract/FaultStatus"


class MandatoryFixtureReview(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name) / "FaultStatus"
        shutil.copytree(BASE, self.folder)

    def manifest(self):
        return json.loads((self.folder / "manifest.json").read_text())

    def put_manifest(self, value):
        (self.folder / "manifest.json").write_text(json.dumps(value))

    def change_status(self, name, change):
        path = self.folder / name
        value = json.loads(path.read_text())
        change(value)
        path.write_text(json.dumps(value))
        manifest = self.manifest()
        entry = next(item for item in manifest["fixtures"] if item["file"] == name)
        entry["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        self.put_manifest(manifest)
        return manifest, entry

    def check_rejected(self):
        with self.assertRaises(subject.AcceptanceError):
            subject.validate_faults(self.folder, FIRMWARE)

    def test_actual_current_fixture_set_is_accepted(self):
        result = subject.validate_faults(self.folder, FIRMWARE)
        self.assertEqual(len(result["fixtures"]), 68)
        self.assertEqual(len(result["recoverySequences"]), 4)

    def test_missing_bootstrap_status_cannot_hide_behind_manifest_update(self):
        name = "bootstrap-hand_obstructed-unconfirmed.json"
        (self.folder / name).unlink()
        value = self.manifest()
        value["fixtures"] = [item for item in value["fixtures"] if item["file"] != name]
        self.put_manifest(value)
        self.check_rejected()

    def test_unknown_payload_not_listed_by_manifest_is_rejected(self):
        (self.folder / "apparently-healthy.json").write_text("{}")
        self.check_rejected()

    def test_duplicate_manifest_entry_cannot_satisfy_required_count(self):
        value = self.manifest()
        value["fixtures"][-1] = copy.deepcopy(value["fixtures"][0])
        self.put_manifest(value)
        self.check_rejected()

    def test_healthy_off_requires_new_revision_even_with_valid_hash(self):
        name = "recovery-hand_obstructed-new-revision-off.json"
        fault = json.loads((self.folder / "bootstrap-hand_obstructed-unconfirmed.json").read_text())
        self.change_status(name, lambda value: value.update(sequence=fault["sequence"]))
        self.check_rejected()

    def test_healthy_off_cannot_keep_output_unknown_even_with_valid_hash(self):
        self.change_status("recovery-camera_frame_stale-new-revision-off.json",
                           lambda value: value.update(laserOn=True))
        self.check_rejected()

    def test_failed_revision_cannot_pretend_it_is_admitted(self):
        self.change_status("bootstrap-request_lease_expired-confirmed-off.json",
                           lambda value: value.update(requiresNewRevision=False))
        self.check_rejected()

    def test_missing_chain_is_not_optional(self):
        value = self.manifest()
        value["recoverySequences"].pop()
        self.put_manifest(value)
        self.check_rejected()

    def test_chain_cannot_reuse_a_different_failure_cause(self):
        value = self.manifest()
        value["recoverySequences"][0]["healthyOffFile"] = value["recoverySequences"][1]["healthyOffFile"]
        self.put_manifest(value)
        self.check_rejected()

    def test_required_generator_provenance_cannot_be_omitted(self):
        value = self.manifest()
        value["sources"].pop("Host tests/test_gameplay_fault_contract_review.py")
        self.put_manifest(value)
        self.check_rejected()

    def test_source_hash_mismatch_rejects_otherwise_valid_fixtures(self):
        value = self.manifest()
        value["sources"]["bridge_runtime.py"] = "0" * 64
        self.put_manifest(value)
        self.check_rejected()

    def test_status_code_cannot_be_reclassified_with_consistent_hash_and_severity(self):
        manifest, entry = self.change_status("worker-hand_obstructed-unconfirmed.json",
                                            lambda value: value.update(reasonCode="controller_fault"))
        entry.update(reasonCode="controller_fault", expectedAutoPause=True)
        self.put_manifest(manifest)
        self.check_rejected()


PROVENANCE_SPEC = importlib.util.spec_from_file_location("paired_provenance_review_subject", ROOT / "Tools/paired_contract_provenance.py")
provenance = importlib.util.module_from_spec(PROVENANCE_SPEC)
PROVENANCE_SPEC.loader.exec_module(provenance)


class BuildReceiptReview(unittest.TestCase):
    """Exercise receipt validation with declared fake binaries; never execute them."""
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.app = self.root / "app"
        builder = self.app / "PhysicalGo/scripts/shared_regressions.py"
        builder.parent.mkdir(parents=True)
        builder.write_text("# fake builder identity for metadata tests\n")
        self.sources = {}
        for name in ["PhysicalGo/Sources/Runtime.swift", "PhysicalGo/Tests/Standby.swift", "PhysicalGo/Tests/Continuity.swift"]:
            path = self.app / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("// " + name + "\n")
            self.sources[name] = provenance.sha(path)
        self.config = dict(format=2, builderSHA256=provenance.sha(builder),
                           toolchain={"version": "fake compiler; no execution"}, commonArguments=["fake-swiftc"])
        runtime_manifest = dict(self.config, kind="runtime", module="PhysicalGoTestRuntime",
                                inputs=[self.input("PhysicalGo/Sources/Runtime.swift")])
        self.runtime = self.receipt("runtime", runtime_manifest, {"libPhysicalGoTestRuntime.dylib": b"fake runtime", "PhysicalGoTestRuntime.swiftmodule": b"fake module"})
        self.library = self.runtime.parent / "libPhysicalGoTestRuntime.dylib"
        self.pointers = {}
        self.runners = {}
        for role, name, source in [
            ("standby", "PhysicalLaserStandbyTests", "PhysicalGo/Tests/Standby.swift"),
            ("continuity", "PhysicalAIGuidanceContinuityTests", "PhysicalGo/Tests/Continuity.swift"),
        ]:
            manifest = dict(self.config, kind="runner", runtime=provenance.identity(runtime_manifest),
                            executable=name, inputs=[self.input(source)],
                            runtimeArtifacts={n: provenance.sha(self.runtime.parent / n) for n in
                                              ["libPhysicalGoTestRuntime.dylib", "PhysicalGoTestRuntime.swiftmodule"]})
            runner = self.receipt(role, manifest, {name: ("fake executable " + role).encode()})
            self.runners[role] = runner
            identity = provenance.identity(manifest)
            executable = self.root / "bin" / (name + "-" + identity)
            executable.parent.mkdir(exist_ok=True)
            executable.write_bytes((runner.parent / name).read_bytes())
            pointer = Path(str(executable) + ".build.json")
            pointer.write_text(json.dumps(dict(schemaVersion=1, runnerReceipt=str(runner), runtimeReceipt=str(self.runtime),
                                              runnerIdentity=identity, executableSHA256=provenance.sha(executable))))
            self.pointers[role] = pointer

    def input(self, name):
        path = self.app / name
        prepared = b"// prepared snapshot\n" + path.read_bytes()
        return dict(name=name, originalPath=str(path), sha256=provenance.sha(path),
                    preparedSHA256=hashlib.sha256(prepared).hexdigest())

    def receipt(self, kind, manifest, outputs):
        directory = self.root / "artifacts" / kind / provenance.identity(manifest)
        directory.mkdir(parents=True)
        for name, data in outputs.items():
            (directory / name).write_bytes(data)
        for i, item in enumerate(manifest["inputs"]):
            raw = directory / "original" / item["name"]
            raw.parent.mkdir(parents=True, exist_ok=True)
            raw.write_bytes((self.app / item["name"]).read_bytes())
            prepared = directory / "prepared" / (str(i) + ".swift")
            prepared.parent.mkdir(exist_ok=True)
            prepared.write_bytes(b"// prepared snapshot\n" + raw.read_bytes())
        files = {str(p.relative_to(directory)): provenance.sha(p) for p in directory.rglob("*") if p.is_file()}
        result = directory / "complete.json"
        result.write_text(json.dumps(dict(manifest=manifest, files=files)))
        return result

    def validate(self):
        with patch.object(provenance, "linked_paths", return_value=[self.library]):
            return provenance.validate_build_pointers(self.app, self.pointers, self.sources)

    def test_exact_declared_receipts_are_accepted(self):
        self.assertEqual(set(self.validate()), {"standby", "continuity"})

    def test_missing_required_runtime_snapshot_is_rejected(self):
        (self.runtime.parent / "original/PhysicalGo/Sources/Runtime.swift").unlink()
        with self.assertRaises(provenance.ProvenanceError): self.validate()

    def test_receipt_from_equal_bytes_but_other_source_tree_is_rejected(self):
        other = self.root / "other/Runtime.swift"
        other.parent.mkdir()
        other.write_bytes((self.app / "PhysicalGo/Sources/Runtime.swift").read_bytes())
        value = json.loads(self.runtime.read_text())
        value["manifest"]["inputs"][0]["originalPath"] = str(other)
        self.runtime.write_text(json.dumps(value))
        with self.assertRaisesRegex(provenance.ProvenanceError, "[Oo]riginal|requested|source path"):
            provenance.load_receipt(self.runtime, "runtime", self.app)

    def test_hardlink_in_other_parent_does_not_preserve_resource_lookup(self):
        other = self.root / "other/Runtime.swift"
        other.parent.mkdir()
        os.link(self.app / "PhysicalGo/Sources/Runtime.swift", other)
        value = json.loads(self.runtime.read_text())
        value["manifest"]["inputs"][0]["originalPath"] = str(other)
        self.runtime.write_text(json.dumps(value))
        with self.assertRaisesRegex(provenance.ProvenanceError, "[Oo]riginal|requested|source path"):
            provenance.load_receipt(self.runtime, "runtime", self.app)

    def test_unresolved_directory_alias_cannot_change_multi_parent_fixture_lookup(self):
        alias = self.root / "alias-to-Sources"
        alias.symlink_to(self.app / "PhysicalGo/Sources", target_is_directory=True)
        value = json.loads(self.runtime.read_text())
        value["manifest"]["inputs"][0]["originalPath"] = str(alias / "Runtime.swift")
        self.runtime.write_text(json.dumps(value))
        with self.assertRaisesRegex(provenance.ProvenanceError, "[Oo]riginal|requested|source path|canonical"):
            provenance.load_receipt(self.runtime, "runtime", self.app)

    def test_unattested_loaded_library_is_rejected(self):
        wrong = self.root / "wrong.dylib"
        wrong.write_bytes(self.library.read_bytes())
        with patch.object(provenance, "linked_paths", return_value=[wrong]):
            with self.assertRaisesRegex(provenance.ProvenanceError, "unattested"):
                provenance.validate_build_pointers(self.app, self.pointers, self.sources)

    def test_executable_must_match_named_suite_artifact(self):
        role = "standby"
        runner = json.loads(self.runners[role].read_text())
        name = runner["manifest"]["executable"]
        executable = Path(str(self.pointers[role]).removesuffix(".build.json"))
        extra = self.runners[role].parent / "unrelated-output"
        extra.write_bytes(executable.read_bytes())
        (self.runners[role].parent / name).write_bytes(b"different named suite")
        runner["files"][name] = provenance.sha(self.runners[role].parent / name)
        runner["files"][extra.name] = provenance.sha(extra)
        self.runners[role].write_text(json.dumps(runner))
        with self.assertRaises(provenance.ProvenanceError): self.validate()

    def test_semantically_malformed_receipt_fails_as_provenance_error(self):
        value = json.loads(self.runtime.read_text())
        value["files"] = list(value["files"])
        self.runtime.write_text(json.dumps(value))
        with self.assertRaises(provenance.ProvenanceError): self.validate()

    def rewrite_runner_manifest(self, role, transform):
        previous = self.runners[role]
        receipt = json.loads(previous.read_text())
        transform(receipt["manifest"])
        identity = provenance.identity(receipt["manifest"])
        directory = previous.parent.with_name(identity)
        previous.parent.rename(directory)
        updated = directory / "complete.json"
        updated.write_text(json.dumps(receipt))
        self.runners[role] = updated
        old_pointer = self.pointers[role]
        pointer = json.loads(old_pointer.read_text())
        pointer.update(runnerReceipt=str(updated), runnerIdentity=identity)
        name = receipt["manifest"]["executable"]
        executable = old_pointer.parent / (name + "-" + identity)
        executable.write_bytes((directory / name).read_bytes())
        destination = Path(str(executable) + ".build.json")
        destination.write_text(json.dumps(pointer))
        self.pointers[role] = destination

    def test_missing_exact_runtime_outputs_cannot_be_substituted_by_input_identity(self):
        self.rewrite_runner_manifest("standby", lambda value: value.pop("runtimeArtifacts"))
        with self.assertRaisesRegex(provenance.ProvenanceError, "[Rr]untime|linked"):
            self.validate()

    def test_same_runtime_input_identity_cannot_hide_changed_linked_output_hash(self):
        self.rewrite_runner_manifest("standby", lambda value: value["runtimeArtifacts"].update(
            {"libPhysicalGoTestRuntime.dylib": "0" * 64}))
        with self.assertRaisesRegex(provenance.ProvenanceError, "[Rr]untime|linked"):
            self.validate()

    def test_new_source_not_in_receipts_cannot_be_silently_omitted(self):
        self.sources["PhysicalGo/Sources/New.swift"] = "0" * 64
        with self.assertRaisesRegex(provenance.ProvenanceError, "omit or add"):
            self.validate()

    def test_valid_pointer_cannot_be_used_after_executable_changes(self):
        binary = Path(str(self.pointers["continuity"]).removesuffix(".build.json"))
        binary.write_bytes(b"different executable")
        with self.assertRaisesRegex(provenance.ProvenanceError, "hash mismatch"):
            self.validate()


if __name__ == "__main__":
    unittest.main()
