# Laser control, calibration and thermal holding

[Start here](README.md) · [Current status](../IntegrationChecklist.md)

The app requests a physical indication; the Python bridge independently admits
the target and owns the controller; firmware enforces local motion/beam guards.
Only the root integration chat operates hardware unless ownership is explicitly
transferred. Read the laser [AGENTS.md](</Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/AGENTS.md>)
and shared handoff before any serial operation.

## Source map

The links below identify components in the canonical repository. Current runtime
code is in the isolated worktrees named by the [checklist](../IntegrationChecklist.md);
the canonical checkout may be older. Use the paired host pinned by the launcher,
not an arbitrary similarly named `laser_bridge.py`.

| Component | Responsibility |
|---|---|
| [PhysicalLaserGuidance.swift](../../Sources/PhysicalLaserGuidance.swift) | App request/status schema, short renewable lease, target evidence, generation/recovery and dark-frame admission. |
| [LatestFileExchange.swift](../../Sources/LatestFileExchange.swift) | Live app background status reads and latest-only request writes; original request deadlines and status timestamps stay authoritative. |
| [bridge_lease.py](</Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware/bridge_lease.py>) | Strict request parsing, immutable revisions, expiry, cancellation and worker generation gate. |
| [bridge_runtime.py](</Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware/bridge_runtime.py>) | Request/status file loop, independent supervision, worker lifecycle, OFF/standby barriers. |
| [bridge_hardware.py](</Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware/bridge_hardware.py>) | Actual backend, calibration admission, bounded coarse travel, optical correction, cue dispatch and logging. |
| [point_session.py](</Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware/point_session.py>) | Serial ownership, receive/write transport and controller response matching. |
| [bridge_off.py](</Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware/bridge_off.py>) | Fresh serialized full-OFF confirmation. |
| [bridge_frames.py](</Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware/bridge_frames.py>) | App-owned frame consumption and freshness/identity checks. |
| [bridge_setup.py](</Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware/bridge_setup.py>), [bridge_reference.py](</Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware/bridge_reference.py>), [bridge_alignment.py](</Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware/bridge_alignment.py>) | Commissioned artifact binding, reference management and optical registration/preparation. |
| [bridge_thermal.py](</Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware/bridge_thermal.py>) | New v44 causal telemetry/session helper; consult checklist for integration/installation status. |
| [AimControl.ino](</Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware/AimControl/AimControl.ino>) | Firmware state machine, motor configuration/readback, local current/motion/temperature/heartbeat safeguards. |

`laser_bridge.py` is the explicit hardware launcher; it is not an offline test.
`commission_app_bridge.py` is also live hardware commissioning, even though it
uses a private request directory. Importability and a private directory do not
make a tool harmless to run. The bridge and serial port each have an exclusive
lock; do not start a competing diagnostic controller.

## Request, acknowledgement and observation

Files live under `~/Library/Application Support/Physical Go/LaserBridge/`:
`request.json`, `status.json`, `driver.lock` and `frames/`. The app renews its
request about every 200 ms with a 600 ms lease. Heartbeats change lease times,
not the immutable operation. Host expiry is supervised independently of a motor
worker continuing to send firmware heartbeats.

Live request/status file IO runs on two independent background queues. There is
at most one read and one write in flight, plus one replaceable pending request.
The main-thread consumer checks the cached status's original timestamp; a slow
read cannot extend freshness. Queued requests retain their original lease expiry,
and OFF replaces pending pointing work. An in-flight write can finish first;
OFF submission is never treated as an OFF acknowledgement. Manual (`automatic:
false`) test instances keep synchronous IO for deterministic protocol fixtures;
`bridge-io-test` and the async cases in `ai-laser-test` cover the live exchange.
Optional bounded latency tracing includes camera queue, analysis and main-thread
delivery timings, plus background bridge IO duration.

An OFF request does not prove darkness. A new producer requires an OFF handshake.
The host invalidates old worker commands, waits for quiescence and obtains a
fresh hardware receipt before publishing state. Status must match producer and
revision and be recent; old results cannot bless a replacement target.

To use camera evidence after light, the app requires confirmed darkness, a
post-dark frame watermark in the same stream, and at least a 300 ms presentation
flush. Callback-time streams need their explicit measured flush bound. Neither a
dark receipt nor an “adequate” pointing result accepts a move or changes clocks.

The legacy contract is documented in [laser-bridge.md](../laser-bridge.md).
Some historical sections there describe earlier milestones; use its current
extension note and the checklist to distinguish those from current behavior.

## Monitored holding: schema-2 contract

The exact agreement lives in the laser repository's
[Gameplay standby protocol.md](</Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware/Gameplay standby protocol.md>).
It is more authoritative than a paraphrase here. v39 lacks this monitored
standby capability; private v43 thermal firmware cannot illuminate or play.
Installed gameplay firmware v44 provides this contract. The current paired
software is Physical Go 0.261 with host `04b76c7`. A short dark check and earlier
interrupted gameplay were exercised; the latest recovery changes remain physically
unverified. The completed prior calibration needs requalification after movement.

The new capability is `darkMotorStandbyV1`. Discovery uses schema-1 full OFF,
then a new schema-2 OFF revision and matching confirmation before active use.
Standby carries an explicit `playSession`; a hand can request `retainOnly` for
an existing safe hold but cannot authorize cold engagement or recovery engagement.

| State | Meaning |
|---|---|
| Full OFF | Beam off and motor bus power released. Required for shutdown/pause/fault. |
| Holding | Beam dark, motors held, bus powered; uses a separate dark receipt. |
| Cooling | Motors released between indications, with measured temperature supervision. |
| Arming | Bounded dark cold startup; not a dark-evidence acknowledgement or illumination permission. |
| Transitioning | Fresh scoped heartbeat while the host finishes a warm handoff; output is uncertain and no dark receipt or first-light acknowledgement is allowed. |

The native transition deadline is three seconds across revision changes. A valid
transition must echo the current producer, revision, session, camera context,
stream epoch, setup and standby capability. It conservatively reports possible
light, explicitly unconfirmed illumination, and no OFF/dark timestamps or frame
watermarks. Only a subsequent genuine state can authorize recognition or a click.
The ordinary 0.75-second status freshness guard stays in force.

A missing status still immediately requests OFF. Classified camera/lease failures
can use the existing confirmed-dark recovery. If the driver instead returns an
unexplained scoped full OFF, or remains missing for three seconds after the latch,
the native AI owner pauses the game and clock, retains the pending move, and
requires explicit recheck/Resume. Hardware recovery does not resume the game.

The accepted policy enters cooling at either motor's 45°C reading. Persistent
hold can return after both stay below 40°C on fresh measured evidence for
30 seconds, with a live eligible session and clear validated board. At 50°C or
a lower configured motor limit, and on failed/stale required telemetry, stop and
latch full OFF. This is a sampled policy, not a guarantee that physical case or
internal temperature can never exceed a threshold.

Host and MCU clocks are independent. Causal acknowledgements bound acquisition
age using host-clock events; do not subtract nominal MCU elapsed time from Mac
uptime. Telemetry output must not stall motion guards or the motor-bus watchdog.
The cached USB core's `availableForWrite()` alone does not prove a nonblocking
write. The new protocol documents its endpoint-ready bounded output path.

## Calibration has three distinct parts

See [Calibration and timing limits](../CalibrationAndTiming.md) for the two
initial fits, ongoing checks, and the staged separation between longer static
geometry analysis and fresh final clearance. Its tables distinguish computation
deadlines from camera, lease, motor and temperature evidence limits.

1. Select and verify the actual app camera and its advancing stream.
2. Verify the app's board grid/reference geometry for the current board position.
3. Verify the pointer's optical model and binding to that camera/setup, including
   fresh target checks after the camera, board or pointer moves.

`SetupBinding` hashes the setup/model/reference artifacts, checks camera/context,
image dimensions, board size and allowed targets, and registers current pixels
against the commissioned reference. That validates identity and geometry; it
does not prove an unmoved pointer solely from a file hash. Reacquire optical
evidence. The app supports 9/13/19 boards, while the inspected hardware setup
admission is commissioned for 19×19; do not assume app size support implies
pointer calibration for that size.

The November 24 full calibration passed five fitting targets and nine independent
checks, and was bound for play. The subsequent movement invalidates its current
qualification. The binding is retained and gameplay is blocked pending new
geometry/attended optical review. See [the calibration checkpoint](../LaserMovementCheckpoint.md).

## Latency and physical tests

Measure AI decision receipt, command dispatch/acknowledgement, first visible
light and final pointing accuracy separately. Calibration attention beeps and the
native AI stone click are different cues. Native click uses first confirmed
illumination once per move; retries and centering stay silent. Dispatch/playback
acknowledgement does not prove acoustic/optical simultaneity or audibility. Warm holding can avoid repeated cold ARM/HOLD work,
but no historical timing is a measured speedup of the new implementation.

The accepted sequence is software/fault tests, a short root-owned dark hold/stop
check, fresh calibration, ordinary fast-AI recognition, centering, then controlled
captures. Formal two-hour endurance is optional. The partial private thermal run
is useful evidence but did not establish a two-hour pass, thermal plateau,
physical cooling recovery, case temperature or seated noise performance.

## Initial calibration progress

The passive [calibration progress panel](../CalibrationProgressUI.md) reads the
external runner's versioned status. It shows actual stage, completed target
checks and elapsed time, with explicit stale/stopped/review-required states.
It cannot command hardware or activate a calibration binding.

## Future manual requalification design

[Explicit manual requalification](../ManualRequalificationDesign.md) describes a
design for replacing incident-specific restart adapters. Explicit manual
requalification was subsequently implemented and physically entered. Later global
steering completed full-board qualification on the prior setup; that setup then
moved and requires fresh qualification. See
[the movement checkpoint](../LaserMovementCheckpoint.md) and current checklist.
This does not authorize automatic retry or an occupied-board calibration run.


## Historical November 23 prediction disagreement, distinct from aiming error

The camera measures the spot and requests small corrections; the motors
separately control their encoder positions. Calibration also compares a local
response estimate against the frozen global model. Its 3px consistency limit
compares predictions, not actual target accuracy. A clean settlement can fail
that check before the next camera measurement.

On November 23, requested pose 1860/2294 passed with 2.919px agreement, but actual
settlement 1860/2292 failed at 3.450899px. A separately admitted stationary
observation then found the frozen prediction 1.46px from the actual spot and the
local estimate 5.10px away. This was an intermediate waypoint, not an
intersection accuracy test.

Generic observed-anchor requalification is implemented on laser branch
`codex/initial-spot-requalification` (`a84faa5`). It passed 34 independently rerun
tests and physical position and two-axis qualification. The default stops after
qualification; explicit full validation uses the established monitored-pose
policy. The optional expected-pose gate on `codex/initial-spot-pose-gate`
(`ece72fa`) passed 54 tests and a stationary physical check. Neither activates a
gameplay binding.

Those November 23 steering investigations are historical. Later global steering
completed the full calibration; its source and limitations are in the movement checkpoint. An optional conservative proof must not silently become
a new required guarantee: proving containment over every permitted holding
position makes some edge checks impossible, although the established policy can
test them. Consult the current checklist for enabled source and physical results.
The proposed recovery does not permit retries after controller, camera, hand or
transport faults.


## Ephemeral IPC publication

The [ephemeral IPC implementation installed in 0.260](../../Experiments/EphemeralIPC/README.md)
uses same-directory POSIX temporary-write/close/rename for live broker PNGs,
manifest and request JSON. It preserves atomic visibility and original deadlines,
without claiming crash durability. Persistent game/calibration writes are excluded.
The broker retains four protocol images using a queue-owned list after one startup
scan. Optional bounded trace events separate encode, pixel write, manifest and
pruning costs. Private benchmarks did not establish a speedup; consult the current
checklist for installation/physical-validation status rather than assuming this
source change fixed the observed interruption.
