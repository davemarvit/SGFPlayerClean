# Next physical test session

Current feedback-test update — November 24, 2026: **Controller fully OFF;
retry launcher waiting at READY in PTY 7981. Do not start a competing driver.**
Root owns hardware. Frozen feedback source `352948b` in
`/Users/Dave/DYNAMIXEL-Go-Pointer-worktrees/three-point-feedback` is pushed.
Launcher: `work/PhysicalGo-Three-Point-Feedback.command`. Three camera rechecks
passed after the first attempt. Fresh user READY remains required before hardware.

First feedback attempt `three-point-feedback-20261124-141443-66813` stopped after
K10 for native `handObstructed: true`, with alignment valid. The exact saved
`guard-rejected-frame.png` appears empty: suspected false obstruction, not proof of
actual hand intrusion. Full OFF at `1795558540.6453667`, no controller error;
source manifests unchanged, PTY 32249 exited 1. READY-to-OFF: 57.152896 seconds.
K10 reached 0.1083 cells / 5.309 px in 27.668217 seconds (four moves), then
0.0331 cells / 1.625 px in 40.888455 seconds (six moves). F14 was interrupted
before a measured landing. Six further target results remain outstanding.

Benchmark route: K10, F14, B10, K2, S10, P15, K18. Same frozen three-point affine
seed only; fresh optical anchoring and local response updates within each target,
reset for each new target. Time to 0.20 cells is recorded before at most three
extra refinements toward 3 px. Near-edge inward waypoints/smaller steps avoid an
overshoot exposed by simulation. No dense-model steering or global learning.
248 calibration tests passed (19 optional skipped), including 17 local/wide/feedback
tests; 51 base model tests passed. This is a calibration-runner benchmark, not
installed gameplay latency. Hardware guards and final full OFF remain enforced.

Separate offline learning work `3ad106c` in `gameplay-learning-offline` is pushed:
10 tests pass. Shadow residual and separate response learning improve medians but
regress some fresh tail errors; no live promotion, installation or physical timing
claim. Eligible samples require actual motor/spot pairs, reliable pose timing and
board-plane evidence. Score-before-update, holdout checks and rollback implemented.
See `Firmware/Experiments/GameplayLearning/README.md` in that worktree.

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
