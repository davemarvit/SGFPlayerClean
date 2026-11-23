# Camera, AI and laser integration — current checklist

Updated: November 22, 2026 (Pacific time).

Maintain this document after meaningful changes or tests. Keep investigation
history in [LivePositionIssues.md](LivePositionIssues.md). Distinguish source,
offline verification, installation and physical validation.

## Current checkpoint

- Physical Go **0.252/build 253 is installed and signature verified**. It adds
  captured-stone indication, fixes ended AI games constraining grid recovery,
  and prevents cached camera pixels crossing a stream restart. Seven application
  suites (590 checks), eight build-registry tests and 29 host tests pass.
- Post-install camera check: 151 fresh frames in 15 seconds, maximum observed
  age 0.245s; correct camera, aligned empty board and hand-clear throughout.
  Game/clocks are unchanged. App remains paused, bridge disabled, recording and
  warning feedback off. Temporary keep-awake assertion is released.
- Fast AI test mode is enabled on the paused empty-board game. The old 267-move
  game and clocks are backed up. New game remains at move 0; clocks preserved.
- Correct camera and fresh board grid were verified after equipment moved.
  Full laser recalibration is incomplete: K10, D16, Q16 and Q4 were within three
  camera pixels before a motor fault stopped calibration. No new binding activated.
- **Laser and motor power are OFF. Original v39 firmware is restored and fresh
  OFF confirmed.** Production bridge remains stopped. Root alone owns hardware.
- Heat testing is partial: v43 passed a 60-second check, then held for about
  15 minutes before a camera timestamp interlock stopped endurance-02. Highest
  internal temperatures were 16°C/17°C; no motor or thermal fault was reported.
  No two-hour pass, cooling transition, external-temperature, power or noise
  measurement has been established. Dave now prefers monitored actual gameplay;
  a formal two-hour endurance test is optional, not a prerequisite.
- The exact camera check that failed was not retained by the old generic error.
  A subsequent ten-minute passive audit found no failing checks. Detailed
  timestamp logging is added. At Dave's request, an explicit camera-independent
  option is now prepared for the stationary, beam-disabled heat test only; it
  retains the app OFF lease and all motor protections. It is offline-tested,
  not physically rerun. Gameplay camera safeguards remain unchanged. The separate
  stream-cache bug is not the proven cause of the interruption.
- **No dependency on a laser-agent response is confirmed.** The incoming shared
  response remains November 21. A written request is not acknowledged ownership.
  Parallel agents have worked offline; coordinate before any serial access.

## Immediate next steps

1. Implement temperature-protected holding in the gameplay firmware/bridge/app.
   This is the immediate software gap: private heat-test holding cannot indicate
   moves, and installed v39 gameplay lacks continuous temperature supervision.
   Preserve full OFF for pause/disconnect/fault and keep optical camera guards.
   Log both motor temperatures, maxima/trends and holding/cooling transitions.
2. Verify overheating, stale/failed telemetry, cooling recovery and cancellation
   offline, then check a short physical dark hold and Pause/full-OFF. A formal
   two-hour stationary test is no longer required before supervised gameplay.
3. Verify the moved setup and complete fresh laser calibration before playing.
   Existing motion faults must still stop the attempt; no guard relaxation.
4. Play several ordinary moves with fast AI and recognition checks. Start without
   centering hints, so ordinary hand/stone acceptance and cue timing are clear.
   Check a lingering hand, slow withdrawal, correct placement and Pause/Resume.
5. Enable centering hints: deliberately offset a stone, then place it between
   intersections; verify the wiggle marks the observed disk without accepting a
   guessed move. Check hand-triggered darkness, centering and removal.
6. Use controlled legal single- and two-stone capture fixtures (see the capture
   test plan), rather than waiting for random AI captures. Check AI placement
   before prisoner indication, partial/out-of-order removal, no repeated cue,
   no phantom reply, and single/multiple-capture clock behavior.
7. Continue normal play while logging both temperatures. Use real-session data
   to assess whether temperatures level off under this mounting/load/room setup.
   Cooling/trip events remain actionable even if earlier readings were cool.

## Work list

| # | Task | Current status / completion criterion |
|---|---|---|
| 0 | Faster AI test mode | Installed and enabled since 0.251. Eight visits, no HumanSL, warm worker retained between replies. Normal opponent profile is preserved. Latest regression measured 12.904s cold and 0.219s warm; earlier run was 9.090s/0.170s. Real engine and four normal HumanSL profiles pass. Physical gameplay still awaits calibration. |
| 1 | Resolve motor movement faults | Unresolved physical interpretation. Untouched, released base reported raw speed +2 in 2 of 15 readings; encoder position varied one count. A dark FASTARM probe stopped before HOLD or movement. During endurance-02, 8,429 held sample pairs had speeds only 0/1; base encoder stayed 2422 and tilt ranged 2143–2144. These are different conditions, not an event-rate estimate or proof of no movement. Prepare an attended optical comparison; guards unchanged. |
| 2 | Finish laser calibration | Partial. Complete moved-setup coverage/accuracy checks and activate a fresh binding. Reset transient camera evidence and capture a dark empty-board reference before gameplay. |
| 3 | Physically validate hand clearance | Partial pass: paused empty-board and single-stone placement/removal checks detected hands and returned to clear; the stone did not leave a false hand flag. Still test live acceptance, clocks and hand-triggered beam shutoff. No exact withdrawal latency claimed. |
| 4 | Test moves and placement | Pending calibration. Verify human recognition, AI indication, physical placement, turn transitions and clocks on the new game. |
| 5 | Test captures | Physical tests pending. Verify delayed, single, multiple and partial removals and the intended clock policy. Offline tests preserve a legitimate cleanup-plus-reply while rejecting a remaining prisoner mistaken for a new move. |
| 6 | Reduce and measure move-to-laser delay | Fast approach/fine correction exists. Nonblocking simultaneous cue/light dispatch is implemented and tested offline; actual acoustic/optical timing is unverified. Measure first visible light separately from final pointing accuracy, for AI and online play. |
| 7 | Hold motors during active play | Next implementation priority at Dave's request; gameplay implementation remains pending. Private heat-test firmware is not gameplay standby. Add monitored dark holding distinct from full OFF, 45°C cooling fallback, below-40°C recovery after a stable dwell, and full release for pause/disconnect/fault/manual repositioning. |
| 8 | Validate prolonged holding and cooling | Private v43 commissioning-03 passed 60.022s, 533 pairs, maximum 14°C, clean OFF. Endurance-02 stopped at 917.235s on the camera timestamp gate, maximum 16°C/17°C, current maxima 3mA/11mA. Original v39 restored. Firmware temperature/current/motion/USB/heartbeat/ACK checks and host interlocks are implemented and tested; causal freshness passed eight two-hour clock-drift simulations. Dave no longer requires a formal two-hour test; monitor temperatures during actual gameplay instead. Actual cooling transitions and seated noise remain unvalidated. Never restart automatically after a fault or raise limits to force a pass. |
| 9 | Fix ended-game grid recovery | Installed in 0.252; physically unvalidated. Ended AI history no longer constrains a cleared board; unfinished/paused games still do. The original failure and fix were reproduced against the archived empty-board recording and preserved 267-move SGF; 21 focused checks pass. Full recovery lifecycle regression also passes. Live finish/reopen workflow remains to check. |
| 10 | Test laser centering hints | Pending calibration and live clearance. Verify the hint marks the observed off-center stone without inventing its intended intersection, stops for a hand, clears after centering, and yields to placement/capture guidance. |
| 11 | Implement/test captured-stone indication | App installed in 0.252 and host source updated; production bridge remains stopped. Placement precedes prisoner indications; prisoners are indicated individually and silently, with positive dark evidence, capability checks and retained clock behavior. Current full-app tests: 42 state, 47 laser-contract and 37 controller checks; 29 host tests pass. Physical accuracy on both stone colors, partial/out-of-order removal, hand entry and cleanup clocks remain untested. Old saves without explicit capture context do not gain guidance from stale history. |
| 12 | Complete online-opponent integration | Pending. Protocol accepts online source, but native camera publication/observation is AI-only and lacks an authoritative online target producer. Wire moves/orientation and preserve server clocks before separately validating online placement, captures and timing. |

## Accepted behavior

- Dave authorizes unattended **dark** heat testing while away, after software
  checks and a short monitored hold pass. Presence is not another approval gate.
  Two endurance attempts have stopped early; do not hide that as a two-hour pass.
  Dave now makes formal two-hour testing optional and prioritizes monitored play
  with automatic cooling fallback, temperature logging and recognition/marker tests.
- Prefer fast dark travel followed by bounded fine correction.
- Start the audible cue with laser activation; playback must not delay light.
- Preserve the meaning of full OFF. Persistent holding is a separate mode.
- At 45°C, release holding torque and accept slower per-move activation while
  cooling. Keep temperature readings available. Resume below 40°C only after
  both motors remain cool for 30 seconds. At 50°C, or a lower configured motor
  limit, latch full OFF. Missing/failed/stale readings also stop. A sampled
  threshold is not a guaranteed absolute temperature ceiling.
- If full power-off prevents temperature readings, a measured cooling curve may
  schedule torque-off wake checks. Actual readings must authorize recovery;
  elapsed time alone cannot. Do not auto-resume after a hard trip or fault.
- Camera-independent heat mode is confined to stationary private firmware that
  cannot illuminate or command travel. It does not disable gameplay hand/camera
  checks. The mode is explicit in the command and recorded in its result.
- Fast test mode changes AI thinking time, not clearance or board verification.
- The optical-motion diagnostic is a separate attended test. A stationary-looking
  spot only bounds movement to the camera's measured resolution and cadence.

## Evidence and coordination

Session artifacts:
`/Users/dave/Documents/SGF PLayer/work/ai-laser-integration/fresh-board-20261122-133741`

- `thermal-host/commissioning-03`: completed v43 short check.
- `thermal-host/thermal-endurance-02`: partial physical endurance and OFF evidence.
- `thermal-host/restore-after-endurance-02.json`: original v39 restored/OFF.
- `thermal-analysis/reports/thermal-endurance-02-20261123T005725.907151Z`:
  temperature/current/encoder report and plots.
- `thermal-host-tested-v43-endurance-02`: exact tested host, before diagnostic
  logging improvements. Current host logs identify the failed camera age and
  manifest-read timing; these additions have not been physically rerun.
- `camera-age-after-endurance-02`: ten-minute passive audit, no hardware use.
- `stone-clearance-01`: paused single-stone/hand physical check.
- `capture-guidance-candidate`: reviewed patches, integration tests and
  `combined-reply-fix`; implementation now applied to source.
- `ended-game-recovery-candidate`: reproduced cleared-board failure and fix.
- `broker-epoch-cache-candidate`: deterministic cross-stream pixel-cache race,
  fixed by using stream epoch plus frame ID. Separate from the heat-stop cause.
- `optical-motion-diagnostic-candidate`: measurement plan and pure analysis only;
  no beam-capable diagnostic firmware is implemented.

Historical latency audits (`gameplay-latency-audit.json`,
`laser-command-latency.json`): November 21 receipt-to-ON acknowledgement median
5.174s; ARM plus HOLD about 1.80s. Final TRACK/SWEEP dispatch-to-ON acknowledgement
median 83.2ms, p90 105.3ms. These are protocol timings, not optical measurements
or a measured saving from persistent holding.

Plans: [standby and thermal design](LaserStandbyThermalDesign.md),
[capture and centering tests](LaserCaptureCenteringTests.md).

Shared outgoing handoff:
`/Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware/AI play integration reply.txt`.
Incoming file: `AI play integration response.txt` in the same directory.

Startup timing correction retained: the read-only v40 diagnostic's timestamps
began after the cached OpenRB library had already raised motor power. Its actual
powered duration was source-inferred at about 3.54s, not the earlier claimed 3s.
No torque or light was commanded. Raw evidence remains unchanged. Later thermal
firmware starts its timer before the first possible power edge.
