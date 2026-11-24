# Calibration speed: candidate map before independent validation

Historical source proposal. Later global steering and a full five-fit/nine-check
run completed on the previous setup. The current runner is separately pinned;
the old “today” source analysis below is not its current implementation. See
[the laser checkpoint](LaserMovementCheckpoint.md); no setup-speed improvement is claimed.

Source-only proposal, 2026-11-23. No hardware, fitting, image processing, or test workloads were run for this assessment. Reviewed runner SHA `a8f2e4e7c5a5218933d2c8ccf476dc39f4c872d0fa846f28fbd059f49fdcc1de`.

## Recommendation

Yes: after the five fit targets, construct and freeze a candidate global map from **fit-stage observations only**, then use it to seed bounded dark travel toward the nine held-out targets. Continue optical measurement and correction; retain independent acceptance. This uses information already collected without requiring a new architecture or weakening validation.

Today both routes use the same local Jacobian correction loop; `fit_model` is called only after both routes and confirmed full OFF. The fit routine needs at least nine observations plus full-board coverage, so “after five points” means after five completed fit targets and their intervening measured samples, not fitting five observations. See [route loop](/Users/dave/DYNAMIXEL-Go-Pointer-worktrees/calibration-experiment-camera-age/Firmware/Tools/commission_gameplay_calibration.py:602), [current final fitting](/Users/dave/DYNAMIXEL-Go-Pointer-worktrees/calibration-experiment-camera-age/Firmware/Tools/commission_gameplay_calibration.py:848), and [fit prerequisites](/Users/dave/DYNAMIXEL-Go-Pointer-worktrees/calibration-experiment-camera-age/Firmware/gameplay_calibration.py:245).

## Small implementation boundary

1. At the completed fit-route boundary, freeze the training list, setup identity, and source provenance. Fit a private candidate; reject nonfinite, out-of-domain, ill-conditioned, or poor-residual predictions before using it. Keep final publication after complete validation and full OFF.
2. Treat fitting as an explicit computation stage. Preserve present full-OFF fitting semantics initially, then requalify actual pose/spot in a new session before movement; do not casually insert a potentially long numerical optimizer into powered operation. A later independently supervised computation design is possible.
3. Use candidate predictions as suggestions inside existing motor spans, board margins, edge exit/approach routing, and fresh optical checks. Begin with the existing per-move envelope, not a single cross-board jump. Keep local feedback as fallback if candidate and observed response disagree. A candidate gives no new authority to illuminate or move outside those limits.
4. Freeze the candidate throughout validation. Keep final intersection error below 3 pixels and independent model prediction error below 8 motor counts. Validation measurements may support local control, but must not enter candidate training. Record candidate hash, initial prediction error, correction count, and final measured error separately. See [independent validation](/Users/dave/DYNAMIXEL-Go-Pointer-worktrees/calibration-experiment-camera-age/Firmware/gameplay_calibration.py:279).

This primarily improves validation travel. It does **not** shorten the first five fit targets. One partial full-calibration-04 snapshot had 98 observations, 98 moves, and all five fit targets complete; that is a snapshot, not a final latency result or a speedup measurement.

## Other repeated work worth measuring

| Source-supported behavior | Possible improvement after timing attribution |
|---|---|
| Every inset transit waypoint uses the same `<3px` stopping test as the actual calibration intersection. [Loop](/Users/dave/DYNAMIXEL-Go-Pointer-worktrees/calibration-experiment-camera-age/Firmware/Tools/commission_gameplay_calibration.py:628) | Separate safe transit arrival from precise measured-target arrival. Use an explicitly validated interior region for transit, while retaining 3px for all fit/held-out targets. This could reduce work during the first five targets too. |
| The planner limits optical travel to 40px near an edge and 110px elsewhere; only one adaptive local Jacobian drives travel. [Planner](/Users/dave/DYNAMIXEL-Go-Pointer-worktrees/calibration-experiment-camera-age/Firmware/board_commission.py:13) | Compare spatially informed candidate predictions against existing local steps. Do not widen limits just to reduce observations. |
| Every correction repeats PREPARE, geometry A, fresh proof B, light activation, five-frame consensus, registration, POSE, DARK and dark-state confirmation. [Measurement](/Users/dave/DYNAMIXEL-Go-Pointer-worktrees/calibration-experiment-camera-age/Firmware/Tools/commission_gameplay_calibration.py:474) | Reducing correction count removes complete cycles. Later investigate reuse of immutable reference computations and separately bounded short-lived geometry, retaining genuinely new safety evidence. |
| Fast travel issues GOTO and a second GOTO at actual settled pose to prime the next gain transition. [Movement](/Users/dave/DYNAMIXEL-Go-Pointer-worktrees/calibration-experiment-camera-age/Firmware/Tools/commission_gameplay_calibration.py:530) | Attribute both command waits before changing this intentional transition rule. |
| Optical sampling calculates a median and two registrations before spot detection; the runner also writes images and the growing result. [Acquisition](/Users/dave/DYNAMIXEL-Go-Pointer-worktrees/calibration-experiment-camera-age/Firmware/bridge_hardware.py:176) | Use completed-run timing to decide whether caching, reduced copying, or bounded asynchronous diagnostic writes matter. No current evidence establishes these as the dominant cost. |

## Acceptance evidence

Offline: immutable training/holdout split; no validation refit; bad map rejected; bounded route and edge path; fallback after wrong prediction; no lost fresh-frame, cancellation, thermal, or OFF behavior. Replay archived completed observations to estimate prediction error, clearly labeled counterfactual rather than measured travel time.

Physical comparison: same setup, same target tolerances and held-out coverage; compare observations, correction counts, command waits, computation time, total duration, and interruption rate. Portable setup success also needs first-stage timing and repeated new-setup trials. No percentage speedup is justified yet.
