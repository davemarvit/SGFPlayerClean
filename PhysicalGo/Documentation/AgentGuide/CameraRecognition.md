# Camera, hand clearance and stone recognition

[Start here](README.md) · [Current status](../IntegrationChecklist.md)

The app owns the selected AVFoundation camera. The pointer consumes app-published
pixels; starting another camera client can inspect the wrong feed or disturb the
active stream. Device identity, board geometry and laser calibration are separate
things to verify after equipment moves.

## Follow an observation

1. [CameraCapture.swift](../../Sources/CameraCapture.swift) configures the selected
   device, delivers advancing frames and handles bounded recovery. Preview
   visibility alone does not prove that a consumer received a fresh frame.
2. [CameraFrameTimestamp.swift](../../Sources/CameraFrameTimestamp.swift) converts
   a valid camera presentation time to host uptime. A delayed capture remains old;
   it is not relabelled with its arrival time. Callback time is an explicit fallback.
3. [ExperimentModel.swift](../../Sources/ExperimentModel.swift) supplies current
   calibration, reference, expected position and revision to the analysis worker.
4. [CameraAnalysisPipeline.swift](../../Sources/CameraAnalysisPipeline.swift)
   evaluates alignment, exposure, hand evidence, occupancy and tracking. Its early
   safety callback and final result must belong to the same current revision.
5. The selected game controller consumes admitted observations. AI evidence is
   additionally gated by the laser's verified darkness and camera watermark.

| Concern | Sources to inspect |
|---|---|
| Grid finding/tracking | [AutoGridDetector.swift](../../Sources/AutoGridDetector.swift), [BoardAlignmentGate.swift](../../Sources/BoardAlignmentGate.swift) |
| Occupancy and stone shape | [BoardVision.swift](../../Sources/BoardVision.swift), [StoneGeometry.swift](../../Sources/StoneGeometry.swift), [BoardAppearanceDetector.swift](../../Sources/BoardAppearanceDetector.swift) |
| Hands and delayed clearance | [BoardHandDetector.swift](../../Sources/BoardHandDetector.swift), [HandOutlineTracker.swift](../../Sources/HandOutlineTracker.swift), [HandOutlineSampling.swift](../../Sources/HandOutlineSampling.swift), [HandMotionTiming.swift](../../Sources/HandMotionTiming.swift) |
| Glare/lighting/reference evidence | [KnownEmptyLighting.swift](../../Sources/KnownEmptyLighting.swift), [LightingCompensation.swift](../../Sources/LightingCompensation.swift), [OccupiedReference.swift](../../Sources/OccupiedReference.swift), [OccupiedStoneOutline.swift](../../Sources/OccupiedStoneOutline.swift) |
| Established stones and uncertain positions | [EstablishedStoneTracker.swift](../../Sources/EstablishedStoneTracker.swift), [PlacementAmbiguity.swift](../../Sources/PlacementAmbiguity.swift), [RetainedTurnPosition.swift](../../Sources/RetainedTurnPosition.swift) |
| Cadence and backlog | [CameraProcessingCadence.swift](../../Sources/CameraProcessingCadence.swift), [LatestAnalysisInput.swift](../../Sources/LatestAnalysisInput.swift) |

## The laser frame broker

[PhysicalLaserFrameBroker.swift](../../Sources/PhysicalLaserFrameBroker.swift)
publishes immutable PNG names and atomically replaces `frames/latest.json` under
`~/Library/Application Support/Physical Go/LaserBridge/`. It has one replaceable
pending image and retains at most four published PNGs. These transient images
support optical alignment and spot measurement; they are not the same as a saved
diagnostic recording or a saved game.

Each manifest includes camera ID/context, calibration, hand/alignment verdicts,
stream epoch, frame ID, capture/arrival times and timestamp source. Prepared image
bytes are cached by **epoch plus frame ID**. Frame ID alone can repeat after a
restart and must never pair old pixels with new metadata.

The host [FrameReader](</Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware/bridge_frames.py>)
checks identity and capture/publication/arrival ages. A recent manifest write
cannot make an old image fresh. Hardware dark evidence additionally needs a
post-receipt watermark and a presentation flush; callback timestamps require an
explicit measured flush bound. See [Laser control](LaserControlCalibration.md).

## Expected position is useful context, not fresh evidence

Expected stones help tracking, but must not manufacture a newly placed stone or
erase uncertainty. `PhysicalAI.referenceCells` can describe the physical position
before an unplaced AI move even though the logical board already contains that
move and its captures. Preserve this distinction when optimizing recognition.

`ExperimentModel.recoveryExpected` excludes ended AI games from cleared-board
recovery while retaining expectations for unfinished/paused games. A historical
game is not automatically a valid setup constraint after the physical board is
cleared. Preserve the old save; do not repair setup by deleting game history.

## Evidence to collect for a failure

Use the [diagnostic pause procedure](Troubleshooting.md#first-response-to-a-reported-malfunction)
first. Record the selected camera ID, calibration/context, stream epoch, frame IDs,
timestamps, hand/alignment flags, uncertain cells and logical/physical expected
positions. Preserve the frame before the event, the event and clearance/recovery.
The guide does not infer a cause from a generic “stale camera” error alone.

Targeted suites include `--hand-outline-test`, `--hand-stall-storage-test`,
`--latest-analysis-input-test`, `--broker-epoch-test`, `--recovery-lifecycle-test`
and incident-specific fixture suites in [test_suites.py](../../scripts/test_suites.py).
Use the recording that reproduced the defect rather than a visually similar
unrelated image. Offline clearance success still requires a live hand/stone test.

## Expected appearance at individual intersections

The detector already compares local patches with an empty reference. The separate
`StoneAppearanceModel` learns empty/black/white feature ranges from confirmed
calibration photos and is currently an inspector, not a live recognition input.
See the [offline appearance study](../../Experiments/IntersectionAppearance/README.md)
for the capability map, historical findings, November 4 archive coverage audit
and proposed provenance/occlusion requirements. Historical gains do not establish
hand clearance: the earlier offline proposal also resolved an occluded example
to empty. Keep setup-specific references and unknown visibility explicit.

The [proposed confidence contract](../../Experiments/IntersectionAppearance/README.md#confidence-contract-for-downstream-combination)
includes raw per-class support, graded confidence with explicit calibration
status, selected-class confidence and abstention reasons. Visibility/context
quality and shared-image/reference provenance remain separate for downstream
combination. The example is documentation only; no classifier is activated.

## Parallax, stone-set profiles and spatial assignment

The November16 [parallax study](../OfflineHandParallax-2026-11-16.md) is offline;
board-plane alignment does not itself compensate raised-stone height. A fitted
center can also be biased relative to the visible body, independently of physical
parallax. November23 native replay identified a White brightness mask favoring
its upper region. Correct color confidence is not intersection confidence.

The current checklist tracks the narrow assignment guard and staged app. It
blocks new/pending stone assignments when adjacent expected-empty crossings lack
fresh clear evidence, preventing old empty labels from resolving new ambiguity.
The preserved wrongly assigned White and legitimate White are regression inputs.

New isolated, explicitly unvalidated work is in the application repository's
`codex/stone-set-profile-study` (Experiments/StoneSetCalibration and WhiteCentering)
and `codex/stone-set-profiles` (Experiments/StoneSetProfiles) branches. Named sets
separate optional measured thickness from estimator-specific optical candidates.
Camera/grid geometry belongs to the setup. Row-pitch units require their original
board-spacing identity; millimetres require a physical scale. Selection is not
runtime activation. Follow the independent review and retain failed geometry
hypotheses and negative controls rather than calling a low fit residual physical
thickness or portability evidence.

The exact White-vote diagnosis and independent full-search reproduction are on
[`codex/white-vote-mask-diagnostic` at e6a6e85](https://github.com/davemarvit/SGFPlayerClean/blob/e6a6e85/PhysicalGo/Experiments/WhiteVoteDiagnostic/IndependentReview.md).
Its bounded next step separates full-boundary geometry from color classification,
reports coverage/ownership/disagreement, and abstains when unresolved. The
approximately 0.11-row discrepancy in two recorded stones is not a portable
constant correction or a physical thickness measurement.

The fresh displaced-color study is independently reviewed at
[`201a258`](https://github.com/davemarvit/SGFPlayerClean/blob/201a258/PhysicalGo/Experiments/StoneSetCalibration/FreshMidpointIndependentReview.md).
These are two negative episodes at a previously fitted side-middle location;
explicit per-frame-grid → raw-pixel → frozen-grid mapping preserves the small
view change as uncertainty. It is not a live classifier/acceptance test.

The separate boundary experiment
[`b4184d5`](https://github.com/davemarvit/SGFPlayerClean/blob/b4184d5/PhysicalGo/Experiments/BoundaryGeometry/README.md)
exposes center, angular support, neighbor ownership, discrepancy and abstention.
Independent review `4c958ce` proves closed shadows/nonstone patches can still
receive geometric support. Its machine-readable `diagnosticOnly` and
`stoneVersusShadowUnverified` fields forbid interpreting that support as validated
stone identity or centering accuracy. No runtime consumer exists.

For the separate native-detector baseline, see
[`46b9cdd`](https://github.com/davemarvit/SGFPlayerClean/blob/46b9cdd/PhysicalGo/Experiments/FreshNegativeNativeReplay/README.md).
It reproduces archived frame697's footprint categories exactly before replaying
32 saved centered/displaced images. Fresh displaced White yields two uncertain
crossings and no local native fit; fresh displaced Black yields a fit with an
uncertain neighbor. The caller must not confuse stateless class/shape evidence
with full temporal/controller acceptance or an available laser hint target.
