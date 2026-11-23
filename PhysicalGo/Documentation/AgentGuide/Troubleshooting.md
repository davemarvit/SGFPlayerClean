# Troubleshooting and known problems

[Start here](README.md) · [Current status](../IntegrationChecklist.md)

This page is a navigation aid. The checklist owns current open/closed status;
[LivePositionIssues.md](../LivePositionIssues.md) owns detailed incident evidence.
Do not turn a plausible explanation into a diagnosed cause without reproducing
or measuring it.

## First response to a reported malfunction

Follow the application [AGENTS.md](../../../AGENTS.md). When the user reports a
stuck app, wrong board reading, failed setup or another malfunction, first stop
recording image saving and silence warning feedback:

```sh
osascript PhysicalGo/Tools/pause_recording_for_diagnosis.applescript
```

Verify continuous/automatic recording and next-game arming are off. Preserve game
history, timestamps, clock balances and calibration. If the UI changed, inspect
and operate the equivalent controls; a script exit alone is not proof of success.

Inspect the relevant recording and logs. Trim only a demonstrably repetitive tail,
keeping at least 30 seconds after the last meaningful event plus the final image,
using the documented trim tool and its audit. Do not remove evidence needed for
a hand transition, stone cleanup or camera gap. Leave saving/warnings off during
investigation; re-enable them when testing is requested. Prefer next-game arming
to recording irrelevant setup time.

## Symptom routes

| Symptom | First distinction | Read/inspect |
|---|---|---|
| “Wrong camera” | App-selected device versus a separately opened diagnostic camera | [CameraRecognition](CameraRecognition.md); device ID and current app preview/broker identity. |
| Hand never clears | Current hand outline/motion evidence versus retained stone/old background evidence | `HandOutlineTracker`, incident R13 fixture and latest clearance entries. |
| Stone missing or misread | Lighting/shape classification versus ambiguity, alignment loss or stale results | `BoardVision`, `KnownEmptyLighting`, occupied references and incident-specific recording. |
| Cleared board cannot recover grid | Ended history incorrectly constraining recovery versus an intentionally unfinished saved game | `ExperimentModel.recoveryExpected`; recovery lifecycle tests. |
| Laser does not appear | Physical switch, controller identity/OFF handshake, lease, camera, binding, target evidence or latched fault | [LaserControlCalibration](LaserControlCalibration.md); request/status and controller log. |
| Laser is dark but motors remain held | Explicit monitored holding versus full OFF | New state-specific receipt; never infer power release from laser darkness. |
| Camera evidence remains blocked after light | Requested OFF versus confirmed dark receipt and post-dark watermark | `PhysicalLaserGuidance.acceptsObservation`; exact frame epoch, ID and timestamp source. |
| Capture marker points incorrectly or cleanup stalls | Legal prisoner set, placement-first priority, current present/empty witnesses | [Markers](Markers.md); all three capture test layers. |
| Suspected suicide or ko gets generic correction | Confident illegal input versus uncertain vision or capture cleanup | [Illegal-move proposal](../IllegalMoveMarkerDesign.md), current rule policy and `PhysicalMoveInference` filtering. |
| Incorrect time charged during cleanup/recovery | Local, AI-practice or online clock owner | [GameAIClocks](GameAIClocks.md); original accepted event and clock anchor. |
| Motor “moving too fast” while apparently still | Raw velocity estimate, encoder movement and optical spot movement are different measurements | Motor logs and motion safeguards; do not widen a guard to force a pass. |
| Temperature test stops on a timestamp | Camera age, motor causal age and independent clock drift are distinct | The exact failing age field, retained manifest, accepted sample sequence and ACK provenance. |

## Important investigation conclusions and limits

**False hand clearance.** The R13 investigation reproduced a hand-outline boundary
defect and an offline fix. A paused single-stone/hand check later returned to clear
without leaving the stone classified as a hand. Live move acceptance, clocks and
beam shutoff still require their own physical test. Do not relabel the partial
check as complete gameplay validation.

**Stream-cache identity.** A deterministic broker race could pair a new stream's
metadata with cached pixels keyed only by frame ID. The epoch-plus-frame-ID fix
was installed in 0.252. It is a separate established defect, not the proven cause
of a later same-epoch thermal-run camera interruption.

**Thermal run and clocks.** One earlier host converted MCU elapsed time to Mac
time as if their clock rates were identical; drift produced an invalid negative
age. Causal ACK provenance replaced that subtraction. The later v43 run held for
about 15 minutes with a maximum reported internal temperature of 17°C before a
generic camera-age gate stopped it. The rejected manifest/which age was not
retained. A subsequent ten-minute passive audit found no failing checks. This
does not establish a periodic timeout, a camera freeze, a two-hour thermal pass
or a proven permanent fix.

**Untouched motor speed reports.** The released startup sample and the longer held
run were different conditions. Small raw velocity values and nearly fixed encoder
counts do not by themselves prove either visible motion or sensor noise. A future
attended optical comparison can bound movement at the camera's resolution; it
cannot justify overriding the controller guard in advance.

**Private dark-test override.** The explicit camera-independent option belongs
only to the private stationary firmware that cannot illuminate or travel. It
retains the app OFF lease and motor protections. It is not permission to skip
camera/hand/calibration checks in gameplay.

**Old handoffs.** An incoming laser note about a live Q16 marker or a pending
service restart can refer to the previous setup/day. Compare timestamps with the
latest outgoing checkpoint and actual process/device state before acting.

## Preserve a useful incident record

Record the user-visible symptom and exact trigger, selected play mode, saved game
identity/turn, installed app/source hash, firmware/binary identity, request
producer/revision/session, camera context/epoch/frame, relevant timestamps and
final hardware state. Link a bounded recording or transcript and the regression
that reproduces the failure. Separate observation, hypothesis, demonstrated cause,
fix, offline result and physical follow-up.

The November 22 integration session artifacts are under
`/Users/dave/Documents/SGF PLayer/work/ai-laser-integration/fresh-board-20261122-133741`.
Use the checklist's evidence index to choose the relevant subdirectory; do not
treat the latest filename or all archived candidate versions as the current
production implementation.
