# Fresh misplaced Black and White: frozen-model diagnostic

2026-11-23. Both fresh misplaced stones remain well away from either neighboring
intersection under both frozen optical-height hypotheses. This is an offline
negative-control result, not a live recognition or physical-thickness validation.
No model, contour mask, score threshold, camera setting or profile was changed.

The actual moved Black was at raw `(15,9)`, moved toward `(14,9)`. An initial
instruction had incorrectly described `(9,15)` because the human and camera
viewpoints differed. The capture manifest preserves that history. Measuring all
eight stones confirms that `(15,9)` moved `(-0.4293,+0.0104)` cells in the frozen
grid, whereas the seven others changed by at most 0.0125 cells. White then replaced
that displaced Black; seven other Black stones remained. The instructed midpoint
`(14.5,9)` is approximate placement intent, not measured contact ground truth.

Each episode has eight clear frames from the same camera and stream epoch as the
centered calibration. Repeated frames describe stability of one placement; they
are not eight independent tests. `(15,9)` was a training location. These are fresh
negative placement episodes, **not** the preselected held-out locations `(9,3)`
and `(9,15)`, nor a new camera setup.

## Frozen results

Coordinates are raw `(column,row)`. Distances use the norm in grid coordinates,
not millimetres or a physical metric that accounts for unequal board pitches.
The table gives medians over eight frames; the full artifact retains every frame,
mask result, source hash and unchanged coefficient.

| Stone | Frozen geometry | Inferred contact | Distance to `(14,9)` | Distance to `(15,9)` |
|---|---|---|---:|---:|
| Black | Native current-grid model | `(14.5692,8.9475)` | 0.5716 | 0.4340 |
| Black | Refined printed-grid model | `(14.5413,8.9499)` | 0.5436 | 0.4614 |
| White | Native current-grid model | `(14.5166,8.9864)` | 0.5167 | 0.4836 |
| White | Refined printed-grid model | `(14.4878,8.9892)` | 0.4879 | 0.5123 |

Across all frames and hypotheses, the nearest-crossing distance remains at least
0.4334 cells. Thus these hypotheses do not explain away these particular genuine
misplacements. Black and White were separate placements; their numerical
difference is not a controlled measurement of color-dependent error. The small
within-episode ranges are repeatability, not calibrated accuracy or confidence.

## Explicit same-view comparison

The app's current grid changed slightly between centered and negative captures.
The original `evaluate_challenge.py` correctly rejected this exact-grid mismatch
and remains unchanged. For this bounded diagnostic, `fresh_midpoint_audit.py`
maps each body measurement through its own current homography to raw image pixels,
then through the original frozen H or independently fitted printed-grid G. It
reads the original coefficients and never fits a replacement field.

Seven unchanged exposed rail crossings, excluding the moved location, were
measured in the first and last frame of each episode and compared with the
original Black calibration. Maximum raw-pixel crossing displacement was 0.462 px
for Black and 0.535 px for White. Maximum residual after a *diagnostic* median
shift was 0.188 px; the median shifts were predominantly upward, about 0.34–0.46 px.
No translation was applied to the body pixels. The measured movement remains an
uncertainty in this same-view comparison, not proof of exact camera immobility.
At the target, the change in the app's grid alone projects to `(-0.155,+0.090)` px.

These measurements support this explicit offline coordinate comparison. They do
not establish a general registration acceptance threshold. The script records
the measurements for review; it is not an automatic compatibility gate or blind
stone detector. Its crop uses the independently known approximate location.
The local-printed-rail height variant is not evaluated here: the moved stone can
obscure different rails, so the old local correction must not be borrowed.

## Evidence and reproduction

Raw images and metadata remain under:

`/Users/dave/Documents/SGF PLayer/work/ai-laser-integration/stone-session-20261123/stone-set-calibration/{black-midpoint-01,white-midpoint-01}`

The full result is `offline-body-study-02/fresh-midpoint-results.json` under that
same calibration root. Its SHA256 and compact numerical results are checked into
`results-summary.json`. It includes all source-image, metadata, manifest and
frozen-model hashes. Original metadata was neither overwritten nor normalized.

From the repository root, use a new output path:

```sh
python3 PhysicalGo/Experiments/StoneSetCalibration/fresh_midpoint_audit.py CALIBRATION_ROOT NEW_RESULT_JSON
```

The script verifies camera/epoch/dimensions, image hashes, clear/aligned flags,
training-grid agreement and the refined-G hash, uses the existing masks unchanged,
and refuses to overwrite results. The full-body estimator remains exploratory.
Independent setup validation, negative placements at the preselected held-out
locations, crowded positions and live recognition remain unperformed. The named
profile remains an uncalibrated offline candidate and has not been activated.

Focused verification passed for all 16 frames: stored source/image/metadata/model
hashes match, both pixel-coordinate round trips agree within 1e-9 px, reconstructing
the apparent position from each inferred contact and frozen coefficient agrees
within 1e-12 grid units, and both neighbor distances recompute exactly. The six
existing analytic estimator controls also pass. The estimator and original
challenge evaluator have no source changes in this follow-up.
