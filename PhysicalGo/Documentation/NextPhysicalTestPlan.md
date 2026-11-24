# Next physical test session

Current feedback-test update — November 24, 2026: **Controller fully OFF;
remaining-target launcher waiting at READY in PTY 42459. No active controller.**
Root owns hardware. Frozen source `5612839` in
`/Users/Dave/DYNAMIXEL-Go-Pointer-worktrees/feedback-remaining-targets` is pushed.
Launcher: `work/PhysicalGo-Feedback-Remaining.command`. Three fresh camera checks
passed (corner changes 0.115, 0.141, 0.070 px). Fresh user READY is pending.
Remaining route: K2, S10, P15, K18. Earlier targets will not repeat; the model is
still the original three wide observations, hash fedd0febe69daaa9ffa36e1ea6879b8def36d01f047226140e031f9d49c953e5.

Retry `three-point-feedback-20261124-144034-67453`, source `352948b`, PTY 7981
exited 1 after 202.595673 seconds READY-to-OFF. Completed K10: 19.123279 s,
2.631 px; F14: 24.179058 s, 2.544 px; B10: 30.352483 s, 0.959 px. B10 first
reached the 0.20-cell indication threshold at 25.118787 s. K2's last observation
was 0.313809 cells / 17.619 px after 95.198393 s; the next view was interrupted.
Terminal cause: `LaserTransportFault: Serial write completion exceeded deadline`;
native clearance also became unknown after a 0.687-second exposure gap. No positive
hand flag in that terminal frame. Original failed write details were evicted by
later OFF writes from the 64-entry ring, so exact scheduling/kernel attribution
is unavailable. Full OFF at `1795560237.089935`, no controller error, unchanged
source manifests. The actual port-write deadline is 100 ms, distinct from the
600 ms camera/lease checks. This fault is not declared solved.

Source `5612839` adds an explicit remaining-target batch and pins the earliest
eight write failures alongside 64 recent writes. Guards/commands/deadlines remain
unchanged. Offline: 12 serial diagnostic tests, 18 local/wide/feedback tests,
51 base model tests, and threaded controller/heartbeat smoke passed. No physical
run of this new source yet; no firmware, installed app or gameplay binding change.

First attempt `three-point-feedback-20261124-141443-66813` stopped for a false
native hand indication after K10, in 57.152896 s READY-to-OFF. K10 reached
0.1083 cells / 5.309 px in 27.668217 s, then 0.0331 cells / 1.625 px in
40.888455 s. Full OFF1795558540.6453667, no controller error. Exact rejection PNG
saved. Apple Vision replay gives a false right-fabric hand in 3/3 trials, with
one inferred joint at (18.708,14.555) inside the 0.75-cell outside-grid guard.

Native offline audit `e841750` in `hand-rim-diagnostics` runs the production
sampler/detector/tracker against explicitly substituted backgrounds. Older saved
reference: 6/1,078 rim samples fail (one brightness, five color), tracker obstructed.
Recent spot image and identical-image control: all pass, tracker clear. The first
old-reference brightness difference is 0.06885 against a 0.06 limit. This reproduces
background sensitivity but not the missing original live checkpoint. No hand
threshold or app behavior changed. See `PhysicalGo/Documentation/HandRimRejectionReplay.md`
in that worktree; evidence in `work/attended-recheck-20261124-105259/feedback-hand-rejection`.
First-obstruction checkpoint capture remains a useful next instrumentation task;
existing five-second stall capture misses these brief false entries.

Benchmark: frozen affine seed supplies response, fresh optical spot anchors
position, measured corrections update response only within a target; reset at each
new target. Time to 0.20 cells precedes at most three extra refinements toward
3 px. Near-edge inward waypoints/smaller steps prevent simulated overshoot. These
are calibration-runner timings, not installed gameplay latency. Both prior run
folders contain `timing-summary.json`; preserve interrupted travel time separately
from any remaining-target batch. No dense model steers these feedback runs.

Offline learning `3ad106c` in `gameplay-learning-offline` is pushed; 10 tests pass.
Shadow residual and separate response learners improve medians but regress some
fresh tail errors. No live promotion, installation or physical convergence claim.
Qualified actual spot/pose pairs, score-before-update, holdout checks and rollback
are required. See `Firmware/Experiments/GameplayLearning/README.md` there.

Previous completed wide test — November 24, 2026: **Wide three-point physical test completed;
hardware fully OFF, no active launcher/driver or pending READY.** Successful run
`three-point-wide-20261124-135944-63058`, frozen source `b7183b1` in
`/Users/Dave/DYNAMIXEL-Go-Pointer-worktrees/three-point-wide`, PTY 8386 exited 0.
READY-to-full-OFF **87.628823s**; acquisition 78.225342 s; first-to-third selected
observation 72.048064 s. Preflight/operator waiting excluded. Final AimControl v44
OFF at `1795557672.1890821`, controller_error/code null; no cleanup/source faults.

Actual fitting points near H3, D16, Q16: (6.70664,16.00862),(2.96008,3.01514),
(14.72738,3.12532). Minimum pair separation 11.7678 cells; area 76.2427 square cells.
Selected indices 0, 6, 11 among 12 new camera views; 11 dark movements. Only those three
landings enter the affine fit; nine transit views are retained/excluded. Old map
assisted direction only. This measures assisted three-wide-point acquisition, not
cold startup. No intersection-centering was required.

On the same 9 fresh guidance views withheld from both fits, median/max inverse spot
prediction error: three-wide affine 0.742/0.940 cells (30.74/39.45px), dense 97 ray
model 0.172/0.238 cells (6.54/8.38px). Against all 97 old measured samples, wide fit
median 1.496 cells, max 14.984 cells; nearby-three fit median 4.983, max 10.942 cells.
Wider coverage improved median error but leaves large extrapolation errors outside
the triangle. These are predictions at recorded poses, not fresh first landings or
corrected-target accuracy. All 361 nominal motor predictions are in bounds, but
none were commanded under this new model; no gameplay binding/firmware changed.

Reports/comparison/raw evidence are in the run above under
`work/ai-laser-integration/laser-position-recovery-20261123/calibration-acceptance-redesign`;
read `summary.txt` or `three-point-comparison.json`. Earlier local three-point test
completed in 30.064086 s; its failed predecessor and reset records remain preserved.
The three local points were too close because root implemented independent motor
probes. This wider repeat addresses that scope mistake. 11 local/wide tests plus
51 base runner/model tests passed before the physical run. Root solely owns hardware.

The saved checkpoint retains **97 observations and four fitting targets**:
K10 1.68px, A19 2.02px, T19 1.67px, T1 2.48px. A1 and the nine diagnostic checks are
not completed. The last restart rejected actual POSE 1897/2077 against the old
1933/2077 anchor. A preceding interrupted GOTO explains the partial position change;
this is not evidence that all optical measurements were lost.

Dave clarified the objective: minimal startup, optical feedback during play, and
learning from every reliable actual spot/POSE pair. Three non-collinear observations
can seed a local response; a full five-plus-nine tour is an optional validation
procedure, not a mathematical requirement. Do not keep restarting that tour as the
only way to obtain a usable model. The installed gameplay loop records observations
but does not yet update its model and performs a predicted coarse landing before
spot acquisition. A minimal feedback-first gameplay/learning path remains open.

Offline continuation changes are frozen at `58a9cf2` in
`/Users/Dave/DYNAMIXEL-Go-Pointer-worktrees/observed-calibration-continuity`:
retain completed measurements/checks, reacquire actual spot after OFF, remove old
position/3px prediction gates, skip redundant axis probes, and relax only transit
waypoint centering. Clearance stops can ask for fresh READY after confirmed OFF.
231 calibration tests (19 optional skipped), 51 model tests, 25 dark tests passed;
11 focused tests also passed with actual saved recordings. No physical validation,
new gameplay binding, firmware upload or installed app change is claimed.
Details: [observed continuity](</Users/Dave/DYNAMIXEL-Go-Pointer-worktrees/observed-calibration-continuity/Firmware/ObservedCalibrationContinuity.md>).

Physical Go 0.261/build262 and AimControl v44 remain installed. App/camera were left
open, empty Human Black game `D710D336-2746-4004-9796-F63A8D2FB8F5` paused, holding
preference on, hints off, AirPod Pro 3 retained. Previous games/clocks and all unique
recordings are preserved. No desktop screenshots taken. Check processes and fresh
camera state before any future attended hardware step; obtain READY at its prompt.

## Next implementation and physical check

1. Keep hardware OFF while preparing feedback-first gameplay. Preserve the saved
   map and all observations. Do not collect another full tour merely to improve
   first-guess accuracy.
2. Reuse the 97 observations as a starting estimate. Design startup to reacquire
   the current actual spot and use bounded travel plus optical correction. A sparse
   seed must not silently pass the old fixed-model full-domain admission rules.
3. Make every reliable indication a potential learning sample: retain actual spot,
   measured encoder position, setup identity, timestamps and quality. Establish
   stable pose during its frame window and distinguish board from stone surfaces.
   Evaluate new observations before training on them; retain rollback/provenance.
4. Keep camera alignment checks, independent hand/lease protection, motor bounds,
   thermal handling and full OFF. Improve delivery latency separately; moving
   analysis to another thread is not proof that the 600ms fault is solved.
5. Once the minimal path is tested, use one fresh attended startup and a short
   practice game to measure acquisition, corrected accuracy, cue and recovery.
   Ask READY at the actual launcher prompt, monitor to completion/full OFF.

## Optional diagnostic continuation

The tested `--resume-observations` mode can finish the remaining full diagnostic
tour if specifically useful. It preserves progress and avoids exact transit
centering. It is not yet physically tested and should not be presented as the
only path to play. Prior plan/version snapshots remain under
`work/attended-recheck-20261124-105259/docs-before-observed-continuity`.
