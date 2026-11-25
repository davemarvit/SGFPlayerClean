# Offline issue-owner coordination

Dated November24,2026. This is an assignment/evidence ledger, not a replacement issue register. [IntegrationChecklist.md](/Users/Dave/SGFPlayerClean/PhysicalGo/Documentation/IntegrationChecklist.md) remains authoritative; root alone edits it and owns integration, install and all hardware. All31 open scopes have27 owners. No issue is closed by this ledger.

Constraints: offline only; no camera acquisition, serial/controller, app launch/quit, UI mutation, installation, gameplay activation or screenshots. Preserve games, clocks, calibration and raw evidence. Frozen native0628a33 and host2da3c29 remain immutable. New codex sparse worktrees only for edits. Total new disk budget8GB. Coordinator grants at most1Swift build and2heavy jobs overall; no mass builds.

|Scope|Owner under `/root/issue_coordinator/`|Next action|Existing evidence|Declared remaining acceptance|
|---|---|---|---|---|
|PG00|pg00_ai_latency|Trace actual cold/warm worker identity|Historical8.275s/0.114s;67reuse checks|Physical cold/warm reply latency|
|PG01|pg01_stability|Audit synchronized optical/encoder evidence|Released30samples;held8458pairs;optical sync absent|Controlled optical stationary/stepping comparison|
|PG02|pg02_calibration_model|Spatial frozen-model/response audit|97retained observations;three-point and feedback runs|Qualified spatial errors and reuse documented|
|PG03|pg03_hand_state|Complete temporal tracker checkpoint/replay|Checkpoint misses temporal state|False warning fix plus physical entry/withdrawal/message clear|
|PG04|pg04_acceptance|Paired point conversation/both-color lifecycle|Existing paired runtime only standby|Complete attended gameplay flow|
|PG05|pg05_captures|Single-prisoner both-color lifecycle tests|Multi-capture tests already present|Physical single/multiple/partial removal and clocks|
|PG06a|pg06a_freshness|Concurrent blocked-read freshness tests|Independent600ms safety cache implemented|Sustained600ms play and bounded recovery|
|PG06b|pg06b_step_policy|Bounded edge step planner|K18=15moves;15px cap;7d8b530 optical candidate|Measured live latency with containment|
|PG07|pg07_holding|Combined hand/cooling/resume/OFF regression|v44/schema2 existing|Current paired holding/hand/resume physical pass|
|PG08|pg08_thermal|Cooling reheat eligibility regression/fix|Baseline reproduces >=40C stale eligibility|Reviewed firmware and physical cooling/reengagement|
|PG09|pg09_17_continuity|Pause ordering/reopen regressions|Cancellation precedes freeze|Physical finish/reopen preserving unfinished state|
|PG10|pg10_center_hints|Cancel moved/color-changed stale hint|0.12–0.18cell stale-target gap|Physical center targeting/hand/removal|
|PG11|pg05_captures|Silent capture placement-first identity tests|Existing multi-capture suite|Physical ordering/partial cleanup|
|PG12|pg12_online_targets|Inert authoritative online target producer|Existing OGS native state bridge|Server-clock-safe native laser integration|
|PG13|pg13_illegal_moves|Both-color ko/suicide/full restoration tests|Existing tests asymmetric|Physical illegal/restoration pass|
|PG14b|pg14b_20_architecture|Repair stale guides;review boundaries|Canonical register root-owned|Ongoing docs accurate after integration|
|PG15|pg15_19_setup_progress|Minimal workflow passive progress contract|Three-point experiment complete|Usable startup/recovery and measured setup time|
|PG16|pg16_camera_latency|Port1f28d4c and workload-aware summarizer|Prior54hand/stone+26trace checks|Occupied native/host tail attribution|
|PG17|pg09_17_continuity|Freeze clocks before cancellation|Existing transient/3s tests|Fault/reopen physical continuity|
|PG18|pg18_learning|Raw receipt validated passive collector/held-out score|Reuse3ad106c;tails regressed|Provenance/scoring/rollback;no live promotion|
|PG19|pg15_19_setup_progress|Explicit three-point/feedback display modes|Current full5+9 display|Accurate counts/timing without activation authority|
|PG20|pg14b_20_architecture|Cross-change architecture review|Reducer/immutable paired boundaries|Installed combination physical verification|
|PG21|pg21_first_fault|Bounded opt-in first rejection archive|Post-verdict reason lacks exact pre-state|First image/checkpoint/timing retained|
|PG22|pg22_parallax|Leakage-safe passive placement evaluator|Reuse d0ed574 static study|Held-out evidence;no auto correction|
|PG23|pg23_ambiguity|Both-color hints off/on persistence regressions|52focused checks|Physical halfway placements|
|PG24|pg24_frame_diff|Review7d8b530 and stationary-hand controls|Existing regional study includes occupied controls|No stale clearance inference;expanded evidence|
|PG25|pg25_practice_fixtures|Restart/failed restore/backup-corruption tests|166existing checks|Physical fixtures preserve original snapshot|
|PG26b|pg26b_audio|No-audio cancellation/generation click tests|Existing first-light logic|Audible AirPod Pro3 new-move click|
|PG31|pg31_alignment_review|Independent saved-image control sweep|002e4c7;204native checks;exact18per edge|Moved/covered rejection and physical stability|
|PG32|pg32_serial_fault|Independent diagnostic sinks/fault attribution|16mock tests;original cause unavailable|Captured cause/recovery and sustained play|
|PG33|pg33_feedback_gameplay|Explicit safe feedback gameplay route|Seed benchmark separate from gameplay|Paired tests/install/attended game|

## Integration dependencies

PG33 depends on reviewed PG31/06a/06b/07/32 contracts and PG04 executable paired point conversation. PG03 owns tracker checkpoint internals; PG21 owns retention/capture. PG00,PG09/17,PG10 touch distinct PhysicalAI.swift regions and need combined native review. PG15/19 owns progress callbacks; PG06b owns collector step planning. PG18 and PG22 are passive offline collectors with separate laser/stone semantics. All candidate source/test/install/physical states must be reported separately.

## Resource queue

Root released Swift slot after PG31 four suites204checks. PG31 independent saved-image controls has first heavy vision slot. Other vision work waits. Native focused suites queued by readiness; no app install by workers.


## Reviewed checkpoint batch

All entries below are offline-only and not installed or physically verified. No issue closure is implied.

|Scope|Commit|Evidence / integration status|
|---|---|---|
|PG01|212a160|8analyzer tests; no synchronized optical evidence, no mechanical attribution|
|PG03|56e8740|623hand checks; complete temporal checkpoint; PG21 capture complementary|
|PG05/11|d82473a|120checks,40new; test-only both-color single capture|
|PG06a|9dcb5ab|33pass,1native-export skip; blocked refresh, unchanged600ms policy|
|PG07|e74134a|47holding tests; rerun with PG33 candidate|
|PG08|71e8df6|Firmware reheat eligibility defect;7600new+6686existing sanitizer assertions; root review/upload decision pending|
|PG13|5424b03|139both-color illegal/restoration checks; test-only|
|PG14b/20|0b3b668|150local links; stale guide repairs and integration review|
|PG24|7f7623f|19regional+6median checks; recommends7d8b530 for paired integration, no live regional authority|
|PG31|82be920|Independent review of002e4c7;38controls/76invocations,14expectations pass; no blocker|
|PG32|c590b44|65checks; independent diagnostic sinks, original physical cause unresolved|

Fresh-context cross_change_review is an additional read-only reviewer, prioritizing PG33 and PG08. Initial PG33 findings: post-PREPARE actual settlement/containment must precede every light; final optical sample must remain fresh; per-indication DARK cooling requires state-aware resume and fresh pose. Owner repairing; review not yet complete.

Minimal initial-game candidate batch is root-owned: native002e4c7 plus necessary PG03/PG09-17 fixes; host7d8b530,c590b44,PG06a tests,PG06b planner and PG33. Online/parallax/centering/illegal/progress work continues independently and must not delay initial supervised play. Source commits never authorize activation.

## Further checkpoint batch and build ownership

|Scope|Commit|Validation / remaining work|
|---|---|---|
|PG00|0c1811e|10Python checks; native validation pending combined runtime|
|PG02|c18fa8c|11checks,76held-out observations; retrospective only, no steering promotion|
|PG06b|1d2770f|56pass/2archive skips; static review no blocker under conditional response envelope; physical timing pending|
|PG10|29965ff|4host checks; native validation pending combined runtime|
|PG12|3615d68|8registry checks; authoritative inert producer; native test queued, dispatch remains absent|
|PG15/19 host|a7d8d66|36checks; native progress test queued; no activation authority|
|PG16|6d4935d|10Python checks/historical replay; native validation pending combined runtime|
|PG18|c643725 after67e7d61|23checks; reuse3ad106c; no runtime wiring/live learning|
|PG21|a975ab7 after56e8740|Diff check only; native validation pending combined runtime|
|PG22|6aa20a0|14offline checks; no physical thickness inference/runtime correction|
|PG23|c597521|156focused checks; test-only, synthetic reversals labeled|
|PG25|923bc0b|222persistence checks; test-only|

PG04 native runner passed323checks; checkpoint commit forthcoming. PG09/17 currently holds exclusive Swift slot for baseline failure proof and corrected continuity suite. Next short standalone jobs: PG15/19, PG26b, PG12. PG16 prepares a separate optional combined native validation worktree from0628a33 with56e8740,0c1811e,29965ff,6d4935d,a975ab7; no build until explicit slot. This is validation preparation, not root integration or installation.

PG33 implementation remains review-blocked pending actualv44 state-machine proof. Illegal POSE-after-PREPARE approach was removed before commit; candidate uses causally acknowledged thermal actual pose afterREADY. PG33 reports134existing+17focused tests. Actual firmware C++ harness slot granted, no hardware. Independent600ms gameplay evidence remains separate from calibration override. Automatic cooling resume conflicts with an unpatchedPG08 cold-only workaround, so root must choose reviewed firmware or enforce fullOFF on any cooling entry.

Disk after sparse conversions:25GiB free vs29GiB starting, within8GiB incremental budget. Original recordings/caches/frozen checkouts untouched. Source-only candidates pending native tests are explicitly unvalidated until combined receipts arrive.

## Critical handoff ready

Minimal source selection/merge order is pinned in [MinimalFeedbackCandidateManifest.md](MinimalFeedbackCandidateManifest.md), committed5a84149. Native PG09/17 is19db846 (211checks; baseline reproduces bug); PG04 is34c56fe (323native plus paired Python coverage); host PG33 isf2a7531 (240Python and actualv44 firmware772assertions). Independent cross-change report353da15 at /Users/Dave/SGFPlayerClean-worktrees/cross-change-review/PhysicalGo/Documentation/CrossChangeSafetyReview.md approves source for combined offline/paired integration, not activation. Root integrated host in issue-integration-20261124 and is independently building PG08 firmware/rollback; reviewer now checks combined cache/nearNone/planner interactions read-only.

Further completed optional candidates: native PG15/19 80f5bd1 plus hosta7d8d66 (46native+36host+viewtypecheck), PG26b23016f7 (19no-audio tests). PG12 native suite currently holds Swift slot. Optional combined validation follows, then each pending native source checkpoint will receive explicit test results. No issue is closed; no worker installed or accessed hardware.

## Broad target-domain follow-up

Root's exact critical combination nativec53ac05/hoste906f2b passed paired acceptance plus15additional host suites; no worker installation/activation. PG08 offline build/rollback is root-owned. PG12 native validation receipt36c1280 now completes its offline suite. Optional combined native validation remains held while root owns Swift build slot.

Root requested practical arbitrary-intersection feedback admission from minimal three-point setup, separate from seven physically observed target evidence. Cross-review identified that baseline PG06b robust0..2axis/+5px envelope covered only expanded-edge proposals, while interior/fallback and actual settlement/prelight paths used nominal containment. PG06b's exact-seed/fresh-grid/anchor diagnostic-plant sweep of actuale906 approach found354/361 destinations without5px margin breach, four simulated landings and three simulated dark paths below5px (minimum0.898px). This is simulation evidence, not a physical failure or all-board qualification.

Owners now active: PG06b uniform envelope predicate/planner with shrink/replan/failclosed and domain tests; PG33 actual settled/intermediate-axis/recenter/prelight/start-after-cooling revalidation using same predicate; cross_change_review independent combined review. Root frozenhost stays unchanged until new candidates are tested/reviewed. No uncertainty relaxation, new fit or mandatory calibration tour. Continuous-hold drift and physical response assumptions remain explicit limits.

PG15 reconnect provenance follow-up afce786 passes8offline tests: fresh reference path required, old/new paths+SHA retained, pixels written before admitted setup. Historical/raw/root-derived binding artifacts untouched; no migration is implied.

## Uniform defensive guards and remaining domain blocker

PG06b uniformhelper64983d0 + PG33 actualpose guard4019f80 passed45focused checks; three new regressions fail baseline. Root integrated these and PG15provenance afce786 as host4c650ed. Exactfrozen4019f80 saved-anchor diagnostic simulation:358reached/3failclosed (T6/T4measured-anchor admission, A1finite150s), minimum sampledpath7.3887px. Driftperimeter stress20reached/52failclosed/0breaches. These checks demonstrate consistent conditional guarding, not universal physicalresponse qualification.

Expanded diagnosticplant controls materially violate the assumed response envelope from other starting regions: center361 gives345reach/11failclosed/5landingbreaches (minimum−12.28px); oppositeperimeter72 gives42reach/28failclosed/1landing and1darkpathbreach. Root explicitly BLOCKED full-board host/firmware activation and chose native-only installation preparation. No worker hardware action occurred.

Finite next action assigned PG02+PG06b: analyze retained97observations and qualifiedfeedback for local responsevectors, cross-axis residuals, direction/travel length, nearest qualified coverage, held-out/error separation and diagnosticcounterexamples. Determine whether a data-supported bounded candidate exists; observedmaxima are not guarantees. No arbitrary blanketthreshold, livepromotion, mandatorynewtour or unrelatedholdredesign. Independent reviewer approves defensive source only; domain policy remains blocked. Optionalnative validation still awaits rootSwift release.

## Finite retained-response investigation completed

PG06b report7313fc7 pins all five simulation cohorts to nine runtime hashes matching root4c650ed. PG02 report927034a passes16tests and separates86fit observations,11interspersed observations and76later feedback observations. Four of71 retained physical movement endpoints violate the logged-J independent0..2axis hull plus5px (three near5–6px, one87.04px outside). Frozen dense local derivative covers these71endpoints with maximum2.047px hull distance, but that observed maximum is not a guarantee; all four corners lack nearby held-out legs and intermediate travel is unobserved. The response-envelope assumption is therefore contradicted by retained endpoint evidence, not only diagnostic simulation.

Reports: host Firmware/Experiments/FeedbackEdgeSteps/DomainAssessment.md (7313fc7), and Firmware/Experiments/SpatialCalibrationAudit/RESPONSE_ENVELOPE.md (927034a). Explicit next offline comparison is same guarded planner/driver with retained86fit dense local derivative recomputed at observed pose, no secant adaptation, across existing anchor/center/opposite cohorts and four observed violating legs. This comparison is documented and DEFERRED, not started. It would be a retained prior, not a three-point-only fit or physical qualification. Full-board activation remains blocked.

All issue owners have completed their finite deliverables. Only optional combined native validation remains active under one granted Swift slot: PG00/10/16/21 plus PG03 at combinedHEAD6f1b491. It does not gate root's native-only installation or authorize host/firmware activation.

## Optional native validation completed

Seven suites passed857native checks plus20Python checks on combinedsourcea60394ff93c62d72075dce52e7ca8549ae260e27, immutable runtimeeafcc91160e631dc76942c82464467a6eee88a48b56c6170fc029872c93b68dc. This validates PG00/10/16/21 with PG03 in the separate optional source combination; it is not the installed minimal native combination. Suite counts: idle78, AIplay169, AIlaser283, markers80, hand/stone67, latency26, async154.

Initial run passed703checks but async fixture failed because a restarted5MBcustom-store session omitted its1MBallowance. Test-only fix7b20745 added that argument; no productionbudget change. Only async runner rebuilt, passed154, originalfailedattempt preserved with provenance. No worker installation, hardware, audio playback or visible UI operation occurred. Offline real-engine timings5.499s cold/0.070s warm are not physical reply latency.

All27issue owners and additional cross-reviewer have delivered finite checkpoints. Every31open scope retains its declared acceptance; no physical issue is closed by these offline outcomes. Root owns final install/UI smoke, current hardware state and the canonical register. Next response-envelope experiment is documented/deferred, host/firmware activation remains blocked, and optional source integration is separate.

## Focused movement-correction follow-up completed

The user's subsequent authorization resumed only PG06b implementation, PG02 provenance/admission work and independent review. The previously deferred dense-response experiment was executed and converted into a concrete gameplay fix. [DenseResponseCandidateManifest.md](DenseResponseCandidateManifest.md) pins source order, binding policy, evidence and remaining attended checks.

Qualified helper272e4c9, docs f9dde4f, attended policy115710f, gameplay runtime71fe937, wording a288718 and final evidence d56d749 are ready for root integration. Gameplay uses the dense derivative at each freshly observed actual encoder pose and a measured spot anchor, with no secant carryover or silent affine fallback. Frozen three-point benchmark remains unchanged. Original model/training/setup lineage and fresh-reference identity are pinned; extrapolation is logged under explicit attended_full_board_v1 instead of imposing79 artificial strict-hull route refusals.

The production helper fixes the observed endpoint defect:4/71 envelope violations become0/71. Exact-source simulations reach361/361 from anchor and center; opposite routes70/72 and repeated-drift34/72 retain existing prelight/guard/time refusals, with zero sampled margin breaches across all four cohorts. All seven formerly violating trajectories reach.66 focused checks pass. Final independent review4b1f936 verifies ten production hashes and recommends integration plus supervised361-coordinate attempts; it supersedes the earlier response-domain block for this exact candidate, without claiming physical success at all intersections.

Root reports the PG08 firmware fix installed and verified fully OFF. Workers performed no hardware, UI, installation or activation. Root owns exact combined acceptance, immutable package/binding, fresh preflight and READY. All focused worker jobs are complete and resource slots released; all issue-level physical acceptance remains tracked by the root-owned canonical register.







