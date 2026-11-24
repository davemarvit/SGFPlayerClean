# Next physical test session

Operational update — November 24, 2026: **Hardware fully OFF; no calibration
launcher/driver active or waiting for READY.** Last run
`continued-fit-20261124-124528-48748/attempt-000` exited 1 with confirmed
AimControl v44 OFF at Unix `1795553137.9640346`, no controller error. Root remains
sole hardware owner. No new physical run has been performed since that receipt.

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
