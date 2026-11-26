# Independent overnight requirements review — November 26, 2026

Status: **contract review in progress; no new implementation approved yet**.
Reviewer `/root/overnight_requirements_review`; root owns integration, installation,
all hardware, and physical acceptance. This document is an independent review
artifact, not a replacement issue register. No camera, serial, installation or
desktop screenshot is used by this reviewer.

## Scope and source baseline

The authorized batch follows the 76-group spatial audit (`54548df`) and 63-group
temporal audit (`23163e8`), together with canonical `CurrentPriorities.md` and
`IntegrationChecklist.md`. Native baseline is `fb4697c4` (0.268/build269).
Host baseline candidate is `32d7911`, including durable measured anchor recovery
and exact preflight failure capture. Immediate baseline approval belongs to the
existing reviewer; this report reviews new overnight changes and their combination.

Assigned changes: held-spot bounded correction/hysteresis; distinct fresh safety
and stationary spatial ages; native cold-admission phases; typed coherent geometry
requalification and local support; competing new-stone assignment. These are
independent mechanisms sharing authority, evidence and recovery state.

## Requirements versus numerical policy

Required observable contracts are: the requested physical intersection is uniquely
identified; real current pixels support relevant visibility and clearance; actual
motor pose and permitted motion are contained; current request/session/generation
authorizes the action; thermal and hardware watchdog evidence is current; geometry
and model provenance describe the actual setup; finite recovery does not silently
become indefinite actuation; game history and clocks change only on their existing
authorized evidence.

The current `.20 cell`, `.6 s`, `150 s`, fixed frame counts, residual percentiles,
and phase deadlines are engineering policies implementing those contracts. Their
presence in a test does not establish their necessity. A replacement needs evidence
for its purpose, including reasonable successful cases; preserving every old veto
is not itself a review objective. Installed firmware constraints remain actual
interface constraints until changed through separately justified work.

In particular, a long stationary hold need not consume an active correction budget.
Use cumulative active acquisition/correction time and moves plus a bounded
per-recovery wall-clock episode. Preserve budget across repeated recoveries for
the same intent; do not refresh it merely by retrying or briefly reporting success.
Do not substitute this accounting for unchanged light, lease or thermal deadlines.

Root selected a provisional 30-second per-recovery wall cap, additionally clipped
by the remaining cumulative 150 seconds of active work and 25-plan ledger. This
applies to small held drift, fresh resampling and coherent requalification; it
does not authorize a new full coarse route. The 30 seconds is a bounded recovery
and responsiveness policy, not a demonstrated physical necessity. Log legitimate
exhaustion so replay or physical evidence can justify revision.

## Interaction test matrix

| Contract | Positive control | Adversarial combination / required result |
|---|---|---|
| Lease and generation | Same live target continues through fresh evidence and bounded correction | Cancel/retarget/pause/replaced session during delayed fit, pose proof or publication: old worker cannot publish adequate, retain authority, relight or command motion. |
| Fresh hand clearance | Older stationary spot plus independently fresh clear safety can remain useful | Safety stops advancing while old spot/geometry remains valid; new hand arrives during recovery; hand tracker resets to unknown: deny motion/light immediately through existing guard, never derive clearance from spot age or recognition. |
| Spatial age | Genuine delayed processing with unchanged actual pose and geometry can use an explicitly bounded older result | Any intervening command, changed telemetry/session object, pose drift or geometry epoch invalidates stationary reuse. Publication clock cannot replace capture clock. |
| Geometry identity | Small coherent supported change can request dark requalification | One-cell alias, rotation/reflection, reference/model/camera/stream identity change, missing interior support or nonlinear local warp cannot become eligible merely from small global residual. |
| Local support | Harmless missing rail/glare can use sufficient alternate real support | Global fit passes while target neighborhood or relevant containment boundary lacks support: global p95 is not a target bound or proof of visibility. |
| Requalification | Verified dark transition, fresh three-frame fit, unchanged identities, fresh actual-pose spot | Old spot/reference pairing cannot survive replacing geometry; no re-aim from transformed historical spot alone. A coherent image shift alone cannot prove camera–laser rigidity. |
| Pose and corridor | Fresh contained spot and supported local response permit bounded correction | Edge/corner target plus hold tolerance plus geometry allowance plus encoder drift must retain full asynchronous motor corridor containment; do not add independent nominal margins and claim a proof. |
| Hold hysteresis | Jitter straddling acquisition boundary avoids futile fault/restart | Sustained drift triggers finite correction; unavailable evidence interrupts first. Adequate/accepted semantics must remain explicit while outside acquisition accuracy. |
| Recovery budget | Long stable waiting followed by one justified correction can succeed | Alternating coherent-shift and drift recoveries cannot independently reset active-time/move allowances or each other's episode deadline. Failed requalification terminates its bounded episode. |
| Light duration | Lit geometry renewal/continued hold retains original illumination start | Re-aim, phase transition, geometry certificate renewal, status emission or correction success cannot reset continuous-light origin. Only positively commanded/verified dark-to-light sequence starts a new interval. |
| Thermal authority | Fresh paired monitored evidence permits current action | Older spatial result or extended native admission cannot relax thermal age, ACK generation, hardware engagement deadline or firmware watchdog. |
| Cues | First valid adequate target retains once-per-move cue behavior | Hold recovery/requalification/retries cannot fabricate another light transition or repeated placement click; approaching/outside-acceptance state must not be reported as newly accepted. |
| Native admission | Explicit delayed setup/transport progress fits an outer envelope | Replayed/stale arming status or repeated retry cannot reset original admission origin; phase progress cannot extend firmware permission or bypass same-scope OFF/recovery checks. |
| Recognition | Strong uniquely assigned off-center stone with weak empty neighbor can confirm | Halfway competing assignment, separate neighboring stone, cover/glare, edge/corner and both colors remain distinguishable; counts/history cannot establish exact location or hidden emptiness. |
| History and clocks | Recognition stability uses accepted distinct causal frames | Recovery/camera gaps preserve game and clock policy; inferred hand exit remains clock evidence only, never light permission. |
| Time domains | Monotonic active-time and episode deadlines tolerate ordinary scheduling | Wall-clock jump, future capture, delayed IO, reused frame ID or stream epoch, and stale immutable snapshot cannot create younger evidence or renew authority. |

## Source-first review anchors

At host `32d7911`, `bridge_feedback.py` has separate checks before post-image pose,
after optical work, and inside atomic generation-checked anchor publication.
`bridge_gameplay.py:gameplay_guard` already checks fresh cached safety independent
of the optical worker. Age changes must preserve this independence and publication
fence, rather than changing every `.6` occurrence.

`FeedbackOperation.hold` shares lit renewal with measured observation; today a
spot outside `.20` faults, including an earlier check during lit renewal.
A correction implementation must handle both entry paths consistently, and must
not pass an out-of-acceptance sample through an unchanged renewal veto accidentally.

`approach` currently creates its own time origin and local count. Calling it again
from hold without explicit shared accounting would reset the allowance. Its stable
hold successor has no original absolute lifetime; the new policy should preserve
the ability to wait for the player.

The spatial owner's initial proposal uses a typed exception carrying evidence,
then a fresh dark constructor and identity/displacement guard before optical
reacquisition. This is a useful separation of eligibility from permission. Exact
implementation and combined counterexamples remain to be reviewed.

The temporal proposal subsequently narrowed to typed optical-result expiry and
bounded **fresh resampling**, retaining the 600 ms acceptance ceiling. It does
not reuse an older spot as current spatial authority. Only processing/causal-pose
waiting expiry is eligible; ordinary camera/safety expiry is not thereby changed.
The recovery owner remains the single outer loop.

The proposed native cold-admission margin is a fixed 16-second outer envelope
from the original cold origin, only with fresh authenticated dark arming and
same-controller thermal progress. The GA-only host receipt wait would be 14
seconds; firmware's 12-second engagement limit and RS remain unchanged. These
are provisional overhead policies, not measured worst-case allowances. Thermal
sequence advancement establishes monitor liveness, not GA phase progress. New
optional controller token/generation/epoch fields are needed to establish that
scope; old host statuses must retain the default 12-second behavior. Consuming
validated terminal active/OFF evidence before testing the cold timeout addresses
a separate ordering defect in the baseline.

PG23's narrowed proposal uses a same-frame exposed-wood receipt from an existing
successful two-rail and inner-body-wood path to explain a low-confidence EMPTY
neighbor. This is more concrete than guessing location from a confidence scalar.
The receipt must bind exact image/frame, point and reading and be invalidated by
mutations. UNCERTAIN, nonempty, covering geometry and conflicting assignments stay
blocked. No hand/laser authority follows from the receipt. Exact delayed R16 pixels
are unavailable, so a later retained-frame result cannot prove removal of that
incident's 25-second delay.

## Approval ledger

| Batch / exact revision | Decision | Remaining conditions |
|---|---|---|
| Initial contracts, no new code pinned | Pending | Exact source review, focused owner regressions and combined matrix evidence. |

Offline approval will identify source revisions and evidence explicitly. It does
not establish physical reliability, installation, a sustained-light acceptance
result, or a full-board calibration. Canonical integration status remains owned by
the issue coordinator and root.
