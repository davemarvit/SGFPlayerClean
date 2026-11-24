# Physical Go: current conversation handoff

Updated November 24, 2026 during attended calibration. **Physical Go 0.261/build
262 and AimControl v44 remain installed. App/camera open, new empty game paused.
Camera alignment passed; laser requalification is still incomplete.**

**Active continuation:** PTY 38073, `continued-fit-20261124-121422-43815`, started
after fresh READY. Root owns hardware.
The prior continuation `continued-fit-20261124-120522-42111` stopped after consistent
probes with insufficient measured tilt travel; PTY 55574 exited. Full OFF confirmed
at 1795550752.159239, no controller error. Check existing process before launching.
Monitor this run through completion and verify its final OFF; do not start another driver. Monitor using
`work/attended-recheck-20261124-105259/calibration-status.py`.

Calibration source is frozen `d92e6a8` in
`/Users/Dave/DYNAMIXEL-Go-Pointer-worktrees/calibration-observed-fit-anchor`. It includes
printed-boundary consensus, bounded OFF-lease/unknown-clearance recovery and fresh
pre-fit actual-pose/two-axis qualification, with one bounded extra tilt probe for
insufficient measured travel. Explicit continuation preserves the original 20 observations plus one reviewed stationary
position anchor and K10 (1.68 px) from the last stopped run. A19 and all remaining
fit/independent targets still need completion. Fresh position/two-axis checks passed in this active run; fitting resumed. The original finite deadline is
retained. Do not modify frozen source or reinterpret saved unknown as clear.

See the checklist's November 24 attended section for exact failures and tests.
The new launcher targets this continuation, not a fresh arbitrary run. All final
qualification and binding review must precede gameplay. Current empty Human Black
game: D710D336-2746-4004-9796-F63A8D2FB8F5. Previous games/clocks are backed up and
preserved through app controls; holding preference on, hints off, AirPod Pro 3.
No desktop screenshots were taken.

Read [AGENTS.md](../../AGENTS.md), [the checklist](IntegrationChecklist.md),
[next physical test plan](NextPhysicalTestPlan.md) and
[the new delivery/test report](CameraSafetyDelivery.md). Source/offline/install
results are distinct from physical validation. No old READY applies to a new run.

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
