# AI / laser integration handoff — 2026-11-21

## Current contract status — November 24

The legacy schema-1 contract below remains supported. Monitored gameplay holding
is implemented in v44 and the installed 0.260/host `1ae717e` combination.
The canonical branches below carry current docs but older runtime source; exact
installed-source worktrees are identified in the checklist.
The exact schema-2 agreement is maintained in the laser repository's
[`Firmware/Gameplay standby protocol.md`](https://github.com/davemarvit/DYNAMIXEL-Go-Pointer/blob/codex/monitored-gameplay-holding/Firmware/Gameplay%20standby%20protocol.md).
It adds explicit same-game standby permission, retain-only hand handling,
temperature telemetry and dark receipts distinct from full OFF. The current
extension also includes bounded scoped `transitioning` without dark/light evidence.
Short dark/earlier gameplay tests do not validate the newer recovery changes; consult
[IntegrationChecklist.md](IntegrationChecklist.md) for current evidence.

Implemented in the authoritative `/Users/dave/SGFPlayerClean` source. The game
publishes a move and its receipt time; it does not issue serial commands. The
hardware project remains authoritative for motors, optical calibration and cues:
`/Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer`.

## Behaviour and clock boundary

1. On receiving a valid KataGo answer, record its receipt timestamp before saving
   the move or beginning pointing. Switch elapsed practice time to the human at
   this instant. Receipt is not laser arrival or stone-placement time. The timing
   code uses monotonic uptime; the persisted event uses Unix seconds for correlation.
   For a capture of two or more stones in AI practice, immediately pause that next-player clock
   until the complete physical position is verified: the played stone is present
   and every prisoner is removed. This excludes aiming, placement and cleanup for
   that capturing move. A human capture of two or more likewise pauses the AI clock during cleanup. Single-stone captures keep the clock running.
   Partial removals, uncertain readings, and hand entry cannot release the hold.
   Save/restart retains the hold without changing the original receipt timestamp.
2. Publish the pending move in canonical camera-grid coordinates: zero-based row
   from top, column from left, BEFORE display rotation. Include board size, color,
   game UUID, move number and original decisionReceivedAtUnix.
3. Request pointing only with a fresh, clear, aligned camera view and a connected
   driver. For a committed AI move, the engine supplies the exact coordinate;
   uncertain occupancy must not prevent its placement cue. Require a validated
   frame captured after target selection and, after illumination, confirmed-dark
   evidence. Positive stone evidence at the target still latches OFF. This cue
   never accepts physical placement, learns an empty label, or advances the game.
   Once pointing, keep renewing the same target without classifying through the spot.
4. Any detected hand over the board latches OFF for that target. The current
   detector does not establish hand intent, so this deliberately also stops for
   other hand entry. Seeing either color stone at the target also latches OFF. Clearing the hand
   alone does not relight: require three distinct fresh clear dark observations
   spanning at least 450 ms. Occupancy uncertainty can preserve a pending move cue,
   but not a centering hint. A positively observed stone remains latched OFF.
   Classified camera/lease interruptions use the same confirmed-OFF recovery;
   an expired OFF request first receives a new OFF revision. Hard faults stay latched.
5. Illuminated frames do not update stored stone/lighting/reference evidence.
   Hand detection and the live preview remain active. OFF does not accept a move. Confirm the correct stone and capture removals using
   the existing stable-observation rules. Reject illuminated/buffered frames until
   a fresh matching OFF acknowledgement plus 300 ms and, for hardware, the
   evidenceAfter watermark described below. The screen marker remains.
6. Pause/end/mode change clears the target. Camera interruption, unknown hand state,
   stale evidence, or unverified alignment inhibits pointing. No target for passes.
   A restored pending move keeps its original receipt time, and the app starts paused.
   Old pre-integration saved moves have no receipt stamp and remain screen-only.

This release measures elapsed practice time, with no time-loss adjudication. Pause
freezes it; restart restores accumulated time without charging app downtime. Laser
acknowledgements NEVER edit clock anchors. For online play, preserve authoritative
server clocks and receipt of the opponent move; do not reset clocks on laser events.
Online transport wiring is a next step, not enabled by this implementation.
The capture-cleanup exclusion is an AI-practice policy approved by Dave; it does
not authorize pausing or rewriting a real online server's clocks.

## Local bridge v1

Directory: `~/Library/Application Support/Physical Go/LaserBridge/`.
The app atomically replaces `request.json` about every 200 ms while enabled.
The driver atomically replaces `status.json`. One driver must hold `driver.lock`
(exclusive nonblocking flock), including the simulator. The hardware driver must additionally retain the existing
Controller serial-port lock; never bypass it. Driver status mode MUST
be `simulation` unless it actually owns the commissioned hardware.

Request fields: schemaVersion=1, producer (UUID per app process), sequence (integer
revision), sentAtUnix, expiresAtUnix (600 ms lease), action (`point` or `off`), reason,
target (nullable), cameraContext (nullable), streamEpoch (UUID). Target fields: source (`ai`, later
`online`), session UUID, moveNumber, size, row, col, black, decisionReceivedAtUnix.
The same target identity is source/session/moveNumber. A heartbeat changes only
lease times; identical revisions are idempotent. Never queue expired targets.

The current cameraContext combines the AVFoundation camera ID and sorted-key
JSON reference BoardCalibration encoded as base64 (current calibration if no
reference exists). Small tracked corrections do not change the reference identity.
It identifies the camera and normalized
corner-intersection mapping. It is NOT optical calibration or permission to reuse
an old laser map. Changing context suppresses the pending target until explicitly
requested again. The driver must independently match its commissioned setup.

Status fields: schemaVersion=1, producer and sequence echoing the accepted request,
updatedAtUnix, mode (`simulation` or `hardware`), state (`off`, `approaching`, `adequate`, `refining`,
`spot_not_found`, `fault`), laserOn (boolean), offSinceUnix (Unix seconds, only after the serialized controller LOW
confirmation barrier), detail (short user-visible description). Status older than 750 ms,
wrong session/revision, future time, or non-OFF state cannot admit stone evidence.
Do not report OFF merely because an OFF command was enqueued. If a fault is dark,
report OFF with an explanatory detail after confirming it.

On a new producer, stop and require an initial OFF handshake. Validate target,
sequence, immutable contents per revision, clock range and lease. Host loss must
stop both illumination AND in-progress/refinement work within the lease, independent
of the serial worker continuing its own HB. Keep the firmware's tighter heartbeat,
USB, movement/current and OFF checks. Every long operation must be cancellable by
OFF/new target/lease expiry. The normal audible cues remain driver-owned; no new
firmware lighting or movement authorization is implied by reading this file.

## What the laser agents still need to provide

Latest coordinated state: AimControl v35. The laser agent now reports four outer
corners and four inset edge midpoints reached within 3px of its fitted grid in the
current setup (run10–13). This extends the earlier center-region demonstration;
it does not approve arbitrary targets or a changed setup. The standalone point_at.py
uses an older local map and must not be auto-launched for arbitrary AI moves.
Broker-to-current-calibration binding, the persistent service and integrated
hand/placement validation remain pending. Deliberate targeting of existing stones
is deferred; AI targets are legal empty intersections.

- Extract a persistent, cancellable target service from the current fast optical
  runner. Bind the v1 contract above; retain bounded moves, two cues, optical
  confirmation, continuous hold, OFF handling and firmware watchdogs.
- Preflight the requested cameraContext and target against a validated mapping;
  reject uncommissioned board sizes or points outside its approved mapping.
  Do not silently extrapolate the local center model across the board.
- Connect the optical Observer to the app-owned broker described below. The game
  owns AVFoundation and hand monitoring. Replace the Observer's second capture;
  do not run both camera clients and assume alignment.
- Supply serialized controller LOW acknowledgements, hardware evidenceAfter
  watermarks and measured camera-buffer flushing. The app's 300 ms guard is a
  minimum, not validation of this camera's latency. Do not shift offSinceUnix to
  disguise buffering. Target detection must not mistake the dot for a stone.
- Test interrupted aiming, hand entry during coarse/refinement motion, wrong stone,
  stale results, duplicate requests, lost app/USB/camera and placement with captures.
- Report actual optical reach and cutoff latency separately from decision receipt.

No live motors, laser, serial port, camera settings, or current game were changed
by this integration task. A hardware driver is deliberately not auto-launched.

## Hardware-free verification

`python3 PhysicalGo/Tools/laser_bridge_simulator.py` runs a reference consumer using
no external packages. Enable Connect laser bridge in Play AI. Its status explicitly
says Simulation; this proves the request/acknowledgement flow, not physical aiming.
Use `--directory` for an isolated test directory. Stop with Ctrl-C.
Swift regression: `python3 PhysicalGo/build.py --ai-laser-test`.
Python regression: `python3 PhysicalGo/Tests/test_laser_bridge.py`.

## Coordination update after the laser agent's reply

Ownership is agreed: this work owns AI/game integration; the other agent owns
laser control, calibration, hardware testing and serial ownership. No AI-side
hardware process is running. Shared working folder: `/Users/dave/SGFPlayerClean`.
Please write proposed changes/questions beside this handoff, for example
`Firmware/AI play integration response.txt`, without overwriting this contract.

Use `approaching`, `adequate`, `refining`, `spot_not_found` for the requested feedback
states. The app displays the driver's detail string and only accepts `off` as
the required controller-OFF state; hardware frame watermarks still apply. A new point revision replaces/cancels the old aim; OFF cancels
all work. Repeated heartbeats of the same revision must not restart work. Position
adequacy feedback is useful to the player but never changes the clock boundary.
An adequately positioned spot can remain on until hand entry/placement/cancellation;
all continued illumination still requires the renewable lease and driver interlocks.

## Shared camera broker and hardware evidence extension

The laser agent's reply is accepted. The app now owns a bounded, asynchronous PNG
broker at `LaserBridge/frames/latest.json`. It publishes analyzed camera frames at
the app's existing delivered cadence; it does not change capture rate. Encoding
and writes run on a utility queue. There is only one pending image; slow publication
skips intermediate frames. At most four published PNG files are retained. A slow
reader retries the latest manifest if its named file has expired. Published image
names are immutable. No additional AVFoundation client is opened.

Manifest schemaVersion=1 fields:
- frame: streamEpoch, frameID, capturedAtUptime, arrivedAtUptime, capturedAtUnix,
  timestampSource (`cameraPresentation` or `callback`), presentationSeconds (optional).
- publishedAtUnix, imageFile (relative basename), encoding (`PNG`), width, height.
- cameraID, cameraContext, referenceCalibration, currentCalibration (nullable),
  handObstructed (nullable; unknown is not clear), alignmentValid.

Pixels are the original unrotated camera CGImage, with no board rectification,
labels, stone overlays or display rotation. Calibration corners are normalized
TL/TR/BR/BL intersection coordinates; the encoded homography is also available.
The hand/alignment flags and pixels always belong to the same frame. A missing
hand field means unknown. `cameraPresentation` is the camera PTS converted through
the host clock; it is not a separately measured optical exposure timestamp. A
`callback` timestamp must never be described as exposure time. Publication time
includes processing/encoding delay and is not capture time.

Request v1 additionally carries streamEpoch (stable UUID until reconnect/reset).
The immutable revision fingerprint is now action/target/cameraContext/streamEpoch.
Per-frame IDs do NOT change the target revision. Reconnect increments the request
revision, latches pending guidance OFF and changes epoch. Readers must reject a
manifest from a different request epoch; an old manifest may briefly remain while
queued IO finishes. Camera dimension changes also reset the stream.

DriverStatus optional fields: setupId, reasonCode, requiresNewRevision,
evidenceAfter. requiresNewRevision=true for the processed operation latches output
OFF until explicit Show point again or a new move. Echo the processed request
revision on a rejected operation, even when no pointing was admitted. On lease loss,
invalid revisions and faults the driver must revoke the token and require a NEW
point revision; a late heartbeat cannot resurrect canceled work. The simulator
now tests and implements this restriction too.

For HARDWARE mode, evidenceAfter is REQUIRED before placement confirmation:
`{streamEpoch, frameID, timestampSource, callbackFlushSeconds?}`. The app requires:
1. Matching producer/revision and fresh state=off, laserOn=false.
2. A current frame in the same request/watermark epoch, with frameID STRICTLY GREATER
   than the watermark, and timestampSource matching the watermark.
3. Capture Unix time at least offSinceUnix+0.3 for cameraPresentation.
4. For callback fallback, a separately measured callbackFlushSeconds >=0.3 is
   mandatory; capture/callback time must be beyond offSinceUnix+that bound. Missing
   or invalid bounds block hardware-backed placement. Do not invent a buffer bound.

The driver must publish offSinceUnix at its actual serialized controller LOW
confirmation barrier. This is confirmation of the controller output state, not a
measurement by an optical power sensor; v35 has no such sensor. Never shift this
boundary forward to disguise buffering. The watermark/flush policy handles that
separately. The app owns final move acceptance. Simulation has no optical output
and uses the original time-only dark-frame guard; it cannot certify hardware.

The driver must compare the actual app camera ID, dimensions, geometry and fresh
pixels to its independently commissioned setup. No cameraContext or setupId by
itself approves a target. The hardware agent retains capability/region checks,
controller locks, cues, firmware duration limits and all live tests.


### Laser-agent acceptance and latency evidence

The laser agent accepted the broker fields, streamEpoch fingerprint, evidenceAfter
and requiresNewRevision contract in the shared response. It owns the offline
consumer, cancellation/OFF-barrier tests and later live validation. Its standalone
camera and controller are now closed/OFF; this task did not control either.

Three standalone ffmpeg 15fps cycles showed lit frames arriving 0.415–0.561 seconds
after DARK acknowledgement. That establishes why 300ms alone is insufficient for
that pipeline. These samples are NOT a conservative bound for the app's different
AVFoundation broker. No production callbackFlushSeconds is configured automatically;
hardware callback-based stone acceptance remains blocked until its pipeline is
measured. Camera-presentation timestamps retain their actual capture-age information.


## Live integration checkpoint — November 21, 2026, lights on

The hardware agent implemented the persistent service (`Firmware/laser_bridge.py`)
and app-broker optical backend in the DYNAMIXEL workspace. This supersedes earlier
notes above about those components still being absent. Current pilot admission
covers selected empty-board targets; arbitrary full-game coverage remains pending.
AimControl v36 adds explicit cued TRACK with continued refinement until OFF,
cancellation, heartbeat/USB loss or fault. v35 retains its bounded SWEEP fallback.

A real 19x19 HumanSL 5k AI-first game generated canonical Q16 (the rotated app view
labels it Q4). The exact decision-receipt timestamp was preserved in saved game
and laser request. Human elapsed time began at receipt, before aiming/placement.
Laser-enable acknowledgement occurred about 4.666 seconds after receipt; repeated
optical samples reached about 1–2 pixels of the fitted intersection. Continuous
marking exceeded the previous duration limit without accepting a false stone.
UI Pause produced a matching real OFF acknowledgement and frame watermark. The
saved pending move and elapsed balances survived a controlled app restart.
Hand entry, physical stone acceptance, captures and broader target coverage still
require live validation; these results do not establish a complete physical game.

The app captured a fresh empty-board reference at the user's request. Hardware
binding was updated to that exact context. The driver separately checks dense image
registration and app-grid identity: at most 20% of the minimum projected grid
spacing, capped at 8 pixels. This explicitly measured estimate-tolerance policy
is distinct from its 3-pixel optical refinement target.

App 0.211 reads a single driver-status snapshot before sampling wall time. This
prevents a concurrently published status from appearing falsely in the future,
which could flicker the connection label or latch a false driver interruption.
A deterministic publication-interleaving regression failed on 0.210 and passes
with the correction; strict stale/future-status checks remain in force.


## Requested follow-up: automatic re-show after an empty hand visit

Status: filed for later; not implemented in the current test. Requested by Dave
on November 21, 2026 during the live hand/placement trial.

When a hand approaches, extinguish the pointer. After the hand withdraws, if the
same AI move is still awaiting placement and fresh clear/aligned camera evidence
positively confirms that intersection remains empty, show the target again
automatically. A correctly placed stone keeps it off and follows normal stable
placement/capture confirmation. A wrong-color stone also keeps it off.

Evaluate a short hand-clear stabilization period to avoid flicker during a
placement gesture. Preserve confirmed-OFF/dark-frame evidence requirements, leases,
and driver interlocks. Hand withdrawal must not clear a fault, expired lease,
pause, setup change or uncommissioned target. Re-show must not change the move's
original decision timestamp or clock anchor. Add live empty-hand/no-placement,
actual placement and wrong-stone trials when implementing.

## Two-stone live test and registration repairs — November 21, 2026

The live empty-hand test extinguished the beam and left the pending move intact.
Explicit Show point again reacquired the point; placing the first black stone
was accepted only after confirmed OFF and dark camera evidence. A subsequent
human white move was accepted and triggered KataGo's second move (canonical D16,
displayed Q16). Its original decision-receipt timestamp remains unchanged.

That reply exposed two separate blockers. Hardware dense registration compared
stones against an empty board and failed its .95 correlation gate. The backend
now excludes localized foreground differences only when at least 85% of the
board and 70% of each quadrant remain, retains the .95 gate, and requires agreement with independent ORB inlier correspondences (median at most
1.5 px, 90th percentile at most 2.5 px). Eight occupied-board admission/rejection
regressions and 54 existing bridge checks pass. This conservative
coverage limit still needs validation on more populated boards.

The app's independent grid check also intermittently found fewer than three
matching segments on the faint top rail. It now samples additional positions
within each outer segment; a segment still counts once, and all existing
contrast, shape, distribution and movement requirements remain. The recorded
failure and eight later frames pass the revised check. This change does not
replace the saved empty pixels, alter grid calibration, or bypass hand checks.
Full-game and capture validation remain outstanding.

Live0.212 follow-up:29consecutive fresh broker frames were aligned/hand-clear,
confirming the faint-edge repair in the running app. Restart preserved the exact
saved game, receipt timestamp and paused balances. A separate resume deadlock
remained: whole-board unknown readings returned before target-empty admission.
The pending target now receives positive-empty admission after complete reading
shape/range/uniqueness validation, independently of whole-board confirmation.
Unknown/occupied target and malformed readings remain OFF; unrelated uncertainty
still blocks placement acceptance and turn advancement. No clock policy change.

## Completed three-stone checkpoint

After the tracking repair, the pointer held the second AI point for over80seconds
(24optical measurements, roughly1–2px error) and extinguished during placement.
The user confirmed seeing the point. Glare then blocked board confirmation.
The user dimmed lighting, temporarily cleared the board, and a fresh empty
reference was captured at2026-11-21T22:29:59.621089UTC. After restoring all three
stones, the live app read3stones/0uncertain and confirmed the pending move.
The app now says Your turn / White to play. Original decision receipt and saved
clock/game history survived the controlled pauses and restarts.

Hardware reference/setup was also refreshed under the new lighting, with323
fitted lattice inliers and six passing live-frame registration/grid checks.
The board-to-motor model is unchanged. The active driver uses the DYNAMIXEL
project's dim reference setup/model; the nine-point pilot remains active.
The old full-board candidate is stale after this reference/context change and
must be regenerated/revalidated by the hardware workstream before activation.
The next actual AI target must validate optical aiming under the new lighting.


## Occupied-board lighting baseline, 0.214

KnownEmptyLighting retains independent empty-patch evidence across ordinary
position changes, discards changed intersections and their immediate neighbors,
and requires three fresh matching frames over at least 0.4 seconds before reuse.
Changed/new empty patches still require eight independent frames over 1.4 seconds.
Weak empty readings can receive the same 0.85 confidence as previously uncertain
readings only when their pixels match an independently trained, unexpired patch.
Expected game labels never generate camera evidence. All occupied anchors must
still independently match at confidence 0.9; new stones pass through unchanged,
and changed pixels invalidate old wood. Hand, alignment, laser-dark evidence,
context, interruption and expiry gates remain. The real empty-reference image
is preserved; this is local appearance adaptation, not a fabricated empty photo.

Validation: 101 known-empty checks and 171 residual-glare checks pass, including
new/weak stones, missing stones, occupied-anchor uncertainty, move/removal changes,
hand/alignment invalidity, duplicate timestamps, gaps, expiry and feedback loops.
Some policy tests deliberately alter confidence on saved real photos and assign
synthetic timestamps; these do not claim new live temporal observations.


## Full-board admission under current lighting — November 21, 2026

The DIM setup 59ae22d15ca21148 now has an active 361-target binding.
Its refreshed audit passed 361 pose/Jacobian checks and 130,321 nominal routes,
with at most two bounded dark waypoints and maximum Jacobian condition 14.528.
Current-light hardware checks passed 13 distinct physical intersections in 15
successful target runs: all four corners, center, near-edge midpoints, interior
points, and A19–L1–A19 (two actual coarse waypoints in each direction).
Each accepted run required two consecutive optical errors at most 3 px;
worst final error was 2.818 px. This validates interpolation with per-target
optical correction, not 361 individual physical accuracy measurements.

These tests found and repaired two host issues: repeated one-count corrections
could stall against servo deadband, and residual coarse-goal error could kick
an axis when PREPARE changed position gain. Bounded same-direction command
compensation (at most four counts, still within original fine limits) and a
dark hold recentered on the measured pose resolved the tested failures.
Firmware v36, stationary/velocity guards, limits, camera and lease checks are
unchanged. 56 bridge tests and nine occupied-registration tests pass.

Evidence resides in the DYNAMIXEL project's Camera checks/App bridge 2026-11-21/
dim reference: domain-audit.json, full-board-anchors-hold/result.json,
long-route-current-code/result.json, validation-summary.json. Earlier stopped
runs remain available for diagnosis. Game history, decision timestamps and
paused balances were preserved throughout private commissioning. Full-game,
capture-removal and crowded-board qualification remain separate live tests;
automatic relighting after empty-hand withdrawal remains deferred.


Live continuation: White320 was accepted, then AI Black300 arrived at
1795301764.5492702. The clock switched on receipt before laser enable; optical
error refined to about1.5px and the user confirmed seeing the point. Placement
extinguished the beam, but a stale hand outline blocked confirmation despite
reliable empty hand poses. A four-second diagnostic recording preserves this
failure (Diagnostic 2026-11-21 14-59-25 12B774A8). The user confirmed hands clear;
Freeze/Resume camera reset only temporary tracking, and fresh camera evidence
accepted the fifth stone. This is a recovery workaround, not an automatic fix.
The next AI move318, outside the old nine-point allowlist, was indicated and its
placement accepted automatically. The game continued to move9. A simple perimeter
change-band probe remains offline: existing labeled recordings show both useful
rejections of old false alarms and remaining false positives. No hand-clearance
thresholds or production tracker code were changed in this experiment.

D7 White recognition repair (0.215 candidate): after move11, displayed D7
(raw297, canonical N4) was physically occupied but remained uncertain. A bounded
four-second recording at15:06 preserved the failure; hand obstruction was false.
The live-image classifier saw White1.0 and both reference rails were covered,
but pale reference glare made the stone retain apparent wood tint. The detector
now admits an independently fitted current-image rim, with >=10/12 radial
sectors, support in all quadrants, a consistent stone-sized radius, strong live
White color, covered reference rails, no surviving live cross/wood, and separate
ownership. Provisional White labels receive the same outline evidence as uncertain
labels before the final tint contradiction check. Game history is not a visual
label and persistent brightness change alone remains insufficient.

Validation: six real positive/negative frames, each tested at three brightness
levels and three half-pixel alignment offsets:19,549 assertions pass. Existing
727 shaded-white checks,27 geometry/alignment cases and64 glare-grid checks pass.
No hand-tracker, clock, laser protocol, calibration or hardware thresholds changed.
The exact11-move game and paused elapsed balances are backed up before restart.
Live D7 replay remains pending until installation and physical replacement.

2026-11-21 normal-lighting/noise investigation: Dave restored normal room
brightness and requested tolerating ordinary image variation rather than further
room-light adjustment. Native app remains0.215/build216; noise candidate remains
OFFLINE at scratch/lights-on/restart-glare/KnownEmptyLighting-candidate.swift.
It spatially averages local patches and learns bounded level/color/center noise
from independently empty observations only, retaining fixed anchors, eight-frame/
1.4second learning, interruptions/context/stone gates and expiry. Existing101
known-empty +171residual-glare checks pass, including new/weak stones and removal.
The candidate is not a completed fix for current startup verification.

Hardware image-quality trial (no serial/laser or geometry change): jtfrey/uvc-util
https://github.com/jtfrey/uvc-util was built in scratch from source and used only
on the webcam USB control interface. The native app is still the sole video
capture owner. Device FULL HD WEB CAM0bda:0567 atUSB location0x01100000.
Original controls saved in scratch/lights-on/restart-glare/camera-controls-before.txt:
auto-exposure-mode8, exposure-time-abs166, gain64, brightness0, automaticwhitebalance
true (reportedtemperature4600), gamma300, contrast34, backlight0, exposurepriority0,
powerline1. ACTIVE TRIAL: auto-exposure-mode1 (manual), exposure166, gain32.
Only those three values were written; all are read back successfully. Do not
silently revert or change exposure before the pending matching empty reference.
Revert with uvc-util -L0x01100000 -s gain=64 -s exposure-time-abs=166
-s auto-exposure-mode=8 (actual arguments separated with spaces).

Normal-lightauto frame atD7 had~87% of sampled pixels with a clipped RGB channel
and~53% with allRGB>=250/255. Manual166/gain32: no sampled channel clipped and
medianRGB about184 rather than253. Geometry aligned and hands clear throughout.
Fixed-coordinate3x3 RGB temporal sampling over real recordings: dimglarepoint277
standarddeviation~4–5levels; manualnormal~0.5–0.8; D7manual~1.2–1.5 versusdim~3.7–4.
Saturated auto-normal samples misleadingly have lowvariance. Exact numbers in
scratch/lights-on/restart-glare/noise-comparison.json; these are measured camera
outputs, not a calibrated sensor-gain/noise model.

Bounded8second native recordings:15:32:43 1273DB88 (normalauto),15:39:10 5B57795D
(manual166/gain32). Recording/mode/warnings off again; no redundant tails trimmed.
The old emptyreference is from DIM lighting. Currentmanual image still has weak
empty readings and White317 uncertainty versus that reference; no full-board
verification or live D7 acceptance claimed. Game11moves/clock balances unchanged;
laserOFF. Dave was asked to temporarily clear11stones for a matching genuineempty
reference; awaitingconfirmation. D7wasalreadyremoved. Restore DISPLAY coordinates:
Black Q4,Q16,E4,D4,C5,B5; White D16,D5,C6,C4,C3. D7staysEMPTY untilverifiedresume.

Occupied references (0.216/build217): explicitly confirmed current physical AI
position seeds a labeled reference; it is not installed as an empty photograph.
The UI is Play AI > Occupied reference > Capture occupied reference. Confirmation
requires the actual physical board to match the saved game. A fresh clear aligned
camera frame and confirmed dark laser evidence are required. Pixels are sampled
within each intersection, including its center; labels are black/white/empty.
Fresh three-frame/.4second matches can support uncertain/weak readings. Strong
contradictions and changed patches invalidate that point. A move invalidates its
point and immediate neighbors, including prior shadows. Camera/game identity and
subcell geometry are checked; gaps, hand/laser frames and duplicate timestamps
cannot complete revalidation. Original empty reference, calibration, game moves
and clock logic are unchanged.

Stable-board refresh is enabled by default, with a persisted user toggle. Every
10seconds, after at least8stable frames over2seconds, independently correct raw
readings (confidence>=.9,8observations/1.4seconds per patch) can replace their own
patches. Ambiguous patches retain their previously confirmed anchor. Output from
the occupied reference, the empty-lighting adapter and established-stone tracker
never serves as independent training labels. Periodic updates are partial,
bounded labeled feature data; no periodic camera-image recordings are created.
One atomic current.json lives in Application Support/Physical Go/Occupied References.
Loading an archive requires fresh revalidation, never immediate trust.

408 regression checks pass, including8 fully verified frames from the real
11-stone normal-light/manual-exposure recording, actual D7 White, real White
addition/removal in glare, strong contradictions, changed neighborhoods, camera/
grid change, interruption, archive reload, duplicate timestamps, refresh disable,
and proof that uncertain White317 cannot train itself. Full suite1.69seconds.
Live installation and 11-stone/periodic refresh verification remain next.


2026-11-21 occupied-reference live validation and 0.217 follow-up:
0.216 captured the reviewed 11-stone position without clearing the board. Full
position verification resumed Human White, and live generations 2 through 5
proved periodic refresh. Dave then placed White displayed D7 (raw297/N4). Its
former empty patch was correctly invalidated, but the primary detector remained
uncertain: the jade White body is slightly darker and more cyan than the glary
wood. Game was paused with12physical/11saved moves, laserOFF; no false move was
recorded and no new stone was absorbed into an empty reference.

0.217 adds tightly gated White object evidence: changed genuine-empty before
patch, unchanged surrounding samples, color agreement with two confirmed Whites,
absent grid rails, a complete sharp12-sector outline, and three fresh matching
observations. No fixed board coordinate is special-cased. The before-image is
retained separately from any subsequently accepted White reference. This is new
object evidence, distinct from merely matching an old occupied patch. Only the
former may train a new White patch. Resume can accept a fully observed legal
human move already on a nonempty saved board; empty-game startup still requires
verified empty, and unrelated missing/extra stones still block.

Partial references: uncertain labels and displaced-placement regions plus their
8neighbors are excluded. Capture has a confident-areas-only option that also
excludes weak/mismatching raw readings and their neighbors. Unresolved regions
do not block stable independent updates in other areas. They are never resolved
or trained merely from the expected game position. Strong unexplained board
contradictions still block refresh. This integration currently runs in Play AI;
local deferred-location history has not yet been connected to these references.

648 occupied-reference checks pass, including current-light D7 before/after,
no new White on nearby empty glare, archive/commit continuity, uncertain-region
exclusion and periodic refresh elsewhere. AI suite41 lifecycle checks plus real
KataGo and rank_20k HumanSL responses pass. Actual0.217 live continuation remains
to be checked. The reference-feature upgrade uses the retained reviewed genuine
11-stone BEFORE image, not the current12-stone view. Manual camera166/gain32,
normal room brightness; original trueempty image and game timing preserved.

0.217 live restart retained history/clocks and manual camera controls, but its
0.05-grid occupied-reference geometry gate rejected a legitimate0.064-grid
startup refinement. Native alignment supported the unchanged board with313grid
matches and10/11known stones. The whole reference was cleared before classification,
so D7 remained unaccepted. Bounded5s recording16:23:54 DA210C49 captured this;
images/diagnostics/warnings thenOFF, gamepaused, no redundant tail.
0.218 raises only that small-refinement gate to0.10grid; independent camera
alignment and per-patch pixel/color matching remain mandatory. Added12real
post-restart frames plus actual reviewed archive as regression: D7 AND the entire
12-stone position verify; larger moved-grid rejection remains tested.674checksPASS.

0.218 live recognized D7 asmove12; AI BlackB7/raw335/N2 received
1795307350.652653, White clock started atreceipt, pendingphysicalplacement.
Laser initially failed old3500-feature registration undermanualexposure.
Bounded fallback12000features in laser point_vision.py preserves ALL acceptance
thresholds. Eleven registration tests pass including actualpendingB7 binding,
large-motion/broad-occlusion/false-dense-fit rejection. Soleowner9426 replaced
gracefully by27871, identical commissioning/firmware. LiveB7 admitted82inliers,
geometry2.897px<6.644pxcap, opticalerrorrefinedto1.05px, thenhand/placementOFF.
DaveconfirmedB7placed; actual13stonephoto reviewed. Confirmation initially
blocked because neighboringWhite317anchor had been discarded whenD7committed;
Pause/Resumeresets fullposition verification.0.219 retains unchanged neighbor
anchors but resets their freshness; changedpoint labels and actual changedpixels
still invalidate. Reviewed capture also permits a pendingAIstone only when
independentrawreading already positivelysees its correctcolor atconfidence>=.9.

0.219/build 220 LIVE PASS: the reviewed physical 13-stone board seeded an occupied
reference through the native UI, including the independently seen pending Black
B7. Resume verified the full position: pendingPlacement=false, native UI “Your
turn · White to play,” laser OFF. Live reference generation 1→2 proves periodic
refresh with all 13 stones retained. 676 occupied-reference checks pass.
Original history, decision receipts and paused clock balances were preserved.
D7 was accepted by camera evidence; B7 was generated by KataGo. Its decision
receipt remains 1795307350.652653. Current laser service PID: 27871.
Partial capture and uncertain-location exclusions currently run in Play AI.
Local deferred-history integration and full crowded-game/capture-removal
qualification remain outstanding.

A6 follow-up (move15/raw355): no laser because old dim optical baseline failed
masked texture agreement under normal manual exposure with14stones. Native game
paused; warnings and recordings verifiedOFF. Explicit optical-only occupied
reference refresh: three fresh accepted old-to-current registrations (75/61/72
inliers), corner agreement0.047px, unchanged motor parameters/offsets, all361
Jacobian conditions<15(max14.527). New setup93a90dbd55587110 lives in laser project
Camera checks/App bridge 2026-11-21/occupied normal reference. Active soleowner
PID30415; old27871 stopped cleanly.13registrationtestsPASS, including negative
motion/occlusion/hand/grid/blank checks. Live A6 laser nowon and tracking3.3px;
user confirmation/physical placement pending. No native application changes.

0.220/build221 B8 follow-up: after Black A6 placement Dave played White B8/raw334
before intermediate AI-placement confirmation. Fix permits the combined legal
transition only with fresh positive evidence at the AI point. Missing AI stone,
two human moves or unrelated changes still reject; original AI receipt remains.
White fallback now records component evidence scores (not calibrated probabilities):
outline0.30, learned appearance0.30, visible-grid absence0.15, local background0.15
and before-image change0.10. For a previously observed White, local background
weight is0.05 and appearance continuity0.20. Neighbor-stone edge samples are
excluded from background comparison, while a genuine empty before-image is
required to infer new White. Clear hand/alignment/freshness gates remain.
Three strong matching object observations over>=0.4s establish the candidate;
brief weak frames may retain it for<=0.6s only while current pixels still match.
An actual changed/removal patch immediately invalidates retention; retained output
alone cannot train reference updates. Strong primaryWhite detections also retain
the genuine empty before-image for subsequent uncertain frames. The current
B8 recording verifies16stones for consecutive frames; surrounding empty glare
never becomes another new White. AI suite55checks passes including real engines.
Live verification remains next. No laser hardware changes for this release.

0.221/build222 follow-up: live0.220 accepted White B8 as move16 and generated
Black C7/raw316 as move17 (receipt1795309654.483047). A reference-label bug
prevented positive-empty laser admission: the logical AI move relabeled its
physically empty destination before placement. Reference labels now use the
pre-AI position while pending, including prisoners not yet removed. Confirmed
placement advances labels; raw positive stone evidence still overrides empty
reference support. Manual reviewed capture retains the logical-board guard.
706 reference checks pass, including pending-target empty support and independent
Black override. AI tests cover pending/restored/confirmed labels and captures.
The mistakenly erased C7 patch can be recovered from the reviewed14stone before
photo: same identity and calibration, current actual pixels pass unchanged patch
matching tolerances. Other current reference features remain intact. No guard,
engine move, timing receipt, hardware service or optical reference changes.

0.221 live result: unchanged saved17moves/receipts/clock balances across restart.
C7 original empty patch restored; current pixels matched production tolerances.
Producer6E325234-4A9F-43A4-B71E-6DFA2C1079CA seq5 POINT admitted by existing
service30415, operation1795310178912706000-5. LaserON/adequate, refined8.0px to1.4px.
User prompted for Black C7 placement.706 reference and60 AI checksPASS.

0.222/build223 C7 acceptance: physical Black C7/raw316 was consistently detected
and service confirmed OFF at1795310211.6468365, watermark231. Adjacent existing
WhiteD7/raw297 andC6/raw317 fell below fallback evidence score after placement.
Known-White body continuity now has an invariant band (chroma distance<=0.01,
luminance change<=0.04), fading to zero at the existing0.025/0.10 bounds.
The score threshold0.92 and outline/color-exemplar/locality/grid gates remain.
Neighbor background masks also include raw-positive new stones, since pending
AI reference labels intentionally still describe the pre-placement position.
New-White before-image change requirements unchanged.20actual C7 frames now
produce consecutive full17stone witnesses; actual D7 removal still rejects.
728 occupied-reference checksPASS. No hardware/service/clock changes. Native
recording17-18-44 lasts4seconds; no redundant tail was trimmed. WarningsOFF.

0.222 live verification PASS: all17stones accepted within2seconds after Resume;
pendingPlacement=false, UI White to play, laserOFF. Original17moves and decision
receipts unchanged, pausedbalances preserved across restart. No physical stones
lifted or referencearchive changes required. Next test: normalWhite move.

E3 recovered and placed.14registration testsPASS. Gracefully stopped30415,
activated opticalsetup9217a7acf7701bb8 with service39751. Motorparameters,
offsets,firmware,guards unchanged. Op1795311178580097000-31 aimedE3, refined
18.3px to3.35px, then physicalplacement accepted; move29pendingfalse,White turn,
laserOFF verified. User continued play. E3receipt1795310990.76651 preserved.
Refresh anchored via earlier accepted operation23 darkimage(819inliers), then
3fresh registeredframes(1411/1455/1432inliers), corneragreement0.0379px.
All361Jacobianconditionspass,max14.528. Folder:occupied move28 reference.
Follow-up: bounded ongoing opticalreference refresh before localized stone
accumulation exceeds quadrantcoverage. Native occupiedreference is distinct
from laser opticalreference; do not weaken coverage gates.

D9/raw295 after move33: primary camera recognizes White at0.89–0.96, but
HandOutlineTracker stays active with depth7.55/edge1/poseLost=true, despite
reliable empty hand pose and visibly clear board. Native recording17-36-09
2839A8DF captures4seconds of this failure; no redundant tail. Clock paused.
Restart clears hand track, but strict full-board reverification exposes stale
empty patches and White296/317 anchors. Restart recording17-38-03 1EBD5176
captures handclear and D9 stillpositivelyWhite. Preparing explicit visually
reviewed occupied reference for actual34move position (33physicalstones due
capture), including D9; game staysat33 until normal legal/camera confirmation.
Need durable hand-clearance fix: preserve frozen baseline and seed/change-mask
in diagnostics to reproduce onset; current recording lacks tracker background.
Do NOT clear hand merely by timeout or absent pose. Need board-rim/texture
clearance with stone-aware foreground masks. Also improve retaining independent
appearance evidence immediately after accepted moves, before10second refresh.
Current recovery is explicit reference/tracker reset, not a claimed rootfix.
No laserhardware/opticalreference changes; service39751 remains owner.

D9 recovery verified: camera accepted raw295 asWhite move34 without lifting;
AI replied raw313(C10) move35, laser operated and placement accepted. Original
33moves/receipts preserved. Rootcause review: automatic occupied refresh WAS
running (generation47, updated1795311286.854022), but only301/361entries remained.
A single photometric mismatch deletes an entry; replacement requires repeated
independent confidence, while uncertain points exclude their whole neighborhood
from refresh. Newlyaccepted White296 had an emptyorigin but noWhiteanchor yet.
This creates a local recovery deadlock under changing shadows/glare, despite
updates elsewhere. Separate hand-outline frozenbaseline persists while active;
occupied-reference updates cannot clear that stale hand track. Recoveryabove
is not a durable fix. Need preserve/quarantine reference evidence, perpoint
illumination-aware revalidation, timely independent newstone anchors, and
reproducible rim-clearance diagnostics. Never learn from gamehistory alone.

2026-11-21T17:49:59
0.223/build224 reference/hand recovery work (not installed yet): suspect patches
are quarantined with original pixels and can recover only through3fresh matching
frames/>=0.4s; label changes discard incompatible evidence. New accepted White
anchors retain>=3independent primary observations before10second routine refresh.
Per-patch refresh no longer stalls globally on an unplaced AI stone; uncertain
neighbors still block empty learning, independently seen stones may update.
Hand clearance additionally tests preserved texture across the full entry rim
strip when an interior change spoils whole-component correlation. Same pixel,
texture, fingertip and2clear-frame requirements. Checkpoint records frozen hand
background/state once when diagnostics start, enabling exact offline reproduction.
737referencechecks,189syntheticoutlinechecks,67recordedoutlinechecks,7photographed
pipelinechecksPASS. D10/raw294 is primaryWhite confidence1; live obstruction is
again stalehandtrack, edge1 depth3.45. Game35paused, service39751 preserved.

2026-11-21T17:58:21
0.223 final regressions:761occupied-reference checksPASS, including20actualD10
frames with sustained full-board recognition. Added overdue-deadline regression:
old periodic path cleared all incomplete candidates every frame once the deadline
passed with none ready; now removes only refreshed candidates. This was a genuine
recovery starvation bug. Empty recovery uses current localwood classification
(existing>=0.75 acceptance), strong visibility of bothgridaxes>=0.75, and3fresh
proofs over>=0.4s. Eightproofs plus stable independent patch pixels needed totrain.
Neighborstone edge pixels need not match for current grid/wood proof to be counted.
Quarantined templates remain inactive until independently revalidated.
One-time upgrade recovers58 mistakenly discarded patches from earlier genuine
D9 reviewed archive ONLY as quarantine, matching identity/calibration/labels;
no currentphoto recapture or gamehistory inference. Filequarantine-upgrade.json
records points. Liveinstallation/placement test next. Game35/D10raw294 remains
paused; exact game and balances preserved. Handtests189+67recorded+7pipelinePASS.

2026-11-21T18:03:07
0.223/build224 installed, source0711990db4454fd3c40263bf4629aaeb952cf2650ed9f9dfba4aa68ad3610d04.
58old original patches upgraded into quarantine only; original35moves/receipts/
pausedbalances preserved. LiveD10/raw294 accepted asmove36 without stone lifting
or newreferencephoto. KataGo replyBlackD11/raw293 move37 receipt1795312917.286665.
ProducerD376DB62-DEB4-4674-B7A2-7727484C5838 seq7 POINT; existingservice39751
tracking1.4px. Userprompted to placeBlackD11 for livehand-clearance verification.
761reference+189syntheticoutline+67recordedoutline+7pipelinechecksPASS. Durable
reference fixes and rimclearance installed; repeated livehandtest stillpending.

2026-11-21T18:03:52
0.223 live continuation: BlackD11(move37) and followingWhiteC11/raw312(move38)
both accepted. Camera reports handclear, laserOFF, KataGo thinking. Active
reference recovered287to338patches,5quarantined remain, D10anchorretained. No
newmanualreferencephoto. This validates first continued play after installation;
recorded/synthetictests cover clearance path, repeatedlivehand qualification
continues. Originalgame retained. User can continue normal play.


## Alignment preparation during AI thinking — 0.225/build226

After the physical human move (and any capture cleanup) is confirmed, the app
renews an OFF request with reason `ai_thinking` and optional metadata:

```
alignmentPreparation: {
  session: UUID, moveNumber: next AI move number, size: 19,
  positionConfirmedAtUnix: Unix time when the position was confirmed
}
```

This is image-only preparation, not motor arming or permission to illuminate.
The same preparation identity follows the AI point request. Pause, cancellation,
pass and departure from thinking/placement clear it; restoring an already-pending
AI move does not invent a previously confirmed preparation. Metadata is omitted
when guidance is disabled. Existing v1 consumers can ignore the optional field.

The hardware backend uses a fresh camera-presentation frame captured after both
position confirmation and confirmed OFF plus 0.3 seconds. It checks the commissioned
setup/model/reference, native grid and full optical registration while KataGo
thinks. It refreshes during longer searches, at most once every two seconds.
Results are scoped to app producer, game, move, camera context/epoch and artifact
hashes. Invalid/obstructed camera observations discard the cached context.

On the AI reply, a fresh clear frame still passes identity and target checks.
The prepared transform is reused only if a bidirectional optical-flow movement
check agrees: at least 40 points, 85% valid tracks, coverage in all four quadrants,
median displacement <=0.5px, 95th percentile <=1px, and native-corner change <=2px.
Cache age is limited to 10 seconds. The native-to-optical grid gate remains.
An in-flight preparation can finish during dark motor travel. A missing, stale or
changed view falls back to full registration; full registration failure prevents
illumination. The final dark-reference stage also uses this guarded reuse.
Optical spot feedback still measures the illuminated spot; it is separate from
this board-to-camera alignment preparation.

Offline evidence: 83 AI and 68 laser/protocol checks, recorded-image registration
and backend lifecycle tests. The image-only ablation lives in the pointer project
at `Firmware/Simulations/check_ablation.py`; it writes only to an explicit scratch
output and does not open a camera or serial controller. It distinguishes replay
accuracy, injected faults, and timing subtraction estimates. Source changes are
staged for the next laser-service start. No live speedup is claimed before testing.


## Empty-hand return — 0.226/build227

A hand entry still immediately requests OFF without accepting the AI stone.
For the same pending target, automatic re-show is permitted only after current
matching driver OFF evidence (including the hardware frame watermark and dark
flush interval) and three distinct, unambiguous empty-target observations spanning
at least 0.45 seconds. Unknown hand/alignment, uncertain target, observation
interruptions and gaps over0.6seconds reset the streak. Re-show uses a new revision
with reason `empty_after_hand`; target identity and AI receipt time are unchanged.

Only a hand-entry suppression can recover this way. A stone-like target reading,
driver interruption, camera/context/epoch change, pause or disable cannot be
overridden by a subsequent hand observation. Explicit Show point again remains
available. This adds no firmware commands and leaves optical admission and
per-target correction/placement verification in the driver and game respectively.


## Capture clock threshold correction — 0.227/build228

User clarification supersedes the earlier all-captures policy: only captures of
TWO OR MORE stones pause elapsed time for physical placement/removal. Zero- and
single-stone captures preserve normal decision-receipt clock switching and keep
the next side's clock running during the physical update. Board verification is
still required before play continues. The exact legal capture count gates both
new moves and restored cleanup flags; old single-capture flags normalize on
resume. Multi-stone legacy saves retain the hold. Recorded moves, AI receipt
timestamps and already accumulated clock balances are not rewritten.

## L14 recovery update — 2026-11-22

Native 0.247 separates authoritative pending-move indication from physical stone
confirmation. The L14 target was uncertain (0.78125), so an expired lease could
not recover under the old positive-empty-only gate. Board uncertainty no longer
resets the independent clear-view recovery streak. A second lease expiry while
already OFF now advances the rejected OFF revision; it cannot renew that revision
forever. No camera-age, hand, dark-frame, watermark, alignment, or hardware-fault
guard is relaxed. Stable correct-color placement and capture cleanup still decide
game progression. The original AI receipt timestamp and clock boundary remain.

Regression: 275 AI laser lifecycle, clock-receipt, dark-frame and protocol checks,
including uncertain-target recovery after hands/camera/lease interruptions, expired
OFF revisions, positive stones, invalid/unknown camera states, and malformed frames.
