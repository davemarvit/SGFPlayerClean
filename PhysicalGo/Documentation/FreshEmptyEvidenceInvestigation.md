# PG23 fresh empty-crossing evidence investigation

Source baseline: `fb4697c4ef314d83a253bd0aa219de1bb6b3d61f`.
This checkpoint is a **reviewable native recognition candidate**, not installed.
It carries existing positive reference-wood proof through the actual analysis
pipeline to the AI controller's expected-empty neighbor check. Original capture
time, image/reference identity, unchanged readings and existing spatial/temporal
admission rules remain required. No physical delay improvement is claimed.

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
approximately 1.3 GB of existing regression fixtures; the full worktree including
tracked resources and its native regression cache is approximately 1.5 GB.

## Findings and bounded producer experiment

The actual reference-backed empty test already compares at least sixteen current
wood samples, requires at least 75% matching color/level support and independently
requires at least 75% survival of both printed rails. It sometimes reports 0.75,
which the controller's blanket 0.8 neighbor veto discards.

An initial, stricter engineering hypothesis required all four innermost samples
at offsets ±0.075 cell to match wood. It was intended to challenge a halfway
stone, but those patches can straddle printed ink. **The next diagnostic falsified this proposal for the
retained frame:** point 59 has 21/27 matching wood samples, 3/4 horizontal and 4/4
vertical rail support, but only 3/4 matching innermost samples. A four-inner-sample
receipt would abstain and would not repair this case. Four-of-four was an
engineering hypothesis, not a user or root requirement. Its failure calls for
examining the missing support and competing stone hypotheses, not automatically
loosening it to three-of-four.

This second diagnostic retained `inner-result.json`, `inner-result.log` and
`inner-timing.json`. Its whole runner took 3.322 seconds including image IO,
one detector call and JSON serialization; that is not production latency.
The next diagnostic compared unchanged fit thresholds with the independently
admitted White40 outline and provisional existing Black60 mask around Black41:
quality was 0.730711 without masks, 0.738917 with Black60 and 0.706712 with both.
No fit qualified and all 361 labels stayed unchanged. The opposite-color mask
hypothesis did not resolve the missing outline. Point59 is the weak empty neighbor in this photograph;
it must not be conflated with the later game's new White59 stone.

The schema binds support to an exact image UUID, reference UUID, capture uptime,
point and unchanged reading. Reading replacement, timestamp replacement, image
or reference replacement, manual labels and tracker reassignment invalidate the
receipt. Unknown hand state, blocked lighting, disappearing rails or a covering
stone outline also prohibit its use. Original capture uptime must be passed
explicitly; processing time/redraw fallback must never generate a receipt.
Geometry conflicts are current-image guards: same-image refinement can discard a
bad outline while preserving an unchanged pixel receipt. Reading and provenance
replacement permanently discard it. The test draft explicitly covers this
distinction rather than claiming every observation mutation is irreversible.

The candidate consumer is only the expected-empty neighbor
veto. It cannot clear hand/dark gates, authorize a target, lower stone-confidence
or fit thresholds, reset witness timing, or add a move. Existing spatial offset,
legal single-addition and capture validation remain authoritative. Expected stone
counts may constrain a candidate but cannot prove an obscured location empty.

## Semantic receipt experiment

The four-inner-sample requirement was removed from the experimental receipt.
Those probes can straddle printed ink; their counts remain diagnostic metadata.
The producer retains the **original unmasked reference-wood predicate**, including
its sample-count, color/level and independent two-rail gates, without changing any
threshold or classifier result. No shadow-mask fallback emits a receipt.

The focused producer and pure spatial-eligibility experiment passed 30 checks:

* Retained point59 receives its actual current-image positive proof; all361
  classifier readings equal the immutable baseline. The old blanket neighbor
  test blocks target41, while the receipt-aware experiment makes it spatially
  eligible under the existing legal single-addition function.
* Nine synthetic pixel controls on the same photographed board cover partial
  black, full black, neutral gray, white/glare, wood-colored cover, axial halfway
  black/white and diagonal halfway black/white. All nine *observed* outputs
  withheld point59's receipt. The runner requires receipt rejection for the
  seven central/axial covers and separately requires target41 ineligibility for
  all nine. It intentionally permits a diagonal receipt if that crossing remains
  clear, provided competing assignment still prevents the move.
* Four archived actual halfway-White275 observations still reject; four archived
  legitimate White180 observations remain eligible. These are observation
  boundary fixtures, not fresh reruns of their original pixels.
* Wrong expected color remains ineligible; missing capture time emits no receipt.

This eligibility experiment explicitly synthesizes the prior board from the
later photo minus target41. The historical delayed controller checkpoint is
missing. It does not exercise the live controller's clocks, dark/hand episode,
consecutive fresh witnesses or persistence, and it measures no delay improvement.

The final original-timestamp producer/eligibility replay passed all 30 checks in
`PhysicalGo/.build/pg23-original-time-replay/`; `provenance.json` records the source,
input and immutable-runtime hashes. No synthetic time is substituted for the
photograph or archived observations. Schema/provenance tests passed 188 checks.

## Runtime wiring and native verification

`ExperimentModel` passes its optional original `captureUptime` to the worker's
`originalCaptureUptime`. `trackingTime` may fall back to processing time, so it is
not used to make a receipt. The detector binds each receipt to the immutable
GrayFrame image UUID, reference UUID, capture uptime, point and exact reading.

`EstablishedStoneTracker` and `KnownEmptyLighting` now copy the raw observation
before replacing readings. The reading setter drops incompatible receipts and
tracker reassignment invalidates receipts at both source and destination points.
This also retains other existing image metadata rather than reconstructing an
incomplete observation. Manual photo preview still reconstructs without receipts.

In `PhysicalAI.consume`, only a low-confidence **EMPTY** expected-empty neighbor
can be resolved by `hasFreshEmptyCrossingEvidence`. Unknown/nonempty neighbors,
covering outlines, target assignment offsets and all later move/capture/temporal
rules are unchanged. The trace's `freshEmptyPlacementNeighbors` lists the target
and neighbor points whose positive proof avoided the scalar-confidence reset;
`unresolvedPlacementNeighbors` still records remaining blockers.

The complete shared native regression runtime compiled as
`f0f733ded0318b301994f2306c6bb0ead04b2e13ac636acc648284a867c89f98`.
The following 572 checks passed:

| Suite | Checks |
|---|---:|
| `--ai-empty-evidence-test` (actual controller/pipeline) | 113 |
| `--ai-ambiguous-placement-test` | 57 |
| `--ai-checking-controller-test` | 31 |
| `--empty-evidence-test` | 188 |
| `--known-empty-lighting-test` | 101 |
| `--stone-tracking-test` | 82 |

The new controller suite covers both colors at nine edge/corner/interior points,
normal multi-frame stability, unsupported-neighbor streak resets, duplicate and
stale frames, wrong image/reference/time, reading mutation, uncertain/extra
objects, conflicting geometry, hand/unknown-hand, lighting and the real manual
dark barrier. The pipeline test proves original capture time and immutable image
identity survive analysis, while absent original time produces no receipts.
The existing photographed ambiguity and tracker suites remain green.

Logs: `.build/pg23-controller-validation.log` and
`.build/pg23-controller-rerun.log`. The first app-suite attempt encountered missing
tracked Kokoro resource files in the sparse checkout; materializing those files
fixed setup. There was no native source compilation failure. The final five-suite
rerun passed; the separately completed provenance suite supplies the sixth suite.

Reproduction tool: `PhysicalGo/Tools/replay_fresh_empty_evidence.py`, with explicit
immutable runtime, later-frame metadata/image, archived empty reference and a new
output directory. It verifies all baseline sources and runtime artifacts before
compiling its small subset, records input hashes, and never operates the app.

## Required before installation and issue closure

1. Independent review of the complete producer, propagation and consumer diff.
2. Root-owned combined native/host integration validation and installation.
3. Root-owned physical replay must establish actual recognition improvement.
   The original R16 25.418-second delay cannot be measured retroactively.
