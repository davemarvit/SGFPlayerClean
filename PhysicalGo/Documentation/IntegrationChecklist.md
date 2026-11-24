# Camera, AI and laser integration — current checklist

Updated: November 23, 2026 (Pacific time).

Maintain this document after meaningful changes or tests. Keep investigation
history in [LivePositionIssues.md](LivePositionIssues.md). Distinguish source,
offline verification, installation and physical validation.

## Current checkpoint

**Current integration in progress:** reviewed source `e5e2395` on
`codex/integrated-physical-test-candidate` is preparing 0.258/build 259.
It combines recovery/progress/optional timing logs, ambiguity protection,
fast-test idle reuse, named stone-set controls, illegal-move screen feedback
and four reversible practice positions. The combined regression build is running;
installation and physical validation remain pending. See the
[consolidated physical test plan](</Users/dave/SGFPlayerClean-worktrees/integrated-physical-test-candidate/PhysicalGo/Documentation/NextPhysicalTestPlan.md>).
This supersedes the older recommendation below to install 0.257 next.
Latest user report says eight Black stones; the earlier photo showed seven Black
and one displaced White. No fresh visual claim is made. Laser calibration still
needs an empty board and resolution of the saved steering disagreement.


- **Installed: Physical Go 0.253/build 254 and v44 firmware.** The app is paused
  at move 5 with an unplaced AI Black stone. The board holds seven centered Black
  calibration stones and one deliberately displaced White near raw (14.5,9).
  Do not Resume against that mismatch. The failed game and earlier good
  three-move checkpoint are preserved, including clocks.
- **Hardware is fully OFF.** Last confirmed full OFF was Unix
  1795478146.9190755 after manual-validation-01; no later hardware commands.
  Production bridge is stopped. The app's bridge setting is ON only to publish
  passive camera samples and OFF requests. Diagnostic recording and warnings are
  OFF. Root remains sole hardware owner.
- **Recommended next test app: 0.257/build 258, built and independently verified.**
  Pushed `7edf1b0` on `codex/recognition-fast-test-candidate`; version/source
  commit `47dc15b` combines narrow ambiguity baseline `347eb84` with reviewed
  fast-test idle reuse `8c142a2`. Optimized build and eight registry checks pass.
  Independent packaging review verifies signature, 158 source inputs, four build
  inputs and all 173 bundle files. Capture directory is preserved. The candidate
  is frozen read-only and has not been installed or launched. Installed 0.253 and
  signed narrow 0.256 remain unchanged for rollback/comparison.
  [Candidate and verification receipts](</Users/dave/Documents/SGF PLayer/work/ai-laser-integration/stone-session-20261123/app-0257-candidate/README.md>).
  The narrow guard passed five suites (52 ambiguity, 80 marker, 146 lifecycle
  checks plus real engines, 278 AI-laser, 37 capture-controller). Idle reuse
  additionally passed 42 focused checks and AI-play162/AI-laser278/ambiguity52.
  Neither optical profile nor boundary experiment is included in the app.
- **Attended recognition:** two hand/slow-withdrawal cycles and ordinary
  Black72 → White180 → Black300 acceptance passed. A halfway White stone was
  correctly classified White but wrongly assigned to 275, followed by AI288.
  This failed ambiguity test motivated the narrow fix. Both diagnostic recordings
  are retained with KEEP; the first reached its 5GB session cap, not a full disk.
  Capture handling and laser markers remain physically untested.
  [Session evidence](</Users/dave/Documents/SGF PLayer/work/ai-laser-integration/stone-session-20261123/session-result.json>).
- **Fast AI is active at eight visits.** Observed acceptance-to-reply time was
  9.047s after Pause/Resume and 1.174s on the next uninterrupted move. Cold worker
  restart likely explains the difference; the load/search split was not measured.
  Separate reviewed idle-worker reuse candidate `8c142a2` passes 42 targeted
  checks plus AI-play 162, AI-laser 278 and ambiguity 52 regression checks. It is
  included in signed 0.257, not installed; signed 0.256 remains the guard-only comparison.
- **Stone-set evidence is saved:** eight centered outer-star White and Black
  stones, eight fresh camera samples per color. An accidental second White pass
  is explicitly labeled `white-repeat-01`, never Black. Profiles, optional manual
  thickness, and six-fit/two-held-out optical estimates are reviewed offline
  candidates only. Physical thickness and portability remain unidentified.
  Fresh displaced Black and White episodes are now saved at raw (14.5,9);
  Frozen-model comparison preserves displacement: nearest crossing distance
  Black 0.434–0.461 cells, White 0.484–0.488 across two geometry hypotheses.
  Independent review `201a258` reproduces all results. This location was a
  training anchor, not the preselected held-out location. Independent setup
  remains pending.
- **White centering mechanism independently reproduced.** Native replay and a
  separate recomputation of all 8,450 pixel votes and the complete fit search
  show the brightness cutoff/objective favoring the upper bright region. Native
  centers are about 0.11 row above independent visible-body estimates in both the
  centered and misplaced examples. This is estimator disagreement, not a
  measurement of physical stone height. The next geometry study should retain
  full-boundary evidence, uncertainty and abstention separately from color.
  No optical correction is installed. See the [camera guide](AgentGuide/CameraRecognition.md).
- **Latest laser stop was a prediction disagreement, not a timeout.**
  Manual-validation-01 passed fresh optical and steering qualification, then
  planned [1681,2289] passed at 2.143px while actual settlement [1681,2287]
  failed the unchanged 3px gate at 3.172px. There is no fresh optical observation
  at that settled pose. All nine accuracy targets remain pending and no gameplay
  binding is active. Better fitting alone still fails the full settlement-region
  checks; a richer bounded-probe protocol is studied offline, not executed.
  [Detailed laser checkpoint](LaserMovementCheckpoint.md).
- **Combined calibration optimizations and workflow logging pass offline.**
  Laser `codex/workflow-review-integration` runtime `3498fb2`, documentation
  `42e5022`: 183 host/calibration/workflow plus 38 model/importer tests pass.
  Earlier aggregate errors were incomplete test doubles, now corrected. Tracing
  is opt-in and unactivated. This does not resolve the physical steering stop.
- **Thermal/holding validation remains partial.** Dark holding commissioning
  passed; earlier endurance held about 15 minutes before a camera interlock,
  maximum reported 16/17°C. No two-hour, cooling-transition or noise/power pass is
  claimed. Dave prefers monitored gameplay with cooling fallback.
- Earlier signed 0.254/0.255 candidates remain separate and uninstalled. See
  [overnight results](OvernightSoftwareResults.md) for those broader changes;
  0.257 now combines the focused recognition fix and idle fast-test reuse. The
  narrower 0.256 remains available for comparison.
- Dave briefly returned and supplied both displaced-color examples; no more
  physical input is needed for their offline comparison. Preserve camera/setup. No
  acknowledged external laser-agent dependency is outstanding. Historical
  experiments and original source checkpoints remain in the issue history.

## Parallel software work — current state

Hardware is OFF and app0.253 remains installed. These candidates are isolated;
selecting or saving a stone profile does not activate a correction.

| Workstream | Owner | Current state |
|---|---|---|
| Calibration optimizations and timing logs | Root, component authors and independent reviewers | Integrated on laser `codex/workflow-review-integration`, runtime3498fb2/documentation42e5022. All183 host/calibration/workflow tests plus38 model/importer tests pass. Native tracing remains opt-in; no hardware run or speed claim. |
| Historical timing importer | `workflow_timing_model` | Reviewed importer retains uncertain/missing boundaries; three actual reports exported. Included in integrated candidate. |
| Laser steering/settlement | `fast_calibration`, `adaptive_calibration` | Actual3.172px failure reproduced. Better rolling fits alone still fail full settlement-region checks; current motion samples poorly constrain the other axis. Bounded richer-probe protocol and offline feasibility study completed at `927b63b`, eight tests pass; no production fix or physical execution. |
| Ambiguous intersection assignment | `marker_scenarios`, `contract_review`, Root | Guard in signed0.256 and combined0.257;5/5 narrow suites pass. Same-camera negative photos saved; installation and physical retest pending. Correct color, wrong intersection was the defect. |
| Stone-set profiles | `calibration_progress_ui`, `contract_review` | Isolated named picker/editor/storage on pushedbf241bc:34 author and15 independent checks, SwiftUI typecheck pass. Not hosted in app and not applying vision changes. |
| Parallax/appearance estimate | `intersection_appearance`, `architecture_review` | Eight centered White and eight centered Black samples analyzed; six fitted/two held out per color. Reviewed only for unvalidated optical-candidate storage. Physical thickness remains unidentified; fresh Black/White negatives remain displaced after frozen correction; same-view grid consistency within0.54px. Independent setup pending. Native White-fit diagnosis independently reviewed at `e6a6e85`: exact pixel-vote and complete optimizer replay; no production optical fix. |
| Faster Pause/Resume testing | `latency_logging`, `contract_review` | Pushed `8c142a2`: 42 targeted checks plus AI-play162/AI-laser278/ambiguity52 pass. Only completed idle fast-test engine may survive ordinary pause; active work cancels. Included in signed0.257; not installed. Signed0.256 is retained separately. |
| Combined recognition/fast-test app | `build_provenance`, Root | Pushed7edf1b0; optimized signed0.257/build258 independently verified and frozen. Installed0.253/signed0.256 unchanged. Not installed or launched. |
| Full-boundary geometry evidence | `intersection_appearance`, `architecture_review` | Pushedb4184d5, independent review4c958ce. Frozen29 cases reproduce;7 controls pass. Shadow-contaminated outlines and round nonstone patches can pass geometry checks. Explicit diagnostic-only fields; no production promotion. |
| Fresh-image native detector replay | Root, `contract_review` | Pushed46b9cdd: actual archived697 footprint categories reproduce exactly;32 saved samples replayed. Fresh displaced Black has uncertain neighbor and off-center fit; displaced White has two uncertain crossings and no local fit. No temporal/controller acceptance or hint claim. |
| Repeatable capture-test fixtures | `capture_guidance`, Root | Pushedf0009e9: single/two-prisoner four-move human-Black fixtures, fast mode,34 actual rules-engine and20 actual-controller checks pass. No AI SGF import/picker; activation remains an explicit preserved-state transaction. No current-game edits. |

## Immediate next steps

1. Fresh Black/White negative comparison is complete without refitting: both
   remain displaced after the frozen correction. The user sits at camera-image
   right, so raw (15,9) moved toward (14.5,9), not held-out raw (9,15). These are
   fresh episodes at a previously fitted location. The app made a small grid
   adjustment; exposed crossings establish same-view consistency within 0.54px,
   retained as uncertainty. This is not an installed-app acceptance test.
2. Install the verified combined0.257 candidate for recognition/fast-AI tests,
   retaining signed0.256 for comparison and saved0.253 for rollback. Preserve the failed paused game/history/clocks. Deliberately
   recover the saved three-move test checkpoint before resuming physical play;
   current logical game has five moves and the board now holds eight calibration
   stones (seven Black, one displaced White). Do not press Resume against that mismatch.
3. Retest halfway placement, removal and correct centering, with hint preference
   both off/on. The fix blocks uncertain assignment; it does not yet promise a
   laser marker or parallax-corrected center. Then test ordinary placement and
   controlled captures using retained recordings.
4. Return to laser work only with an empty board and verified equipment setup.
   The blocker is steering-response/settlement disagreement, not a run timeout.
   Review the richer response evidence/probe plan before another attempt. All
   nine accuracy targets and final binding activation remain pending.
5. After laser qualification, test monitored holding, hand-triggered darkness,
   move indication, centering hints and single/multiple captured-stone markers.
   The [capture run card](</Users/dave/Documents/SGF PLayer/work/ai-laser-integration/attended-capture-kit-20261123/RUN_CARD.md>) avoids waiting for a random AI capture. Check partial removal,
   cue priority and clock behavior. Thermal cooling transitions remain unvalidated.
6. Keep stone-set estimates offline until misplaced-stone negatives and independent
   setup checks pass. Improve White body-center measurement and distinguish
   parallax, printed-grid error and estimator bias. Optional physical thickness
   entry and named profiles are available as reviewed source candidates only.

## Work list

| # | Task | Current status / completion criterion |
|---|---|---|
| 0 | Faster AI test mode | Installed and enabled since 0.251. Eight visits, no HumanSL, warm worker retained between replies. Normal opponent profile is preserved. Latest regression measured 12.904s cold and 0.219s warm; earlier run was 9.090s/0.170s. Real engine and four normal HumanSL profiles pass. Ordinary physical camera/AI moves passed November 23; laser indication awaits calibration. Separate reviewed idle-worker reuse through Pause/Resume passes three regression suites at `8c142a2`; not installed. |
| 1 | Resolve motor movement faults | Unresolved physical interpretation. Untouched, released base reported raw speed +2 in 2 of 15 readings; encoder position varied one count. A dark FASTARM probe stopped before HOLD or movement. During endurance-02, 8,429 held sample pairs had speeds only 0/1; base encoder stayed 2422 and tilt ranged 2143–2144. These are different conditions, not an event-rate estimate or proof of no movement. Prepare an attended optical comparison; guards unchanged. |
| 2 | Finish laser calibration | Partial. Complete moved-setup coverage/accuracy checks and activate a fresh binding. Reset transient camera evidence and capture a dark empty-board reference before gameplay. |
| 3 | Physically validate hand clearance | Two attended hand/slow-withdrawal cycles and ordinary live placement acceptance passed November 23. The stone did not leave a false hand flag. Hand-triggered beam shutoff remains untested; no exact withdrawal latency claimed. |
| 4 | Test moves and placement | Camera/AI ordinary placement passed Black72 → White180 → Black300 exactly once; ambiguity failed and narrow fix awaits physical retest. Laser indication and broader clock/capture cases remain pending. |
| 5 | Test captures | Physical tests pending. Verify delayed, single, multiple and partial removals and the intended clock policy. Offline tests preserve a legitimate cleanup-plus-reply while rejecting a remaining prisoner mistaken for a new move. |
| 6 | Reduce and measure move-to-laser delay | Fast approach/fine correction exists. Nonblocking simultaneous cue/light dispatch is implemented and tested offline; actual acoustic/optical timing is unverified. Measure first visible light separately from final pointing accuracy, for AI and online play. |
| 7 | Hold motors during active play | Implemented and offline-tested; app 0.253/v44 installed and short dark commissioning passed. Native opt-in, explicit game identity, two-stage OFF handshake, retain-only hand behavior, distinct held/cooling dark evidence, temperature current/max/trend, and hard-fault reset indication are offline-tested. Preserve 45°C cooling, below-40°C measured 30-second recovery and full release for pause/disconnect/fault. Production gameplay bridge remains stopped pending fresh calibration; opt-in is off. |
| 8 | Validate prolonged holding and cooling | Private v43 commissioning-03 passed 60.022s, 533 pairs, maximum 14°C, clean OFF. Endurance-02 stopped at 917.235s on the camera timestamp gate, maximum 16°C/17°C, current maxima 3mA/11mA. Reviewed v44 is now installed after the short dark pass. Firmware temperature/current/motion/USB/heartbeat/ACK checks and host interlocks are implemented and tested; causal freshness passed eight two-hour clock-drift simulations. Dave no longer requires a formal two-hour test; monitor temperatures during actual gameplay instead. Actual cooling transitions and seated noise remain unvalidated. Never restart automatically after a fault or raise limits to force a pass. |
| 9 | Fix ended-game grid recovery | Installed in 0.252; physically unvalidated. Ended AI history no longer constrains a cleared board; unfinished/paused games still do. The original failure and fix were reproduced against the archived empty-board recording and preserved 267-move SGF; 21 focused checks pass. Full recovery lifecycle regression also passes. Live finish/reopen workflow remains to check. |
| 10 | Test laser centering hints | Pending calibration and live clearance. Dave proposes a stricter centering tolerance when “Mark ambiguous stones” is enabled; mandatory uncertain-intersection abstention must remain active with hints off too. This is a proposed preference, not an implemented threshold change. Correct and misplaced White stones both measured offset0.28 in this session, so raw offset alone cannot choose the policy. Verify the hint marks the observed off-center stone without inventing its intended intersection, stops for a hand, clears after centering, and yields to placement/capture guidance. |
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
| 21 | Unified workflow and timing contract | Implemented and independently reviewed offline on pushed `a4867ea`, branch `codex/workflow-timing-model`: 64 stages, eight parallel lanes, 37 timing options, generated event schema and selected-path collection plans; 23 tests pass; seven outcome definitions include move-to-light, centering, cue/light skew and failure-to-OFF. [Design and usage](https://github.com/davemarvit/DYNAMIXEL-Go-Pointer/blob/a4867ea1f713648aee7b817127411750c89903ef/Firmware/Experiments/WorkflowTiming/README.md). Existing-log inventory identifies collection gaps. Runtime adoption and historical-report migration are integrated offline in3498fb2;183 host/workflow plus38 model/importer tests pass. Native logging remains opt-in and unactivated; installed timing policies are unchanged. |
| 22 | Named stone sets and parallax correction | User requested automatic estimates saved per named set, with optional measured Black/White thickness. Profile UI/model candidatebf241bc passes34+15 checks and typecheck; not integrated. Hardened optical study `8f692b3` and review `c7286b1` permit offlineCandidate storage only. Eight centered stones per color collected; six-fit/two-held-out analysis and White development negative complete. Fresh Black/White negatives captured at previously fitted side-middle location; frozen-model comparison retains displacement for both colors; independent setup pending. Physical thickness, optical height, grid units and metric scale are separate. |
| 23 | Reject ambiguous intersection assignments | Attended White midpoint was classified White correctly but assigned incorrectly. Narrow0.256 source347eb84 requires fresh neighboring evidence;52 dedicated checks and four related suites pass; signed candidate and rollback saved. Physical retest pending. Marker strictness preference cannot disable mandatory assignment abstention. |
| 24 | Separate full-boundary geometry from classification | Frozen offline experiment b4184d5/review4c958ce:29 cases and7 controls reproduce. Shadow-contaminated supported center can err0.118cells; nonstone dark disk also passes. Every output is diagnosticOnly/stoneVersusShadowUnverified; no runtime consumer or accuracy improvement claim. Native fresh replay separately shows missing White midpoint footprint. |
| 25 | Repeatable attended capture fixtures | Pushedf0009e9, artifact-only four-move human-Black positions for single/two White prisoners. Fast mode true,34 rules-engine+20 controller checks, preserved-state loading boundary and short run card. Neither live fixture loading nor physical removal/laser pass performed. |

## Isolated overnight improvements (November 23)

Dave authorized reversible software improvements while away, including extra
latency logging and adaptive-calibration research/prototyping. Hardware work is
still deferred. Earlier0.254/0.255 remain separate staged candidates. The next focused
recognition retest uses the combined0.257 candidate described above; experiments
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
