# Physical Go: current conversation handoff

Updated November 24, 2026. **0.260/build 261 and AimControl v44 installed. App
closed, driver stopped, last confirmed full OFF `1795516412.7072308`. The board
moved relative to the camera/laser; qualification is required before laser use.**

Read [AGENTS.md](../../AGENTS.md), [the current checklist](IntegrationChecklist.md),
[the morning plan](NextPhysicalTestPlan.md), [camera reliability](CameraFreshnessReliability.md)
and [laser checkpoint](LaserMovementCheckpoint.md). The [guide](AgentGuide/README.md)
and [documentation index](DocumentationIndex.md) route to focused source/evidence.
Read the primary laser [handoff](</Users/Dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware/AI play integration reply.txt>);
older incoming messages and frozen worktree copies are historical.

## Exact continuation sources

- Installed app source: `/Users/Dave/SGFPlayerClean-worktrees/gameplay-ui-and-delivery`,
  `codex/gameplay-ui-and-delivery`, runtime `87200da`, compiled after `35c14a1`.
  Later documentation commits do not identify a different installed executable.
- Host: `/Users/Dave/Documents/SGF PLayer/work/ai-laser-integration/laser-position-recovery-20261123/calibration-acceptance-redesign/gameplay-session-source`,
  `codex/gameplay-session-admission`, pinned `1ae717e2c693aeca441325909e7634c906416be3`.
- Calibration launcher uses separately pinned frozen source. Read its guards
  before running; do not copy current docs into frozen sources and invalidate pins.
- Canonical repositories contain current guides but older runtime code. Start
  implementation from the appropriate installed-source worktree, after checking Git.
- Exact hashes, paired acceptance, installation and first-launch records:
  [overnight-0260](</Users/Dave/Documents/SGF PLayer/work/ai-laser-integration/laser-position-recovery-20261123/calibration-acceptance-redesign/gameplay-activation-20261124/overnight-0260>). Signed 0.259 rollback retained there.

## What is finished and what is open

Five calibration fit targets plus nine independent checks passed on the prior
setup (max final check error 2.990 px). Calibration was bound and real gameplay
reached 12 plies. After the movement, all three fresh camera checks reject the old
alignment. The old binding is retained; a launcher marker blocks its use. Camera
and laser reportedly stayed fixed together, but this does not eliminate parallax
if the board plane changed. An offline transfer estimate is deliberately not
production-loadable; 35/361 targets extrapolate beyond its prior domain.

0.259 moved request/status file IO off the UI thread; F5 was physically verified.
The subsequent 600 ms camera expiry still occurred. 0.260 adds stage tracing,
ephemeral IPC, honest bounded host transitions, unrecoverable-link-loss clock
pause, large AI clocks, four-sided labels and independent click controls. All
listed offline/paired checks and first-launch smoke passed. No 0.260 physical
endurance or audible click pass is claimed. Metadata still waits for PNG delivery;
separating them is the next proposed reliability improvement.

Game `EA70E983-9FAF-40ED-8939-312ED10A1A68` is paused at 12 plies, White E3 pending.
Clocks are Black 728.2641341662966 s / White 65.05366220814176 s. The real board is
empty. Preserve the save; choose a new empty practice or restore its stones before
Resume. Do not edit snapshots to bypass board agreement.

## Next actions and constraints

Continue offline reliability work; then root can perform current camera geometry
and attended optical qualification, review a new binding, and test ordinary play
under the [physical test plan](NextPhysicalTestPlan.md). Check for an existing run
and serial owner first. Wait for a fresh READY at the launcher's attended prompt.
Do not auto-restart from a prior READY or treat software tests as optical evidence.

No unattended laser, motor or audio tests. Keep AirPod Pro 3 output. Diagnostic
image saving/warnings remain off until a requested test. Notify Dave before any
desktop screenshot; actual camera images are the board evidence. Preserve the
before/after-movement recordings separately. The conservative data-pruning audit
is in `work/data-pruning-20261124`; retain unique recordings and KEEP evidence.
No component agent has an outstanding hardware assignment.

> Continue Physical Go from this handoff and the current checklist. Inspect the
> installed-source worktrees and current runtime state. Preserve game/clocks and
> the hardware-off state while addressing the open camera freshness path. Before
> physical play, qualify the moved setup with Dave present and record final OFF.
