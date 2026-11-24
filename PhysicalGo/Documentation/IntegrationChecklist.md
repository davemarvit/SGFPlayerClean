# Camera, AI and laser integration — current checklist

Updated November 24, 2026 (Pacific time). This is the authority for current
implementation, installation, open work and physical validation. Read the
[handoff](NextConversationHandoff.md) to resume, the [project guide](AgentGuide/README.md)
for architecture, and the [documentation index](DocumentationIndex.md) for scope.
Prior checkpoints and exact earlier results are preserved in
[integration history](IntegrationHistoryThrough20261124.md) and
[LivePositionIssues.md](LivePositionIssues.md); their old “current” statements
and running process IDs are not current operating instructions.

## Current checkpoint

**Installed: Physical Go 0.261/build 262 and AimControl v44. Hardware driver
stopped; app closed; board empty. The setup moved after calibration and requires
requalification before laser use. The 600 ms camera-freshness problem is open.**

| Item | Verified record |
|---|---|
| App | `/Users/Dave/Applications/Physical Go.app`, signed 0.261/build 262 |
| App source | `/Users/Dave/SGFPlayerClean-worktrees/camera-safety-delivery`, branch `codex/camera-safety-delivery`; runtime `9c516f1` |
| Embedded source hash | `79f2ec079f3d116af313d612b4ad4a8f71ddb569211cce14f4c6f4a0569a30d7` |
| Installed executable SHA-256 | `b381f986a7a5e513bd77428adb28f4c7916b889c039556c3e0e577a4c3a7fee3` |
| Coordinated host | `/Users/Dave/DYNAMIXEL-Go-Pointer-worktrees/camera-safety-delivery`, branch `codex/camera-safety-delivery`, pinned `04b76c74257be04565385ec6d4a0e9cb0faf6848` |
| Firmware | AimControl v44; documentation work does not upload firmware |
| Last physical full OFF | Unix `1795516412.7072308`: beam off and motor bus power released; driver PTY 47092 exited 0, serial port subsequently free |
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
  App was **not launched** after this install. Saved game hash is unchanged;
  no camera, desktop screenshot, audio, serial or hardware operation occurred.
- Earlier 0.260 first-launch AX smoke verified paused game, large clocks and click
  controls; it is not a 0.261 first-launch or physical validation result.
- Receipts/logs/actual wire messages: [camera-safety-delivery-20261124](</Users/Dave/Documents/SGF PLayer/work/camera-safety-delivery-20261124>).
  [Implementation and test details](CameraSafetyDelivery.md) include the separate
  empty-board regional-change audit. Live recovery and AirPod Pro 3 audibility
  remain unverified on the latest version.

## Preserved game and equipment

Game `EA70E983-9FAF-40ED-8939-312ED10A1A68` is paused at 12 plies with White **E3**
pending (raw row 14, column 16, index 282). F5 was accepted earlier. Saved elapsed
balances: Black `728.2641341662966` seconds, White `65.05366220814176` seconds.
`AI Games/current.json` SHA-256 is
`0e5a41a3a0bb24d4d0cd1b051793faa150dc97c6f059a985143f52234101e0ea`.
Dave cleared the physical stones for analysis. Preserve this game; use the app's
practice loader for a new empty game or restore its position before Resume.

Twenty actual AUSDOM camera frames (1920×1080, ID `0x11000000bda0567`) were clear
and aligned **before** the reported movement. Three later camera-only frames
were clear but all had `alignmentValid=false`, with approximately 9–35 px corner
displacement. Dave reports camera and laser remained fixed relative to one another;
their relation to the board changed. The old map/binding is retained as evidence,
not qualified for the moved setup. See [laser checkpoint](LaserMovementCheckpoint.md).

## Current work list

| # | Work | Status / next evidence needed |
|---|---|---|
| 0 | Faster AI test mode | Installed: eight visits/no HumanSL; only completed idle workers survive ordinary Pause/Resume. Active searches and faults cancel. Measure cold/warm physical replies separately. |
| 1 | Motor movement faults | Earlier released/held encoder and raw-velocity observations remain inconclusive; no guard relaxation. Attended optical comparison remains optional follow-up. |
| 2 | Laser calibration | Prior setup passed five fit targets and nine independent checks, max final error 2.990 px. Movement invalidates current qualification; requalify before use. |
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
| 22 | Stone profiles/parallax | Named sets and optional per-color thickness installed since 0.258; no optical/parallax correction activated. [Passive-play feasibility audit](../Experiments/PassiveStoneHeight/README.md) reproduces historical held-out comparisons and shape/offset identifiability controls; no passive collector or correction installed. Independent setup/height identification remains open. |
| 23 | Ambiguous assignment | Guard installed since 0.258; 52 focused checks recorded. Retest halfway stones in both colors with hints off/on; correct color is not correct intersection. |
| 24 | Boundary geometry/difference studies | Diagnostic/offline work only. New full-resolution empty-board audit averages 4.26/361 regions requested across 19 comparisons; this is not stone/hand validation. Shadow/nonstone controls and fresh evidence remain required; unchanged pixels cannot supply fresh clearance or positive stone witnesses. |
| 25 | Practice fixtures | Four paused, reversible starts installed; 166 persistence/controller checks recorded. Follow displayed rotated coordinates and preserve original snapshot. |
| 26 | AI UI and sound | Introduced in 0.260, retained in 0.261: large clocks, four-sided labels, independent move-click controls. First-light cue once per move; E3 retry deduplication explains no repeat click. Actual headphone audibility still pending. |
| 27 | Saved-data retention | Three abandoned partial backups pruned only after exact duplicate/prefix verification (306,201,499 logical bytes). All unique game/recording/calibration evidence retained. APFS clone consolidation did not produce measurable material free-space gain. Audit at `work/data-pruning-20261124/`. |

## Immediate next steps

1. Follow [NextPhysicalTestPlan.md](NextPhysicalTestPlan.md): new camera geometry,
   attended interior optical screening, then independent boundary checks/binding
   review. The offline transfer estimate is a hypothesis, not a production model.
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
launching. No driver, unattended laser/motor/audio test or active agent dependency
is left running. An old READY is not a confirmation for a new physical run.
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
