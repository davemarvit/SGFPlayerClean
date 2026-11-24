# Physical Go: current conversation handoff

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

Minimal-seed assessment: offline source `5c167da` in
`/Users/Dave/DYNAMIXEL-Go-Pointer-worktrees/minimal-calibration-assessment` compares
three local affine, three spread affine, five ray-model and 71-point dense-prefix
fits on 21 later withheld observations. Three-point global extrapolation is poor;
this does not measure adaptive optical convergence. First-to-third local saved
observation span is 11.082s, excluding startup/preflight/OFF, not a new tour time.
The proposed physical test times three observed positions (no intersection-centering
needed), then scores new targets before learning from them. Full97-model comparison
is diagnostic, not independent ground truth. Four math tests passed. No new physical
run, hardware activation or minimal-runner implementation in this assessment.
Report: [minimal comparison](</Users/Dave/DYNAMIXEL-Go-Pointer-worktrees/minimal-calibration-assessment/Firmware/Experiments/MinimalCalibration/README.md>).

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

## Current sources and receipts

- App `/Users/Dave/SGFPlayerClean-worktrees/camera-safety-delivery`, branch `codex/camera-safety-delivery`, runtime `9c516f1`.
- Host `/Users/Dave/DYNAMIXEL-Go-Pointer-worktrees/camera-safety-delivery`, branch `codex/camera-safety-delivery`, pinned `04b76c74257be04565385ec6d4a0e9cb0faf6848`.
- The canonical repositories contain current guides but older runtime code.
  Earlier 0.260 and calibration worktrees retain their own immutable provenance.
- Exact source/binary hashes, signed 0.260 rollback, logs, paired acceptance and
  literal Swift messages: [artifacts](</Users/Dave/Documents/SGF PLayer/work/camera-safety-delivery-20261124>). The gameplay launcher now pins
  this matched pair and still checks the equipment-movement blocker before serial.

## Earlier offline installation checkpoint

Safety metadata now has a small independent latest-only writer/reader, avoiding
PNG compression/write delays while preserving original timestamps and no unsafe
fallback. Optical aiming still requires its own fresh matching image. Final
native safety suite: 26 checks; host safety suite: 15 tests with Swift exports;
all five selected integrated suites and mandatory native→host→native acceptance
passed. Host gameplay 134/bridge 149 tests passed. Signed optimized build installed;
the app was left closed and no live hardware/audio/camera operation was performed.
This is not proof that every 600 ms failure is solved.

The fixed-anchor regional-change prototype was audited against 20 real pre-bump
empty-board images: 19 comparisons averaged 4.26 regions requested; median 7.39 ms
excluding decode, under concurrent build load. All three misaligned later images
were ineligible. No classifier skipping, map learning or optical correction was
activated; current hand detection still needs fresh White-stone shapes.

## Prior setup history (superseded by current state above)

Prior calibration completed five fit targets/nine independent checks (max final
error 2.990 px), was bound, and used for play. Subsequent movement failed all three
alignment checks. Old binding is retained and blocked. Camera/laser fixed-relative
geometry does not eliminate unknown board-plane parallax; the transfer estimate
remains a nonproduction diagnostic.

Game EA70E983-9FAF-40ED-8939-312ED10A1A68 remains paused at 12 plies, White E3
pending. Clocks: Black 728.2641341662966 s / White 65.05366220814176 s. Physical
board is empty; preserve the saved game and choose a new empty practice or restore
the position before Resume. Do not edit the snapshot to bypass board agreement.

Root checks existing process/serial ownership, establishes new camera geometry,
then performs attended interior and boundary optical qualification before binding.
Test ordinary play/hand darkness/recovery/clock pause and first-light click on
AirPod Pro 3. Record final controller full OFF. Diagnostic image saving/warnings
remain off until requested testing. No unattended motor/laser/audio run is scheduled.
Notify Dave before desktop screenshots; actual camera files are board evidence.
Preserve unique recordings/KEEP evidence and the existing pruning audit.
