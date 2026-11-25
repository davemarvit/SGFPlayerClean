# Exact temporal hand-tracker checkpoints

PG-03 offline diagnostic improvement, November 24, 2026. This does not resolve
or physically validate the false hand warning. No detector, rim, fingertip,
freshness or clearance threshold changes.

The existing checkpoint saved the frozen background, active state, entry edge,
center and learned appearance. It omitted the recent clear-reference queue,
last frame time/source, initialization progress, pending clear-frame confirmation,
outline motion samples, and disagreement-warning state. Restoring it could change
the very next decision: accept a duplicate, miss a gap reset, delay the second
clear-frame confirmation, lose the original clock estimate, or restart a warning.

`HandOutlineTracker.Checkpoint.temporal` now retains that state. The queue keeps
its existing bound of at most 90 sampled frames within 0.8 seconds. Capturing the
checkpoint uses Swift value semantics; encoding should occur off the camera/main
queue because the retained reference frames increase serialized size. No new
per-frame recording or disk-write path is added by this change.

Historical snapshots omit `temporal`. They still decode and restore spatial
state only, with conservative fresh timing/initialization. Their missing history
cannot be reconstructed. New production snapshots have non-null `temporal`;
manual/counterfactual test checkpoints can explicitly remain spatial-only.

For an exact first-fault replay, retain the **pre-observation** checkpoint, sampled
frame, pose, timestamp/source and result. Raw image replay also needs the matching
calibration, reference identity, expected board and analysis settings. Capturing
a complete tracker checkpoint does not recover missing historical camera frames
or prove that a pose was a real hand.

Validation command:

```sh
python3 PhysicalGo/build.py --hand-outline-test
```

Passed November 24, 2026: 623 checks (412 synthetic outline checks, 144
photographed boundary checks and 67 recorded-outline checks), including 84 added
checks for temporal/legacy replay. Compiled only the standalone hand suite; no
app build, launch, installation, camera acquisition or controller use.

The suite round-trips a checkpoint before each observation across four board
edges, initialization and reference updates, hand entry, pose loss, duplicate
frames, two-frame clearance, original clock estimate, source changes and gaps.
It also checks exact delayed-warning reproduction, duplicate-stall suppression,
legacy decoding and existing retained photographed hand/withdrawal regressions.

Installation and attended hand entry/withdrawal/accepted-placement verification
remain root-owned and are still required before PG-03 can close.
