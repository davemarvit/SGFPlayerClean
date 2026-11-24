# Offline named stone-set calibration proposal

Offline prototype and profile design, November 23, 2026. No installed UI, runtime
model or laser change. Fresh negative-control collection remains in progress.

The user normally does not know stone thickness. A named stone set should be
calibrated from deliberately centered examples and recalled later. Optional
measured thickness is useful input, not a required setup field.

## Distinguish the quantities

- The setup model contains the current camera identity/intrinsics/crop, printed
  grid homography, board row/column pitch, and camera pose hypothesis. Recompute
  or verify it after moving equipment; it is not a property of a stone set.
- The set model contains separately supported Black and White effective optical
  heights, the contour/center estimator version, measurement uncertainty and
  calibration provenance. An effective optical height describes where the
  measured visible center projects; it is not automatically physical thickness.
- Optional `physicalThicknessMm` is a user measurement. Store its provenance and
  uncertainty separately. Do not relabel a fitted effective height as caliper
  thickness or substitute one for the other without a validated shape model.
- Without known board pitch or another metric scale, the fitted optical height
  can be reported in row-pitch units. Such a value is tied to the original pitch;
  it cannot silently transfer between boards of different spacing. Once a known
  row pitch is supplied, preserve the conversion and its provenance.
- A height inferred under assumed intrinsics remains conditional on those
  assumptions. Naming/saving the profile does not make that uncertainty disappear.
  A new camera/stone-lighting setup needs compatibility checks and validation,
  especially when only a single-plane camera hypothesis is available.

## Proposed collection and fitting contract

Eight confirmed White stones, then eight confirmed Black stones, at raw-camera
(col,row) coordinates `(3,3),(9,3),(15,3),(3,9),(15,9),(3,15),(9,15),(15,15)`.
The center `(9,9)` remains empty. The user centers the stones deliberately; these
explicit labels, not detector guesses or expected AI moves, provide the intended
contact positions. Each pass keeps its own immutable pixels, metadata and setup
identity. Reject changed geometry/camera or ambiguous user confirmation.

Measure each visible body independently and save raw/rectified crops with the
contour, fitted ellipse, nominal point and any native fitted center. Inspect
failed/fragmented/clipped contours. A simple color/dark-body mask is only an
offline diagnostic; its threshold sensitivity and shadow/edge bias must be
reported. The prior compact-vote fit and new contour are different measurements,
and neither automatically identifies hidden board-contact centers.

Reuse `Tools/parallax_lab.py:camera_geometry` and its sensitivity assumptions.
For known intended position `P`, camera projection `C`, observed apparent center
`A`, fit the constrained relation `A-P = k(P-C)` separately by color/stone family.
Retain the existing six-well-spread-anchor minimum; do not insert fabricated native
confidence scores to make an unrelated extractor pass the old fit API. A small
explicit confirmed-anchor adapter may use the same bounded scalar relation and
robust residual weighting, preserving estimator/provenance differences.

Freeze two held-out positions before seeing fit errors: top and bottom middle,
`(9,3)` and `(9,15)`. The other six include all four corners and left/right middle.
Fit only those six, then report both held-out residual vectors, their uncertainties,
and whether correction made them better or worse. Leave-one-out across all eight
is an additional internal check; neither split is an independent setup test.
Never absorb held-out residuals into a free translation or a locally distorted
height map. Fitting all eight after evaluation may produce a candidate profile,
but preserve the original held-out results and no-live-adoption status.

For camera height `H` in row pitches, `h = H*k/(1+k)` is effective height in row
pitches. Report the camera-hypothesis sensitivity and per-anchor residuals. Do not
publish a calibrated probability from eight samples. A negative fitted height,
large unexplained cross-direction residual, unstable contour, sparse support,
geometry conflict or incompatible thickness family should remain unsupported.

## Proposed profile fields

`schemaVersion`, stable `stoneSetID`, user-visible `name`, `status: offlineCandidate`,
`createdAt`, and a separate entry for each supported color/thickness family:

- `physicalThicknessMm`: optional value/uncertainty/source; null if unknown.
- `effectiveOpticalHeight`: value, units, reference board-pitch identity, metric
  conversion when known, interval type and assumptions. It is estimator-specific.
- `measurementModel`: contour/shape estimator, version, feature family and visible
  coverage requirements; this prevents silently reusing a height with another
  estimator that has a different center bias.
- `confidence`: descriptive support/uncertainty plus explicit calibration status;
  never label an arbitrary fit quality as probability of correct placement.
- `validation`: training/held-out point IDs, residuals, failed hypotheses, negative
  controls and independent setup validation status. Include the earlier centered /
  midway White pair and real-misplacement regressions before live adoption.
- `provenance`: immutable capture IDs/hashes, user confirmation, camera and setup
  model IDs, grid/reference revisions, board pitch source, source-code hashes.
- `compatibility`: supported camera/geometry assumptions, board-pitch requirements,
  lighting/stone finish limitations and explicit conditions requiring revalidation.

Setup geometry is referenced, not embedded as a reusable stone-set property.
Named profile selection must preserve the current grid and game. Applying a
profile later would be a separate reviewed implementation: verify a few confirmed
centered examples under the new setup, or abstain if geometry/scale/estimator is
unsupported. Current work creates offline candidate evidence only.

## November 23 captured passes and measured results

The White and Black passes each contain eight exact broker images with manifests,
source hashes and explicit confirmation of the eight centered positions. They
share camera `0x11000000bda0567`, stream epoch
`F6BDAB92-1B01-438C-AA70-7E8E0BB61F06`, raw 1920×1080 and the same current grid.
The intervening `white-repeat-01` capture was correctly relabeled White by root
and is **not** included in the Black data or these estimates.

Durable artifacts are under:
`/Users/dave/Documents/SGF PLayer/work/ai-laser-integration/stone-session-20261123/stone-set-calibration/offline-body-study-02/`.
Each color's `results.json` retains every body/rail measurement, capture/code
hashes, model variants, held-out residual vectors and principal-point sensitivity
sweep. `anchors.png` shows red nominal grid, yellow independently measured rail
crossing and blue visible-body center. Eight repeated frames remain one static
episode; the fitting sample count is six anchors, not sixty-four independent
placements. [results-summary.json](results-summary.json) links and hashes the
larger local reports.

| Color / geometry hypothesis | Effective optical height, row pitches | Six-anchor maximum residual, cells | Held-out errors before → after, cells |
|---|---:|---:|---|
| White / native current grid | 0.223 | 0.078 | 0.116 → 0.065; 0.102 → 0.032 |
| White / local exposed-rail correction | 0.267 | 0.064 | 0.161 → 0.062; 0.123 → 0.024 |
| White / refined printed grid G | 0.260 | 0.086 | 0.141 → 0.087; 0.134 → 0.038 |
| Black / native current grid | 0.063 | 0.063 | 0.140 → 0.090; 0.060 → 0.061 |
| Black / local exposed-rail correction | 0.123 | 0.074 | 0.198 → 0.101; 0.051 → 0.024 |
| Black / refined printed grid G | 0.099 | 0.080 | 0.165 → 0.092; 0.048 → 0.019 |

Consult the exact JSON for all components. The native-grid Black bottom-middle
held-out result gets slightly worse; it is not omitted. Refined G is the existing
laser printed-grid fit from `manual-validation-01/setup.json`, checked against the
new exposed rails rather than assumed interchangeable with the old reference H.
Across eight rail crossings, residuals after a diagnostic median translation are
about 0.9–1.0px median and 1.4px maximum. The height fit uses unchanged G, not that
translation. This is an offline consistency check, not live laser-registration
qualification, and it does not replace the app's calibration.

The distinction between geometry variants is material. A ±1% principal-point
sensitivity sweep alone gives much narrower height ranges: refined-G White
0.2555–0.2649 and Black 0.0971–0.1018 row pitches. Those are **sensitivity ranges**,
not confidence intervals; grid choice, contour bias, physical placement error and
individual stone variation are excluded. Naming a profile does not remove them.

White uses an exploratory cyan-body mask with four thresholds; Black uses dark
body masks relative to local wood plus opening to remove thin grid rails. These
are different optical center estimators. They can include rims/shadows differently,
so the fitted heights do **not** establish a ratio of physical stone thicknesses.
The lower-right White supports thresholds 25/30 in every frame, while thresholds
15/20 are incomplete; this is explicitly recorded, and cannot be advertised as robust glare
handling. The development support rule accepts at least two complete threshold
families across the eight frames, bounded center spread and usable exposed rails.
That rule was adjusted after inspecting this calibration and is not independently
validated. All other White anchors and all Black anchors support all four masks.

The earlier centered/midway White pair is excluded from height fitting. Against
the frozen refined-G White model, the inferred contacts are approximately
`(9.096,8.962)` and `(9.054,14.470)`. The centered example is 0.103 cells from its
intersection; the midway example is 0.473/0.533 from the two neighboring rows.
The model therefore preserves this misplacement instead of correcting it away.
Because that pair informed contour-estimator development, it remains a development
negative control, not untouched validation. A fresh Black midpoint capture is
requested separately and will be evaluated without refitting the positive model.

## Candidate profile and reproduction

`make_candidate_profile.py` emits a standalone `StoneSetProfile` matching the
isolated `Experiments/StoneSetProfiles/StoneSetProfile.swift` candidate library.
The actual sample is `offline-stone-set-profile.json` in the artifact directory.
It has three separate optical-height candidates per color, uncalibrated confidence
metadata, sensitivity ranges and complete capture/code provenance. Measured
physical thickness and metric conversion are null. The temporary board-spacing
identity binds the unknown pitch to this study; it does not assert the spacing of
another board. The file is **not installed, selected or applied**. Native decoding/validation of this exact study02 producer file and the model/store
test suite pass 34 checks. Evidence hashes are in `native-profile-validation.json`;
no app was launched or profile installed.

From the application repository root, choose new output paths:

```sh
python3 PhysicalGo/Experiments/StoneSetCalibration/estimate.py CAPTURE_DIR NEW_REPORT_DIR --refined-setup REFINED_SETUP_JSON
python3 PhysicalGo/Experiments/StoneSetCalibration/make_candidate_profile.py WHITE_RESULTS_JSON BLACK_RESULTS_JSON NEW_PROFILE_JSON
python3 PhysicalGo/Experiments/StoneSetCalibration/evaluate_challenge.py MODEL_RESULTS_JSON CHALLENGE_MANIFEST NEW_CHALLENGE_RESULTS_JSON
python3 -m unittest discover -s PhysicalGo/Experiments/StoneSetCalibration -p test_estimate.py
```

The first command runs one OpenCV thread and took approximately 5–6 seconds per
color pass. Input confirmation, capture hashes and camera/grid/epoch consistency
are checked. It refuses to overwrite an output directory. The challenge evaluator
uses frozen model coefficients and records all candidate residuals; it never
learns from a displaced stone or declares a move. The local-ink variant abstains
on a displaced challenge when its fresh rail evidence is unavailable; it does not
borrow the old centered stone's local-ink correction. Six small analytic controls
pass, covering a known height, a preserved halfway negative, sparse/collinear
support an inadmissible negative-height boundary, invalid numerical inputs and the
non-identifiability of height under a constant contour bias. No production runtime
classifier has been changed or activated.

Independent review added a useful identifiability control: even zero physical
height plus a constant upward contour bias of 0.05 cells produces a positive
fitted effective height with a small residual. Therefore a good field fit cannot
by itself separate physical thickness from estimator bias. Nonfinite centers,
malformed coordinate arrays and nonpositive/nonfinite camera heights now abstain
before fitting. Existing recorded measurements were finite; the guards do not
change their numerical estimates.
