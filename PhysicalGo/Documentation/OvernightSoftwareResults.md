# Reversible overnight software work — November 23, 2026

The primary installation remains **0.253/build254**, and the signed **0.254/build255**
physical-test baseline is preserved. No hardware, camera, installed app, active
binding or saved game was changed by this work. Lighting/setup verification and
physical calibration remain required when Dave returns.

## Later consolidation in progress

The next app candidate, 0.258/build 259, starts from the reviewed 0.255 code below
and adds the reviewed recognition/fast-test changes, hosted stone-set storage,
screen-only illegal feedback and pending four-position practice-loader merge.
It is not yet verified or installed. Keep the 0.255 build/paired receipts as
historical evidence; they do not prove the later combination. See
[NextPhysicalTestPlan.md](NextPhysicalTestPlan.md) and the current checklist.
Recovery, [build provenance](BuildProvenance.md), [paired acceptance](PairedContractAcceptance.md)
and [opt-in tracing](LatencyDiagnostics.md) remain part of the combined source;
no adaptive learner or optical stone correction is activated.

## Optional integrated candidate

**0.255/build256** is built and signed, with matching source/binary hashes verified
before and after copying. It is **not installed or physically validated**.

- App code commit: `939fe27c6030b483b8140d355b45b6e3687a2d0a`.
- Host code commit: `45ed952131852a3aa3b32ddb7f27626d8fd998eb`.
- Both use `codex/overnight-reviewed-candidate` in their separate worktrees.
- App worktree: `/Users/dave/SGFPlayerClean-worktrees/overnight-guidance-reducer`.
- Host worktree: `/Users/dave/DYNAMIXEL-Go-Pointer-worktrees/overnight-source-manifest`.
- App source hash: `e63bdbb90964f08cc336e60fff7fdac3190af0412750ff2f0782462913151112`.
- Binary hash: `e8057cc4546b8ce3b7f37c58f953d8db0fcfd0912f69353e853ebf3cf391df56`.

The candidate adds a pure transient-recovery state machine, optional bounded
latency diagnostics, complete declared calibration-source inventories, immutable
regression build inputs and mandatory paired app/host acceptance. The adaptive
learner is **not imported or activated** in this candidate. Firmware and timing,
thermal, movement and hand-clearance limits are unchanged.

Candidate bundle, source/resource manifest, source snapshots and validation logs:

```text
/Users/dave/Documents/SGF PLayer/work/ai-laser-integration/fresh-board-20261122-133741/overnight-software-20261123/
```

The signed app is `candidate-0.255/Physical Go.app`; `candidate-0.255/manifest.json`
records its identity, bundle resources and exact host inventory. The earlier
signed 0.254 is still in the session's
`gameplay-holding-validation/app-0254-candidate/Physical Go.app`.

## Validation

| Check | Final result |
|---|---|
| Combined app regression | 11/11 suites pass: 495 continuity checks, 225 standby, 278 laser lifecycle, 47 capture contract, 37 capture controller, 80 marker scenarios, 12 resume, 26 progress, 26 tracing, 16,825 reducer parity and 105 independent reducer checks. |
| Combined host regression | 344 tests pass; zero skips, including saved-image cases. |
| Build and contract tooling | 69 tests pass; real tiny Swift compiler probe enabled, zero skips. |
| Mandatory paired acceptance | Fresh immutable native artifacts export real requests; production Python parser/runtime with fake hardware publishes actual statuses; native consumers verify them. Exact app source, linked runtime output and all tracked host Python source identities are checked. |
| Optimized app bundle | Full build and strict signature verification pass. Not launched or installed. |
| Adaptive shadow prototype | 56 author/independent tests pass across the core and cleared-board campaign; synthetic positive and negative numerical audits. This remains a separate experimental branch. |

The broad host run caught a pre-existing simulated-device race: initializing its
millisecond counter as a float could produce `3.0` on an early first tick. The
production parser correctly rejected it. Only the fixture was corrected; the
new regression exercises 0, 0.5 and 1.9ms first ticks. The final344-case rerun passes.
The first ad hoc tooling aggregate used stdin, which is incompatible with the
multiprocessing spawn tests; canonical per-file commands passed all69 checks.
Failed logs are retained rather than replaced by successful results.

The paired acceptance is a composed encoder/runtime/consumer test with fake
hardware. It is not concurrent whole-process testing, physical laser validation,
or a measurement of acoustic/optical onset. Build snapshots cover source/artifact
identity; source-relative runtime resources remain live and are documented.

## Rollback and independent branches

| Workstream | Saved branch / principal commit |
|---|---|
| Recovery extraction | app `codex/overnight-guidance-reducer`, `dbc443f`; review registration `f38cc33`. |
| Build provenance | app `codex/overnight-build-provenance`, `c258d5d`. |
| Paired contract acceptance | app `codex/overnight-contract-acceptance`, `0498e073`. |
| Latency diagnostics | both `codex/overnight-latency-tracing`; app `848a67a`, host `139d795`. |
| Calibration source inventory | laser `codex/overnight-source-manifest`, `f4280c4`. |
| Adaptive shadow research | laser `codex/overnight-adaptive-calibration`, `f47f36c` (core `dc03dc9` plus independently reviewed campaign). |

Nothing requires resetting a primary checkout. To keep tomorrow's original test
plan, use the preserved signed0.254 and original reviewed host code. To evaluate
0.255, use the paired candidate worktrees and its matching manifest. Diagnostics
are opt-in and can be disabled without reverting source. Neither branch activates
adaptive calibration or permits a stale/moved setup. Do not swap versions or
bindings during active hardware operation; preserve game/clocks and establish OFF.

## Adaptive calibration and the user's distortion hypothesis

The research prototype compares an unchanged map, a global motor-count bias and
a bounded local residual field. It uses actual measured motor/spot pairs rather
than treating a requested intersection as an observed location. Synthetic tests
show uniform bias benefits from a simple global correction, while spatially
varying error can benefit from local corrections. This is not a measured benefit
on the user's physical board.

The design/literature, exact synthetic results and independent review live in:

```text
/Users/dave/DYNAMIXEL-Go-Pointer-worktrees/overnight-adaptive-calibration/Firmware/Experiments/AdaptiveCalibration/
```

Current saved observations do not establish the settled motor pose throughout the
camera exposure, so they remain quarantined. New diagnostics preserve unknowns
and mark their adaptive audit records ineligible instead of manufacturing evidence.

At Dave's suggestion, a completed, independently reviewed offline campaign now
plans 49 distributed locations: 25 fit locations and 24 separate validation
locations, including eight edge locations. Two approach directions and repeated
anchors bring the default to 130 measurement episodes. An optional all361 plan
has 832 episodes. Actual duration and feasible physical routes remain unmeasured.

First aim before feedback is recorded separately from final settled pose/spot
evidence. Comparisons include motor bias, board translation, rotation, affine
deformation and the existing local residual correction. Repeated anchors flag
possible time drift; missing first aims remain failures. A review found and fixed
a fit/validation leak when an actual final spot landed away from its assigned
training target. The original adaptive core and candidate hashes are unchanged.

The campaign code, seven synthetic examples, PNG/SVG illustrations and independent
review are committed at `f47f36c` on the separate adaptive branch. See
[the campaign plan](/Users/dave/DYNAMIXEL-Go-Pointer-worktrees/overnight-adaptive-calibration/Firmware/Experiments/AdaptiveCalibration/CAMPAIGN.md)
and [independent review](/Users/dave/DYNAMIXEL-Go-Pointer-worktrees/overnight-adaptive-calibration/Firmware/Experiments/AdaptiveCalibration/CAMPAIGN_REVIEW.md).

This is a logical measurement plan and analyzer, not a motor route or hardware
executor. A constant motor-angle bias can itself look spatially distorted in
board coordinates, so shape alone does not prove the cause. The sparse synthetic
survey gives only modest local-model improvement; it does not establish adequate
coverage or any physical gain. A later attended comparison must measure original
and frozen candidate first aims, correction counts, timing and failures. No
adaptive activation or hardware action was added.
