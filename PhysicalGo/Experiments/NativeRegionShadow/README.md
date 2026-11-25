# Native regional shadow scheduling — November25,2026

**Defer runtime adoption.** This bounded native experiment is substantially cheaper
than the prior full-image Python gate, but it selects nearly the whole board and
still misses three changes in confidence evidence. It cannot save enough measured
classification work to cover its own cost. Installed native `1f6fb91` remains
unchanged; this directory has no production consumer.

## Fixed scope and evidence

Native base:`1f6fb91cac57616791d47c2fea4cc4eca0426a28`(installed0.265 source).
Exactly16 existing consecutive CrowdedWhiteAdjustment images,frames1379–1394,
cover3.152469s. They are historical occupied-board recordings from November2,
not the current webcam/setup. The fixture's original pending points are
39,20,58,78,77,97,96. No saved-game file is loaded into a mutable recorder or changed.

Every frame runs the **complete existing `BoardDetector.detect` stone-recognition
path** against the prepared original reference. No classification is actually
skipped or replaced. This is not the complete live `CameraAnalysisPipeline`:
live camera delivery, fresh grid tracking, Vision hand pose, temporal hand tracking,
game decisions and laser control are not run. Their costs cannot be counted as
savings. The fixture supplies retained calibration; conditional shadow planning
assumes it remains usable and that required hand/visibility admission is supplied
separately. Unknown versions of those conditions force full inspection in the
pure module; these assumptions do not qualify a live frame.

`result.json` stores per-frame native classifications/confidence, required and
proposed work sets, missed cells and timings. `provenance.json` hashes all nine
compiled source inputs and every used fixture, including original photo-label
corrections/provenance. The original fixture images are read from the existing
checkout; no images are copied or regenerated on disk.

## Shadow contract

The pure `ShadowScheduler.swift` returns **work requests only**. It cannot return
occupancy, fresh clearance, a placement vote, grid validity or activation authority.
Sampling uses existing `GrayFrame.patchMean/patchColor` primitives at a5×5 grid
within each intersection cell(9,025 small patches per frame), rather than another
full-image conversion. A fixed first-frame descriptor is retained for the entire
sequence; small changes cannot be absorbed by continuously advancing the anchor.

Normalization fits global gain/offset in three bounded robust passes using
prior independently classified empty cells, excluding the halo of pending,
uncertain and White-stone cells. These are **current wood candidates**, not proof
that an old empty cell is still exposed. The fit uses191 candidates after setup;
gain ranges0.9817–0.9989 and offset0.0001–0.0113. Failed/insufficient fitting requests
full inspection instead of declaring the image unchanged.

Frozen scheduling criteria:at least two of25 sample pairs differing by6/255 in
normalized luminance or0.018 in red/green chroma request that cell plus its immediate
neighbors. Invalid samples and a majority of nearly clipped/dark samples request
inspection. This is an exploratory scheduling policy, not a calibrated visibility
classifier. Thresholds were fixed before replay and not changed to erase failures.

Mandatory requests include the fixture's pending points, previously uncertain
cells and White-stone cells needed by the current hand-mask contract. Scope change,
unknown geometry/hand/visibility, a post-dark evidence barrier, or a1s full-refresh
deadline force all361 cells. Refresh requests occurred on1379,1384,1389 and1394;
they did not advance the original fixed anchor or create clearance evidence.

The full current recognition is used **after the scheduling decision as an audit
comparator**, never as an oracle to rescue the requested set. Required comparator
cells include current uncertainty, current White-stone evidence, occupancy changes,
crossing the explicitly chosen0.95 confidence boundary, appearance/disappearance
of a placement offset, offset movement>0.04cells, and pending points. The0.95
boundary tests whether cached evidence changes; it is not asserted to be every
game mode's actual acceptance threshold or a calibrated probability.

## Concrete result

Average selected cells:**358.5625/361**; range351–361. Only39 of5,776 cell visits
(0.675%) would have been omitted. The independently observed stone/unknown labels
are not replaced by the scheduler. Three required confidence changes were missed:

| Frame | Cell | Fixed-anchor confidence | Current confidence | Occupancy |
| --- | ---: | ---: | ---: | --- |
|1381|344|1.00000|0.93750|Empty→empty|
|1390|304|0.93750|0.96875|Empty→empty|
|1393|28|0.90625|0.96875|Empty→empty|

These are **not three missed stone placements**. They show that even a mostly
unchanged physical scene can change the evidence a fresh confirmation consumes.
The module cannot reuse an old high-confidence reading or manufacture a new vote.
No threshold was relaxed and no result was silently relabelled acceptable.

## Measured cost and its limits

The generated build-only copy of `BoardVision.swift` adds two clock reads and
an accumulator around each iteration of the original initial per-cell classification
loop. It changes no decisions and never changes the checked-out production file.
The build script requires exact source boundaries before inserting the hooks.
Neighbor conflict resolution, outline fitting, visibility refinement and final
reconciliation still run globally. No independently skippable runtime stage was
proven by this instrumentation.

| Cost | Median per frame | Total across16frames |
| --- | ---: | ---: |
|Small sample extraction|1.248ms|20.089ms|
|Shadow normalization/scheduling|0.416ms|6.422ms|
|Full native stone recognition|52.781ms|848.554ms|
|Instrumented initial classification loop|4.861ms|78.826ms|
|Loop work belonging to proposed omitted cells|0.011ms|0.441ms|
|Hypothetical net saving after sample+schedule cost|−1.620ms|−26.071ms|

Even the optimistic arithmetic loses about1.63ms/frame. Actual savings are zero
because the full detector still runs. Per-cell timing includes observer overhead;
the "omitted work" sum is an unrealized upper bound, not an accepted optimization.
The first frame is included and no warm-up repetitions were added. Recognition
ranged50.29–55.48ms; these16 observations are descriptive, not a long-run latency
tail study. PNG decode/reference preparation are excluded. The optional reference
patch preparation belongs to the existing native implementation, not this gate.

This explains why avoiding a large number of cell labels would not necessarily
avoid much work:the timed initial loop is only about9%of complete recognition,
and expensive shared geometry/appearance dependencies remain. Here almost no
cells were omitted anyway.

## Held-out controls and pure contract checks

No control below was used to tune thresholds:

- Retained hand frame950 from the same historical fixture:raw scheduling requests
  all361 cells, including independently labelled occluded95 and134. Explicit
  `handUnknown` also forces full work. This is a scheduling check, not a new hand
  detector validation or proof that all hands would trigger pixel differences.
- A labelled synthetic2px whole-board translation of anchor pixels, preserving
  grayscale and RGB together:raw scheduling requests all361; geometry-unknown
  policy also requests all361. No newly estimated homography is accepted.
- A labelled synthetic Black disk at known-empty cell180:raw scheduling requests
  95 cells including180. This is a changed-pixel control, not a physically validated
  Black-stone recognition result. Full detector comparison above applies to the
  retained16-frame corpus; these controls test the proposed work sets only.

Ten pure checks passed:identical samples, each of five mandatory full-inspection
triggers, scope change, neighboring-cell margin, changed-cell detection, and the
fact that identical hidden pixels still look unchanged without independent
visibility information. The prior block experiment's unsaturated-cover and
equal-summary negative controls remain relevant; they are not superseded by
success on these three controls.

## Recommendation and remaining acceptance

**Defer this scheduler.** It fails both bounded acceptance conditions:zero omitted
required evidence changes and avoided eligible work exceeding gate cost. Do not
integrate it merely because sampling is now cheaper, and do not trade away fresh
hand/placement/visibility evidence to make a timing result look favorable.

If PG24 is revisited, first identify a measured expensive stage with an explicit
dependency boundary. A diagnostic-only stage profiler around geometry/outline
refinement on a small retained corpus is more useful than further tuning these
pixel thresholds. Current White masks must still come from current independent
fits, as `HandOutlineSampling.swift` requires. Reusing accepted game/display state
and generating fresh sensor evidence remain different operations.

PG24 stays open. This checkpoint supplies an executable negative result and
reusable pure work-request boundary; it closes no installation or physical test.
Root owns integration, app builds and attended hardware verification.

## Reproduce

The focused build compiles nine sources, including a generated instrumented copy;
it does not build or launch the app. Reserve the compiler/compute slot with root.

```sh
python3 PhysicalGo/Experiments/NativeRegionShadow/run.py \
  --fixtures /Users/Dave/SGFPlayerClean-worktrees/camera-safety-delivery/PhysicalGo/Tests/Fixtures/CrowdedWhiteAdjustment \
  --output /tmp/pg24-native-shadow-reproduction
```

Use`--prepare-only` to inspect the exact command, generated source and hashes
without launching a compiler. The bounded replay has a180s timeout. One initial
experimental Swift expression hit the compiler's type-check complexity limit;
splitting that expression into typed steps produced the successful build/run.
No detector threshold, installed artifact, game or raw recording was changed.
