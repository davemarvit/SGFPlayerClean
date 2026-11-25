# Glare visibility: bounded offline geometry study

November 24, 2026. Native base `c53ac0502e920fda5a3ac5b50cba1ec330fdc051`.
Implemented only as a Python/OpenCV diagnostic. **No runtime consumer, installation,
camera access, controller action, UI operation, or live exposure change.** Root owns
hardware and the separate 600 ms optical-freshness correction. This study does not
block or replace that correction. The canonical integration checklist is unchanged.

The practical answer is yes: visible portions of the printed lattice can locate
crossings inside glare. Predicting where a crossing lies and observing what occupies
it are different outputs. Complete clipping can make empty, Black and White produce
identical pixels; no extrapolation can recover that lost state from that frame.
The information-loss control below demonstrates this explicitly. Partial glare often
leaves enough rim, wood color, or rail contrast to classify normally; brightness
alone should not veto that evidence.

## What the installed source already does

- `Sources/AutoGridDetector.swift`: rectangle proposals are followed by printed-grid
  fits. `knownGridSupport` verifies visible segments in both directions and requires
  distributed coverage/borders; expected stones choose eligible samples but do not
  create fresh pixels. `refineKnownGrid` fits exposed outer rails and intersects
  them. This already embodies a limited line-extension approach. The strict border
  requirements are a possible glare limitation, not grounds to remove them blindly.
- `Sources/BoardAppearanceDetector.swift`: robust local wood brightness/color plane,
  cross evidence in both directions, bounded White rim, and exposed-wood evidence.
  The brightness plane already interpolates/extrapolates local expected empty
  appearance; its bounded slopes/residuals avoid unconstrained lighting invention.
- `Sources/BoardVision.swift`: reference comparisons, spatial lighting correction,
  current-appearance fallback, rail disappearance, current White rim recovery, and
  wood-tint contradictions. Missing ink can create uncertainty; it does not by
  itself prove a stone. A fitted disk is separate from color and grid assignment.
- `Sources/StoneAppearanceModel.swift` and `Experiments/IntersectionAppearance/`:
  offline class compatibility is already available. Scores explicitly are not
  calibrated occupancy probabilities. It remains an inspector, not a runtime input.

The failed `live-photometric-stop` run has metadata but no exact failed lit PNG or
region scores. This study therefore does **not** attribute that failure to glare.
The passive OFF camera pair is independent retained evidence of current appearance,
not a reproduction of the lit failure or a motor/stand vibration experiment.

## Prototype and evidence

`probe.py` rectifies using the frame's own retained homography, probes narrow dark
ridges between intersections, robustly fits visible horizontal/vertical rails,
intersects those lines, and fits a diagnostic homography. It requires at least 10
supported rails in each family spanning 14 of 18 intervals. Each rail needs 24
inliers across at least nine intervals. Local search is +/-0.15 grid units.
This is retained-grid refinement, not independent grid acquisition.

Outputs keep geometry, local rail observations and clipping distinct:

- A pixel mask marks all-channel near-clipping (`min(B,G,R) >= 250`). It is an
  intentionally simple diagnostic, **not a glare classifier or admission rule**.
  White stones can clip; unsaturated glare and opaque covers need not clip.
- Each crossing has nearby observed-rail probe counts and clipped fraction.
- Reconstructed coordinates are tagged interpolation/extrapolation according to
  supported rail spans. Green marks mathematical interpolation; orange marks
  extrapolation. Neither color means empty or safe.
- Every intersection's `stoneState` is `unknown`, and `freshClearance` is false.
  This prototype has no stone classifier and supplies no placement/capture evidence.

Retained replay: nine frames, all with a supported diagnostic fit. The current
passive pair supports 19 horizontal + 19 vertical rails; occupied move88 supports
17 + 19; six D7 empty/White glare fixtures support 19 + 19. The passive anchor's
clipped fraction is 0.0953%; the second frame is 0.0174%; the occupied and D7 images
have zero pixels meeting this threshold after rectification. Visible glare therefore
is not equivalent to that clipping mask.

Maximum displacement **from the supplied prior**, not ground-truth error: passive
0.058 grid units, occupied move88 0.049, D7 up to 0.095. The two passive fitted grids
differ little, but systematic ridge/warp bias remains possible. Do not install these
homographies or treat small residuals as calibration accuracy.

Nine synthetic controls pass: clean grid; central clipped region; central
unsaturated opaque cover; 25 Black/White disks; three distinct hidden states made
pixel-identical by clipping; blank rejection; half-board cover rejection;
14-pixel translation beyond local search rejection; and measuring a small known
translation. Both central-cover cases retain global geometry while their hidden
crossing has zero nearby rail probes and unknown state. These are analytical
image controls, not physical hand/glare validation.

Reproduce (preinstalled Python numpy/OpenCV; no app build):

```sh
python3 -m unittest discover -s PhysicalGo/Experiments/GlareVisibility -p 'test_probe.py' -v
python3 PhysicalGo/Experiments/GlareVisibility/replay.py \
  --evidence-root '/Users/Dave/Documents/SGF PLayer' \
  --output '/Users/Dave/Documents/SGF PLayer/work/glare-visibility-offline-20261124/replay'
```

Local output: `/Users/Dave/Documents/SGF PLayer/work/glare-visibility-offline-20261124/replay/`.
`summary.json` includes original frame hashes and probe-source hash; per-frame JSON
embeds exact metadata and diagnostic outputs. PNGs are derived camera-only
rectifications/masks, never desktop screenshots. Raw sources were left intact.
`results.json` in this experiment is the small retained numeric summary.

## Finite next implementation proposal

1. Add an offline visibility record to the existing native replay, keeping separate
   `gridLocation`, `observedInk`, `body/rimSupport`, `colorSupport`, `clipping`,
   `occlusionUnknown`, and source frame/context. Integrate neither synthetic pixels
   nor reconstructed crossings into `exposedWoodConfidence`. A partial glare mask
   should reduce usable samples, never synthesize empty/stone/hand evidence.
2. Compare robust global line-family fitting against existing native alignment on
   this fixed corpus, then existing moved/covered and parallax fixtures. Hold out
   whole rails/regions when fitting and measure held-out errors. Report interval
   growth outside the supported hull and fit sensitivity across subsets. Reject
   ill-conditioned fits or insufficient spatial coverage. This prototype's residuals
   and prior displacement are not calibrated uncertainty bounds. Lens distortion,
   wood grain, star points, grid shadows and crowded stones remain failure modes.
3. For appearance, reuse confirmed setup-specific class templates and the existing
   local wood model: predict distributions of empty wood+cross, dark body+rim, and
   pale body+rim at each crossing under a bounded illumination field. Compare only
   observed samples outside independently detected occlusion/clipping. Require
   observed discriminating body/rim/rail evidence and unique assignment. A missing
   cross under glare must stay unknown; a bright disk needs bounded White evidence;
   dark shadows need exclusion. Avoid counting the same pixels/reference twice as
   independent evidence, and do not use game expectation as a label.
4. Evaluate exactly one bounded passive multi-frame window offline. Retain an old
   accepted state as historical context, but require fresh readable evidence after
   a placement/removal and after any possible hand interaction. Repeated identical
   glare is correlated evidence, not growing confidence. Capture removal remains
   pending until the required crossing is freshly readable; no invented clearance.
5. Only after root review and the freshness work is complete, consider attended
   exposure bracketing or an altered viewing/light angle. Shorter exposure can
   recover highlight detail only if the sensor signal was not already unusable;
   it can also lose black-body detail. Different viewpoints can move specular
   reflections, but require per-view calibration and raised-stone parallax handling.
   Lock/label exposure, camera identity, timestamps and setup per frame. Do not merge
   a moving hand/stone across views or renew the 600 ms deadline from an old image.
   Polarization/diffuse lighting are setup experiments, not software guarantees.

Board-plane line reconstruction does not correct stone-height parallax. Color
identity can be right while assignment to a neighboring intersection is wrong.
Retain full-body boundary, neighbor ownership and centering uncertainty; do not
move fitted stone centers onto reconstructed grid points merely because they are
expected there. Unknown visibility should block a required transition, while
preserving accepted game history and allowing unrelated geometry diagnostics.

No broad framework, new runtime classifier or automatic exposure policy is proposed
for this checkpoint. Next reviewable deliverable is the native visibility record
and fixed-corpus error/false-transition report, before any runtime integration.
