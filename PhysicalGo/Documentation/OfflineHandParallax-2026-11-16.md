# Offline hand-clearance and raw-camera parallax experiments

The raw photographs support a position-dependent parallax hypothesis. The
camera-constrained experiment reduces placement flags for real stones in this
static scene, but does not yet justify a live change. A freer offset fit also
excuses a genuinely misplaced stone. Simple hand-clearance timeouts fail on
lingering fingertips. All experiments remain offline; no app source, live game,
clock, or Go capture behavior is changed by this work.

## Evidence and scope

Inputs are the preserved laptop incident, the reviewed 65- and 85-move games,
HalfwayNudge and CrowdedWhiteAdjustment photos, and recorded hand-outline fixtures
including A18 placement, A19 removal, and Black move 67 shadow withdrawal.
Results and compiled standalone exporters are stored outside the repository at:

`/Users/dave/Documents/SGF PLayer/work/hand-parallax-stage10`

The original incident remains at:

`/Users/dave/Documents/SGF PLayer/work/laptop-parallax-incident`

The user confirmed B4 and E1 are real stones. The original record ends with Black
move 17; photographed colors and alternating play infer **18 White B4, 19 Black
E1**. `user-labels.json` and `inferred-19-moves.sgf` preserve this offline extension.
Both added moves replay legally without captures. Their placement times are
unknown; neither clock values nor timing evidence were manufactured. Alternation
resolves this two-stone ordering, not arbitrary larger groups of missing moves.

The late static recording has 81 completed analyses. It does not contain the
placement moments of E17, C16, or C4. Later established stones are available for
fitting this scene; they would not have been available during the first few moves.
This is a static assignment experiment, not a causal replay of those early holds.

## Parallax model and safeguards

A board-plane homography aligns printed intersections, not the visible tops of
raised stones. For camera height H, effective stone height h, camera projection C,
and intended intersection P, the idealized board-plane apparent displacement is:

`d(P) = k (P - C), k = h / (H - h)`

Consequently, stones farther from the camera's projection have greater apparent
displacement. We compare a two-parameter uniform translation, a three-parameter
radial expansion plus translation, and a one-parameter expansion constrained by
the camera geometry inferred from the original-image homography.

The raw-camera estimate assumes orthogonal grid axes, square pixels, zero skew,
zero lens distortion, and a specified principal point. It permits different row
and column pitches. A single plane cannot verify these assumptions. Invalid or
degenerate solutions abstain; no grid calibration is moved to follow stone tops.
Height is an effective fitted height in grid units, not a measured stone thickness.

Each fit uses at least six well-spread established stones with matching color,
confidence >= .94, strong outlines, and bounded displacement. All evaluated
points are excluded from fitting. Robust residual weighting limits outliers.
Relief requires the existing assignment flag, a strong target outline, confidence
>= .90, bounded correction, coverage of the predicted target, and no neighboring
projected intersection inside the enlarged outline. It cannot change occupancy,
create a move, remove a stone, release a hand gate, or create a clock press.

The first strict experiment required target confidence >= .94 and relieved zero
flags. Its code and output are retained in `initial-strict/`. The subsequent
exploratory version uses the production strong-geometry confidence level of .90
and requires outline quality >= .90. This adjustment used this incident; results
are development evidence, not a frozen held-out accuracy estimate.

## Parallax results

| Model | Static frames with a fit / 81 | B4 flags relieved / 81 | C4 flags relieved / 81 | C16 flags relieved / 8 | False relief on two older misplacement photos |
|---|---:|---:|---:|---:|---:|
| Uniform translation | 47 | 44 | 45 | 5 | 1 |
| Free radial field | 49 | 49 | 49 | 5 | 1 |
| Raw-camera constrained | 49 | 49 | 49 | 5 | 0, but abstained on both |

E17 and E1 had no assignment flags in this late static sequence. E17's earlier
hold is documented in the observation journal, not reproduced here. The touching
white stone at D4 remains a separate unresolved classification/ownership case.

In CrowdedWhiteAdjustment frame 950, a genuinely misplaced white stone has an
original offset of .36 cells. Translation reduces it to .223 and the free radial
fit to .221, incorrectly waiving the flag. Frame 816 remains flagged. The
raw-camera variant cannot establish admissible camera geometry on these older
photos, so its zero false relief is **abstention, not demonstrated discrimination**.
The halfway-nudge photo also lacks sufficient established anchors for a field;
its two uncertain intersections remain unresolved. These failures and abstentions
must not be counted as broad recognition improvement.

All 150 reviewed placement endpoints from the two completed games retain their
original assignment outcomes, as do eight reviewed empty-edge samples. The
supplied prior boards are held fixed; this is not a full sequential replay.
The policy only offers relief of existing flags, so zero new flags is partly
guaranteed by construction and does not establish general non-regression.

For a representative raw frame, the central pinhole hypothesis places the camera
projection near the displayed right edge, consistent with the user's setup.
`raw-perspective.png` shows the original photograph and spatial displacement field.
Across 25 principal-point hypotheses within +/-1% of image dimensions and 81
frames, 1,620/2,025 geometry hypotheses are admissible, with 980 supported height
fits. The inferred focal lengths range from 606 to 1,284 pixels, and effective
heights from .119 to .224 row spacings. These ranges are sensitivity results,
**not confidence intervals** or verified lens calibration.

The B4/C4 relief on 49 frames survives every admissible principal-point hypothesis.
Requiring every tested hypothesis including invalid ones to support relief yields
zero. All 25 hypotheses abstain on camera geometry for the crowded-stone negatives;
the halfway photos have admissible geometry but too few anchors. Lens uncertainty
and negative-case coverage remain unresolved.

All 81 incident analyses still have the original hand hold. Thus these geometric
proposals demonstrate **zero live move acceptances or clock resumptions**.

## Hand-clearance results

The archived tracker reports depth .15 at the rim with a reliable empty pose in
all 81 clear static frames. Its historical frozen baseline/learned appearance was
not recorded, so the initiating error cannot be reconstructed exactly. A fresh
tracker clears the scene, but resetting could absorb an undetected hand into its
background and cannot establish an earlier hand-exit time.

The exporter reuses the unchanged production tracker on 660 recorded frame
evaluations, including injected missing-pose and two-second camera-gap variants.
It adds 480 synthetic evaluations across four edges and three scenarios: pose
lost at the rim, pose missed entirely, and a camera gap with a fingertip still
present. Repeated frames are not independent trials or an error-rate estimate.

| Shallow-depth limit / wait | Incident frames relieved / 81 | New false-clear synthetic frames / 480 |
|---|---:|---:|
| .20 cells / .8 seconds | 77 | 116 |
| .20 cells / 1.5 seconds | 74 | 104 |
| .20 cells / 3 seconds | 68 | 76 |
| .10 cells / 1.5 seconds | 0 | 52 |

No variant changes the recorded-fixture clearance results. The synthetic complete
pose-miss/reinitialization cases also expose 264 baseline false-clear frames;
these are existing counterexamples, not regressions introduced by the timeout.
All four proposed timeout rules are rejected. Motionlessness and missing pose
cannot distinguish background from a real stationary fingertip.

The lab never emits a press estimate, preserves original timing evidence, and
resets its wait across gaps. All 13 tested gap-transition rows have no tracker
press estimate. A later static clear scene is not authority for backdating clocks.

## Validation and next useful work

- 14 offline unit checks pass, including a known synthetic raw-camera projection,
  target exclusion, sparse-support abstention, actual halfway displacement,
  input immutability, gap reset, and the lingering-fingertip counterexample.
- The Python assignment-offset port matches native production output exactly on
  all ten older photos, including confirmed-board neighbor handling.
- 329 native processing-gap, hand-outline, removal, and clock-accounting checks
  pass across three existing suites. This work changes no production source.
- Input hashes, per-frame decisions, source hashes, and test logs accompany the
  external artifacts. Existing game evidence is retained.

Next, record the frozen hand reference, learned appearance, selected component,
and its relation to the rim/shadow when a hold stalls. That evidence is necessary
to test a clearance rule based on actual component disappearance rather than a
timeout. For parallax, obtain lens/board geometry plus deliberately centered and
slightly misplaced stones across the same oblique view, including early sparse
positions and touching stones. Evaluate with the candidate withheld and a fixed
protocol before considering live adoption. The current positive scene cannot
establish that distinction by itself.

## Reproduction

From the repository root, use an external output directory. Python requires NumPy,
Pillow, and Matplotlib; the native exporters require macOS/Xcode Swift tools.
The previous stage's reviewed caches and their preserved photo snapshots must
remain available at the paths recorded in their `plan.json` files.

```sh
OUT='/Users/dave/Documents/SGF PLayer/work/hand-parallax-stage10'
INCIDENT='/Users/dave/Documents/SGF PLayer/work/laptop-parallax-incident'
PREVIOUS='/Users/dave/Documents/SGF PLayer/work/prehand-stage9'
python3 PhysicalGo/Tools/build_hand_clearance_audit.py "$OUT"
python3 PhysicalGo/Tools/hand_clearance_lab.py --replay "$OUT/hand-replay.json" --incident "$INCIDENT" --output "$OUT"
python3 PhysicalGo/Tools/prepare_parallax_photos.py "$OUT"
python3 PhysicalGo/Tools/run_parallax_lab.py --incident "$INCIDENT" --previous "$PREVIOUS" --native "$OUT/geometry-native.json" --output "$OUT"
python3 PhysicalGo/Tools/raw_parallax_audit.py --incident "$INCIDENT" --output "$OUT" --native "$OUT/geometry-native.json" --photo-inputs "$OUT/geometry-inputs.json"
python3 -m unittest discover -s PhysicalGo/Tools -p test_parallax_clearance_lab.py
python3 PhysicalGo/build.py --hand-outline-test --hand-clock-test --processing-gap-test --debug-tests
```
