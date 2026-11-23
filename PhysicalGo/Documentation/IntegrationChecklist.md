# Camera, AI and laser integration — current checklist

Updated: November 23, 2026 (Pacific time).

Maintain this document after meaningful changes or tests. Keep investigation
history in [LivePositionIssues.md](LivePositionIssues.md). Distinguish source,
offline verification, installation and physical validation.

## Current checkpoint

- **Latest physical run stopped fully OFF.** `validation-resume-02` on pushed
  `6cf3c99` passed fresh position admission and both independent motor probes
  (candidate displacement residuals 1.207 and 2.154 pixels). All 93 combined
  offline tests passed without skips. Guarded A10 approach shrank to four/two
  motor counts while still selecting the fast profile; repeated measured poses
  showed no useful progress. No validation target completed. A separate serial
  write completion deadline stopped the run after 123 total observations;
  full OFF confirmed Unix1795470112.9394574, no controller fault, source inventory
  unchanged. Last observed pose was [1720, 2274], board [1.88144, 9.12087].
  The small-step profile fix is independently reviewed and pushed as `0e7434a`
  (four focused and 51 existing checks passed); not physically retested.
  Bounded serial timing diagnostics are integrated as `bbc7f72`; the final
  combined 112 checks pass without skips. Neither follow-up change has been
  physically retested; the communication delay cause remains unresolved.
  Automatic retry correctly refused a transport fault. The original five fit
  targets remain preserved, all nine accuracy targets remain, no binding active.
- **Large-move diagnostics are planned, not yet run.** Record the first visible
  landing before correction, with the camera fixed, and compare distance,
  direction, diagonals and repeats. The recording audit found a largest observed
  span of 2.965 intersections
  during fitting and 2.548 during validation; these are intervals between optical
  observations and can contain multiple commands. No board-width jump was tested.
  Begin with one qualified 2–3 intersection span in both directions after steering
  qualification; the larger optional campaign is not a gameplay prerequisite.
  See the saved [protocol](</Users/dave/DYNAMIXEL-Go-Pointer-worktrees/overnight-adaptive-calibration/Firmware/Experiments/AdaptiveCalibration/LARGE_MOVES.md>)
  at pushed source `86bf0b9`. Failed or merely predicted landings are not training
  observations.
- **Latest physical result:** `full-calibration-04` ran for 702 seconds with
  explicit 10-second camera age, 7200-second overall allowance and target timer
  disabled. All five fit targets passed: K10 2.21px, A19 1.76px, T19 2.31px,
  T1 2.58px, A1 2.86px. After 106 observations, the first validation leg stopped
  on the independent 250ms polling-cache watchdog: approximately 322ms elapsed
  between polls while camera and app lease remained valid. Full OFF confirmed
  Unix1795467167.9429295 without controller fault; source inventories unchanged.
  Maximum reported temperatures were 15/17 C. Camera evidence never exceeded
  0.538 seconds, so this run did not physically exercise over-0.6-second evidence.
  The 95 fit-stage samples produce a **fit-only, unvalidated** candidate (median
  residual 2.49, p95 5.19 motor counts). No binding activated. Recovery must
  requalify actual pose and preserve those measurements; all nine validation
  checks remain. Root owns hardware, currently fully OFF.
- **Previous full-run result:** bounded automatic recentering passed: eight small
  dark moves with optical checks brought the spot to board coordinates
  [3.05686, 3.09366], followed by confirmed full OFF. Host `8fd0630` has
  179 passing targeted checks. Subsequent `full-calibration-03` passed K10
  (2.45px) and A19 (2.73px), then stopped after 17 observations when camera
  evidence exceeded its unchanged 0.6-second lifetime. The supervisor cancelled
  the session; this was not the experimental overall/target timeout. Final
  v44 full OFF confirmed Unix1795465259.8695755, with no controller fault.
  Source inventories and saved game/clocks are unchanged; no map/binding activated.
  Calibration is incomplete. Review of safe full-OFF pause and requalification
  is active offline; hardware remains off. The preceding run's image mismatch
  remains consistent with Dave's reported nearby movement/shadow.
- Preserved physical-test baseline code checkpoints: app `64a1b77`, laser `11d3855`,
  both on `codex/monitored-gameplay-holding`.
  Staged calibration, progress UI and gameplay recovery changes are included.
  Signed **0.254/build 255** candidate is built and verified, but not installed.
  Candidate and source/game snapshots are under the session artifact directory
  `gameplay-holding-validation/app-0254-candidate/`.
  Source hash: `c03914ec09b7de194b7ede5707ee266699a9c60dfff2bc1abe882346e5d03a9b`.
- **Optional 0.255/build256 candidate is also built, signed and verified**, with
  reviewed recovery extraction, opt-in tracing and improved provenance/tooling.
  App `939fe27`, host `45ed952`, both on separate
  `codex/overnight-reviewed-candidate` worktrees. Eleven app suites,344 host
  tests,69 tooling checks and mandatory paired acceptance pass. Not installed or
  physically validated; 0.254 remains available. See [overnight results](OvernightSoftwareResults.md).
- Both projects have pushed Git checkpoints before gameplay-holding changes.
  App baseline: `e8b2b14` on `codex/physical-go-confidence-validation` in
  [SGFPlayerClean](https://github.com/davemarvit/SGFPlayerClean).
  Laser baseline: `1060bef` on `main` in the new private
  [DYNAMIXEL-Go-Pointer](https://github.com/davemarvit/DYNAMIXEL-Go-Pointer)
  repository, rooted at the existing laser project folder. Future laser code
  and tests belong there. Large `Camera checks/` recordings remain local and
  ignored; the repository includes firmware, bridge, tests, CAD and documentation.
- Physical Go **0.253/build 254** and reviewed **v44 firmware** are installed.
  App signature/source hash and firmware upload were verified. Eight app suites,
  four final targeted suites, actual Swift/host contract exchange, host transport
  checks and independent firmware/USB/timing checks passed offline.
- Physical dark commissioning passed: 19.360 seconds, 143 paired reports,
  reported motor temperatures 11–12°C, maximum causal sample age 148.183ms.
  Holding, dark reuse and final full OFF were verified without travel or light.
  Optical gameplay and physical cooling transitions remain unvalidated.
- Correct app camera, fresh grid and empty board verified after installation.
  Game/clocks are byte-identical and paused. Broker publishes OFF/no-target
  evidence; production bridge is stopped. Recording/warning feedback remain off.
- Fast AI test mode is enabled on the paused empty-board game. The old 267-move
  game and clocks are backed up. New game remains at move 0; clocks preserved.
- Correct camera and fresh board grid were verified after equipment moved.
  Full laser recalibration is incomplete: K10, D16, Q16 and Q4 were within three
  camera pixels before a motor fault stopped calibration. No new binding activated.
- **Hardware is fully OFF:** validation-resume-02 confirmed fresh v44 OFF.
  Production bridge and calibration are stopped; root remains sole hardware owner.
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

0. Signed 0.255 candidate and paired checkpoints are ready, with 0.254 retained
   as a fallback. Install and visually verify the selected candidate when returning
   to the board; installed app is still 0.253. Preserve
   the paused game/clocks and verify the restored lighting/setup before testing.
1. Temperature-protected holding is implemented and installed in app/firmware;
   host runtime is implemented, offline-tested and stopped pending calibration.
2. Short physical dark holding/reuse/full-OFF check passed. Physical gameplay
   Pause/Resume and cooling recovery remain to test; two-hour endurance is optional.
3. Complete fresh full-board laser calibration before playing. The earlier
   120-second target timeout now has an explicit experimental override (normal
   defaults unchanged,153 offline checks pass). The longer retry instead stopped
   on an image-similarity rejection consistent with Dave's reported nearby
   movement/shadow. Investigate dark pause and full requalification for transient
   lighting; do not lower the0.95 threshold merely to admit this image. The
   earlier staged A/B prelight timing fix is working in these partial runs.
   No full-board model is qualified. See latest history and calibration timing.
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
| 7 | Hold motors during active play | Implemented and offline-tested; app 0.253/v44 installed and short dark commissioning passed. Native opt-in, explicit game identity, two-stage OFF handshake, retain-only hand behavior, distinct held/cooling dark evidence, temperature current/max/trend, and hard-fault reset indication are offline-tested. Preserve 45°C cooling, below-40°C measured 30-second recovery and full release for pause/disconnect/fault. Production gameplay bridge remains stopped pending fresh calibration; opt-in is off. |
| 8 | Validate prolonged holding and cooling | Private v43 commissioning-03 passed 60.022s, 533 pairs, maximum 14°C, clean OFF. Endurance-02 stopped at 917.235s on the camera timestamp gate, maximum 16°C/17°C, current maxima 3mA/11mA. Reviewed v44 is now installed after the short dark pass. Firmware temperature/current/motion/USB/heartbeat/ACK checks and host interlocks are implemented and tested; causal freshness passed eight two-hour clock-drift simulations. Dave no longer requires a formal two-hour test; monitor temperatures during actual gameplay instead. Actual cooling transitions and seated noise remain unvalidated. Never restart automatically after a fault or raise limits to force a pass. |
| 9 | Fix ended-game grid recovery | Installed in 0.252; physically unvalidated. Ended AI history no longer constrains a cleared board; unfinished/paused games still do. The original failure and fix were reproduced against the archived empty-board recording and preserved 267-move SGF; 21 focused checks pass. Full recovery lifecycle regression also passes. Live finish/reopen workflow remains to check. |
| 10 | Test laser centering hints | Pending calibration and live clearance. Verify the hint marks the observed off-center stone without inventing its intended intersection, stops for a hand, clears after centering, and yields to placement/capture guidance. |
| 11 | Implement/test captured-stone indication | App installed in 0.252 and host source updated; production bridge remains stopped. Placement precedes prisoner indications; prisoners are indicated individually and silently, with positive dark evidence, capability checks and retained clock behavior. Current full-app tests: 42 state, 47 laser-contract and 37 controller checks; 29 host tests pass. Physical accuracy on both stone colors, partial/out-of-order removal, hand entry and cleanup clocks remain untested. Old saves without explicit capture context do not gain guidance from stale history. |
| 12 | Complete online-opponent integration | Pending. Protocol accepts online source, but native camera publication/observation is AI-only and lacks an authoritative online target producer. Wire moves/orientation and preserve server clocks before separately validating online placement, captures and timing. |
| 13 | Illegal-move feedback | Tested proposal ready: [design](IllegalMoveMarkerDesign.md) and tracked [experiment](../Experiments/IllegalMoveMarkers/README.md), 83 checks against actual engine sources. Existing suicide observations can fall through to generic mismatch before the specific illegal-move diagnostic. Candidate adds a separate diagnostic path without accepting illegal moves, guessing ambiguous placements, or mistaking prisoners for new moves. Specific screen feedback is recommended first; a distinct silent laser pattern remains a proposal. No production integration or physical validation; does not block the core test. |
| 14 | Modular project onboarding documentation | Created [AgentGuide](AgentGuide/README.md): nine focused pages with start/resume instructions, capability/subsystem/problem routes, source entry points and targeted validation. All 157 local link targets were checked. Linked from both AGENTS files and project READMEs. Scope is inspected code, durable handoffs and current conversation context; other historical chats were not available through tools. This checklist remains the live status authority. |
| 15 | Dependable new-setup calibration | Staged implementation independently reviewed: 93 calibration plus 24 dark tests pass, including actual retained images and movement/occlusion rejection. Geometry A may be analyzed dark for up to 3s; distinct fresh B verifies all 72 boundary points against A and the original reference. A expires 5s after capture; B retains 600ms freshness. Offline B proof took about 117ms. Physical validation pending. v44 run04 previously verified K10 within 1.86px; no full-board map is active. Commissioning metadata allowance is 250ms. Beep and stationary spot checks passed. No end-to-end setup speedup claimed. Use only the app broker. |
| 16 | Occupied-board processing latency | [Measured report](OccupiedBoardTiming.md): ten archived pairs, 79 usable observations. A two-stone pair takes ~1.3s while a crowded matched-reference pair takes ~0.15s; reference/lighting/convergence matter more than stone count alone. Isolated cropped-image prototype roughly halves slow positive cases, but some rejections become slower; no production gameplay integration. Empty-calibration verifier takes ~0.16–0.23s on the exact failed images and is being reviewed separately. Native camera pipeline remains untimed. |
| 17 | Gameplay continuity on device faults | Candidate 0.254 is implemented and independently reviewed; not installed. Final 492 continuity checks consume 68 actual host statuses and full recovery sequences, including delayed OFF, AI retargeting, hand waits, Pause/Resume and scope/hard-fault rejection. Final source also passes 225 standby, 278 laser lifecycle and 47 capture-contract checks. Scoped hard-fault pause preserves history/placements/prisoners/clocks; explicit recovery and physically confirmed camera-only fallback are implemented. Ordinary hand/camera transient recovery no longer invents a hard fault or leaves guidance latched. Physical validation pending. Installed 0.253 can still stop guidance while local AI clocks continue; online clocks remain authoritative. |
| 18 | Continuous laser-map refinement during play | Dave authorized advance software/literature work overnight after initially deferring this. An isolated offline/shadow prototype now compares baseline, global offset and bounded local residual correction using actual measured poses/spots, confidence/provenance and chronological validation. Separate reviewed branch; no live learning or map activation. Retain baseline model and rollback; distinguish raised stones, outliers and changed equipment. Independent algorithm and campaign reviews complete; 56 tests pass. Cleared-board survey plan covers 25 fit + 24 reserved locations (130 episodes with approaches/anchors), optionally all361. First aim and final metrology remain separate; no hardware executor. Physical validation follows initial calibration/gameplay baseline. |
| 19 | Initial-calibration progress UI | Implemented and independently reviewed; not installed. Actual stage/target, five calibration plus nine accuracy checks, elapsed/stage time and stale/stopped/shutdown-unconfirmed/review-required states. No unsupported ETA. Passive asynchronous publishing cannot interrupt shutdown; injected publisher-failure tests pass. 26 native checks, SwiftUI typecheck and 128 calibration/progress/dark tests pass. Registered as `--calibration-progress-test`; final four-suite app regression and eight build-registry checks pass. Signed full app build and signature/source-hash verification passed; visual/physical validation pending. See [progress UI](CalibrationProgressUI.md). |
| 20 | Overall architecture and development-process review | [Review completed](ArchitectureReview.md). Existing app/host/controller boundaries are sound; no wholesale rewrite recommended and no new immediate source blocker found. Prioritize a pure scoped recovery/admission state machine, explicit status meanings, paired transition tests, measured I/O isolation and immutable build snapshots. Camera-failure clock policy needs an explicit decision before claiming complete/unattended reliability. At Dave’s subsequent authorization, reducer extraction, build/source provenance and paired acceptance are implemented and reviewed on isolated overnight branches; optional0.255 integrates them. Remaining recommendations include measured I/O isolation and explicit camera-failure clock policy. |

## Isolated overnight improvements (November 23)

Dave authorized reversible software improvements while away, including extra
latency logging and adaptive-calibration research/prototyping. Hardware work is
still deferred. The signed 0.254 candidate and primary code branches remain the
physical-test baseline; experimental branches are not automatically promoted.
Root maintains this table and serializes full Swift builds. Each experiment has
its own worktree, review and targeted acceptance checks.

| Work | Experimental branch | Gate before considering adoption |
|---|---|---|
| Pure transient-recovery state machine | app `codex/overnight-guidance-reducer` | Passed independent review,495 actual-host continuity checks, legacy suites and16,825 parity/105 independent checks; included in optional0.255. |
| Immutable regression inputs and build ownership | app `codex/overnight-build-provenance` | Passed mutation/concurrency/failure tests, Unicode/compiler probes and final combined full build; included in optional0.255 tooling. |
| Mandatory paired app/host contract acceptance | app `codex/overnight-contract-acceptance` | Passed fresh actual native→host→native acceptance with exact source/runtime output pins; missing/mismatched coverage fails. Included in candidate tooling. |
| Complete calibration source provenance | laser `codex/overnight-source-manifest` | Reviewed startup/final-only bounded inventory passes transitive/add/remove/modified-source tests and combined344-case host suite; optional hostcandidate. |
| Optional bounded latency diagnostics | both repos `codex/overnight-latency-tracing` | Reviewed/tested, default off; final combined native and344 host tests pass. Explicit clock/loss/ACK semantics, no training-eligible observations claimed. |
| Adaptive-map offline prototype | laser `codex/overnight-adaptive-calibration` | Core and postgame49/361-point diagnostic extension reviewed:56 tests, synthetic comparisons and positive/negative numerical audits; commit f47f36c. No executor or activation; physical benefits unmeasured. See overnight results for plan/review links. |

App worktrees: `/Users/dave/SGFPlayerClean-worktrees/`.
Laser worktrees: `/Users/dave/DYNAMIXEL-Go-Pointer-worktrees/`.
No camera-continuity policy changes, new firmware limits or physical actions are
part of these experiments. Adaptive learning remains separate from the optional integrated candidate; physical validation remains pending. Unfinished or uncertain candidates remain separate.

## Accepted behavior

- Dave prioritizes reliable gameplay over fast setup. Longer calibration is
  acceptable; test failure recovery and clock/history preservation before play.
- Initial calibration may analyze a stationary scene for longer than the live
  clearance budget. Keep geometric-measurement lifetime separate from current
  hand/movement evidence; changed scenes invalidate old results. The staged
  calibration-only policy is implemented and independently reviewed, not yet
  physically validated.

- Dave authorizes unattended **dark** heat testing while away, after software
  checks and a short monitored hold pass. Presence is not another approval gate.
  Two endurance attempts have stopped early; do not hide that as a two-hour pass.
  Dave now makes formal two-hour testing optional and prioritizes monitored play
  with automatic cooling fallback, temperature logging and recognition/marker tests.
- Prefer fast dark travel followed by bounded fine correction.
- Start the audible cue with laser activation; playback must not delay light.
  Also beep whenever Dave needs to look for a calibration/test spot.
- Ambient context: Dave reported 61°F (16.1°C), then raised the heating setpoint
  to 68°F (20°C) before visible calibration. Do not attribute all subsequent motor
  temperature rise to holding; the actual room warming curve is unmeasured.
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

## Transient lighting during calibration — November 23 follow-up

**Completed study:** at Dave's explicit request, `scene_change_detection` examined
16 historical comparisons and12 synthetic controls on isolated branch
`codex/scene-change-diagnostics`, latest commit `a7286f7` (pushed). Eight offline
tests pass; the follow-up compares edge direction and magnitude on historical
images and nine additional synthetic controls.
Its report separates camera/setup provenance and records limits: similar-colored
obstructions can defeat scalar residual tests. Recommended next work is structured
rejection diagnostics and dark pause/requalification, with complementary local
texture/occupancy and grid evidence. See
[scene-change study](/Users/dave/DYNAMIXEL-Go-Pointer-worktrees/scene-change-diagnostics/Firmware/Experiments/SceneChangeDiagnostics/README.md). Diagnostic results do not constitute physical validation; the existing live
checks remain unchanged during this study.

**Recenter physically validated:** initial-spot-04 was outside the unchanged
fresh-start interior margin. At Dave's request, `codex/calibration-recenter`
commit `8fd0630` adds fresh dual-reference/pose/spot qualification, measured K10
as direction evidence, up to eight dark steps capped at eight pan/five tilt counts,
and remeasurement after each. Independent targeted checks: 179 pass. Physical
`recenter-01` reached [3.05686, 3.09366] and confirmed full OFF. It does not create
or activate a calibration map. The subsequent full run stopped on stale camera
input, as recorded above; no further hardware run is active.

A single rejected optical measurement currently ends the full calibration.
The desired improvement is beam-off waiting with bounded attempts/time and
preserved valid progress, followed by genuinely fresh full scene/hand/identity
and motor-pose qualification before any relight. A changed setup, stale stream,
controller/thermal fault or uncertain pose must still stop. A similarity score
is not a probability; the0.94775 observed score does not justify lowering0.95.
This recovery behavior is proposed, not implemented or physically validated.

Dave refined the lighting requirement: give broad, gentle illumination changes
less weight than localized stone/hand-sized changes. Separate geometric grid
alignment, spatially smooth lighting and localized residual/edge changes rather
than replacing one global cutoff with a lower one. Broad area alone is insufficient:
large obstructions must not be normalized into lighting. Small objects must remain
visible to local checks even when whole-board scores look good.
An offline robust quadratic log-gain diagnostic on the saved rejected median
improved rectified correlation0.9578→0.9762, gradient correlation0.9800. Simple
synthetic stone/occlusion and shifted-grid controls retained residual changes;
the stone still had high global correlation, illustrating the need for local
connected-region/grid-visibility tests. These are different preprocessing/scores
from productionECC, not proof the original0.95 gate should accept this image.
No live threshold or classifier changed. Evidence is
`full-calibration-02/lighting-separation-diagnostic.json` in the session directory.

## Per-intersection appearance evidence — November 23

Completed offline study integrated as `8212400`; independent root replay agrees
with the stored-feature audit. See [intersection appearance study](../Experiments/IntersectionAppearance/README.md).
BoardVision already uses an intersection-specific empty reference; the learned
StoneAppearanceModel is inspector-only. The confirmed November 4 archive has
144 samples but only six points observed in all three states; it is separate
from the current moved setup. The historical proposal's occluded-to-empty error
prevents treating appearance agreement as hand clearance. No runtime change.
Dave additionally requested confidence for downstream combination. The completed design and illustrative JSON preserve class scores,
confidence/calibration status, visibility/abstention reason and shared-source
provenance for fusion. This is a documented contract, not an activated runtime API.

## Camera-age experiment and recovery — November 23

Dave explicitly clarified that the 0.6-second camera limit must not apply to
this stationary experimental run, and that transient camera delays should not
repeatedly destroy calibration progress. The prior long-run override covered only
overall/target deadlines, not this independent check; that implementation was
incomplete for his intended experiment.

- Experimental camera-age override is implemented as `98a2fb6` on an isolated
  pushed branch; 219 targeted checks and independent review pass. Explicit
  10-second policy reaches metadata, optical and PNG reader paths; ordinary
  defaults remain 0.6 seconds. Physical initial-spot-05 passed and confirmed
  full OFF. Its maximum observed age was 0.367 seconds, so physical validation
  of an over-0.6-second frame remains outstanding (offline replay covers it).
  App lease, polling cache, causal post-movement/post-light frames, geometry,
  controller and thermal checks remain. Accepting older frames necessarily
  increases potential unseen-hand latency; observed obstruction still rejects.
- `architecture_review` owns independent review. `fast_calibration` separately
  owns full-OFF recovery and progress-preserving requalification, using new
  workers/session and actual pose/spot; poisoned cancellation state is not reset.
  Interrupted motor commands must not be replayed from assumed positions.
- Recovery remains in progress, not physically tested. The camera-age experiment
  is run directly from its reviewed host branch; installed app/firmware unchanged.
  The explicit 16-step recenter allowance (`424f3a5`) passed independent review
  and 171 calibration checks; physical recenter-02 succeeded in 12 steps.
  Per-step caps remain unchanged. Hardware is fully OFF pending recovery review.
  A 45-second passive audit recorded 756 metadata observations,
  448 unique frames, median capture age 0.233 seconds and maximum 0.545 seconds;
  this does not negate the recorded earlier 0.615-second expiry under active work.

### Polling-cache interruption and speed follow-up

The 10-second camera experiment did not fail on camera age. A separate 250ms
polling-cache deadline expired during a shared-process scheduling gap; camera
and app lease remained valid. Serial/thermal/heartbeat threads also show a gap,
so thread separation alone does not establish independent supervision. The exact
blocking function is not yet proven. `occupied_board_timing` is investigating
this offline; `fast_calibration` is implementing reviewed progress-preserving
full-OFF recovery and historical validation-only resumption. New sessions/workers
and fresh actual pose/spot are mandatory; interrupted commands are not replayed.

[Calibration speed proposal](CalibrationSpeedProposal.md) recommends freezing a
fit-only candidate after the five fit targets and using bounded predictions to
reduce later validation travel. It also identifies excessive precision at
transit waypoints as a possible first-stage cost. These are proposals, not live
changes or measured speedups. Full-calibration-04 timing evidence is saved beside
the run: median spot collection 1.008s, median aggregation 0.233s, registration
0.362s (p95 2.808s), detection 0.309s; these are separate observed stage durations,
not an additive end-to-end latency breakdown.

### Recovery candidate reviewed and physical continuation started

`983ef924` is isolated on `codex/calibration-recovery` and pushed. Author checks:
194 calibration tests (one unrelated optional fixture group skipped) and 25 dark
tests; independent review: 31 focused tests with actual calibration-03/04 evidence,
no skips/failures. Mixed transport/cleanup errors cannot be silently treated as
camera interruptions; failure classification retains the actual deadline snapshot.
The historical continuation and fresh admission are now physically exercised;
automatic interruption/restart and complete nine-target validation remain unproven.
See [recovery design and command](/Users/dave/DYNAMIXEL-Go-Pointer-worktrees/calibration-recovery/Firmware/Calibration%20recovery.md).

Offline scheduling probes did not reproduce the live 322ms pause: image operations
kept synthetic heartbeat gaps below 40ms; forced garbage collection below 47ms.
Encoding the final large report produced a 350ms gap, but happens after shutdown
and therefore does not explain the live stop. Exact cause remains unproven.
The archived probe report recommends bounded stage/CPU/loop-gap/GC diagnostics.

### Larger-move prediction experiment — requested November 23

Dave requested larger moves to expose and model landing errors. Add a controlled
interior-point campaign after the dark return and steering requalification:
record the **first observed landing before correction**, predicted versus actual
position, measured settled motors, move length/direction and subsequent correction.
Use horizontal, vertical and diagonal spans, both directions, repeated endpoints
and approaches from different origins. Hold out complete directed transitions
from fitting; distinguish spatial distortion, directional bias and repeatability.
The camera stays fixed. The data-only plan is complete as `86bf0b9` on the
isolated adaptive branch: [large-move proposal](/Users/dave/DYNAMIXEL-Go-Pointer-worktrees/overnight-adaptive-calibration/Firmware/Experiments/AdaptiveCalibration/LARGE_MOVES.md).
Start with six short directed pilot moves; expand only if useful. The optional
larger matrix is not a requirement before gameplay. No new hardware executor or
physical movement was added by this proposal. The failed edge prediction is
explicitly excluded from training because no spot was observed.
