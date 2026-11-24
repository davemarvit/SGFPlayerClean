# Laser control, calibration and thermal holding

[Start here](README.md) · [Current status](../IntegrationChecklist.md)

The app requests a physical indication; the Python bridge independently admits
the target and owns the controller; firmware enforces local motion/beam guards.
Only the root integration chat operates hardware unless ownership is explicitly
transferred. Read the laser [AGENTS.md](</Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/AGENTS.md>)
and shared handoff before any serial operation.

## Source map

| Component | Responsibility |
|---|---|
| [PhysicalLaserGuidance.swift](../../Sources/PhysicalLaserGuidance.swift) | App request/status schema, short renewable lease, target evidence, generation/recovery and dark-frame admission. |
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
Gameplay firmware v44 provides the new contract. The November 23 checklist records
Physical Go 0.253/v44 installed and the short dark check passed; fresh full-board
calibration and gameplay validation remain separate. Consult that checklist for
later installation and physical results.

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

Old full-board interpolation evidence is not approval for a moved setup. At the
November 22 checkpoint, recalibration was partial and no fresh full binding had
been activated. Check the live checklist before using any saved binding.

## Latency and physical tests

Measure AI decision receipt, command dispatch/acknowledgement, first visible
light and final pointing accuracy separately. Sound starts with light dispatch
without waiting for playback to finish; actual acoustic/optical simultaneity
still needs measurement. Warm holding can avoid repeated cold ARM/HOLD work,
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
requalification was subsequently implemented and physically entered; the later
settlement-response disagreement still prevents full-board qualification. See
[the movement checkpoint](../LaserMovementCheckpoint.md) and current checklist.
This does not authorize automatic retry or an occupied-board calibration run.
