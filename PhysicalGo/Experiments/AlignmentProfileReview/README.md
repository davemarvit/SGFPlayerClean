# Independent alignment profile review — November 24, 2026

PG-31 remains open for paired installation and attended physical verification.
This review found no blocking regression in candidate
`002e4c711ba290cdf94f0f9071a2133b92d00ce0`. The bounded outer-rail search fixes
the retained 18:15 rejection with the existing contrast, normalized-shape,
fraction, quadrant and distinct-segment requirements intact.

The reviewer did not edit the candidate worktree, build Swift, acquire a camera
frame, access serial/controller hardware, launch the app, change UI state,
install software, or capture a desktop screenshot. Root remains the hardware
and integration owner. The authoritative issue state remains
`PhysicalGo/Documentation/IntegrationChecklist.md` in the integration repository.

## Independent checks

`replay_controls.py` ran 38 saved-image controls against each of root's retained
baseline and candidate standalone native replay binaries: 76 native invocations.
The script's exit status was zero; all 14 declared acceptance/rejection
expectations passed. Other controls measure behavior rather than invent a new
movement or lighting threshold. Full results, file paths, input hashes and
executable hashes are in `control-results.json`.

| Control | Baseline | Candidate | Interpretation |
|---|---|---|---|
| Exact rejected frame | Reject | Accept | Candidate fallback has support on all four borders. |
| ±0.5 and ±1 pixel, both axes (8) | 4 accept / 4 reject | All accept | Bounded jitter robustness. |
| 2 pixels, four directions | All reject | Left/down accept; right/up reject | Two-pixel image movement can be tolerated; the one-pixel search radius is not a one-pixel movement-admission threshold. |
| 5 pixels, four directions | All reject | All reject | No new admissions. |
| 10 pixels, four directions | Left/up accept | Same | Both use `tracking correction accepted`, with identical reported fit/error metrics. |
| 20 and 30 pixels, four directions (8) | All reject | All reject | Larger moved-board controls remain rejected. |
| Brightness factors 0.7, 0.85, 1.15, 1.3 | Only 1.3 accepts | All accept | Better exposure robustness for these synthetic variants. |
| Opaque 32-pixel stripe over each outer rail (4) | All reject | All reject | All four covered-border controls remain rejected. |
| Blank frame | Reject | Reject | No image support admitted. |

The left/up 10-pixel cases are deliberate existing tracking corrections, not
claims that the board stayed stationary. Their fitted maximum movements are
0.2867 and 0.3402 cells, below the unchanged 0.4-cell tracking bound; profile
errors improve from 0.04575 to 0.01724 and from 0.04102 to 0.01594 respectively.

Read-only inspection of root's `/tmp/physicalgo-alignment-profile-tests.log`
also confirmed 204 checks across occupied-grid (74), crowded-alignment (48),
glare-grid-recovery (64), and resume-alignment (18), all passed. These are root's
test results, not a second independently compiled suite.

## Scope and review observations

- The anchor samples remain unchanged. Only the fresh outer-rail samples search
  offsets; interior profiles still use zero offset. Each segment increments
  support once, regardless of the number of trials. Required support from every
  border and quadrant is preserved.
- The shift is at most 0.04 grid units. For the exact saved 1920×1080 calibration,
  enumeration of every sampled outer profile yields maximum continuous sample
  displacement 0.996492 pixels. The formula estimates pixel distance with a
  one-cell projective secant: its literal one-pixel guarantee should not be
  generalized to arbitrary perspective geometries without checking actual
  transformed sample distances. This is a portability concern, not a measured
  failure on the current setup. `patchMean` additionally rounds coordinates to
  pixel centers; sampling radius and motion tolerance are different quantities.
- No gate for hand clearance, camera age, lease, thermal state or controller
  authority is changed. Alignment acceptance alone does not establish that a
  hand is absent.
- Both executables were supplied by root. Their exact hashes are retained, but
  this reviewer did not rebuild them or create an independent source-to-binary
  receipt. Source review covered the committed candidate; its provenance remains
  linked to root's compile/test record.

## Reproduce

Run with Pillow available, using explicit saved files and the two standalone
`ReplayAlignment` executables. No build or live services are invoked:

```sh
python3 PhysicalGo/Experiments/AlignmentProfileReview/replay_controls.py \
  --baseline /path/to/ReplayAlignment \
  --candidate /path/to/ReplayAlignmentCandidate \
  --anchor-image /path/to/user-empty-reference-180203.png \
  --current-image /path/to/guard-rejected-frame.png \
  --anchor-calibration /path/to/anchor-calibration.json \
  --previous-calibration /path/to/previous-calibration.json \
  --output /path/to/control-results.json
```

Generated synthetic images are temporary derived controls; raw inputs are never
modified. Output timing includes process startup, reference loading and anchor
reconstruction, so it is not native pipeline latency or a live speed measurement.

## Remaining acceptance

The anchor is reconstructed from the user-captured empty reference; the exact
live tracker checkpoint was not saved. These controls cover one setup and one
incident, with synthetic translation, exposure and occlusion. They do not prove
physical hand-stop behavior, occupied-board reliability across arbitrary lighting,
or sustained gameplay. Root must integrate the intended combination, run the
paired acceptance, install it with rollback, and physically verify stable-board
continuity plus moved/covered-board rejection under attended safeguards.
