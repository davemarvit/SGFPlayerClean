# PG23 fresh empty-crossing evidence investigation

Source baseline: `fb4697c4ef314d83a253bd0aa219de1bb6b3d61f`.
This checkpoint is a **schema and test draft**. No detector emits these receipts,
and no recognition decision consumes them. No installation or physical claim.

## Retained photograph result

The original R16 trace records 130 ambiguity resets and 25.418 seconds before
acceptance. Its delayed frames, outlines and tracker checkpoint were not retained.
The available `post-texture-fault-board.png` was captured later, after acceptance;
it cannot establish an improvement in the original delay.

An instrumented copy of the unchanged detector ran once against immutable
runtime `135a20c1f79a0cc09a2c4dd16cbb8284171736d807d30eab5ed6335be0a2dde6`.
All 177 input sources and 359 runtime artifacts matched their manifest hashes.
The exact original reference PNG was reused from the prior archived investigation.
All 361 readings match the earlier 0.264 replay exactly:

* Point 41: Black, confidence 0.9666666667, no admitted placement outline.
* Point 59: Empty, confidence 0.75, supplied by **shadedEmptyEvidence**, not the
  reference-free `exposedWoodConfidence` path.

Consequently, a liveWood-only exception would not repair this retained case.
Detector duration was not instrumented; this run supports no performance claim.

Local artifacts remain in `PhysicalGo/.build/pg23-empty-proof/`:

* `result.json` SHA256 `bccc80bebcf1a7afe2dd151970bcd265b02f8ff86b51890c48f12beb1e86b2a7`
* `result.log` SHA256 `d228663385aed7860a227ea2235125e6014e433101e8ef08a52effdbaee9b438`
* `command.json` and `provenance.json` describe the immutable runtime and inputs.

The source photograph and reference were not duplicated. The worktree contains
approximately 1.3 GB of existing regression fixtures and under 1 MB of diagnostics.

## Bounded proposal awaiting image validation

The actual reference-backed empty test already compares at least sixteen current
wood samples, requires at least 75% matching color/level support and independently
requires at least 75% survival of both printed rails. It sometimes reports 0.75,
which the controller's blanket 0.8 neighbor veto discards.

A receipt may be defensible for its standard **unmasked** path only when all four
existing innermost samples at offsets ±0.075 cell also match the same color/level
gates. This adds no image passes and changes no classification thresholds. The
inner requirement must reject a halfway stone occupying the near side of a
neighboring intersection. Whether retained point 59 passes is not yet established.

The schema binds support to an exact image UUID, reference UUID, capture uptime,
point and unchanged reading. Reading replacement, timestamp replacement, image
or reference replacement, manual labels and tracker reassignment invalidate the
receipt. Unknown hand state, blocked lighting, disappearing rails or a covering
stone outline also prohibit its use. Original capture uptime must be passed
explicitly; processing time/redraw fallback must never generate a receipt.

Even if validated, the proposed consumer is only the expected-empty neighbor
veto. It cannot clear hand/dark gates, authorize a target, lower stone-confidence
or fit thresholds, reset witness timing, or add a move. Existing spatial offset,
legal single-addition and capture validation remain authoritative. Expected stone
counts may constrain a candidate but cannot prove an obscured location empty.

## Required work before any acceptance change

1. Measure the actual four inner samples at retained point 59.
2. Verify current-pixel controls: halfway/bleed, opaque body, shadow, glare,
   displaced stone, real second stone, both colors and board edges/corners.
3. Run receipt provenance regressions, including reused timestamps on different
   images and changed readings restored to their previous values.
4. Run real controller sequences showing acceptance improves on supported fresh
   evidence while ambiguous and illegal sequences preserve moves and clocks.
5. Independent review and root-owned full native validation/integration.

At this checkpoint only Swift syntax parsing and `git diff --check` have passed.
The new test suite is not yet executed. The physical baseline owns the build slot.
