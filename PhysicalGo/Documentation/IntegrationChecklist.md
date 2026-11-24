# Camera, AI and laser integration — current checklist

Operational update — November 24, 2026: **Hardware fully OFF, controller fault
latched; reset requested from Dave and pending.** The physical three-point attempt
`three-point-20261124-133938-58346` exited 1 after one observation and zero completed
movements. READY-to-OFF was **16.2945466 seconds**, not a completed calibration time.
Final receipt: AimControl v44 OFF at `1795556395.0343037`, retaining
`RESULT ERROR reason=target_step_too_large gpio_high_ms=3843`.

Root's new test requested a 36-count PTO move; v44 fast-session fine moves permit
24/12 counts. The controller rejected before writing the goal. Corrected source
`019b6d7` in `/Users/Dave/DYNAMIXEL-Go-Pointer-worktrees/three-point-step-limit`
uses 18/10 with explicit fine-bound checks and seven passing focused tests.
Initial source `dca4653` remains frozen. Base suites passed 237 (19 skipped) and51.
`work/PhysicalGo-Three-Point.command` is pinned to the correction; no retry is
running or waiting. Do not restart before explicit reset, fresh full-OFF admission,
camera checks and READY. Root remains sole hardware owner. Firmware unchanged.

User still wants a timed successful three-point physical run and comparison with
the saved97 observations. The minimal-runner implementation is now present; it
collects three fresh spots without intersection centering and ends fully OFF.
Old map assists probe direction only, not the three-point fit. Completion and
accuracy comparison remain pending. A post-OFF comparison script is prepared at
`work/attended-recheck-20261124-105259/three-point-comparison/compare.py`.

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

Updated November 24, 2026 (Pacific time). This is the authority for current
implementation, installation, open work and physical validation. Read the
[handoff](NextConversationHandoff.md) to resume, the [project guide](AgentGuide/README.md)
for architecture, and the [documentation index](DocumentationIndex.md) for scope.
Prior checkpoints and exact earlier results are preserved in
[integration history](IntegrationHistoryThrough20261124.md) and
[LivePositionIssues.md](LivePositionIssues.md); their old “current” statements
and running process IDs are not current operating instructions.

## Current checkpoint

**Installed: Physical Go 0.261/build 262 and AimControl v44. Hardware fully OFF, driver stopped; app/camera last left open, game paused, board empty.
Camera alignment has been re-established; laser requalification is incomplete.
The 600 ms reliability problem remains open.**

| Item | Verified record |
|---|---|
| App | `/Users/Dave/Applications/Physical Go.app`, signed 0.261/build 262 |
| App source | `/Users/Dave/SGFPlayerClean-worktrees/camera-safety-delivery`, branch `codex/camera-safety-delivery`; runtime `9c516f1` |
| Embedded source hash | `79f2ec079f3d116af313d612b4ad4a8f71ddb569211cce14f4c6f4a0569a30d7` |
| Installed executable SHA-256 | `b381f986a7a5e513bd77428adb28f4c7916b889c039556c3e0e577a4c3a7fee3` |
| Coordinated host | `/Users/Dave/DYNAMIXEL-Go-Pointer-worktrees/camera-safety-delivery`, branch `codex/camera-safety-delivery`, pinned `04b76c74257be04565385ec6d4a0e9cb0faf6848` |
| Firmware | AimControl v44; documentation work does not upload firmware |
| Last physical full OFF | Unix `1795556395.0343037`, target_step_too_large retained; reset pending, no active driver. |
| Launch guard | `gameplay-activation-20261124/gameplay-requalification-required.json` blocks `work/PhysicalGo-Play.command` until current geometry, attended optical qualification and binding review |
| Rollback | Signed 0.260 bundle in `work/camera-safety-delivery-20261124`; preserve the saved game and paired host compatibility when rolling back |

The canonical app and laser repositories contain current documentation but older
runtime source than these isolated worktrees. **Do not build or launch the canonical
checkout assuming it is the installed combination.** Frozen calibration source,
old build receipts and pinned launchers must retain their provenance.

## Verification and limits

- 0.261 publishes checked hand/alignment metadata independently of PNG delivery;
  host `04b76c7` consumes it without borrowing timestamps/verdicts for old pixels.
  No camera/status/lease/thermal threshold changed. This removes one dependency,
  not proof that all 600 ms interruptions are solved.
- Final native safety suite passed 26 checks including >600 ms image stalls,
  bounded pending work, epoch reset, write failure and actual Swift exports.
  Integrated broker 49, monitored standby 345, guidance continuity 184 and AI-laser
  283 checks passed. Host 15 safety/wire, 134 gameplay and 149 bridge tests passed.
  Mandatory fresh app → host → app acceptance passed with 68 generated host statuses.
- Optimized build and strict signature verification passed. Signed 0.261/build 262
  is installed with matching binary/source hashes and a signed 0.260 rollback.
  The app was subsequently launched for the November 24 attended session below.
  No desktop screenshots were taken; camera-only evidence and accessibility controls were used.
- Earlier 0.260 first-launch AX smoke verified paused game, large clocks and click
  controls; it is not a 0.261 first-launch or physical validation result.
- Receipts/logs/actual wire messages: [camera-safety-delivery-20261124](</Users/Dave/Documents/SGF PLayer/work/camera-safety-delivery-20261124>).
  [Implementation and test details](CameraSafetyDelivery.md) include the separate
  empty-board regional-change audit. Live recovery and AirPod Pro 3 audibility
  remain unverified on the latest version.

## Preserved game and equipment

The 12-ply E3 test `EA70E983-9FAF-40ED-8939-312ED10A1A68` and original
five-ply game were preserved through the app's practice/return controls and
session backups. Current game `D710D336-2746-4004-9796-F63A8D2FB8F5` is an empty,
paused Human Black practice. Holding preference is on; centering hints are off.
Keep AirPod Pro 3 selected.

Fresh camera geometry and empty-board reference are established. Current stream
is `F1514C6F-7D81-4BEC-98ED-12BACE6F60E3`, AUSDOM `0x11000000bda0567`, 1920×1080.
The previous gameplay binding remains blocked for the moved setup.

## November 24 attended calibration

Five attempts stopped safely: old seed/context mismatch; a 3.017 px local boundary
measurement disagreement; an OFF lease expiring across a 641 ms request-read
interval; a 4.018 px local boundary disagreement; and unknown native hand clearance.
Read timings include scheduling and are not syscall-only measurements. The last
stop followed a 0.8 s gap between delivered camera observations. A hand-tracker
reset is plausible, but those published records alone do not identify the delayed
pipeline stage or prove which intermediate frames were analyzed.

- Calibration-only OFF-lease recovery: frozen source `982bdbf`, 206 calibration
  tests (12 optional skipped), 25 dark tests and 30 focused checks passed.
- Printed-boundary consensus: frozen source `3445585`. It rejects competing local
  line models and retains the 3 px map limit. Both rejected images, 100 fresh
  camera checks (max 2.129 px), 57 focused tests and four historical sequence tests
  passed under the existing lighting. No room-light change was needed.
- Latest stopped attempt retained 20 observations/19 moves and completed K10 at
  1.68 px. A19 was observed but not completed. Full OFF is recorded above.
- Pre-fit recovery source `8b8a4e2`, worktree
  `/Users/Dave/DYNAMIXEL-Go-Pointer-worktrees/calibration-fit-resume`, adds fresh
  actual-pose/two-axis requalification and full-OFF restart for independently
  classified unknown clearance. It does not treat unknown as clear. 214 calibration
  tests (15 optional skipped), 25 dark tests and eight focused/actual-record replay
  tests passed. One explicit hash-bound migration retains the old measurements,
  unchanged original failure report and original finite run deadline.
- `continued-fit-20261124-120522-42111` stopped after fresh position agreement
  (1.608 px) and two consistent probes: actual tilt travel was only three counts,
  below the independent response-basis requirement. Full OFF confirmed; PTY 55574 exited.
  Updated source `371cccc` in `calibration-fit-probe-extension` permits one extra
  same-direction contained tilt probe only for insufficient measured travel. All
  nine focused/actual-record replay tests passed. Three fresh camera checks passed;
  The next stationary observation stopped before new travel on old-anchor prediction disagreement; full OFF1795551006.046342. Source `d92e6a8` now uses that reviewed stationary position as the anchor, preserving all accuracy checks. Ten focused/record-replay and17 recovery tests passed. PTY38073 is running `continued-fit-20261124-121422-43815` after fresh READY; fresh position/two-axis checks passed and fitting resumed. No new binding is qualified.

Evidence and launcher backups: `/Users/Dave/Documents/SGF PLayer/work/attended-recheck-20261124-105259`.
Calibration attempts are under `work/ai-laser-integration/laser-position-recovery-20261123/calibration-acceptance-redesign`.
Native 0.261 and AimControl v44 were not replaced during this session. Independent
native timing instrumentation is pushed at `1f28d4c` in
`/Users/Dave/SGFPlayerClean-worktrees/camera-pipeline-attribution`; 54 photographed
hand/stone checks and 26 trace checks passed. It is not installed.

The passive stone-height study is pushed at `d0ed574` in `passive-stone-height`.
Effective optical offset may be learnable; physical thickness is confounded by
placement habits, camera pose and detector bias. Spatial correction did not
consistently beat mean bias in the small existing sample. Eight analytic controls
passed. A passive collector and any correction remain unimplemented.

## Current work list

| # | Work | Status / next evidence needed |
|---|---|---|
| 0 | Faster AI test mode | Installed: eight visits/no HumanSL; only completed idle workers survive ordinary Pause/Resume. Active searches and faults cancel. Measure cold/warm physical replies separately. |
| 1 | Motor movement faults | Earlier released/held encoder and raw-velocity observations remain inconclusive; no guard relaxation. Attended optical comparison remains optional follow-up. |
| 2 | Laser calibration | Prior setup passed five fit targets and nine independent checks, max final error 2.990 px. 97 current-setup observations retained; all hardware OFF. Minimal feedback-first startup/learning is now the objective; no new gameplay binding. |
| 3 | Hand clearance | Ordinary hand withdrawal and placement were observed. Recheck beam darkness and fresh-clear recovery in 0.261; do not confuse the later real hand episode with the 600 ms expiry. |
| 4 | Ordinary placement | Earlier Black/White moves and F5 laser indication passed. Broader 0.261 play, halfway-placement correction and clock behavior still need an attended run. |
| 5 | Captures | Offline coverage exists; single/multiple/partial removals and both colors need physical validation. |
| 6 | Move-to-light latency | Background request/status IO installed since 0.259; 0.260 added publication-stage tracing/ephemeral IPC; 0.261 separates safety metadata from PNG delivery. Injected-stall tests pass; no live latency improvement established; [600 ms reliability work remains open](CameraFreshnessReliability.md). |
| 7 | Monitored motor holding | v44/schema 2 implemented; short dark commissioning and interrupted gameplay exercised. 0.261 + host `04b76c7` retains honest bounded `transitioning`; physical recovery test pending. Full OFF still releases bus power. |
| 8 | Thermal endurance/cooling | Earlier short and partial endurance records retained; no two-hour physical pass or measured cooling recovery. Formal two-hour test optional. Monitor actual play; no unattended run scheduled. |
| 9 | Ended-game grid recovery | Fix installed since 0.252 and offline-tested; live finish/reopen validation remains. Unfinished paused games still constrain expected position. |
| 10 | Centering hints | Implemented behind preference; physically validate observed-disk target, hand stop and removal/centering. Never infer the intended intersection from an ambiguous disk. |
| 11 | Captured-stone indication | Installed app/host behavior; AI placement precedes silent individual prisoners. Physical accuracy/partial cleanup remain unverified. |
| 12 | Online-opponent laser integration | Still pending; accepting `source: online` in the wire schema is not a native authoritative target producer. Preserve server clock authority. |
| 13 | Illegal-move feedback | Screen-only diagnostic installed since 0.258; 69 controller and 83 mechanism checks recorded. Physical suicide/ko/restoration pending. Illegal-move laser pattern remains a proposal. |
| 14 | Documentation | November 24 reconciliation updates current guides, handoff, protocol and installation state; dated evidence retained and indexed. |
| 15 | New-setup calibration | One full run completed; no general setup-time improvement proven. Launcher now preserves any saved game and tests fresh OFF leases; seven injected guard cases pass. Post-movement camera/optical qualification is next. |
| 16 | Camera/occupied-board latency | Native timing now measured. Recent analysis median 60.1 ms, max 173.6 ms; no sustained analysis backlog established. Older occupied optical-registration reports describe a separate path. |
| 17 | Gameplay fault continuity | Scoped hard-fault pause installed; 0.260 adds continuous three-second transition bound and pause on unrecoverable own-game link loss. Classified camera/lease recovery remains. Live validation pending. |
| 18 | Adaptive map refinement | Offline/shadow only. No production learner or automatic model update. Recent residual interpolation worsened 4/8 supported endpoints and was not promoted. |
| 19 | Calibration progress | Installed passive stage/target/check display; five fit + nine independent checks, no ETA or binding authority. One 1,230.9-second observation span is not a reliable ETA model. |
| 20 | Architecture/process | Pure recovery reducer, immutable builds and paired acceptance integrated. Independent safety metadata is now installed in 0.261 and paired with host `04b76c7`; physical validation remains. |
| 21 | Timing contract/logging | Optional bounded native/host tracing implemented. Cross-process clock domains and missing events must remain explicit; no ACK-to-actual-light equivalence. |
| 22 | Stone profiles/parallax | Named sets and optional per-color thickness installed since 0.258; no optical/parallax correction activated. Independent setup/height identification remains open. |
| 23 | Ambiguous assignment | Guard installed since 0.258; 52 focused checks recorded. Retest halfway stones in both colors with hints off/on; correct color is not correct intersection. |
| 24 | Boundary geometry/difference studies | Diagnostic/offline work only. New full-resolution empty-board audit averages 4.26/361 regions requested across 19 comparisons; this is not stone/hand validation. Shadow/nonstone controls and fresh evidence remain required; unchanged pixels cannot supply fresh clearance or positive stone witnesses. |
| 25 | Practice fixtures | Four paused, reversible starts installed; 166 persistence/controller checks recorded. Follow displayed rotated coordinates and preserve original snapshot. |
| 26 | AI UI and sound | Introduced in 0.260, retained in 0.261: large clocks, four-sided labels, independent move-click controls. First-light cue once per move; E3 retry deduplication explains no repeat click. Actual headphone audibility still pending. |
| 27 | Saved-data retention | Three abandoned partial backups pruned only after exact duplicate/prefix verification (306,201,499 logical bytes). All unique game/recording/calibration evidence retained. APFS clone consolidation did not produce measurable material free-space gain. Audit at `work/data-pruning-20261124/`. |

## Immediate next steps

1. Implement minimal feedback-first startup and qualified learning from gameplay
   observations. Use the saved 97 observations; do not automatically repeat the full
   diagnostic tour. Follow [NextPhysicalTestPlan.md](NextPhysicalTestPlan.md).
2. Physically validate the independently delivered metadata and inspect remaining tail delays described in
   [CameraFreshnessReliability.md](CameraFreshnessReliability.md). Preserve original
   timestamps and fail-dark behavior; do not call moving IO off-thread a complete fix.
3. With qualified equipment and Dave present, test the click on AirPod Pro 3 and
   start a new empty practice game. Record ordinary moves, hand stop/recovery,
   transitions, clock pause on unrecoverable fault and final controller full OFF.
4. Continue controlled capture, centering and ambiguous-placement cases after
   ordinary play is stable. Record pass/fail/skipped rather than promoting offline
   checks to physical validation.

## Operating preferences and ownership

Root is the sole hardware owner. Check for an existing process/serial owner before
launching. Hardware is fully OFF and the attended driver has exited; there is no
unattended run. Independent agent instrumentation is complete and not installed. An old READY is not a confirmation for a new physical run.
Diagnostic image saving/warnings are off. Preserve games, clocks and calibration.
Notify Dave before **any desktop screenshot**; use actual camera files for board
evidence and accessibility text for UI checks. Keep AirPod Pro 3 selected.

Retain 45°C cooling, both motors below 40°C for 30 seconds of measured evidence
before renewed holding, and 50°C/lower configured-limit hard OFF. Sampled thresholds
are not guarantees of absolute temperature ceilings. Actual firmware faults need
their explicit reset workflow; a generic camera delay does not justify a power-cycle.
Three pixels was Dave's preferred aiming accuracy, not an immutable hazard limit;
implemented quality/geometry/control checks have distinct meanings and units.
Calibration-only experimental timing overrides do not widen gameplay's 600 ms.
