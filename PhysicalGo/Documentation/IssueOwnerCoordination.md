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


