# Calibration accuracy and recovery policy review

Updated November 23, 2026. Design handoff; **no production change or new live
policy is implemented or physically validated**. This document captures the
completed architecture proposal and staged implementation audit so continuation
does not depend on access to this chat or its sub-agents.

## User requirement

Three pixels was an arbitrary preferred distance between the laser spot and an
intersection. Dave accepts a larger initial error followed by correction and a
useful final indication beyond three pixels. Such a quality miss should not stop
the whole system. Distinguish aiming quality, uncertain measurement, coherent
setup movement, and actual hardware/control hazards. Numeric limits in servo
counts are unrelated to this pixel preference.

## Evidence and limits

Latest hardware source is `acea4b341fcc78777556c3f56b14344aa1834de8` in
`/Users/dave/DYNAMIXEL-Go-Pointer-worktrees/midpoint-line-profiles`.
Full03 stopped on two local boundary differences of approximately four and three
pixels, while the other 70 points differed by at most 0.159 pixels. Independent
registration estimated at most 0.053 pixels of whole-board movement. Native and
fitted sampling guides differed, and a profile switched between competing dark
features. These are extraction disagreements, not measured laser aiming errors.

Three pixels represents 4.6–9.4% of local grid spacing in these images. The two
failed point differences represent about 0.072 and 0.059 cells. This supports
reviewing unnecessary whole-operation stops, but cannot establish a false-stop
rate or a generally acceptable final aiming tolerance.

- [Exact diagnosis](</Users/dave/Documents/SGF PLayer/work/ai-laser-integration/laser-position-recovery-20261123/moved-setup-full-calibration-03/boundary-jump-analysis/README.md>)
- [Counterfactual study, reproduction and physical experiment](</Users/dave/Documents/SGF PLayer/work/ai-laser-integration/laser-position-recovery-20261123/moved-setup-full-calibration-03/acceptance-rule-study/README.md>)

Global registration alone misses local altered-line/occlusion controls. Those
controls demonstrate lost local evidence; they are not independently established
physical hazards. Do not label every old rejection as ground-truth unsafe or
make a test merely preserve all existing failures. Percentile trimming would
hide uncertainty rather than explain whether the affected region matters.

## Proposed implementation sequence

1. **Compare consistent full geometry measurement.** Evaluate B through the same
   full grid/local-boundary pipeline used for A, then compare fitted coordinate
   maps for coherent movement. Preserve local visibility/quality evidence and
   original timestamps. Do not select whichever sampling guide happens to pass.
   Replay the exact full03 evidence and local altered-line controls before
   selecting this as an implementation. It is a candidate, not a validated fix.
2. **Define one versioned aiming-quality result.** Route termination, final
   validation, physical-evidence auditing and checkpoint validation must agree.
   Store requested target, actual spot, pixel and board-cell error, unique spot
   and intersection identity, and desired versus useful quality. Values of
   0.10 cell desired / 0.25 cell usable are suggestions for offline comparison
   only, not user-approved or established live defaults. Existing correction
   already permits large initial misses. Keep independent model holdout error
   in motor counts separate; never train on held-out targets.
3. **Preserve progress across recoverable measurement pauses.** Design a versioned
   ledger of completed observations/targets at dark boundaries, separate from
   permission to use a current local response model. On unresolved inconclusive
   vision, fully OFF and record a truthful paused-measurement result, pending
   target and exact rejected evidence. Resumption must establish unchanged setup,
   compatible source/policy, current pose/spot and fresh steering. Saved pose is
   historical evidence. Existing v1 checkpoint/current-J and complete-candidate
   resume contracts do not support this new behavior. No automatic retry after
   hardware, transport, thermal, lease or cancellation failures is proposed.
4. **Handle prediction disagreement according to purpose.** It may call for a
   smaller step or fresh response measurement rather than prove an optical miss.
   Use a separately admitted stationary observation when actual beam containment
   is established. Keep pre-command refusal distinct from post-settlement
   observation eligibility; retain meaningful hand/control/containment checks.

The smallest next milestone is the offline geometry comparison plus review of
shared policy/ledger contracts, then one bounded implementation slice. A broad
rewrite or immediate hardware retry is not necessary to establish that milestone.

## Source audit: distinct uses of the number three

Paths below are relative to the laser source worktree above.

| Check | Source/consumer | Purpose to preserve or revise |
|---|---|---|
| Per-image boundary-to-map error | `Firmware/gameplay_calibration.py`, `printed_boundary` | Local measurement evidence; classify ambiguity separately from movement. |
| Fitted map displacement | `Firmware/calibration_prelight.py`, `EmptyBoardReference` | Coherent setup change; separate from noisy individual points. |
| Pairwise displacement of 72 boundary observations | `Firmware/calibration_prelight.py`, `GeometryAnalysis.verify_fresh` | Current full03 failure; unequal guide semantics under review. |
| Lit-frame registration | `Firmware/Tools/commission_gameplay_calibration.py`, geometry/measure | Current observed-image relationship; do not silently weaken. |
| Model/local endpoint and probe response | Steering/recovery modules and commissioning runner | Prediction confidence and response qualification, not final aiming error. |
| Route termination | Commissioning runner | Desired centering versus useful unambiguous indication. |
| Final target proof | `validation_report`, `audit_pointing_domain`, physical-evidence consumers | Shared explicit quality/evidence version required. |
| Checkpoint target proof | Checkpoint/resume consumers | Same shared policy; cannot silently reinterpret v1. |
| POSE ±3 and probe singular-value minimum | Motor pose/response checks | Servo-count units, not pixel aiming tolerance. |

`bridge_setup` binds exact setup/model/reference hashes and allowed targets.
Changed target acceptance requires an explicit evidence-policy version and
updated auditor output. Do not pass weaker evidence under an unchanged schema.
Recovery/pilot samples must not acquire held-out validation credit.

## Completed review and continuation

Architecture review and quantitative study are complete. The calibration author
has delivered the staged plan above; the [author’s detailed plan](</Users/dave/Documents/SGF PLayer/work/ai-laser-integration/laser-position-recovery-20261123/calibration-acceptance-redesign/PLAN.md>) records source locations and regression commands.
**The proposed same-full-pipeline B comparison has NOT RUN.** No replay process
is active. The next chat must first create its offline replay harness against
the saved/control set; do not assume the proposal passed. None of these agents owns hardware. Durable reports, rather than
agent availability in another chat, are the continuation basis. Read
[NextConversationHandoff.md](NextConversationHandoff.md) for OFF state, source,
preserved games, next actions and current hardware ownership.
