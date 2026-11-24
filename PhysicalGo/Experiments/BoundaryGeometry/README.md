# Visible-boundary geometry diagnostic

2026-11-23. **Useful evidence separation, not a replacement center estimator.**
A fixed edge-based prototype finds substantially more of the White outline than
the native compact bright-region fit, but can absorb cast-shadow edges into an
apparently supported ellipse. It also abstains on five of nine current Black
cases under the frozen radius bound. These failures remain in the results.
No runtime source, optical-height model, profile, game or hardware was changed.

## What the interface means

`BoundaryEvidence` in `boundary.py` separates an optional candidate outline from
an outline meeting the engineering policy. Both are in the visible image's grid
coordinates, **not board-contact coordinates**. Its fields include:

- Center, principal radii and orientation; no physical-height correction.
- Fraction of radial directions with supporting edge points, longest missing
  arc, excluded neighboring-owner directions and the supplied neighbor context.
- Signed compact-fit minus outline discrepancy, when an actual native fit exists.
  Principal ellipse radii and native grid-axis radii are identified separately.
- Leave-one-angular-quadrant-out center spread, explicitly a sensitivity measure.
  It excludes shadows, wrong boundary choice, grid error and other model biases.
- An uncalibrated support score equal to retained angular coverage. This is not a
  probability of stone color, existence or center accuracy. Class probability
  and calibrated probability remain null, including when the result is supported.
- Explicit abstention reasons, source/setup provenance and correlation family.

`status=supported` means only that this particular edge ellipse satisfies the
frozen engineering policy. It **does not mean the stone body has been identified
reliably**. A cast shadow can pass those geometric checks. A downstream consumer
must not turn support into move acceptance, hand clearance or waived centering.
The candidate remains present when abstaining so failures can be inspected;
`supportedOutline` is null in that case.

The geometry uses RGB edge differences, not the cyan mask, White class votes,
corrected-reference brightness or a constant offset. It therefore provides a
different measurement mechanism, but the same camera pixels, lighting and grid
still correlate its errors with color/native/contour evidence. Confidence must
not be multiplied as though these were independent observations. The input color
hypothesis is recorded for provenance and is deliberately not used to select the
edges. Occupancy evidence remains a separate unresolved input.

## Frozen experiment and results

Commit `738f2d7` selected 29 cases and fixed all numeric policy constants before
any boundary replay. It uses the first frame of each new episode, all eight
centered anchors of each color, and predefined historical cases. Repeated images
were not selected for favorable results. Subsequent metadata-only cleanup removed
unverified dates from two setup grouping IDs and pinned auxiliary native/photo
label files; case selection, geometry inputs and policy stayed unchanged.

| Frozen group | Geometrically supported | Abstained | Interpretation |
|---|---:|---:|---|
| Current centered White | 8 | 0 | Visible outlines fit the engineering policy |
| Fresh misplaced White | 1 | 0 | New episode, prior training location; shadow ambiguity remains |
| Current centered Black | 4 | 4 | Four major radii exceed the assumed 0.62-cell bound |
| Fresh misplaced Black | 0 | 1 | Major radius 0.62018; boundary is very close to the arbitrary limit |
| Frame697 White pair | 2 | 0 | Stronger native/outline disagreement, not proved improvement |
| Older iPhone centered/nudged Black | 2 | 0 | Different recorded setup, known ROI; limited transfer evidence |
| Crowded displaced White 816/950 | 0 | 2 | Arc/neighbor ownership unresolved |
| Hand-covered historical point95 | 0 | 1 | Externally supplied occlusion gate; not a hand-detector test |
| Shaded empty crossings/current empty center | 0 | 4 | No supported stone-like outline |

The native frame697 fits are above the new outline centers by 0.1438 and 0.2103
rows. Previously, native-versus-cyan-body disagreements were about 0.11 rows.
This larger disagreement is **not evidence that the new center is more accurate**.
Inspection of the saved montage shows some candidate outlines including the
lower cast shadow, especially on Black and the displaced White development case.
Even supported Black outputs can contain shadow. High angular coverage and small
quadrant-deletion spread do not detect that systematic boundary-choice error.
A threshold was not relaxed to admit the near-boundary fresh Black result.

Crowded frame950 is the prior negative in which a free radial correction reduced
a genuine 0.36-cell displacement to 0.221 and falsely relieved it. The new boundary
prototype abstains and performs **no correction at all**. This preserves the
negative; it does not validate a different correction model. Native historical
compact shapes are from the archived exporter; the first stored target shape is
used, with provenance retained. Native fits for the new centered/midpoint captures
are unavailable in this replay and are null rather than synthesized.

## Method and limits

The existing immutable study helper rectifies a known local crop at 160 samples
per cell. This interpolates the original pixels; it does not add camera resolution.
For 72 directions the prototype searches radius 0.22–0.80 cells, compares RGB on
opposite sides of a 0.05-cell edge band, rejects mostly tangential edges, and
retains the strongest radial edge. Candidate points closer to a supplied neighbor
are excluded. A fixed ellipse fit and three bounded residual-pruning iterations
produce an outline. Coverage, missing arc, radius, center displacement and
contested-owner tests either support or abstain. Policy constants are engineering
assumptions, not learned or validated limits. The visible-arc number is retained
sampling-direction coverage; it is not a measured unobscured perimeter length.

Seeds and neighbor centers come from labeled experimental layouts or archived
visual hypotheses. They are not requested/legal moves used as optical truth.
The known midpoint crop is intentionally supplied: this is not blind localization
from the assigned intersection. Historical signatures can contain incorrect or
missing neighbors, so ownership reports describe that input's limits. The hand
case uses independent photo labeling to check that geometry cannot override an
occlusion gate; it supplies no evidence of detecting an unrecognized hand.

No height/contact model from another estimator is applied to these outlines.
Their differing shadow behavior makes such reuse particularly inappropriate.
Needed data include contour/contact ground truth, varied light directions, glare,
stone materials/thickness, additional independently positioned stones and dense
occlusions with verified neighbor ownership. A useful next design must distinguish
stone-to-shadow from shadow-to-wood edges, rather than merely require a closed
ellipse. No further threshold tuning or implementation is claimed here.

## Reproduction and verification

```sh
python3 -m unittest discover -s PhysicalGo/Experiments/BoundaryGeometry -p test_boundary.py
python3 PhysicalGo/Experiments/BoundaryGeometry/replay.py NEW_OUTPUT_DIRECTORY
```

The replay checks frozen image, metadata and auxiliary-source hashes, uses one
OpenCV thread and refuses an existing output directory. All 29 cases took about
two seconds; no native build or camera access is involved. Seven synthetic tests
cover known ellipse center, empty/grid/straight-shadow rejection, occlusion and
unknown-visibility abstention, neighbor ownership, invalid inputs and circular
arc accounting. These are mechanism tests, not a physical accuracy estimate.

Full original and metadata-corrected results and overlays are retained at:

`/Users/dave/Documents/SGF PLayer/work/ai-laser-integration/stone-session-20261123/boundary-geometry-{01,02}`

`results-summary.json` pins the current result and source hashes, all 29 compact
outputs and original-policy identity. The montage labels yellow candidate ellipse,
green retained edge samples and red candidate center. Unchanged estimates between
01 and 02 were verified; only provenance grouping strings changed.
