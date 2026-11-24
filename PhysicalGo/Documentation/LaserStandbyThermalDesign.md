# Monitored dark motor standby and thermal validation

Historical design, subsequently implemented in v44 and the native/host contract.
Installed versions and short/partial physical results are in
[the checklist](IntegrationChecklist.md). Cooling/endurance gaps remain; this
design review itself is not a physical pass or authorization to start a test.

Design prepared November 22, 2026, Pacific time. **Proposal only:** no firmware,
bridge or application changes in this review; no port, camera, sound or hardware
operation performed. Root chat retains exclusive hardware ownership.

## Current decision — November 22 follow-up

Dave prefers temperature-protected holding during actual gameplay with logged
motor temperatures and cooling fallback. A formal two-hour stationary endurance
pass is **not a prerequisite**. The completed private dark test reached about
15 minutes, maximum 17°C, before a camera timestamp interlock stopped it; this
is useful initial data, not a long-duration or gameplay validation.

Gameplay holding and its temperature supervision still need implementation across
firmware, bridge and application. The private v43 thermal image cannot illuminate
or command travel and must not be used for games. Retain offline fault/cooling
verification and a short physical hold/stop check before supervised play. Record
both temperatures, maxima, trend and holding/cooling state during actual sessions.
The 45°C cooling / below-40°C measured dwell / 50°C hard-trip policy below remains
accepted. Longer thermal tests are optional diagnostics, not a gate to every game.

## Recommendation

Keep both motors holding during an explicitly active, healthy, cool game, with the beam
off whenever no indication is authorized. At 45°C switch to cooling operation that
releases holding between indications; below 40°C with stable measured evidence,
automatically restore holding. Preserve the existing `OFF` command as
full beam/motor-power shutdown. Add an explicit, capability-gated standby contract
across the application, bridge and firmware; do not map existing OFF requests to
holding. Implement firmware-owned temperature protection before enabling extended
holding. Resolve the observed motor faults before testing it physically.

This can remove the repeated ARM/HOLD cost from eligible transitions. Historical
November 21 logs place that cost near 1.80 seconds; this is potential savings, not
a measured new latency. Fast travel, measured-position recentering, fresh camera
checks and optical correction remain necessary.

## What current code actually does

| Layer | Existing behavior | Consequence |
|---|---|---|
| `AimControl.ino:disarm()` | Beam LOW, then motor-power pin LOW; resets hold state | OFF has a stronger meaning than darkness |
| `DARK` | Ends an active view and retains a dual hold in ARMED | Useful primitive, but not a complete gameplay standby contract |
| `guard()` | Dark dual sessions expire after 120,000 ms; heartbeat cutoff is 400 ms | Existing dark hold cannot provide a two-hour session merely by sending HB |
| `monitor()` | Reads torque, error, voltage, position and velocity, with 30 ms bounded register reads | Temperature is not sampled and no 45/50°C policy exists |
| `enableAtPresent()` | Current-based position mode is validated; goal current 250 mA, configured limit 350 mA; bus watchdog value 10 | These are current settings, not measured holding demand |
| `LeaseGate.observe/_revoke` | Every new revision revokes the worker and sends OFF | Repeated point/hand/turn revisions currently power-cycle the motors |
| `LeaseGate.activate` | New point needs quiescent workers and a confirmed OFF barrier | A standby barrier must be a separate explicit admission path |
| `PhysicalLaserGuidance.acceptsObservation` | Requires matching fresh state `off`, `offSinceUnix`, plus post-dark camera watermark/flush | Holding darkness needs its own receipt; falsely publishing `off` would break the contract |
| `HardwareBackend.point` | Always FASTARM/HOLD before coarse motion | A verified warm session needs a distinct entry path |

Code reviewed under `/Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware`
and `/Users/dave/SGFPlayerClean/PhysicalGo/Sources`. Existing movement, current,
freshness, generation, camera-identity and hand guards must stay effective.

## Proposed application/bridge contract

Use a new capability `darkMotorStandbyV1` and a separately versioned request/status
schema for standby. Old components continue normal OFF/point behavior. Unsupported
new actions must fail closed; upgrades must start with the ordinary full-OFF
handshake. Do not authorize standby from a stale capability advertisement.

Requests add `action: standby`, with an explicit `playSession` containing source,
session UUID and board size, plus the existing producer/revision, camera context,
epoch and short lease. It has **no illumination target**. Normal active human turns,
AI thinking, capture cleanup and a hand obscuring an already-held board may request
standby. First arming from OFF requires a fresh clear/aligned frame and validated
setup. A hand-obstructed standby request must never initiate torque or motion.

Pause, end game, bridge disable, manual reposition, disconnected online session,
changed camera/setup/session, expired/malformed lease, stale camera stream or any
controller/thermal fault request or force full OFF. Hand entry extinguishes the
beam immediately; an already-stationary hold may remain engaged. Holding through a
hand observation does not grant permission to move or relight. Fresh clear evidence
and normal placement-target checks remain mandatory before the next point.

Status adds explicit `state: holding`, `motorsHeld: true`, `laserOn: false`,
`beamOffSinceUnix`, `darkEvidenceAfter`, and current thermal samples. It must never
call this state `off`, and `offSinceUnix` remains absent unless full OFF was proven.
Unknown beam or motor state remains unknown, not inferred from a request.
Cooling states explicitly report `motorsHeld: false`, `motorBusPowered`, sample age
and cooling policy. Cooling is not a fault and is not permission to relight.

Camera evidence may accept either a genuine full-OFF receipt or a matching fresh
holding/cooling-dark receipt. Both retain the existing timestamp-source requirements,
post-receipt frame watermark and 0.3-second camera-presentation flush. A darkness
receipt proves darkness only; it cannot confirm a stone, capture removal, move,
clock transition or target accuracy. Disable/shutdown still waits for full OFF.

## Ownership and handoff between operations

Keep one serial owner and one active command generation. Add a **separate graceful
transition** operation to the gate; do not weaken `_revoke`, `cancel` or `finished`.

1. Under the gate lock, accept a newer valid standby revision for the same active
   play session/setup and invalidate the old optical worker before any new command.
2. Send priority `STANDBY`. Firmware makes the beam LOW first. If already stable
   and dual-held under the warm-hold policy, it retains that hold. Under cooling
   policy it releases torque into the selected cooling state. If a move is underway
   or the state cannot be safely retained, it performs full OFF instead; no arbitrary position/goal
   rewrite during movement is introduced to rescue the optimization.
3. Wait for the old command worker to quiesce. Fence stale serial replies exactly
   as the current OFF barrier does. Issue a fresh status query and require a fresh
   state-specific `HOLDING_DARK` or cooling acknowledgment with matching session/
   generation. Powered states require healthy fresh temperature samples; an
   acknowledged cooling_sleep state instead explicitly reports bus power off and
   temperature unavailable. A dropped or ambiguous reply falls back to full OFF.
4. Publish the state-specific dark receipt only after both quiescence and fresh hardware
   confirmation. Retain the independent lease and thermal supervisor throughout.
5. A later point revision can use the warm path from a holding receipt only if producer, game,
   setup/camera/epoch and live hold generation still match. `RESUME` revalidates
   pose/velocity/temperatures and enters the normal dark-motion path without
   FASTARM/HOLD. It must neither move nor illuminate by itself. A cooling receipt
   never authorizes this reuse: each indication performs fresh cold pose/configuration
   and torque-enable/settling checks before motion or light.
6. Start coarse travel and the existing recenter/profile transition. Obtain fresh
   dark images, satisfy all normal checks, then dispatch light and sound together.

If hand entry coincides with an active fine/coarse move, full OFF is an acceptable
fallback. “Hold throughout play” is an optimization of healthy stable intervals,
not a requirement to preserve motor power through every cancellation or fault.

Late command/result rejection and immutable revision rules must apply equally to
point and standby. A fault cannot be cleared by a later standby/heartbeat; recovery
requires the existing explicit full-OFF/new-revision procedure. A point worker
unexpectedly returning still forces full OFF. Only the explicit successful holding/cooling
handoff may finish without full power removal.

## Cooling policy and hysteresis

Dave authorizes cooling without ending gameplay: stop holding between indications,
accept slower per-move setup, then restore persistent holding after cooling. Both
powered torque-off monitoring and motor-bus power-off with measured wake checks
are permitted. Neither option may redefine an explicit full-OFF request.

### Hysteresis and normal operation

Use three policy states: `warm_hold`, `cooling`, `thermal_fault`.

- Either axis **>=45°C** enters `cooling`. The beam is not switched on by this
  transition. If already dark and idle, turn both torques off. If indicating a
  current move, mark cooling pending and release at its next normal dark boundary;
  the 50°C hard stop remains effective throughout. A later implementation may
  choose immediate dark release at 45°C if physical heating data warrant it, but
  must avoid repeatedly auto-restarting the same pending indication.
- During cooling, each newly authorized point performs cold pose/configuration and
  hold/settling checks. It may use torque for that indication, then releases it.
  Do not reuse a held-pose receipt after torque was removed. Sample temperature
  before enabling torque and throughout each indication. If actual repeated moves
  prevent cooling, remain in this mode; no timer may force return to holding.
- Reenter `warm_hold` only when **both motors are below 40°C** on fresh measurements,
  with at least 30 seconds of qualifying measured evidence and no intervening sample
  >=40°C. Any new warm reading resets the evidence. Require a live same-game lease,
  no fault latch, a fresh clear/aligned camera frame and safe measured joint poses.
  The reenable operation primes goals at measured position and verifies settling;
  it does not move toward an old target or illuminate. A hand keeps reengagement
  pending, with motors released, until clear evidence returns.
- **>=50°C**, stale/failed telemetry while it is required, hardware errors, motion
  faults, malformed lease or disconnect always enter full-OFF fault handling.
  Automatic cooling recovery never clears these latches. A new explicit recovery
  operation is required, irrespective of later low temperatures.

The 30-second recovery evidence interval is an initial design choice for offline
tests and physical tuning. It is not an established thermal time constant. Initial
entry into persistent holding requires fresh readings below 40°C on both axes.
Initial readings of 40–44°C use per-indication operation until holding admission
passes. Once cooling has been entered, the measured dwell is also mandatory.

### Cooling option A: motor bus powered, torque disabled

This is the simplest implementation to validate first. Add a firmware cooling state
with laser LOW, POWER HIGH and both Torque Enable registers confirmed 0. Continue
temperature/error/voltage checks and heartbeat. Do not apply the normal held-pose
drift test to a released joint; instead invalidate the hold and validate the actual
pose before any later torque enable. No goal, speed or light command is accepted
without explicit fresh point/reengagement admission.

Continuous readings support a genuine below 40°C dwell. Electronics retain some
power draw, so measure whether this cooling rate is sufficient. The 17mA documented
standby figure is not a measured guarantee for our configured units or whole rig.
Loss of a required reading while the bus is powered still causes full OFF/fault.

### Cooling option B: bus off with periodic measured wake checks

This is also permitted; do not reinterpret the explicit full-OFF command to achieve
it. Add distinct leased `cooling_sleep` and `cooling_probe` states. `cooling_sleep`
has laser LOW and motor bus POWER LOW but retains only the explicit active-game
cooling policy. A true `OFF`, pause, disconnect or fault cancels scheduled probes.

At a scheduled probe, assert beam LOW, power only the motor bus, and verify both
motors' startup configuration and Torque Enable==0 before reading temperatures.
No automatic goal update or torque enable is part of a probe. Bound power-up/read
time using measured device startup timing; failed boot, wrong torque state or
failed read causes full OFF/fault. The intentionally power-off interval is not
represented as fresh telemetry: publish `temperatureUnavailable: bus_off` and the
last-reading age. Old readings never authorize torque or illumination.

If still warm, shut motor-bus power off and schedule another check. Once both
motors read below 40°C, keep the motor bus powered with torque disabled and collect
fresh readings throughout the 30-second recovery dwell. Any reading >=40°C resets
the dwell; required-read failure causes full OFF/fault. Two cool readings separated
by a power-off interval do not substitute for this measured dwell. After it passes,
apply the ordinary fresh-camera/pose/session gates before reengaging holding.

A fitted cooling curve may choose economical probe intervals. It cannot authorize
holding by elapsed time alone. Build the curve from actual loaded heating/cooling
records, record ambient/setup/load, and update it when observations disagree. Start
with bounded conservative probing, e.g.15 seconds, then lengthen intervals while
clearly warm. Do not use the model as a safety sensor or claim validity across
changed ambient temperature, cable load or mounting.


## Firmware changes and thermal enforcement

Add explicit holding and cooling states rather than increasing the general
ARM/SESSION timeout. `STANDBY` cannot arm from OFF or grant light: it retains a valid
warm hold or releases into the selected cooling state. `RESUME` is available only
from verified warm holding and returns to the bounded ARMED workflow. Holding and
cooling policy states may outlive 120 seconds under a live lease. The 400 ms heartbeat
and DTR guards remain active in every such state. Motor-bus watchdog and monitors
operate whenever the motor bus is powered; cooling_sleep explicitly has bus power
off and cannot have fresh motor telemetry. Existing legacy timeouts
and finite illumination limits stay unchanged. Firmware version/capability must
change, and the bridge's supported-version admission must be updated deliberately.

Before torque enable, read both motors' Temperature Limit(31), Shutdown(63), and
Present Temperature(146). Require overheating protection enabled and the factory
limit no higher than 70°C; retain any stricter configured limit. Do not rewrite
EEPROM, raise a limit or clear a thermal shutdown automatically.

Thermal enforcement (cooling transitions are specified above):

- Enter cooling mode and warn at reported internal temperature **>=45°C** on either
  motor. Release torque immediately if already dark and idle; disable persistent
  holding/reuse until the below 40°C measured recovery dwell and normal admission
  gates are met. Current authorized indication may finish before torque release,
  subject to the 50°C hard trip; no further between-indication hold is allowed.
- Full OFF at **>=50°C** on either motor. Beam goes LOW before removing motor power.
- While the motor bus is powered after its bounded torque-off startup phase,
  refresh both axes at least every **250 ms**; a missing,
  malformed or failed read immediately faults. A per-axis sample older than
  **750 ms** faults independently, including if the normal sampling path stops.
  Intentional cooling_sleep reports no live reading and is exempt from this
  powered-sampling deadline; it cannot enable torque or light. A wake probe has
  a separate bounded startup/read deadline and requires fresh data before leaving
  torque-off state.
- Require fresh samples before enabling torque, extending hold, resuming motion or
  requesting illumination. Check the trip immediately after each successful read,
  not after both axes or a host telemetry publication.
- Use bounded register reads and check heartbeat/disconnect around each read as
  now. Add the thermal-age guard to the firmware guard path; avoid recursive guard
  calls while establishing the initial torque-off baseline.
- Use a local fault reason identifying axis/reading; preserve last good sample and
  trip evidence after disarm. Host JSON publication is not the safety mechanism.
  Host telemetry staleness in a state requiring live telemetry also forces OFF;
  firmware must protect against a
  blocked host. Healthy heartbeat traffic must not conceal lost thermal sampling.

The 250/750 ms timing values are proposed budgets that require worst-case fake-bus
tests and hardware measurement before admission. At the present bus speed, extra
reads can affect responsiveness and watchdog timing. Do not relax other timeouts
merely to accommodate inefficient telemetry.

Log per-axis device temperature, current, voltage, position, velocity, torque state,
sample sequence, firmware sample age, host receipt time and warning/trip state.
Sample protection at the firmware cadence; save trend records around 1 Hz plus
every warning/trip/state transition. Preserve exact read/failure events near trips.

**50°C is a trip trigger, not a guaranteed absolute ceiling.** Internal sensor
quantization, sampling delay and thermal inertia can produce overshoot after the
power cut. It also does not measure the laser module, supply, connectors or every
case surface. Leave margin and assess those components separately; do not promise
that every component remains below 50°C or is safe to touch.

## Known hardware facts and unknowns

The motor provides internal-temperature feedback in 1°C units; its documented
default temperature limit is 70°C. Overheating torque shutdown depends on the
Shutdown register's enabled bits. XL330 current feedback measures input current;
the motor bus watchdog uses 20 ms units. These are documented capabilities, not
readbacks of this particular assembly. [ROBOTIS control table](https://emanual.robotis.com/docs/en/dxl/x/xl 330-m 288/)

ROBOTIS gives an estimated 0.10 N·m continuous torque, derived from 20% of stall
torque, and a recommended 5 V supply. That estimate is not a two-hour certification
of our load, mounting, airflow or tuning. [ROBOTIS product specification](https://robotis.us/products/dynamixel-xl 330-m 288-t)

At an illustrative 250 mA per motor and 5 V, the pair draws 2.5 W and consumes 5 Wh
in two hours, plus controller/other loads. This is arithmetic using the configured
goal-current setting, not a measured average or strict total-input-power ceiling.
Measure actual current and supply voltage through the test. Mechanical balance,
cable forces, holding gains and corrective motion affect demand. Holding buzz and
chatter must be assessed from Dave's seat; no sound-level claim is established.

## Offline acceptance tests before any live standby

Extend existing native fake-bus `Firmware/AimControl tests` with temperature and
shutdown-register fixtures. Do not test a trip by deliberately heating real motors.

1. Boundaries and hysteresis on both axes: 44°C may maintain an existing valid warm hold;
   45°C enters cooling; 49°C never permits continuous between-indication hold;
   50°C forces full OFF in every powered state. Once cooling, 44°C remains cooling.
   Both axes below 40°C throughout the measured 30-second dwell are required to
   restore holding; a warm reading or per-move reheating resets the dwell.
2. At or above 50°C before torque enable means no torque enable and no laser HIGH.
   In 45–49°C cooling, a newly authorized indication may use torque only after all
   fresh per-move checks, and releases at its dark boundary. A standby request in
   that range must not enable torque or silently retain a hold.
3. Delayed/short/failed reads, missing axis, stale sample timestamps, stopped thermal
   sampling with continuing HB and millisecond-counter wraparound all stop correctly
   in powered states. Intentional cooling_sleep explicitly reports unavailable
   readings; old values cannot clear cooling or authorize torque/illumination.
4. Beam LOW precedes motor-power LOW. Hard trip stays latched across HB, STATUS,
   stale light commands, low subsequent temperatures and renewed app leases.
   Full-OFF query retains fault evidence; automatic cooling recovery cannot clear it.
5. Two hours of virtual-time holding with cool refreshed telemetry and heartbeats
   may remain held. Readings at or above 45°C switch to cooling. Silence/disconnect stops both
   holding and cooling within existing bounds. Ordinary ARMED still expires at
   its original deadline. The dark-only endurance fixture never invokes laser HIGH.
6. STANDBY from stable illumination extinguishes light, then either retains a valid
   warm hold or releases into cooling. During a move it falls back to full OFF.
   Cold STANDBY never arms. RESUME neither moves nor lights and cannot reuse a
   cooling/released-pose receipt.
7. Fake gate/runtime tests race late replies, superseded workers, hand entry,
   point/holding/cooling transitions, lease expiry, new producer/session/epoch,
   explicit OFF and thermal fault. No stale worker can move, relight, power the
   motor bus for a probe or publish a current receipt after revocation.
8. Option B: fake power-up with unexpected torque 1 trips before any motion command;
   probe paths never emit LASER HIGH, torque enable or goal writes. Failed boot/read
   causes full OFF/fault. No time-based cooling prediction clears recovery. Two cool
   probes separated by power-off do not replace the continuous measured dwell.
9. Full OFF, pause, end, disable, manual release and disconnect cancel every delayed
   probe/reengagement. Changed game/setup cannot inherit a cooling schedule or dwell.
10. Native app tests require correct state-specific darkness receipt/watermark,
    reject stale/incompatible status, preserve hand-clearance gates and clocks, and
    request genuine full OFF for stop conditions. Legacy backend still works.

## Staged physical acceptance, owned by root

1. First resolve current motion faults and validate the new telemetry/cutoff code
   offline. Start with a fresh full-OFF acknowledgment and baseline temperatures.
2. In an explicit beam-disabled stationary session, exercise full OFF, lease loss,
   disconnect and test cancellation at cool temperatures. Verify power-off behavior;
   do not drive a real motor to the thermal threshold to prove software logic.
3. Hold 5–10 minutes at a previously validated pose. Record ambient temperature,
   current, voltage, internal temperatures and seated audible observations. Stop for
   oscillation, abnormal noise, rising load or any guard fault; no automatic retry.
4. Extend a stable result to 30 minutes, including relevant tilt poses and cable
   load after separate movement validation. Determine whether temperature is
   approaching a plateau below 45°C, or verify that the cooling fallback releases
   between indications and actually lowers temperature without hard trips.
5. Only then run the two-hour holding/cooling endurance session with the same
   firmware-owned cutoff, live lease,
   explicit duration deadline and independent stop. Include realistic pauses and
   resumed pointing in a later separate gameplay endurance test.
6. Compare torque-off powered and bus-off/probed cooling where implemented: actual
   cooling rate, current/energy, seated noise and next-indication latency. Fit cooling
   estimates only to schedule checks; never let a predicted temperature clear holding.
   Repeated indications may prevent cooling; the slower mode must remain active
   until measured recovery, without timer-forced resumption.
7. Record maximum temperatures, current distribution, energy estimate, endpoint
   voltage, thermal slope, faults, noise and final confirmed OFF. Passing applies
   to the measured load/ambient/setup; changes in those conditions need reassessment.

Standby is not ready merely because the design is written. Implementation, offline
fault tests, fresh calibration and root-owned physical validation remain pending.
