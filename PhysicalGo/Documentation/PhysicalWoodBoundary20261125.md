# Physical wood boundary and edge placement

Candidate based on installed native `939106a` (0.267). This source change is
offline only until root integrates the separate perimeter profile/pipeline
change, reviews the combined implementation, builds and installs it.

The intersection calibration is not the wooden board perimeter. The old hand
region used an implicit 0.75-cell expansion around the outer grid lines. The
new `HandBoardBoundary` holds a separately measured, validated four-corner wood
polygon in canonical grid coordinates. It leaves `BoardCalibration`, camera
context encoding and the laser model/binding unchanged. Its corners must be
ordered TL/TR/BR/BL, enclose every grid corner and fit within the sampled two-cell
camera margin. Cyclic/reversed corner orders are rejected. Edge coefficients
are precomputed; per-pixel containment does not allocate arrays.

The profile/pipeline owner supplies this polygon to `HandOutlineFrame` and pose
checks. Absence retains the old policy and is **not** evidence of an exact wood
boundary. Size/boundary changes discard the old tracker baseline. Visibility
coverage and exterior-pose clearance use only pixels inside the measured wood.
An incomplete exterior pose can be ignored only when its adjacent interior rim
has independent unchanged pixel evidence. Missing pose or missing interior
pixels remain unknown; these cannot authorize illumination.

For explicit wood profiles, the inactive tracker can now detect an entering
finger without waiting for Vision to find a hand skeleton. A connected solid
foreground core must cross the actual wood boundary and include changed
interior core pixels. Exterior pixels may establish connectivity; exterior
changes alone never establish obstruction. Isolated new stones and the dot do
not cross the wooden edge. The sampling integration must prevent an interior
sample's pixel footprint from including exterior image pixels while preserving
separate exterior context for this connectivity check.

New-entry candidates have an interior-only exposure/texture check so a shadow
does not automatically become a hand. It needs at least 12 actual interior
samples, original texture variance above 0.0001, correlation above 0.99,
exposure slope 0.6–1.4, and every sample's luminance residual and chroma change
at most 0.025. Outside texture cannot satisfy these requirements. This is a
new-entry policy, not a relaxation of active-hand clearance. Existing active
clearance additionally excludes exterior samples when an explicit perimeter is
present. Unknown or insufficient texture cannot provide this exception.

## Offline verification

`HandBoardBoundaryTests`: 384 checks passed in a direct optimized Swift build.
Coverage includes all four sides and corners, the measured November 25 polygon,
cyclic/reversed/invalid polygons, incomplete exterior poses, shallow fingers
without grid-line penetration, pose loss, fresh independent exit confirmation,
new entry with no pose, wrong-size profiles, exterior motion, black/white edge
stones, red dots, exposure, local 25% shadows, outside bowls with thin links,
shadows with pale fingers and outside texture that must not hide an interior
finger. All inputs are synthetic sampled-frame contracts, not camera recall
measurements.

The unchanged legacy path passed all 623 outline and retained-photo checks:
412 outline, 144 photographed boundary, and 67 recorded-outline checks. The
direct build used the candidate helper, timing and tracker sources plus the
existing three outline test files; no hardware or UI operation occurred.

`EdgePlacementGuardTests` audits the existing pending-move lifecycle using
injected recognition and an injected AI: A1/T1/A19/T19/K1/K19/A10/T10. A fresh
positive stone at a lit target requests OFF before dark evidence admission;
then stable dark White placement completes without any prior hand episode.
No hand event or optical status may append a move or reset the decision clock.
This behavior already existed; no AI acceptance threshold was changed.

## Limits and remaining work

This does not prove universal fingertip recall. A hand with insufficient
visible difference or no sampled interior core can remain undetected; missing
visibility must not be presented as clearance. A target's uncertain occupancy
still does not alone stop the cue: that established policy prevents glare or
the dot itself from cancelling an authoritative pending move. Positive stone,
actual hand/unknown hand, alignment and freshness checks remain separate.

The profile loader, clipping of real pixel footprints, current-frame image
controls and app installation belong to root's combined integration. Physical
validation must include outside-only hand movement, short shallow edge entry,
edge placement without a large hand episode, stable indication, and actual full
OFF at shutdown. No physical pass is claimed here.
