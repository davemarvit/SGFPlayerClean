# Independent review of the native White-vote explanation

November 23, 2026. Source reviewed at `780caa9`. This is an offline diagnosis of
frame 697, not a production change, physical experiment or general validation.

**The recorded threshold/objective mechanism is verified.** In these two stones,
the White body fails the relative-color path and relies on brightness votes.
The lower body has fewer accepted votes. The actual disk/ring objective selects
the smaller upward region, exactly as documented. This is evidence of a native
center-estimation discrepancy in addition to the visible body's displacement
from the board grid; it does not identify physical thickness.

## Independent checks

The adjacent `review_check.py` reads the retained archive and trace, writes only
`independent-review-results.json`, and performs these checks in about two seconds:

- All eight native-build source hashes, original and generated geometry source,
  generator, image and event archive hashes match the saved manifest. The
  generated Swift diff adds logging only; vote assignment, candidate enumeration,
  objective, tie order and fit acceptance are unchanged.
- Four replayed footprints equal the actual archived operation's footprints,
  including centers, radii and scores. This establishes replay correspondence for
  this scene; it is not proof of identical installed source for every subsystem.
- Both traces contain 4,225 sample cells. Independent recomputation from the
  logged RGB chromaticities and grayscale values reproduces all 8,450 combined
  White votes, including the separate color and brightness branches.
- The neutral/cool color predicate itself has zero supporting samples inside
  both conservative body cores. This is not merely failure of the additional
  brightness floor on otherwise accepted color samples.
- An independent direct-sum search of the full native discrete radius/aspect and
  center lattice reproduces both winners, rather than checking only the supplied
  winning scores. Neither fit uses contextual occlusion or neighbor masks here.

| Point | Native objective | Native radius (col,row) | Native minus visible-body row |
|---|---:|---:|---:|
| Centered White 180 | .921197718631 | (.38,.3572) | −.1080866962 |
| Midway White 275 | .915054503413 | (.36,.3384) | −.1098819467 |

Source correspondence: `BoardVision.swift`'s `supportsWhiteStone` tests neutral
or cool color **relative to corrected wood chromaticity**. `StoneGeometry.fit`
ORs that branch with corrected gray brightness greater than reference + 0.12.
Its objective is inside-vote fraction minus 0.7 times ring-vote fraction. The
native winner is therefore expected for these inputs. There is no 0.28 center
clamp in this search; its search spans ±0.44 cells. The separate 0.28 acceptance
checks elsewhere are not the mechanism producing these two offsets.

The core percentages and exact-color failure explain the algorithm, but do not
establish why the physical lower body is dimmer (illumination, surface, camera
processing and reference effects were not independently manipulated). The
cyan-body diagnostic is itself an appearance estimator, not ground truth for a
contact point. The larger-disk counterfactual is one comparison, not an optimized
replacement. No independent native rebuild was needed for this review: source
and trace parity plus independent pixel-rule and full-search recomputation were
the focused controls.

## Parallax and fitting bias are different quantities

For one image and fixed grid, decompose the reported native offset as:

`nativeFit − grid = (nativeFit − visibleBodyEstimate) + (visibleBodyEstimate − grid)`.

The first term is the approximately −0.11-row disagreement just reproduced.
Both estimators observe the same already-projected image, so changing a camera
height hypothesis cannot repair the native vote mask's missing lower support.
The second term can contain true stone-height projection, grid/calibration error,
physical placement error and visible-body estimator bias. The present diagnostic
cannot split those components. Similar first terms on two stones do not justify
a portable constant correction. In particular, a height fitted to native compact
bright-region centers must not be silently applied to another contour estimator.

## Bounded corrective architecture

Keep color/occupancy support and full-body centering evidence distinct:

1. Keep the existing classifier and raw assignment checks as the baseline. A high
   White class score or compact-disk objective must not be treated as a calibrated
   probability that the physical center is known.
2. Add an **offline parallel geometry measurement**, conditioned on the color
   hypothesis but supported by independently visible boundary/edge evidence.
   It should report its visible arcs/body coverage, neighboring-stone ownership,
   radius/center disagreement and an explicit unresolved result. Do not require
   every interior pixel to pass the White class threshold to count as body
   geometry. Conversely, a permissive cyan mask alone must not label wood as
   stone or merge a stone with a bright patch.
3. Evaluate a fixed geometric consistency/abstention policy on frozen centered,
   displaced, halfway, shadowed, touching, hand-obscured and empty-board examples,
   including both colors and another setup. Preserve the known older false
   correction case. A full-body estimate may challenge the compact fit; it must
   not automatically waive existing assignment/hand/clock gates.
4. Only after that evidence, consider a separately reviewed runtime consumer of
   typed geometry evidence. Record estimator/version and setup in any optical
   profile; do not place camera pose or contour bias into the portable physical
   stone attributes.

The smallest useful next change is a diagnostic interface exposing these two
kinds of evidence and their disagreement, with a frozen replay comparison. It
avoids entangling a new contour estimator with move acceptance. Global brightness
threshold reduction, a constant offset and compensating board-grid motion are
not supported fixes: they could increase wood/shadow false positives and conceal
misplacement while retaining the same centering objective.

The current report is trustworthy within its stated two-stone scope. It supports
investigating the geometry objective before making profile policy; it does not
supply a production replacement or settle the pending Black/independent-setup
validation.
