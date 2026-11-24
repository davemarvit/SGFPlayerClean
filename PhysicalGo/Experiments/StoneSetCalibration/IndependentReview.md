# Independent review: stone-set optical estimates

November 23, 2026. Reviewed study `2673929` and its numerical-admission correction
`fbbb786`, plus WhiteCentering `9e6f22f`. Offline source and retained-data review
only; no app, camera, laser, production recognition, profile installation or
physical experiment was performed.

**Suitable as an explicitly unvalidated, setup-specific optical candidate. It
is not an identified physical thickness or a portable correction.** White/Black
height ratios must not be described as physical thickness ratios. A constant
contour-center bias alone can produce the original positive scalar estimate.
Adding a constant bias term improves identifiability against that particular
nuisance, but does not identify physical height against grid-scale error or
spatially varying appearance bias.

## Findings and disposition

| Finding | Evidence and disposition |
|---|---|
| Numerical admission accepted nonfinite centers | Independent NaN control returned a non-None NaN fit on `2673929`. Fixed in `fbbb786`: finite/shape/camera-height checks abstain. All six focused tests independently pass. The actual stored measurements were finite. |
| White lower-right support was described incorrectly | The complete mask families are thresholds 25/30; 15/20 are incomplete. README corrected. No causal explanation for this difference has been established. |
| Physical height is confounded with contour bias | Zero true height plus constant `[0,-0.05]` cell contour offset yields scalar effective height about 0.0646 row pitches with maximum residual about 0.0407 cells. Low residual is insufficient evidence of physical thickness. |
| Positive/negative evidence remains limited | Six training locations and two fixed heldouts per color, one static setup; eight repeated frames are not independent placements. Masks and support rule were developed on these images. White development midpoint remains ambiguous; fresh Black midpoint and an independent setup remain pending. |
| Storage contract preserves uncertainty | Separate color entries, unknown physical thickness and metric scale, `offlineCandidate`, separate geometry hypotheses, capture/code provenance. No selection or storage operation activates recognition. Keep this separation. |

The corrected `offline-body-study-02` White and Black `conditionalFits` (including
heldouts) are exactly equal to study01 in an independent JSON comparison.
Original artifacts were retained. New estimator SHA is
`684a8633e70005343da96565b5e1e70296d95dbe8e847ad73e12136068bc44d7`.

## Geometry and units

`parallax_lab.camera_geometry` uses normalized homography coordinates, actual
pixel scaling `(width−1,height−1)`, and an assumed pinhole camera with square
pixels, zero skew/distortion and specified principal point. It allows different
column/row pitches. These assumptions are not verified by one plane.

Independent synthetic controls recover a known camera projection, focal length,
height in row pitches and 1.1 column/row pitch ratio. Doubling pixel resolution
preserves the grid-space camera and height and doubles focal pixels. Doubling
both physical board spacing and camera position gives the identical homography:
absolute millimeters are not identifiable from this evidence. A metric pitch
measurement enables a unit conversion, not proof that the fitted optical height
is the physical stone thickness.

Native grid, per-anchor printed rails and refined grid remain separate
hypotheses. Refined geometry checked against eight exposed crossings is useful
local evidence, not independent live-registration qualification. The ±1%
principal-point sweep is sensitivity to one assumption, not a confidence interval
covering contour bias, placement, lens distortion or grid error.

## Requested constant-bias diagnostic

Fit only the same six confirmed-centered training locations:

`apparent − contact = k (contact − cameraProjection) + b_color`

Here `b_color` is a two-component setup/estimator nuisance term. The fixed
upper/lower-middle heldouts and White negative are never fitted. The diagnostic
uses ordinary least squares with three parameters and 12 scalar observations;
it does not replace the original bounded robust scalar estimator or any profile.
All six observed diagnostic solutions are positive and below the original 0.04
bound; unconstrained results are retained to expose possible zero/negative values.

With free bias this is algebraically `δ = k P + intercept`, the same field family
as the earlier free radial model. Changing assumed camera projection is absorbed
by the intercept and leaves k unchanged. Converting k to conditional height still
depends on camera height via `h = H k/(1+k)`.

| Color / geometry | Scalar k → k with bias | Bias (col,row), cells | Conditional h with bias, row pitches | Fixed heldout residuals: scalar → bias, cells |
|---|---:|---:|---:|---|
| White / native | .008625 → .005686 | (.0001,−.0601) | .1478 | .0653→.0650; .0321→.0094 |
| White / local rails | .010321 → .009046 | (−.0137,−.0210) | .2343 | .0617→.0563; .0236→.0132 |
| White / refined | .010001 → .006971 | (−.0315,−.0505) | .1819 | .0867→.0728; .0379→.0143 |
| Black / native | .002404 → .001501 | (.0022,−.0193) | .0392 | .0897→.0915; .0614→.0519 |
| Black / local rails | .004715 → .005069 | (−.0118,.0116) | .1318 | .1007→.0987; .0240→.0401 |
| Black / refined | .003797 → .002796 | (−.0289,−.0101) | .0733 | .0915→.0856; .0194→.0379 |

Do not select a winning geometry/model from these heldout outcomes and then call
them untouched validation. Several Black outcomes worsen. White's development
centered control also worsens: refined scalar error about .103 cells becomes
.1162; the midpoint remains about .4985/.5113 cells from its two neighboring
intersections. This is useful discrimination in one development scene, not a
validated placement threshold or recognition improvement.

The training design has rank 3 and spatial leverage 360 squared cells. Its raw
condition number is about 37.7–37.9, influenced by the choice of origin/parameter
units. Wide corner/side coverage permits slope estimation, but six locations
cannot diagnose general spatial contour distortion. Algebraic rank can remain
three even on a line; it must not replace the existing two-dimensional support
rule.

| Color / geometry | k ± 2 residual-scale standard errors | Leave-one-training-anchor-out k range |
|---|---:|---:|
| White / native | [.002041,.009331] | [.005110,.006234] |
| White / local rails | [.004914,.013177] | [.008454,.009926] |
| White / refined | [.003088,.010855] | [.006489,.007231] |
| Black / native | [−.001849,.004850] | [.000223,.002467] |
| Black / local rails | [.001471,.008667] | [.003816,.006110] |
| Black / refined | [−.001102,.006695] | [.001410,.004504] |

These ranges are **not calibrated confidence intervals**. They assume independent,
equal-variance residual components and omit shared grid, contour and placement
errors. Repeated frames do not multiply the degrees of freedom. The leave-one-out
fits use five anchors solely as a sensitivity diagnostic, not as an admissible
runtime fit. Native/refined Black are compatible with zero even under this narrow
residual model. White's positive ranges do not establish physical height:
synthetic zero-height data with an isotropic grid scale error exactly reproduces
positive k in this three-parameter model. There is no independent grid-error
bound sufficient to exclude that explanation here. Cross-direction residual
vectors and all heldout residuals are retained in the numeric artifact.

## Negative control preserved

Independently replayed the retained older `CrowdedWhiteAdjustment` observations
using their own old free radial fit. Frame950 still incorrectly changes the
misplaced stone's offset from .36 to .221244 cells and waives its flag. Frame816
remains flagged. This reproduces the earlier failure rather than erasing it.
The new study fit was not transferred to that unrelated setup, and no negative
was used to fit the new model. Known-centered anchors improve label quality
relative to the old established-stone training, but do not by themselves validate
this field family for waiving placement flags.

## Compatibility and next acceptance boundary

The row-pitch token currently binds unknown pitch to this study; a native-grid
hash is not a measurement or identity of a physical board. Before cross-setup
application, require explicit board-spacing provenance and setup/model identity,
including actual geometry hypothesis and estimator version. Optical candidates
must not overwrite user-measured thickness. The standalone Swift profile author
reports native producer decode/model/store validation; that is serialization
compatibility, not runtime optical validation. The study README's older “decode
pending” wording should be reconciled with that separate validation record.

Before proposing recognition use:

1. Freeze the estimator and comparison policy before collecting fresh Black and
   White misplaced/ambiguous negatives; preserve raw mandatory assignment guards.
2. Repeat known-centered placements in another setup with measured row/column
   pitch and independently checked camera/grid geometry. Treat contour bias as
   setup/angle dependent until tested, even for the same stone set.
3. Assess whether one shared physical parameter can explain multiple setups with
   separate nuisance terms and predict heldouts. Retain abstention when geometry,
   appearance or placement noise prevents separation. A physical thickness
   measurement is independent evidence, not a target to force the fit toward.

No live promotion is recommended from this single episode. The storage/UI
candidate can progress independently while these optical requirements remain open.

## Reproduction

The adjacent `review-20261123` folder contains numeric controls, exact report and
historical-source hashes, residual vectors, leave-one-out results and full control
outputs. Scripts read retained archives only; they write only their own adjacent
review JSON. They do not open devices or import application runtime code.

```sh
python3 PhysicalGo/Experiments/StoneSetCalibration/review-20261123/compare_bias.py
python3 PhysicalGo/Experiments/StoneSetCalibration/review-20261123/geometry_controls.py
python3 -m unittest discover -s PhysicalGo/Experiments/StoneSetCalibration -p test_estimate.py
```
