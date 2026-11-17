# Laptop layout and offset-stone investigation — 2026-11-16

The three reported placements were recognized as white stones but held as uncertain
placements. This is a geometry/assignment problem, not simply low color confidence.
A separate hand-outline hold persisted after the player stepped away. No recognition,
clock accounting, or Go capture policy has been changed by this investigation.

## Preserved evidence

Local evidence folder:
`/Users/dave/Documents/SGF PLayer/work/laptop-parallax-incident`

- The original SGF, pending history, clock history, and 10,023-observation journal
  for game B17AC611-3EFA-4CCD-87AB-F419834A2E5B; both supplied screenshots.
- The last available automatic clip: 44 full-resolution images.
- A new, bounded static-board recording: 113 full-resolution images, 81 completed
  analyses, empty-board reference, calibration, tracking anchor, poses, fitted
  outlines, and recorder state. Recording stopped after collecting the static case.
- `evidence-manifest.json` verifies 176 preserved files (694,637,721 bytes).
  Copies of image archives use hard links; completed sources are marked KEEP.
- `timeline.json`, `pending-move-summary.json`, `parallax-measurements.json`,
  `stone-offsets.png`, and `analyze.py` retain the measurements and experiment.

The running app was left paused with 17 saved moves. Its SGF, pending-history, and
clock files remained byte-for-byte identical to the incident snapshot. The current
photograph also contains White B4 and Black E1 beyond those 17 moves. The user
subsequently confirmed both intended intersections. Given the saved Black move 17,
their photographed colors and alternating play infer White B4 as move 18 and Black
E1 as move 19. An offline extension records that inference without invented times;
the live record remains unchanged. The saved 17-move SGF alone is therefore
**not complete ground truth for the final photograph**. See
[the follow-up experiment](OfflineHandParallax-2026-11-16.md).

Continuous recording had stopped with “storage limit reached.” The selected 5 GB
is a maximum: the shared 10 GB archive budget can allocate less when older evidence
is pinned. The two prior games occupied about 9.3 GB. Their inactive original
archives were moved into `preserved-archives` outside the rotating budget, with
symlinks retaining their previous paths. No old evidence was deleted. The new static
session received the full 5,000,000,000-byte allowance. Earlier continuous images
of the three problem placements were not available; do not claim image replay of
those placement moments. The observation journal retains their classifications,
geometry offsets, pending decisions, clock events, and confirmations.

## Placement evidence

Displayed orientation is three quarter-turns; canonical points 92, 53, and 41 are
E17, C16, and C4 respectively.

| Move | Displayed point | Pre-confirmation observations | White classifications | Median assignment offset | Placement-uncertain readings |
|---|---|---:|---:|---:|---:|
| 4 | E17 | 160 | 160 | 0.32 cells | 160 |
| 6 | C16 | 183 | 183 | 0.32 cells | 181 |
| 12 | C4 | 299 | 299 | 0.36 cells | 299 |

These readings reported no hand obstruction. They span approximately 49, 52, and
85 seconds respectively, including time spent reviewing. The existing assignment
policy flags offsets at 0.30 cells unless independent outline/ownership evidence
resolves them. Human confirmations were saved; a later centering/disagreement
marker can reappear because confirmation does not rewrite camera evidence.

The static images still show leftward offsets around E17/C16/C4. A subpixel audit
of exposed printed lines gives median calibration residuals of approximately
0.020 and 0.035 cells along the two axes. That is substantially smaller than the
stone offsets. Stone height under an oblique camera is consistent with the
pattern, but physical miscentering and shape-fit error cannot be excluded from
these images alone. Moving the printed-grid calibration to stone centers would
confound those two surfaces.

The detector already searches up to 0.3 cells around weak classifications and fits
stone outlines. It does not explicitly model a spatial parallax field separately
from physical placement error. The failure here happens downstream in assignment
and placement confidence, even when color/occupancy is consistently correct.

A descriptive offline experiment withheld all three reported points and fitted a
simple affine offset field to nine other stable fitted stones. Maximum residuals
at the withheld points were 0.197 (E17), 0.229 (C16), and 0.138 (C4) cells. This is
promising only as a geometry diagnostic. The fit has not been tested against real
misplaced stones or phantom detections; C4 had a qualifying outline in only 13/81
static analyses. Do not substitute these residuals into live acceptance or clocks.

The same static sequence also leaves the touching white stone at D4 uncertain in
81/81 analyses. A parallax correction alone is not demonstrated to solve crowded
stone-outline ownership. Keep this as a separate negative case.

## Hand-outline hold

All 81 completed static analyses report:

- reliable pose result with no hands;
- outline obstruction, `poseLost: true`, edge 0, depth approximately 0.15;
- outcome “hand over board; waiting for clear frame.”

The inspected photographs contain no visible hand. Edge 0 is the canonical top
rim (displayed left). The tracker's depth calculation includes a 0.75-cell guard
outside the printed grid, so depth 0.15 places the tracked component's furthest
point at canonical row -0.60: outside the printed grid, inside that guard. This
points toward a persistent rim/background component, rather than proving that
the interior stone cluster is being tracked as a hand.

The frozen hand-tracker baseline and learned appearance from the initiating hand
entry are not present in this recording. Consequently, the exact cause of this
persistent component cannot be reconstructed from the saved state alone. A
fresh-tracker counterfactual returned three initialization frames followed by
78 clear frames on those same images, while the archived tracker stayed obstructed
in all 81. This isolates dependence on historical state, but cannot establish the
real exit time or justify restarting clocks retroactively. Resetting the tracker
is not a validated live fix: it could learn an undetected hand into its background.

## Clock and UI behavior

For move 12, the audible “Please pause play” began at 19:48:58.628. The automatic
clock hold followed at 19:49:01.675 while that sentence was still playing; it
finished at 19:49:09.192. The UI had meanwhile changed the main action to review
and resume. This explains the apparent missing Pause button; the clocks were
already stopped during the later part of the instruction.

The source UI now:

- keeps smaller clocks, with main-time/byoyomi details on one line;
- places game actions and interpretation controls beside the full board;
- sizes the board against remaining viewport height and scrolls the sidebar
  independently for longer warnings, help, and review controls;
- explicitly says “Clocks stay stopped” on clock review and provides independent
  Pause board checking when a review/storage gate masks the normal Pause action;
- uses recording terminology for camera controls and displays the actual reason
  if diagnostic recording stops.

Large-clock mode and existing actions remain available. Changes are compiled and
checked offline; the running app has not been replaced or restarted.

## Follow-up experiments

1. Preserve the frozen hand baseline, learned appearance, selected component
   bounds, and rejection/clearance reason when an outline hold stalls. Replay
   this rim case alongside real fingertips, missed poses, and camera gaps.
   Missing pose or a stationary component alone must never prove clearance.
2. Estimate a bounded spatial stone-center offset from multiple independently
   visible, established outlines. Keep printed-grid calibration separate. Treat
   the estimate as uncertain evidence, and abstain when support is sparse or
   inconsistent. Hold out the candidate being evaluated.
3. Evaluate the new assignment residual on this case plus genuine halfway stones,
   touching stones, phantom edge candidates, captures/removals, and the 65- and
   85-move games. Score placement accuracy and false acceptance before promotion.
4. Do not manufacture hand-exit timestamps or clock presses from a static image,
   a newly reset tracker, fitted parallax, or later confirmation. Retain the
   existing timing-review and Go capture safeguards.

## Validation

- 49 layout, voice-resource, clock-review pause, and game-preservation checks pass.
  Native offscreen renders cover 1060×740, 1280×800, 1440×900, and 1.5× text.
- 720 existing clock and Go capture checks pass: 113 capture uncertainty, 103
  capture guidance, 75 clock engine, and 429 automatic-capture/hand-clear checks.
- Production native replay of static frame 1 matches every archived intersection
  classification. It reproduces 10 black, 8 white, 10 uncertain, 333 empty; the
  archived outcome is the persistent hand-outline hold. Frame 50 was retained but
  skipped for analysis, so it is used only as photographic evidence.
- `git diff --check` passes. Test windows render offscreen without taking focus.
- The ongoing app remains paused, showing 17 saved moves and no pending moves;
  Black 1:21 and White 0:56. Continuous image recording is off after the bounded
  evidence collection, and automatic diagnostic clips remain enabled.
