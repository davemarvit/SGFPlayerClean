# Calibration, ongoing checks and timing limits

Updated November 23, 2026 (Pacific time). See the
[integration checklist](IntegrationChecklist.md) for current results and ownership.
Physical Go 0.253 and v44 firmware are installed; the game is paused and a fresh
full-board laser binding is not yet active. The staged calibration policy below
is implemented and independently reviewed, with 117 offline checks passing,
and the resumed moved-setup run passed **37 physical staged prelight checks**.
Full-board calibration remains incomplete: that run stopped at the separate
120-second target correction limit while approaching T19. See the latest checklist.

There are two initial calibrations: locating the printed board in the camera
image, then learning where motor positions place the laser on that board.
Later checks verify that these relationships still hold. Correcting one laser
aim during play currently does not rewrite the saved motor map.

## What each stage does

| Stage | Question answered | When it happens | Result and limits |
|---|---|---|---|
| **Initial camera-grid fit** | Where are the board's intersections in this camera image? | Setup, or after the board/camera changes. | Fits printed grid geometry. The current 19×19 qualification checks all 72 boundary intersections as well as interior evidence. This does not calibrate the laser motors. |
| **Initial motor-map fit** | Which motor positions put the laser at each board location? | A new pointer/board/camera setup, followed by independent check targets. | Uses observed laser spots and measured motor poses to fit a candidate map. Separate validation and a reviewed binding are required before gameplay. Numerical coverage of 361 points is not 361 physical measurements. |
| **Ongoing geometry checks** | Is the scene still consistent with the calibrated board? | During calibration samples and before/while using an existing setup. | Checks current grid, reference agreement and identity. A moved scene invalidates old geometry; it is not repaired by changing identity fields or refreshing a timestamp. |
| **Ongoing hand/stream checks** | Is the current view clear, aligned and fresh enough to act? | Continuously while the hardware is active, independently of longer image analysis. | A current permission with a short lifetime. It is never supplied by an old setup photograph or by a completed map fit. |
| **Per-move aiming and correction** | Where is the spot now, and what small correction reaches this target? | Each indicated move or marker. | The saved map supplies an initial aim; optical feedback corrects that indication. The saved map remains unchanged. |
| **Stone recognition and game acceptance** | What stones are physically present, and does that evidence establish a legal move or completed cleanup? | During normal play, using admitted clear/dark observations. | Separate game-state evidence. Calibration success, a laser acknowledgement or a temperature reading cannot accept a stone or switch clocks. |

Continuous map learning during gameplay remains **inactive**, checklist item18.
A separate reviewed offline prototype and cleared-board survey now exist; see
[overnight results](OvernightSoftwareResults.md). Current corrective aiming does
not update the active map.

## Longer static analysis, followed by a fresh clearance check

An image of stationary geometry can be analyzed for longer than a live clearance
permission lasts. The distinction is between **what the older image measured**
and **whether the scene is still safe and unchanged now**.

The staged policy is limited to attended, confirmed-empty calibration. It splits
prelight work into an analyzed image **A** and a later confirming image **B**:

| Step | Staged limit | Required evidence |
|---|---|---|
| Analyze A | Up to **3 seconds** for geometry analysis. | Preserve A's actual capture identity and timestamps. Analysis completion does not make A newly captured. |
| Obtain and verify B | Up to **2 seconds**, at most **3 attempts**. | B must have been captured **after A's analysis finished**. Its own image/metadata must satisfy the live checks. |
| Prove unchanged geometry | Within B's proof window. | All **72 boundary intersections** must remain consistent with both A **and the original reference**, with texture agreement and unchanged camera/context/epoch. Hand clearance is current, not inherited from A. |
| Limit A's total lifetime | At most **5 seconds from A's capture to actual light dispatch**. | Uses A's original timestamps, not analysis start/completion. B cannot renew A indefinitely; changed or over-age evidence requires a new analysis. |
| Keep B fresh | All four camera ages remain within **600 ms**. | Capture/publication Unix ages and capture/arrival uptime ages are checked separately. A recent publication cannot refresh an old capture. |
| Dispatch light | A final ticket lasts at most **150 ms**. | It also expires at any earlier A/B deadline, lease expiry or safety failure. The checks still apply when the serial command is actually written. |

The 3-second, 2-second and 150-ms limits are not added to create an unlimited
grace period: the 5-second A lifetime and the current B/lease limits still cap
the result. Gameplay retains its separate existing freshness policy; this
calibration-only change does not permit old hand or stone evidence during play.

## Other calibration and recognition limits

| Check or operation | Current limit | Meaning |
|---|---|---|
| Entire calibration run | **600 seconds by default**; configurable **60–900 seconds** normally. Explicit `--experimental-long-run` permits up to **7,200 seconds**. | Finite run deadline, not the maximum age of an image. This deadline was **not** the cause of the recent early stops. |
| Correct one named calibration target | **120 seconds by default**; explicit experimental `--target-seconds 0` disables only this timer. At most **35 corrections per navigation stage** remains. | Bounds a target search/correction attempt. Individual motor and evidence safeguards still apply throughout. |
| Refresh commissioning safety metadata | Poll every **20 ms**; cached validation allowance at most **250 ms**. | The allowance is shortened by the remaining app lease, all four actual 600-ms camera-age budgets and the run deadline. Invalid observations revoke permission immediately. It is not a 250-ms extension of those budgets. |
| Actual camera evidence consumed by hardware | **600 ms** age budget. | Remains current for calibration clearance and the existing gameplay frame reader. The staged A exception is for geometric analysis only; B remains live evidence. |
| New post-OFF reference frame | Bounded wait of **3 seconds**. | Waits for a genuinely newer qualifying frame; the wait does not make stale frames acceptable. |
| Normal optical frame collection | Bounded wait of **5 seconds** by default. | Freshness is checked on each collected frame. A shorter remaining staged-proof/run deadline takes precedence. |
| Separate light/dark from camera evidence | At least **300 ms**, plus the required frame watermark. | Avoids admitting buffered images from before the relevant light/dark transition. Callback-time streams require their measured flush bound; calibration requires camera-presentation timestamps. |
| App renews its hardware request | About every **200 ms**, with a **600-ms lease**. | Hardware must stop when the request expires, even if its own firmware heartbeats continue. |
| App considers driver status current | Less than **750 ms** old. | A recent camera image does not make an old hardware acknowledgement current. |
| Native standby camera admission | Less than **700 ms** old. | App-side eligibility; it does not relax the hardware reader's stricter 600-ms requirement. |
| Native move/target evidence window | Less than **1.5 seconds** old where specified by the game/guidance controller. | This is a game-observation bound, not permission for the hardware to use 1.5-second-old clearance. |
| Restore a pending target after a classified camera/lease delay | Observations less than **500 ms** old, plus the stable evidence below. | An additional recovery condition; a new heartbeat alone cannot relight the target. |
| Stable capture/centering or hand-recovery evidence | At least **3 distinct observations spanning 450 ms**; applicable witness gaps over **600 ms** reset continuity. | Evidence must also meet its identity, clear/dark and classification requirements. Waiting 450 ms alone does not establish a stone or clearance. |

The commissioning metadata allowance has been implemented and checked in
88 offline tests. Increasing it from 150 to 250 ms lets a briefly delayed reader
retain a still-valid permission for at most 100 ms longer. It does not change the
20-ms polling cadence, current image ages or final 150-ms light ticket.

## Independent motor and thermal safeguards

These protections continue during image analysis, movement, holding and cooling.
Their timeouts are not extra calibration-processing time.

| Safeguard | Limit | Effect |
|---|---|---|
| Monitored cold engagement | **12 seconds** maximum. | Bounds arming/bootstrap; repeated status messages cannot restart the allowance. |
| Firmware heartbeat | **400 ms**. | Loss stops the controller. Host heartbeats do not extend a finite light deadline. |
| Fresh pose before active commands / configured motor-bus watchdog | **200 ms** for each separate check. | Old pose admission and missing motor-bus communication are independently guarded. |
| Required thermal sample age | **750 ms**. | Host uses a causal acquisition-age bound; firmware also checks its own local sample age. Mac and MCU clocks are not subtracted. |
| Advancing thermal acknowledgement | **1,500 ms**. | Duplicate/stalled acknowledgements cannot keep a session alive. This does not relax the 750-ms sample-age limit. |
| One motor register transaction | At most **30 ms**. | Read/write failure stops the operation; longer image analysis does not extend motor I/O waits. |
| Host serial write | **100 ms** deadline. | Validation is repeated during partial writes; a queued intention is not a completed command. |
| Calibration light sweep | **60 seconds** maximum. | Normal measurement turns it dark much sooner; heartbeats do not renew this finite view. |
| Return from thermal cooling | Both motors below **40°C for 30 seconds** on fresh measurements. | Cooling begins at 45°C; hard stop is 50°C or a lower configured motor limit. Recovery also needs eligible session, clearance and pose evidence. |

The calibration command waits are also bounded: typically 2 seconds for pose/
state queries, 3 seconds for SWEEP/DARK acknowledgements, 4 seconds for PREPARE,
10 seconds for a coarse move and 11 seconds for a fine move. The existing run,
lease, freshness and hardware guards can stop these waits earlier. These reply
waits describe how long the host waits for completion; they do not grant stale
camera permission or a longer illuminated view.

## What failed in the recent attempt

In run04, K10 passed at about **1.86 pixels** of error. A later prelight iterative
alignment calculation took about **1.2 seconds**. The previous path then required
that same analyzed image to remain inside its **600-ms** camera-age limit, so it
refused light. The 600-second whole-run allowance had not expired.

That failure exposed the need to separate static geometric analysis from the
fresh final scene check. The staged A/B policy addresses that distinction; it
does not yet establish a successful full calibration or a measured setup-time
improvement. Retain game/clocks and the failed evidence while validating the new
path. No full-board binding should be inferred from the successful K10 point.

Sources: laser [calibration plan](</Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware/Fast setup calibration.md>),
[calibration runner](</Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware/Tools/commission_gameplay_calibration.py>),
[commissioning evidence permit](</Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware/Tools/commission_gameplay_dark.py>),
[frame reader](</Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware/bridge_frames.py>),
[thermal protocol](</Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware/bridge_thermal.py>),
[firmware](</Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware/AimControl/AimControl.ino>),
[app guidance](../Sources/PhysicalLaserGuidance.swift) and
[capture evidence](../Sources/PhysicalCaptureGuidance.swift).

## Longer experimental allowance (November 23)

Dave explicitly authorized a retry lasting beyond30minutes while away for a
couple of hours, with ordinary calibration unchanged. The separate branch
`codex/calibration-experiment-budget` adds an explicit per-invocation experimental
gate for `--seconds 7200 --target-seconds 0`. This disables only the per-target
elapsed timer; it does not disable the finite overall run limit,35-correction
cap, live camera/hand evidence, movement bounds, temperatures, serial/heartbeat
checks or full-OFF cleanup. Timing options are recorded in the run result.
Review/test and actual-run status belong to the checklist. The previous stopped
spot was too close to an edge for the unchanged fresh-start margin; extra time
is not a substitute for a valid starting spot.
