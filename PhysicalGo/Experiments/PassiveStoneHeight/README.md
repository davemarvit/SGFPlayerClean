# Estimating stone height during ordinary play

November 24, 2026. Offline feasibility audit, not installed or used for recognition.
No camera, application, serial connection, stone profile or laser setting was changed.

**Ordinary play can supply useful observations of the apparent stone-offset field.
It cannot, by itself, uniquely turn that field into physical stone thickness.**
The most useful first feature is passive estimation with held-out evaluation:
learn how a particular stone set appears in this setup, while keeping the
authoritative printed grid and existing placement decisions unchanged.

## What the observations identify

For an ideal point at effective height `h`, camera height `H`, board-plane camera
projection `C`, and actual contact position `P`, the board-rectified apparent center
is `A = P + k(P-C)`, where `k=h/(H-h)`. Ordinary play gives a likely intended
intersection `Q`, rather than independently measured `P`. Writing `P=Q+u` gives

`A-Q = k(Q-C) + (1+k)u + b(Q) + g(Q) + noise`.

Here `u` is actual placement error, `b` is the center estimator's shape/lighting
bias, and `g` is printed-grid/camera error. All are measured in the same board
coordinate system. Repeated frames reduce image noise; they do not average away
the fixed placement error of that stone. Treat one placement as one sampling
unit, even when it supplies many frames.

A global average offset is therefore useful as a diagnostic, but cannot tell
whether stones are thick, placed slightly off center, or measured off center.
A robust spatial fit across the board separates a constant bias from a
position-dependent trend. A placement tendency or grid-scale error with that same
trend remains indistinguishable from parallax. More observations do not resolve
that systematic ambiguity. In particular, never assume a pending AI target is a
confirmed stone location and adjust the model until the stone appears centered.

For direct physical millimetres we also need metric scale and trustworthy camera
geometry. A board homography alone aligns the plane; it does not calibrate every
lens parameter or off-plane projection. The standard planar calibration approach
uses multiple pattern orientations ([Zhang, Microsoft Research](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/11/zhan99.pdf)).
Existing fixed-camera assumptions can support a conditional optical estimate,
with the assumptions recorded. There is no need to move today's calibrated setup
to investigate passive offsets.

## Can shape help?

Yes, as an additional cue with an explicit shape model. An elliptical outline is
already expected from viewing a flat circular object obliquely, so ellipse ratio
alone is not a thickness measurement. Under the illustrative assumptions of an
axisymmetric ellipsoid, orthographic viewing, known diameter `2R`, thickness `t`
and viewing angle `theta` from the board normal, its projected minor/major ratio is

`q² = cos²(theta) + (t/(2R))² sin²(theta)`.

An 8→9 mm change for a 22 mm diameter stone occupying 40 pixels changes the minor
diameter by approximately 0.27 pixels at 35°, or 0.72 pixels at 55°. Directly
overhead it changes by zero. These are analytic examples, not measurements of
Dave's stones. Near-edge views are more informative, but shadows, glare, hidden
boundaries, neighboring stones and departures from the assumed lens shape can
exceed this signal. The silhouette center of a symmetric ellipsoid is its body
center (half its thickness above the contact plane), not its top surface. The
bright-region center can be somewhere else again.

Useful shape features include full visible boundary, near/far rim asymmetry,
ellipse ratio, and estimator-to-boundary disagreement, tracked across board
positions. Shape, offset and known measured thickness should remain separate
evidence channels. The selected black/white color is not a license to assume
the same geometry or optical bias for both.

## What the existing recordings already tell us

The November 23 stone-set study has eight deliberately centered positions per
color, six fitted and two reserved; eight frames of each static scene are not
64 independent placements. Its frozen corrections preserve two fresh displaced
Black/White episodes. Source and review references remain in
[CameraRecognition](../../Documentation/AgentGuide/CameraRecognition.md).

The White native fitter was independently shown to favor the upper bright part
of two stones, differing from their visible-body center by about 0.11 row
(4–5 pixels). Calling all that discrepancy physical parallax would be incorrect.
The earlier study's conditional height varies materially with grid choice and
whether constant estimator bias is included. For example, current-grid White
changes from 0.223 to 0.148 row pitches when constant bias is fitted; Black changes
from 0.063 to 0.039. These are optical candidates, not measured stone thickness.

This audit independently reproduces the current-grid spatial slope using an
explicit centered least-squares calculation. It compares a simple mean offset
against a spatial slope plus offset on the original two held-out positions:

| Color / held-out raw position | Uncorrected error | Mean-only error | Spatial-field error |
|---|---:|---:|---:|
| Black (9,3) | .140 | .100 | .091 |
| Black (9,15) | .060 | .051 | .052 |
| White (9,3) | .116 | .031 | .065 |
| White (9,15) | .102 | .043 | .009 |

Errors are grid cells. Neither correction wins everywhere. These are the same
historical centered scenes, not a fresh test of ordinary-play learning. This audit
does not refit or replace the prior profile, grid or calibration. It supports
measuring several models against held-out evidence instead of presuming height
explains every systematic offset.

## Low-friction plan for normal play

1. Reuse existing before/after move evidence. Choose a few clear, laser-dark frames
   after hand withdrawal; do all optional fitting off the camera safety path.
   Retain per-frame grid geometry and use exposed printed crossings to check drift.
2. Group frames by placement, setup, stone set, color and estimator version.
   Keep body/outline center, native center, mask-threshold spread and visible
   boundary coverage. Exclude occluded/touching/glare-dominated cases from fitting.
3. Treat accepted move identity as a tentative intersection label, not proof of
   exact centering. Keep ordinary-play samples separate from explicitly centered
   anchors. Record selection bias: recognition may preferentially accept stones
   already close to its current model, especially near the edges.
4. Fit robust constant and spatial offset candidates per color once there is
   broad two-dimensional support. Predict a new placement using the frozen model
   from earlier placements before considering that placement for training.
   Hold out entire placements and board regions, not adjacent frames.
5. Evaluate with original raw evidence and all available deliberately misplaced
   controls. Report uncertainty across placements, grids and contour methods.
   Track whether added shape evidence improves held-out prediction. A short
   optional deliberately centered check at separated locations can anchor the
   ambiguity if passive evidence remains inconclusive.
6. Only a later reviewed change could consume a candidate for recognition. It
   must retain real misplacement detection, never move the printed grid to follow
   stone tops, and never affect hand-clearance, clock or laser-motion authority.

There is no reliable universal required count. A few well-spread, independently
centered stones can identify a low-parameter optical field; a first-move cluster
cannot establish a board-wide correction. As a purely idealized calculation,
with 26-row-pitch camera height, assumed 23 mm row pitch, six-cell RMS spatial
spread and independent per-coordinate placement scatter of .05 cells, roughly
25 independent placements give a one-mm *standard error* in effective height.
At .10-cell scatter, that becomes roughly 100. Neither is a confidence guarantee,
and no amount removes systematic placement/grid/shape bias. Effective height is
still not total thickness. Report support and held-out error instead of promising
that the system will know thickness after a fixed number of moves.

## Reproduce

`audit.py` uses Python's standard library only and reads frozen JSON measurements.
It has no runtime importer, camera access or motion interface. Eight analytic
controls check exact slope, constant bias, the placement-only counterexample,
repeated-frame invariance, coincident-support abstention, and shape limits.
`results.json` records inputs and hashes, held-out outcomes and illustrative
sensitivity calculations. Run with a new output path:

```sh
python3 PhysicalGo/Experiments/PassiveStoneHeight/audit.py \
  '/Users/Dave/Documents/SGF PLayer/work/ai-laser-integration/stone-session-20261123/stone-set-calibration/offline-body-study-02' \
  /tmp/passive-stone-height-audit.json
```

Next implementation candidate: a bounded offline move-evidence extractor and
placement-level shadow report. This audit has not installed passive collection,
changed recognition, or claimed a physical-thickness estimate.

## Placement collector and held-out evaluator (PG-22 follow-up)

`placements.py` now implements an **offline measurement-manifest collector** and
placement-level evaluator. It reads already extracted stone-body-center JSON;
it does not extract pixels, acquire frames, change native collection, import
profiles, or feed a correction to recognition. The three original audit files
above are retained verbatim from `d0ed574` (this README adds this section).
No ordinary-play data has yet been evaluated with the new collector. Historical
static-study quality flags must not be invented merely to import that study.

Each manifest has `schemaVersion: 1`, `units: "gridCells"`, `sources`, and `frames`.
A source has a unique `id`, a relative or absolute JSON measurement `path`, and its
lowercase SHA-256 `sha256`. The CLI verifies those files before writing output.
Input and combined source JSON are bounded to 8 MiB, with at most 10,000 frame
rows. Outputs use exclusive creation, so an existing report is never overwritten.
All reads are explicitly named files; there is no scan of user recordings.

A frame row requires:

| Field | Meaning |
|---|---|
| `placementID`, `gameID`, `moveIndex` | Independent placement and accepted game-move provenance; move index is a nonnegative integer. Use stable globally unique placement IDs. |
| `frameID`, `sourceID`, `recordID` | Camera-frame identity and exact measurement record within the hashed source. Distinct mask thresholds from one frame are **not** distinct frames. |
| `setupID`, `cameraEpoch`, `calibrationSHA256` | Explicit setup, stream and printed-grid identity. |
| `stoneSetID`, `color`, `estimatorVersion` | Named stone set, `black`/`white`, frozen center estimator identity. |
| `labelKind` | `acceptedTentative` for ordinary accepted placements, or `explicitlyCentered` for independently centered study positions. Pending AI targets are rejected. |
| `point`, `offset` | Two finite numbers each: zero-indexed `(column,row)` in `[0,18]`, and apparent body-center minus intended intersection in grid cells. |
| `split` | Predeclared `train`, `heldOut`, or `misplacedControl`. Never choose the split after inspecting model results. |
| `quality` | Exact Boolean `true` for each of `handClear`, `laserDark`, `gridStable`, `fullBoundary`, `noGlare`, `noTouching`. Missing/unknown quality rejects the frame. These are recorded offline claims, never live clearance authority. |

The collector rejects conflicting context, point, game/move identity or split
within a placement, even if the conflicting frame fails quality filtering. It
rejects duplicate frame IDs within a placement and multiple placement IDs for the
same game move/context (a renamed placement cannot cross the split). Valid frames contribute a median
body-center offset; one placement has one vote regardless of frame count. Setups,
camera epochs, grids, stone sets, colors, estimators and label kinds are fitted
separately. A changed label regime cannot silently strengthen training support.

The diagnostic OLS constant-plus-radial-field fit is reused from `audit.py`.
A group abstains with fewer than six independent placements, less than four cells
of span on either axis, or nearly collinear support (covariance determinant at
most 1% of squared covariance trace). These are conservative **study gates**,
not calibrated confidence bounds or universal sufficient sample counts. A fit
without held-out placements is explicitly marked unvalidated. Frame replication
cannot satisfy the independent-placement gate.

Held-out placements and misplaced controls never enter fitting. Reports retain
uncorrected, mean-only and field residuals per placement, rather than hiding tail
regressions in one average. `--hold-out-regions` additionally requires training and
held-out placements to occupy disjoint regions in a fixed 3×3 partition of the
19×19 board. This is stronger than holding out adjacent frames, but remains one
user-declared split; it does not prove future-game portability. Deliberately
misplaced control residuals must be reviewed before any future promotion; this
tool has no promotion path or acceptance threshold.

```sh
python3 -m unittest discover -s PhysicalGo/Experiments/PassiveStoneHeight -p test_placements.py -v
python3 PhysicalGo/Experiments/PassiveStoneHeight/placements.py \
  /path/to/reviewed-measurements-manifest.json /tmp/new-placement-report.json \
  --hold-out-regions
```

The 14 tests cover repeated-frame weighting, frozen held-out and misplaced-control
fits, region leakage, color/label separation, conflicting placement identities,
unknown quality, missing/nonfinite provenance, degenerate support, input limits,
source-hash checking and exclusive outputs. Fixtures are explicitly synthetic;
passing them is not physical validation. Source hash verification proves which
measurement document was read, not that its manual quality/label claims are true.
The next step is a native or offline pixel extractor that supplies reviewed real
move measurements with these identities, followed by held-out ordinary-play and
misplacement evaluation. Physical thickness remains unidentified.
