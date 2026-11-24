# Physical Go: current conversation handoff

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
