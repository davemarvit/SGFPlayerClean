# Next physical test session

Operational update — November24,2026: **Three-point physical test completed;
hardware fully OFF, no active launcher/driver or pending READY.** Successful run
`three-point-20261124-135005-60909`, source `019b6d7` in
`/Users/Dave/DYNAMIXEL-Go-Pointer-worktrees/three-point-step-limit`, PTY42102 exited0.
READY to confirmed full OFF: **30.064086s**; acquisition including first view:
19.943720s; first-to-third observation:13.616027s. Camera preflight/operator waiting
are excluded from READY-to-OFF timing. Final AimControl v44 OFF at
`1795557035.856552`, controller_error/code null, no cleanup/source faults.

The corrected18/10-count probes collected exactly three fresh actual spot/POSE
pairs and two dark moves. The97-point map assisted direction only; no old samples
entered the affine fit. The spots span less than0.4 cells: this is a local bootstrap,
not a widely spread three-point tour. Agreement with9 nearby saved observations:
median18.40px /0.347 cells, max21.46px /0.393 cells. Across all97 saved observations:
median176.04px /4.983 cells, max528.15px /10.942 cells. These are inverse spot
prediction errors at saved poses, not measured new landings or corrected accuracy.
Dense97-model prediction of today's3 fresh spots: median5.063px, max5.108px.

The new affine model extrapolates94/361 nominal predictions outside host bounds;
none were commanded. No gameplay binding or firmware changed. Optical-feedback
convergence and learning during play remain untested/unimplemented. Comparison
and concise summary: `three-point-20261124-135005-60909/{three-point-comparison.json,summary.txt}`
under `work/ai-laser-integration/laser-position-recovery-20261123/calibration-acceptance-redesign`.

Prior attempt `three-point-20261124-133938-58346` stopped after one view in16.294547s
when root's36-count fine probe exceeded firmware24-count pan limit. Dave power-cycled
both supplies; OFF/status check proved latch cleared at1795556958.424495. All three
camera checks passed afterward; Dave then gave fresh READY for the successful run.
Both attempts and original97 observations remain preserved. Root solely owns hardware.

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
