# Independent review: visible-boundary geometry

November 23, 2026. Reviewed candidate `89841aa` and its explicit diagnostic-contract
follow-up `b4184d5`. Original case/policy freeze `738f2d7` remains preserved. No
production, profile, game, image archive or hardware change was made by this review.

**Clear as an offline diagnostic experiment; not suitable for runtime promotion.**
Its evidence separation and abstention reporting are useful. Geometric support
still does not establish that the selected edge belongs to the stone body. The
known shadow failure is real, retained and now independently reproduced.

## Review findings

| Priority / scope | Finding | Consequence |
|---|---|---|
| Blocks runtime promotion | A plausible ellipse can combine stone and shadow edges, satisfy every geometric bound and report full angular coverage. | `supported` is not body identity, center accuracy, occupancy evidence or permission to waive a placement warning. |
| Blocks calibrated uncertainty claim | Deleting angular quadrants can produce a small center spread even when the shared selected boundary is systematically wrong. | The spread is sensitivity only; it cannot be interpreted as error bounds or combined with native confidence as independent evidence. |
| Important quality limitation | Four of eight current centered Black cases and the fresh Black midpoint abstain at the fixed radius bound. The fresh case's major radius is approximately .62018 versus .62 allowed. | Preserve these outcomes. Relaxing the bound to admit them would not solve shadow/body identity. |
| Evidence-scope limitation | Seeds, neighbor centers, visibility and grids are externally supplied; some historical neighbors are inferred visual hypotheses. | This is not blind localization, hand detection, certified owner assignment or automatic calibration compatibility. |
| Minor future API hardening | `measure()` updates a nonempty caller-supplied provenance dictionary in place. | Actual replay passes a fresh dictionary, so no current evidence is corrupted. Copy provenance before reusing this as a pure library API. Do not alter the frozen experiment to hide this distinction. |

`b4184d5` adds `runtimeDisposition=diagnosticOnly` and
`boundaryIdentity=stoneVersusShadowUnverified` to every record without changing
geometry. These explicit fields are appropriate. They remain descriptive fields,
not an implemented runtime enforcement layer; there is no runtime consumer here.

## Independent frozen-integrity checks

All 29 case IDs, images, metadata hashes, calibrations, seeds, neighbors, labels,
compact fits and visibility inputs are identical to `738f2d7` after removing only
the setup-grouping strings. Every numeric policy constant is exactly unchanged.
The setup changes remove unverified dates rather than moving observations between
measured physical setups. Added auxiliary hashes pin the native-shape exporter
and independent photo labels.

The original 01, metadata-corrected 02 and contract-tagged 03 artifacts retain all
29 identical geometric results, diagnostics, uncertainty values and dispositions.
Only documented setup strings and the two new contract fields differ. The edge
algorithm and measurement helper hashes match across 01/02; the 03 source diff adds
only the two dataclass fields. Fresh-negative outcomes were not improved by a
threshold change after their replay. A git freeze establishes this experiment's
recorded sequence; it does not make already-seen development scenes a prospective
blind benchmark.

Independent verification completed:

- All frozen image/metadata/auxiliary-source hashes and current source/result
  hashes match.
- Full replay into a new temporary directory produces JSON exactly equal to 03.
- Counts reproduce: **17 supported / 12 abstain**. All abstentions have reasons
  and null `supportedOutline`; all supported records retain explicit unverified
  boundary identity and null class/calibrated probabilities.
- All seven author synthetic controls pass independently.
- New bounded controls retain image pixels, do not use color hypothesis to change
  geometry, and preserve explicit unknown/occluded visibility abstention.

The reviewed montage is consistent with the stated limitation: some lower fitted
arcs follow the outer shadow, including in supported cases. No physical contour
or contact accuracy is inferred solely from visually inspecting that montage.

## Concrete shadow counterexamples

The independent `review_checks.py` adds two fixed synthetic examples without
changing policy or fitting parameters:

1. A circular body centered at `(9,8.925)` overlies a darker adjoining shadow.
   The fitted center is `(9,9.04297)`, an error of **.11797 cells**, yet the result
   is supported with **100% angular coverage**. Quadrant-deletion spread is only
   `(.01497,.00468)` cells. This directly demonstrates that good geometric support
   and small deletion sensitivity can coexist with substantial boundary-choice
   bias.
2. A circular dark patch on bare wood, with no stone at all, also receives
   geometric support with 100% coverage. A single straight shadow edge abstaining
   in the original tests does not establish general shadow rejection.

These are deliberate failure demonstrations, not evidence that every real shadow
has that shape or that the classifier would call the patch a stone. The prototype
has no occupancy decision; the controls show why it must remain separate from one.
Full numeric results are in `independent-review-results.json`.

## Calibration, ownership and negative evidence

Rectification uses the original stored homography and `(width−1,height−1)` pixel
convention. Sampling at 160 points per cell interpolates the source image; it does
not create independent resolution. Color geometry, native geometry and this edge
geometry share pixels and calibration errors despite using different algorithms.
No parallax/contact model is applied and no cross-estimator height is borrowed.

The coverage value counts retained radial sampling directions, not independently
measured unobscured perimeter. Neighbor ownership excludes selected edge samples
closer to supplied neighbor centers with a margin; it cannot detect a missing or
incorrect neighbor hypothesis. The historical hand-covered sample is externally
labeled occluded. Its abstention demonstrates that this gate is retained, not that
an unknown hand would be recognized. The three shaded empty crossings and current
empty center abstain, but the round-shadow counterexample limits that result.

The current fresh White/Black negatives are new episodes at a prior training
location; the seeds already specify their approximate displaced locations. The
older iPhone cases use their own recorded grids and known crops. Neither group
establishes portable blind localization. Crowded frame 950 still abstains, so the
previous false-centering negative is retained; because no correction is attempted,
that abstention cannot validate a correction policy.

## Recommended next boundary

Keep this as a diagnostic producer of candidate outlines, visibility/ownership
context and disagreement. Before any production consumer, require evidence that
distinguishes stone-to-shadow from shadow-to-wood boundaries, rather than another
closed-ellipse criterion. Freeze a future comparison on independently placed
stones with known visible-body/contact labels, varied light directions and dense
neighbors; preserve these shadow, crowded and halfway failures. A classifier may
supply an occupancy hypothesis, but neither its high score nor the outline's high
coverage should resolve the other's unverified geometry automatically.

No global threshold adjustment, constant center correction, physical-height
inference or live integration is justified by the present results. The present
explicit interface is useful groundwork precisely because it records what remains
unverified.

## Reproduction

```sh
python3 -m unittest discover -s PhysicalGo/Experiments/BoundaryGeometry -p test_boundary.py
python3 PhysicalGo/Experiments/BoundaryGeometry/review_checks.py
```

The second command reads frozen archives, runs the 29-case replay in a temporary
directory, and writes only its adjacent review JSON. It neither opens devices nor
imports app runtime code. Original 01/02/03 artifacts are not overwritten.
