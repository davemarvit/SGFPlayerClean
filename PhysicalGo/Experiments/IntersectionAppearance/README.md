# Expected appearance at each intersection

November 23, 2026. Offline investigation; no recognition, app, camera, laser or
safety setting changed. This work answers whether local empty/black/white
appearance could complement the current camera evidence.

**Recommendation:** reuse the existing appearance model and local references in
an observation-only diagnostic first. Add a location-aware description of what is
known, missing, occluded or no longer applicable. Do not start a second independent
classifier or treat agreement between two analyses of the same pixels as two
independent votes. A learned appearance check may help resolve some uncertainties;
it cannot certify that an obscured intersection is clear.

## What already exists

| Capability | Current implementation | What it does / limitation |
|---|---|---|
| Empty appearance specific to each intersection | `Sources/BoardVision.swift`, `KnownEmptyLighting.swift`, `LightingCompensation.swift` | Compares the local current patch with the same location in the empty reference; accounts for lighting, wood tint and surviving grid lines. This already supplies much of the suggested local empty model. A wrong/occupied reference must not be assumed empty. |
| Current-image appearance without trusting an old reference | `Sources/BoardAppearanceDetector.swift` | Fits nearby wood, inspects dark/light bodies and visible grid, bounded white outlines and exposed wood. Shading and adjacent stones already have explicit handling. |
| Learned empty/black/white feature ranges | `Sources/StoneAppearanceModel.swift` | Five features: brightness relative to wood, body brightness variation, color difference from wood, visible grid contrast and body/rim contrast. Descriptive median/ranges, with uncertainty outside support or when alternatives overlap. These are not calibrated probabilities. |
| Confirmed examples and comparison UI | `StoneCalibrationArchive.swift`, `StoneCalibrationWorkflow.swift`, `StoneCalibrationView.swift` | Three user-confirmed photos: empty, six stones, colors swapped. Keeps raw pixels, labels, geometry, versions and camera context. The inspector compares three appearances at a selected point. **This learned model does not change production recognition or dispatch.** |
| Neighbor effects | `StoneAppearanceModel.swift`, `BoardAppearanceDetector.swift` | Learned empty distributions can differ beside one/several black or white stones. Missing neighbor labels remain unknown. Black and white each retain one pooled learned distribution. Dense mixed-color crowds remain poorly represented. |
| Established occupied appearance | `Sources/OccupiedReference.swift`, `OccupiedStoneOutline.swift`, `StoneTurnAppearance.swift` | Remembers supported physical appearances, invalidates/challenges changed patches, and distinguishes raw evidence from retained results. The expected game position alone is not a new visual observation. Do not let a retained answer train itself. |
| Geometry, height and placement | `Sources/StoneGeometry.swift`; offline `Tools/parallax_lab.py` | Fits stone outlines and assignment geometry. The offline parallax study models a position-dependent displacement from stone height. Empty grid plane and top of stone are different surfaces; a single translated template is insufficient in general. |
| Local view quality and stone identity experiments | `Tools/local_quality_lab.py`, `stone_identity_lab.py`, `occluded_identity_lab.py` | Existing offline work on local visible-background quality and identity over time. Reuse their evidence contracts rather than creating a separate game history. |

Paths in this table are relative to `PhysicalGo/`. The production appearance
classifier and the experimental learned feature model are different components.
The latter currently remains an inspection tool by deliberate design.

## Existing historical result — not rerun or newly measured here

The earlier audit in [the app README](../../README.md#guided-stone-calibration-and-experimental-appearance-ranges-066)
and `Tools/StoneAppearanceAudit.swift` / `stone_appearance_report.py` uses frozen
human labels from `Tests/Fixtures/ShadowRegression/v1`. Its metadata identifies
FULL HD WEB CAM, camera ID `0x21440000bda0567`, five November 2 sessions. It is not
the moved November 23 setup and is not pooled with iPhone recordings.

| Earlier experiment, 449 visible labels | Correct | Uncertain | Wrong |
|---|---:|---:|---:|
| Production detector at the time of that study | 391 | 52 | 6 |
| Appearance proposal gated by strong outline/visible grid | 417 | 26 | 6 |

All 26 improvements were empty intersections. The appearance-only model made a
new error. **The gated proposal also changed one occluded uncertain example to
empty.** This is decisive evidence against directly enabling it for hand clearance
or move acceptance. The old counts are selected correlated historical examples,
not current-build or general gameplay accuracy. Training excluded the entire test
session and selected one training sample per labeled point/episode; the equipment
was shared, so this was not an independent setup holdout.

## New measurement — confirmed November 4 calibration archive

`audit_archive.py` reads retained confirmed labels and previously extracted
features. It does not run a camera or classify new images. Full metadata, image
and profile SHA-256 hashes are in [nov4-archive-results.json](nov4-archive-results.json).

Archive: `~/Library/Application Support/Physical Go/Stone Calibration/EF139BC6-9185-4854-AA0E-47C81E439CE3`.
Three captures at 1920×1080: empty at 18:35:54 UTC (app 0.66), then two color rounds
at 18:55:23 / 18:55:54 UTC (app 0.67). The two stone captures identify camera
`0x21440000bda0567`; the legacy empty capture lacks a camera ID. Their association
comes from the saved confirmed calibration session, not an assertion that this
matches today's camera geometry/exposure. No current model is loaded from it.

| Label | Examples | Distinct intersections | Brightness relative to local wood, range |
|---|---:|---:|---:|
| Empty | 132 | 48 | −0.0166 to +0.0153 |
| Black | 6 | 6 | −0.6584 to −0.5508 |
| White | 6 | 6 | +0.0122 to +0.0902 |

Brightness is on a 0–1 scale. In this sample, the dimmest white contrast is only
about 3/255 above the wood estimate, whereas black contrast is much larger. This
supports treating the colors separately and retaining grid/outline/color evidence
when white brightness overlaps empty wood. It does not establish universal bounds.

Coverage is the larger issue: **only 6 of 361 intersections have labeled examples
of all three states**. Forty-two other intersections have empty examples, and 313
have no explicit calibration sample labels. Omitted points are not silently
promoted to ground-truth empties. Neighborhood records comprise 56 open, 40 beside
one black, 40 beside one white, 4 beside several black, 4 beside several white; no
mixed-color or unknown-neighbor examples. There are no labeled hand/glare/shadow
challenge states in this calibration.

The audit exactly reproduces the archived Swift pooled median/range model
(numerical tolerance 1e−10). An internal sanity check withholds all samples at one
intersection before testing that intersection: 142 correct, 2 unknown, 0 wrong.
The two unknowns are one black and one empty. **This is not a held-out episode or
setup evaluation**: training and test share the same three images, lighting and
camera, and unchanged empty spells are repeated. It is a check of feature ranges
and spatial coverage, not evidence that a new classifier should be deployed.

## Proposed incremental design

1. Keep one geometry/context identity: camera ID, image dimensions/crop, board
   calibration revision, empty-reference identity, stone set/height when known,
   exposure regime and capture provenance. A moved camera invalidates location
   templates. Missing context is unknown, not a match.
2. Store a reliable empty patch and feature ranges **per intersection**, with
   its own rail visibility and quality. Where a stone is present during setup,
   that location lacks an empty observation unless an earlier compatible empty
   reference exists. Never write the occupied patch into the empty model.
3. Use shared black/white appearance models with conservative local adjustments
   for measured wood color, perspective and supported height/outline geometry.
   Distinguish an appearance actually observed at a location from one predicted
   from other locations. Do not fit three unrestricted templates independently
   at 361 points from twelve stone examples.
4. Keep absolute lightness and normalized features together. A normalization
   that removes a smooth lighting change must not also remove evidence of a
   low-contrast object. Separate grid-line visibility, chromaticity, shape,
   clipping/blur and local residuals. Broad smooth changes can be consistent
   with illumination; they do not prove absence of a hand or stone.
5. Return `empty / black / white / uncertain`, per-class confidence and the
   selected-class confidence, plus visibility/context status. The historical
   audit calls abstention `unknown`; the proposed contract uses `uncertain`.
   Explicit states should include occluded, clipped/glare, blurred, unsupported
   geometry and missing reference. Poor quality blocks a decision and learning.
   An expected or legal move may prioritize inspection, never provide its label.
6. Compare the new appearance evidence with current detector output in a log.
   Record disagreements and abstentions first. Features share pixels with the
   existing detector, so do not multiply their scores or increase confidence
   simply because they agree. Any future fusion needs calibration on held-out
   episodes/setups, not presumed independence.
7. Learn from explicit confirmed examples or separately validated physical
   evidence with provenance. Keep immutable anchors, bounded candidate updates
   and rollback. A retained decision, board expectation or requested laser target
   cannot train its own confirmation; an obscured location cannot refresh.

A useful diagnostic row would contain `contextID, frameID, point, referenceID,
referenceStateKnown, appearanceActuallyObserved, woodCorrection, featureVector,
classEvidence, selectedClassConfidence, visibilityQuality, contextSupport,
abstentionReason, baselineCall, baselineScore, proposedCall,
neighborEvidenceSource, correlationFamilies`. Record where features were sampled relative
to the fitted stone body and printed intersection. This makes a displaced stone,
a changed light and a wrong class distinguishable in analysis.

## Confidence contract for downstream combination

Dave explicitly requested confidence in addition to the class. Include it from
stage one; the fact that the present model is uncalibrated changes its meaning,
not whether downstream receives useful graded evidence.

| Field | Meaning now | Meaning after calibration |
|---|---|---|
| `classEvidence.empty/black/white.rawSupport` | Original feature distance, metric/version, units and direction. Preserve the actual measurement before any confidence transform. | Unchanged; retained for diagnosis and recalibration. |
| `classEvidence.<class>.confidence` | A 0–1 **appearance-support score**, explicitly `uncalibrated`. For the existing model, `exp(-0.5 * distance²)` is its compatibility score. Higher means a closer feature match, not an observed correctness rate. | May additionally contain a calibrated class probability with calibration ID, target population and evaluation provenance. Never silently change the meaning of the existing support score. |
| `selectedClassConfidence` | The selected class's confidence object, including support score and calibration status. | Also exposes its calibrated probability when applicable to this setup/domain. |
| `bestSupportedClass` | Highest-support class, even when the final label is `uncertain`. | Still distinct from a decision that passes visibility/context requirements. |
| `abstentionReasons` | Explicit reasons for `uncertain`: alternatives overlap, weak support, occlusion, insufficient context, invalid geometry, glare or stale data. | Retained; a strong class probability does not override inadmissible visibility/context. |
| `visibilityQuality` | Separate status and a named quality score when measured; `null` if unmeasured. It describes whether pixels can support this decision, not which color is present. | Any calibrated visibility confidence has its own target and calibration. |
| `contextSupport` | Whether reference, camera, geometry, exposure and appearance domain apply; include missing/mismatched fields and optional named support score. | Controls whether a fitted calibrator is applicable. Out-of-domain results lose calibrated-probability claims. |
| `provenance` / `correlationFamilies` | Capture identity, epoch/frame/time, reference, setup, feature/model revision, dependencies and temporal episode. | Also identify calibration dataset/split/version, preserving shared dependencies. |

A future `classProbability` should name its target explicitly: physical class
conditional on an admissible view and the validated setup domain. Only a jointly
calibrated three-class model may promise a normalized probability vector; a
separate visibility or context score is not a fourth occupancy probability.

The three current appearance-support scores **need not sum to one**. Several
classes can fit poorly, or more than one can fit well. Normalizing those scores
to sum to one would hide those cases; it would not calibrate them. Missing
measurements are `null` with a reason, rather than zero, because missing evidence
is different from evidence against a class.

`uncertain` is an abstention, not a fourth physical stone state. Keep all measured
class confidences when abstaining. `selectedClassConfidence` is then `null`, with
an abstention reason, while the best-supported class and its confidence remain
available. Do not invent a probability of being “uncertain.” A separate future
confidence that the view is unusable would belong to visibility, with its own
labels and calibration.

[confidence-example.json](confidence-example.json) is an **illustrative design
example**, not a measured frame or an implemented runtime API. It shows white
appearance support of about 0.783 from distance 0.7, with class probabilities still
`null`. In the same measurement, an occlusion finding would change the final
label to `uncertain` and selected-class confidence to `null`; the three measured
supports would remain in the log, visibility would say `occluded`, and downstream
would receive `abstentionReasons: ["occluded"]`. A calibration failure that makes
the sampling location invalid would instead mark the class measurements missing;
old scores must not survive as if they described the current intersection.

### How downstream can use it

Initially, consumers can compare relative support, preserve weak alternatives,
prioritize a new observation, or record disagreement. A score of 0.8 cannot be
reported as “80% likely correct.” Selection thresholds and any downstream use
remain separately evaluated; this contract does not activate a new move rule.

Treat feature vectors derived from the same image/reference as a correlated
family. Keep the production detector, appearance model, grid evidence and any
other shared-pixel inputs together for a future jointly evaluated fusion model;
do not multiply their confidences as though they came from independent sensors.
Repeated adjacent frames also share a temporal episode. Explicitly retained
provenance lets consumers deduplicate the same capture and recognize common
reference or model failures. Disagreement is useful evidence, but agreement does
not automatically increase confidence.

For empirical calibration, split by complete episodes and camera/setup families:
fit appearance parameters on training groups, fit confidence mapping/fusion on
separate labeled calibration groups, and evaluate on untouched groups including
a moved setup. No adjacent-frame random split or expected-move labels. For each
class, retain reliability by score band, class errors, abstention coverage and
occlusion failures, with episode-level uncertainty estimates and domain metadata.
If there is too little independent evidence in a regime, keep its status
`uncalibrated` or `unsupported` rather than publishing an unsupported probability.
A later fused probability must itself be calibrated/evaluated; individually
calibrated inputs do not make their arbitrary combination calibrated.

## Validation before any live use

Use the current scene-change manifest separately for its November 21, 22 and 23
setups (`DYNAMIXEL-Go-Pointer/.../Experiments/SceneChangeDiagnostics/`). Those
16 comparisons include a suspected shadow, visibly blurred withdrawing hand and
cleared frames with changed stones. They are valuable challenge candidates, but
the image-level descriptions are not dense per-intersection occupancy/visibility
labels. Do not use the app's hand-clear flag or recorded game position as their
physical ground truth. The scene study's scores are not new appearance results.

Freeze manual labels before looking at the new scores. Label only visible cells;
keep occluded and undecidable cases. Reserve complete later episodes and a moved
setup for evaluation, with no template updates from their test labels. Keep
November 4, November 21, November 22 and November 23 geometry/reference families
separate, even when a camera ID matches. Older iPhone material stays separate.

Report per-color mistakes, newly decisive occluded cells, uncertainty coverage,
changed-stone detection and locality of errors; give episodes one vote rather than
counting adjacent frames as independent trials. Stratify edges/corners, empty
rails, neighboring stones, white glare, black highlights, stone-height offset,
hand/shadow and camera/exposure changes. Evaluate occupied-reference mistakes
explicitly. Recheck current production behavior on the exact same pixels if
claiming improvement; the earlier 391/52/6 baseline is historical.

Next practical step is a diagnostic comparison using the existing feature
extractor and these provenance/visibility rules, followed by manual labeling of a
small current-camera challenge set. Full 361-point stone calibration is neither
necessary nor supported by the present evidence. No new physical user procedure
or runtime gate is required by this report.

## Reproduce the new audit

From the application repository root, choose a new output filename:

```sh
python3 PhysicalGo/Experiments/IntersectionAppearance/audit_archive.py \
  '/Users/dave/Library/Application Support/Physical Go/Stone Calibration/EF139BC6-9185-4854-AA0E-47C81E439CE3' \
  /tmp/appearance-archive-review.json
```

Python standard library only. It validates stage/label association, dimensions,
known camera consistency and finite feature values, hashes retained sources,
checks exact pooled-model parity, and refuses to overwrite the output. The script
is an audit of the existing model, not a replacement feature extractor or a
probabilistic classifier. Raw recordings remain in their existing archive.
