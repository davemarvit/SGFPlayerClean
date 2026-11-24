# Camera, AI and laser integration — current checklist

Updated: November 23, 2026 (Pacific time).

Maintain this document after meaningful changes or tests. Keep investigation
history in [LivePositionIssues.md](LivePositionIssues.md). Distinguish source,
offline verification, installation and physical validation.

## Current checkpoint

- **Hardware fully OFF; no active run or production driver.** Fresh
  `moved-setup-full-calibration-03` stopped after its first dark probe. Full v44
  OFF was confirmed at Unix **1795500739.5855656** and the process exited.
  Root retains sole hardware ownership. No gameplay binding is active.
- **Latest failure is inconsistent local boundary measurement.** Fresh B reported
  movement **3.989569 px from A / 4.049711 px from the original reference**.
  Saved-image diagnosis reproduces N1/O1 feature-selection instability and a
  native-versus-fitted sampling-guide mismatch. The other 70 boundary points
  differ by at most 0.159 px; independent whole-board registration differs by at
  most 0.053 px. This does not support a four-pixel whole-board movement. The
  cross-frame guard rejected inconsistent measurements under the current policy.
  N1/O1 discrepancies are about 0.072/0.059 grid cells. Global-only evidence
  misses local altered-line controls, so local visibility checks still matter.
  No code or threshold change has been made. Fast/architecture are reviewing the
  workflow and three-pixel gates before another patch; occupied-board timing is
  running a quantitative offline study of false stops versus missed movement or
  obstruction. **No new hardware run until reviewed results are available**.
  [Exact diagnosis](</Users/dave/Documents/SGF PLayer/work/ai-laser-integration/laser-position-recovery-20261123/moved-setup-full-calibration-03/boundary-jump-analysis/README.md>).
- **Accuracy requirement clarified:** Dave's original three pixels was an
  arbitrary final spot-to-intersection aiming preference. An initial landing
  farther away followed by correction is acceptable; a final error above three
  pixels is probably acceptable and should not itself stop the whole system.
  Separate aiming quality/convergence and recoverable measurement uncertainty
  from actual hazard/control checks. The current correction loop already accepts
  initial errors above three pixels; final-report rejection at ≥3 px and separate
  prediction/boundary aborts are under review. A three-servo-count limit uses
  different units and must not be conflated with this image-pixel preference.
- **Last optical pose and later settlement are distinct.** Full03 observed
  **2293/2391** at grid **[15.816780, 2.415560]**, then settled at **2312/2391**
  without a new optical observation. Do not plan from the earlier optical pose
  as though no later motion occurred. Fresh ownership, actual pose and optical
  qualification are required before further movement/light.
- **Latest tested source:** `acea4b341fcc78777556c3f56b14344aa1834de8`, branch
  `codex/midpoint-line-profiles`, in its same-named laser worktree. Midpoint
  sampling passed 120 tests and both independent seven-case focused reviews.
  Its stationary spot check and four-command motor-only inward recenter passed
  physically. Those checks do not qualify full-board calibration; all five
  fitting targets and nine independent validation checks still need a successful
  complete run. No partial-fit continuation or old-map fallback is approved.
- **User instruction remains motor-only.** Dave says nothing has been touched.
  Do not ask for a manual power-cycle, joint movement or housing re-aim that could
  disturb the webcam. Historical response estimates are not fresh steering
  authority. Beep when Dave must look for a spot.
- **Installed:** Physical Go **0.258/build 259**, source `87fc4a9`; firmware **v44**.
  [Build/paired acceptance](IntegratedPhysicalTestCandidate.md) passed; physical
  recognition/laser retests remain separate. Installed features include ambiguity
  guarding, fast-test idle reuse, recovery/progress, named stone sets, four practice
  positions and screen-only illegal feedback. No parallax/outline correction,
  adaptive learning or illegal laser pattern is active.
- **Saved practice:** paused empty Human Black, fast AI, zero moves/clocks,
  `EA70E983-9FAF-40ED-8939-312ED10A1A68`. Original five-move game
  `3D20B55B-DBE7-42E1-847E-3B82E60FF65A`, clocks and earlier three-move checkpoint
  have preserved backups; Return to saved game is available. **Root verified all
  six saved-game hashes unchanged after full03.** Preserve subsequent progress.
- **Camera/app:** empty board, app-owned FULL HD WEB CAM `0x11000000bda0567`,
  1920×1080. Use broker images, not screenshots. Connect laser bridge is ON for
  passive publication/OFF requests; recording/warnings OFF, timing logs ON.
  Camera-only tests can proceed separately with the bridge setting OFF and the
  production driver stopped. [Ordered test plan](NextPhysicalTestPlan.md).
- **Separate permission-timing issue remains unresolved.** Earlier startup
  app-lease expiry followed approximately 190 ms request-open plus 93 ms
  manifest-open windows. Exact filesystem/scheduling cause is unproven. This
  full03 boundary rejection is a different failure; successful later polling
  does not fix the earlier one. Calibration's experimental 10 s camera / 0.5 s
  cache settings do not transfer to ordinary gameplay.
- **Evidence and next-chat route:** [laser checkpoint](LaserMovementCheckpoint.md)
  contains the full03 result identity; [handoff](NextConversationHandoff.md)
  carries the current continuation instructions. Raw artifacts are under
  `laser-position-recovery-20261123`. Backup remains
  `/Users/dave/Documents/SGF PLayer/work/ai-laser-integration/stone-session-20261123/before-0258-install`.
  Preserve later progress when restoring. Historical attempts below are not
  current setup authority; root is updating the issue log and primary handoff.

## Parallel software work — current state

Hardware is OFF and app0.258 is installed. Experimental optics remain isolated;
selecting or saving a stone profile does not activate a correction.

| Workstream | Owner | Current state |
|---|---|---|
| Calibration optimizations and timing logs | Root, component authors and independent reviewers | Integrated on laser `codex/workflow-review-integration`, runtime3498fb2/documentation42e5022. All183 host/calibration/workflow tests plus38 model/importer tests pass. Native tracing remains opt-in; no hardware run or speed claim. |
| Historical timing importer | `workflow_timing_model` | Reviewed importer retains uncertain/missing boundaries; three actual reports exported. Included in integrated candidate. |
| Laser steering/settlement | `fast_calibration`, `adaptive_calibration`, reviewers | Latest host acea4b3: weak-image reobservation and motor-only inward recovery physically exercised; full03 stopped on local boundary measurement instability. Accuracy/recovery policy is being revised to reflect Dave’s clarified requirements. Full calibration and binding remain pending. |
| Ambiguous intersection assignment | `marker_scenarios`, `contract_review`, Root | Guard installed0.258;52 dedicated checks and related regressions pass. Same-camera negative photos saved; physical retest pending. Correct color, wrong intersection was the defect. |
| Stone-set profiles | Root, component authors/reviewers | Installed0.258; named picker/editor/storage tested. No optical correction activated. |
| Parallax/appearance estimate | `intersection_appearance`, `architecture_review` | Eight centered White and eight centered Black samples analyzed; six fitted/two held out per color. Reviewed only for unvalidated optical-candidate storage. Physical thickness remains unidentified; fresh Black/White negatives remain displaced after frozen correction; same-view grid consistency within0.54px. Independent setup pending. Native White-fit diagnosis independently reviewed at `e6a6e85`: exact pixel-vote and complete optimizer replay; no production optical fix. |
| Faster Pause/Resume testing | `latency_logging`, `contract_review` | Pushed `8c142a2`: 42 targeted checks plus AI-play162/AI-laser278/ambiguity52 pass. Only completed idle fast-test engine may survive ordinary pause; active work cancels. Installed0.258;67 final targeted checks pass. Earlier signed comparison builds are retained. |
| Combined physical-test app | Root, build_provenance, transport_review | Installed0.258 from87fc4a9, signed and independently verified; original game preserved and paused empty practice ready. Physical validation pending. |
| Full-boundary geometry evidence | `intersection_appearance`, `architecture_review` | Pushedb4184d5, independent review4c958ce. Frozen29 cases reproduce;7 controls pass. Shadow-contaminated outlines and round nonstone patches can pass geometry checks. Explicit diagnostic-only fields; no production promotion. |
| Fresh-image native detector replay | Root, `contract_review` | Pushed46b9cdd: actual archived697 footprint categories reproduce exactly;32 saved samples replayed. Fresh displaced Black has uncertain neighbor and off-center fit; displaced White has two uncertain crossings and no local fit. No temporal/controller acceptance or hint claim. |
| Repeatable capture-test fixtures | Root, capture_guidance, contract_review | Four practice choices installed0.258;166 checks pass. Empty practice loaded/verified; physical captures pending. |

## Immediate next steps

1. Begin the [physical test plan](NextPhysicalTestPlan.md) with bounded recording:
   hand/slow withdrawal, ordinary Black/White placement, halfway placement with
   hints off/on, removal and correct centering. The loaded practice is paused.
2. Check warm AI replies after ordinary Pause/Resume, then use the practice picker
   for single/two-prisoner removals. Follow its displayed coordinates; current
   orientation rotates the canonical fixture labels. Preserve the original game.
3. Check named profile persistence and prepared suicide/ko screen feedback.
   Optical correction and illegal-move laser patterns are not included.
4. Dave prioritizes laser-assisted testing. Finish the acceptance-policy review:
   separate useful aiming accuracy and recoverable image uncertainty from actual
   control hazards. Implement and replay the reviewed changes, then resume fresh
   calibration with motor-only recovery as needed. Qualify the complete map before
   activating a gameplay binding; do not reuse historical setup authority.
5. Once qualified, test cue/light timing, hand darkness, centering wiggle,
   captured-stone markers and monitored holding/cooling. No two-hour run is required.
6. Keep parallax/outline/map studies offline until their independent validation
   criteria pass. Update this checklist with actual physical outcomes.

## Work list

| # | Task | Current status / completion criterion |
|---|---|---|
| 0 | Faster AI test mode | Installed in0.258, eight visits/no HumanSL. Completed idle worker now survives ordinary Pause/Resume; hard faults, active searches and shutdown cancel it.67 final targeted checks pass. Offline real-engine cold/warm was8.275s/0.114s before the constructor-only test isolation change; no new physical speed claim. |
| 1 | Resolve motor movement faults | Unresolved physical interpretation. Untouched, released base reported raw speed +2 in 2 of 15 readings; encoder position varied one count. A dark FASTARM probe stopped before HOLD or movement. During endurance-02, 8,429 held sample pairs had speeds only 0/1; base encoder stayed 2422 and tilt ranged 2143–2144. These are different conditions, not an event-rate estimate or proof of no movement. Prepare an attended optical comparison; guards unchanged. |
| 2 | Finish laser calibration | Motor-only startup recovery passed on acea4b3; full03 stopped on local boundary feature ambiguity after its first dark probe. Hardware fully OFF; no map/binding. Review arbitrary pixel gates, recoverable uncertainty and useful final indication criteria, then complete fresh fit/validation. See current checkpoint. |
| 3 | Physically validate hand clearance | Two attended hand/slow-withdrawal cycles and ordinary live placement acceptance passed November 23. The stone did not leave a false hand flag. Hand-triggered beam shutoff remains untested; no exact withdrawal latency claimed. |
| 4 | Test moves and placement | Camera/AI ordinary placement passed Black72 → White180 → Black300 exactly once; ambiguity failed and narrow fix awaits physical retest. Laser indication and broader clock/capture cases remain pending. |
| 5 | Test captures | Physical tests pending. Verify delayed, single, multiple and partial removals and the intended clock policy. Offline tests preserve a legitimate cleanup-plus-reply while rejecting a remaining prisoner mistaken for a new move. |
| 6 | Reduce and measure move-to-laser delay | Fast approach/fine correction exists. Nonblocking simultaneous cue/light dispatch is implemented and tested offline; actual acoustic/optical timing is unverified. Measure first visible light separately from final pointing accuracy, for AI and online play. |
| 7 | Hold motors during active play | Implemented and offline-tested; app 0.258/v44 installed and short dark commissioning passed. Native opt-in, explicit game identity, two-stage OFF handshake, retain-only hand behavior, distinct held/cooling dark evidence, temperature current/max/trend, and hard-fault reset indication are offline-tested. Preserve 45°C cooling, below-40°C measured 30-second recovery and full release for pause/disconnect/fault. Production gameplay bridge remains stopped pending fresh calibration; opt-in is off. |
| 8 | Validate prolonged holding and cooling | Private v43 commissioning-03 passed 60.022s, 533 pairs, maximum 14°C, clean OFF. Endurance-02 stopped at 917.235s on the camera timestamp gate, maximum 16°C/17°C, current maxima 3mA/11mA. Reviewed v44 is now installed after the short dark pass. Firmware temperature/current/motion/USB/heartbeat/ACK checks and host interlocks are implemented and tested; causal freshness passed eight two-hour clock-drift simulations. Dave no longer requires a formal two-hour test; monitor temperatures during actual gameplay instead. Actual cooling transitions and seated noise remain unvalidated. Never restart automatically after a fault or raise limits to force a pass. |
| 9 | Fix ended-game grid recovery | Installed in 0.252; physically unvalidated. Ended AI history no longer constrains a cleared board; unfinished/paused games still do. The original failure and fix were reproduced against the archived empty-board recording and preserved 267-move SGF; 21 focused checks pass. Full recovery lifecycle regression also passes. Live finish/reopen workflow remains to check. |
| 10 | Test laser centering hints | Pending calibration and live clearance. Dave proposes a stricter centering tolerance when “Mark ambiguous stones” is enabled; mandatory uncertain-intersection abstention must remain active with hints off too. This is a proposed preference, not an implemented threshold change. Correct and misplaced White stones both measured offset0.28 in this session, so raw offset alone cannot choose the policy. Verify the hint marks the observed off-center stone without inventing its intended intersection, stops for a hand, clears after centering, and yields to placement/capture guidance. |
| 11 | Implement/test captured-stone indication | App installed in 0.252 and host source updated; production bridge remains stopped. Placement precedes prisoner indications; prisoners are indicated individually and silently, with positive dark evidence, capability checks and retained clock behavior. Current full-app tests: 42 state, 47 laser-contract and 37 controller checks; 29 host tests pass. Physical accuracy on both stone colors, partial/out-of-order removal, hand entry and cleanup clocks remain untested. Old saves without explicit capture context do not gain guidance from stale history. |
| 12 | Complete online-opponent integration | Pending. Protocol accepts online source, but native camera publication/observation is AI-only and lacks an authoritative online target producer. Wire moves/orientation and preserve server clocks before separately validating online placement, captures and timing. |
| 13 | Illegal-move feedback | Screen-only path installed0.258;69 actual-controller checks and83 mechanism checks pass. Fresh confident human additions use actual rules, excluding ambiguity, pending AI and prisoners. Physical suicide/ko/restoration checks pending. Distinct illegal laser pattern remains a proposal. |
| 14 | Modular project onboarding documentation | Created [AgentGuide](AgentGuide/README.md): nine focused pages with start/resume instructions, capability/subsystem/problem routes, source entry points and targeted validation. All 157 local link targets were checked. Linked from both AGENTS files and project READMEs. Scope is inspected code, durable handoffs and current conversation context; other historical chats were not available through tools. This checklist remains the live status authority. |
| 15 | Dependable new-setup calibration | Staged implementation independently reviewed: 93 calibration plus 24 dark tests pass, including actual retained images and movement/occlusion rejection. Geometry A may be analyzed dark for up to 3s; distinct fresh B verifies all 72 boundary points against A and the original reference. A expires 5s after capture; B retains 600ms freshness. Offline B proof took about 117ms. Physical validation pending. v44 run04 previously verified K10 within 1.86px; no full-board map is active. Commissioning metadata allowance is 250ms. Beep and stationary spot checks passed. No end-to-end setup speedup claimed. Use only the app broker. |
| 16 | Occupied-board processing latency | [Measured report](OccupiedBoardTiming.md): ten archived pairs, 79 usable observations. A two-stone pair takes ~1.3s while a crowded matched-reference pair takes ~0.15s; reference/lighting/convergence matter more than stone count alone. Isolated cropped-image prototype roughly halves slow positive cases, but some rejections become slower; no production gameplay integration. Empty-calibration verifier takes ~0.16–0.23s on the exact failed images and is being reviewed separately. Native camera pipeline remains untimed. |
| 17 | Gameplay continuity on device faults | Installed0.258. Scoped fault pause preserves history, pending placement, prisoners and clocks; explicit recovery and physically confirmed camera-only fallback are implemented. Fresh paired acceptance with exact host42e5022 passes229 export/241 status/495 recovery checks and225/133 controls. Physical recovery remains unvalidated; online clocks remain authoritative. |
| 18 | Continuous laser-map refinement during play | Dave authorized advance software/literature work overnight after initially deferring this. An isolated offline/shadow prototype now compares baseline, global offset and bounded local residual correction using actual measured poses/spots, confidence/provenance and chronological validation. Separate reviewed branch; no live learning or map activation. Retain baseline model and rollback; distinguish raised stones, outliers and changed equipment. Independent algorithm and campaign reviews complete; 56 tests pass. Cleared-board survey plan covers 25 fit + 24 reserved locations (130 episodes with approaches/anchors), optionally all361. First aim and final metrology remain separate; no hardware executor. Physical validation follows initial calibration/gameplay baseline. |
| 19 | Initial-calibration progress UI | Installed in0.258 and independently reviewed; physical validation pending. Actual stage/target, five calibration plus nine accuracy checks, elapsed/stage time and stale/stopped/shutdown-unconfirmed/review-required states. No unsupported ETA. Passive asynchronous publishing cannot interrupt shutdown; injected publisher-failure tests pass. 26 native checks, SwiftUI typecheck and 128 calibration/progress/dark tests pass. Registered as `--calibration-progress-test`; final four-suite app regression and eight build-registry checks pass. Signed full app build and signature/source-hash verification passed; visual/physical validation pending. See [progress UI](CalibrationProgressUI.md). |
| 20 | Overall architecture and development-process review | [Review completed](ArchitectureReview.md). Existing app/host/controller boundaries are sound; no wholesale rewrite recommended and no new immediate source blocker found. Prioritize a pure scoped recovery/admission state machine, explicit status meanings, paired transition tests, measured I/O isolation and immutable build snapshots. Camera-failure clock policy needs an explicit decision before claiming complete/unattended reliability. At Dave’s subsequent authorization, reducer extraction, build/source provenance and paired acceptance are implemented and reviewed on isolated overnight branches; installed0.258 integrates them. Remaining recommendations include measured I/O isolation and explicit camera-failure clock policy. |
| 21 | Unified workflow and timing contract | Implemented and independently reviewed offline on pushed `a4867ea`, branch `codex/workflow-timing-model`: 64 stages, eight parallel lanes, 37 timing options, generated event schema and selected-path collection plans; 23 tests pass; seven outcome definitions include move-to-light, centering, cue/light skew and failure-to-OFF. [Design and usage](https://github.com/davemarvit/DYNAMIXEL-Go-Pointer/blob/a4867ea1f713648aee7b817127411750c89903ef/Firmware/Experiments/WorkflowTiming/README.md). Existing-log inventory identifies collection gaps. Runtime adoption and historical-report migration are integrated offline in3498fb2;183 host/workflow plus38 model/importer tests pass. Bounded native logging is enabled for the current0.258 launch; installed timing policies are unchanged. |
| 22 | Named stone sets and parallax correction | Named picker/editor/storage installed0.258;32 model +15 independent +18 hosting checks pass. New set/Cancel UI checked. Optional measured Black/White thickness may remain unknown; selection does not alter recognition. Optical studies remain offline; physical thickness and independent-setup portability are unidentified. |
| 23 | Reject ambiguous intersection assignments | Guard installed0.258;52 dedicated checks and related regressions pass. Halfway White was correctly colored but wrongly assigned in earlier physical test; retest both colors, hints off/on, removal and deliberate centering. Mandatory assignment abstention remains active regardless of hint preference. |
| 24 | Separate full-boundary geometry from classification | Frozen offline experiment b4184d5/review4c958ce:29 cases and7 controls reproduce. Shadow-contaminated supported center can err0.118cells; nonstone dark disk also passes. Every output is diagnosticOnly/stoneVersusShadowUnverified; no runtime consumer or accuracy improvement claim. Native fresh replay separately shows missing White midpoint footprint. |
| 25 | Repeatable attended capture fixtures | Four paused fast-mode practice choices installed0.258: empty Human Black/White, single and two White prisoners.166 persistence/controller checks pass. Live empty-Human-Black load and relaunch preserve original game bytes exactly. Capture-removal physical tests remain pending; use displayed orientation-aware instructions. |

## Isolated overnight improvements (November 23)

Dave authorized reversible software improvements while away, including extra
latency logging and adaptive-calibration research/prototyping. Hardware work is
still deferred. Earlier0.254/0.255 artifacts remain preserved; their reviewed core changes are now
in installed0.258 for the recognition retest; experiments
are not automatically promoted.
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
with the stored-feature audit. See [intersection appearance study](https://github.com/davemarvit/SGFPlayerClean/blob/8212400/PhysicalGo/Experiments/IntersectionAppearance/README.md).
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
