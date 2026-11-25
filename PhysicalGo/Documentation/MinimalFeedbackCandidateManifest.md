# Minimal feedback gameplay candidate manifest

Prepared November24,2026 by offline issue coordinator. Root alone integrates, builds, installs, binds and performs attended hardware acceptance. This manifest is a candidate selection and dependency record, not activation authority. The canonical IntegrationChecklist remains the issue register.

## Immutable parents

- Native: installed-source documentation HEAD0628a33, runtime9c516f1, new integration branch/worktree required.
- Host: physically tested2da3c29785aa7337871b299380dd3dc289437332. Installed gameplay04b76c7 is its ancestor; camera-safety delivery core preserved.
- Firmware installed: AimControlv44, without PG08 fix. No worker changed hardware.

## Native merge order

|Order|Commit|Purpose|Offline evidence|
|---|---|---|---|
|1|002e4c7|Bounded outer-rail profile jitter|204native checks; independent82be920 review38controls/76invocations; no blocker|
|2|56e8740|Complete temporal hand checkpoint|623checks; detector thresholds unchanged|
|3|19db8463e6c4a0bd102e991e3c3a9db864d8cc18|Freeze pause/shutdown clocks before cancellation|211checks; baseline new regression fails, corrected passes; static no blocker|
|4|34c56fe|Mandatory paired point conversation and native lifecycle tests|323native;12point negatives,10command,16host,24fresh-fixture review checks|

Native checkpoint expansion improves evidence replay, not a demonstrated false-hand detector cure. PG21 first-rejection persistence is optional and outside this minimal batch. Root may omit nonessential evidence-only source only with the omission recorded.

## Host merge order

|Order|Commit|Purpose|Offline evidence|
|---|---|---|---|
|1|7d8b530|Exact same-batch median reuse/local centroid|75owner tests; independent7f7623f review6median+19regional controls; ~49.8MB temporary median|
|2|c590b44|Independent first serial-fault diagnostic sinks|65checks; no deadline/retry relaxation|
|3|9dcb5ab|Blocked refresh/freshness regressions only|33pass,1native-export skip; unchanged600ms|
|4|e74134a|Combined holding/hand/cooling/resume regressions only|47checks; rerun with final PG33|
|5|1d2770f|Conservative larger edge-step helper and benchmark adoption|56pass,2archive skips; independent static no blocker under stated envelope|
|6|f2a75319f36d1257b6e9e272960ae19a2a30bbd5|Opt-in measured feedback gameplay|240Python checks; actual unchangedv44 firmware249+422+101assertions, independent static/proof review|

The shared bridge_hardware.acquire_spot hunk must retain BOTH cached observation from7d8b530 and PG33 initial whole-board acquisition support:

`detect(baseline, observation, near=project(H, [near])[0] if near is not None else None, ...)`

Dropping the first loses optimization; dropping the conditional breaks first acquisition. This is an explicit manual merge-review point, not an instruction to replace the full call blindly.

PG33 intentionally retains the conservative15px planner. Merely adding1d2770f does not enable faster gameplay; root must either explicitly integrate/review its pure helper in bridge_feedback.py and rerun containment tests, or leave it benchmark-only and record that first gameplay uses conservative steps. No physical speed gain is established.

PG33 broad bridge discovery had16 missing historical-image fixture errors, separately documented; the240 passing checks are the available targeted suites, not a claim that every discovered test passed.

## Firmware condition

PG08 candidate71e8df6, Firmware/AimControl/GameplaySupervision.h92–99, restores coolingPolicy when an already-qualified released motor reheats>=40C. Existing source only reset the dwell timer, leaving CN10 eligible for premature warm holding. Both-axis40/44C regressions fail baseline/pass corrected;7600new+6686existing sanitizer assertions, independent static review no blocker. Protocol/schema unchanged; candidate still identifies asv44, installedv44 lacks fix. Root owns release identity, exact offline build/rollback, upload and any host exact-version expectation changes.

PG33 automatically resumes eligible cooling with RS. Consequently, initial gameplay requires reviewed PG08 firmware OR an explicitly implemented fail-closed cold-only policy: fresh both<40C at admission, verified fullOFF upon any cooling entry, no cooling recovery/warm resume. Starting cold or planning a short game alone does not avoid the defect. The current PG33 commit does not implement that workaround.

## Required final validation

1. Record exact combined native/host/firmware hashes and resolve the merge points above.
2. Run native continuity/hand/alignment/AI-laser and modified paired point acceptance on that exact combination, plus host feedback/freshness/holding/serial/median/step-policy suites.
3. Repeat PG33 actual firmware state-machine proof for the selected firmware: post-PREPARE causally later thermal actual pose, every light admission, dark travel/coolingRS, forbiddenPOSE negative. Existing proof runs actual unchangedv44 with instrumented observation probes; no camera or serial.
4. Keep independent600ms gameplay optical/clearance guards. Never import calibration10s overrides or retimestamp stale optics.
5. Root builds/installs one reviewed pair, preserves rollback/game/clocks/reference, and creates explicit reviewed feedback binding. Root alone obtains READY and performs attended game with fullOFF verification.

All issue scopes remain open until their declared acceptance is met. Optional online/parallax/centering/illegal/progress/latency instrumentation batches are separate and must not delay minimal supervised play. A passed mock or source commit is neither installation nor physical validation.

