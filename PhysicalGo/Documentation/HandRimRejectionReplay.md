# November 24 false-hand rejection replay

The exact rejected camera frame from feedback attempt
`three-point-feedback-20261124-141443-66813` is preserved. Apple Vision revision 1
repeated a false hand pose in right-side fabric in three of three offline trials.
One inferred joint maps to board coordinate (18.708, 14.555), confidence 0.682:
outside the 19-line grid, but inside the 0.75-cell obstruction margin.

`Tools/HandRimAudit.swift` runs the unchanged production sampler, hand detector and
outline tracker. It also explains each sampled rim failure using the same limits.
Build it with `python3 PhysicalGo/Tools/build_hand_rim_audit.py EXTERNAL_DIRECTORY`.
Run the executable with metadata JSON, rejected PNG, then one or more background
PNGs. It has no camera, app or controller interface.

The original live outline checkpoint was not retained. All supplied backgrounds
below are explicitly counterfactual, not a reconstruction of the actual state:

| Supplied background | Failed rim patches / 1,078 | Production verdict |
|---|---:|---|
| Rejected image itself (control) | 0 | Clear |
| Saved setup reference | 6: 1 brightness, 5 color | Obstructed |
| Last accepted spot image | 0 | Clear |

With the older reference, the first failure is at grid (18, 11.5): luminance
changes by 0.06885 against a limit of 0.06. The production tracker reports
“Tracking the visible hand outline.” Its unchanged-rim exception requires every
sample to pass; it does not tolerate even one failed patch. The recent spot image
passes in the relevant rim despite being a diagnostic image rather than the live
tracker's unmodified background.

This reproduces a plausible failure mechanism and background sensitivity. It
does not prove which background, gap/reset path, or outline state caused the live
stop. Changing the safety margin or ignoring outliers is not justified by this
single example: a narrow real fingertip must remain detectable. The next useful
instrumentation is a bounded first-obstruction snapshot with the pre-observation
checkpoint, current sampled frame, pose, and rim-rejection reason. Existing stall
snapshots only trigger after five seconds of pose/outline disagreement, so they
miss brief false entries that immediately abort calibration.

No production behavior, installed app, hand threshold or controller guard changed.
Replay output: `work/attended-recheck-20261124-105259/feedback-hand-rejection/rim-replay.json`.
