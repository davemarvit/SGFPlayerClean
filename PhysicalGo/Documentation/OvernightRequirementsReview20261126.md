# Independent overnight requirements review — November 26, 2026

Status: **combined source approved: host
`74d0b83ad037ee69fb8e8c2e97ca27610a3cbfb3` and native
`d014c63b2f4b07e81e10b7c4f9f9ecfed51c15a4` (0.269/build270), including
bounded recovery, admission, PG23 and A2 optical-proof age. Final combined test
completion, packaging, paired acceptance, installation and physical results remain
root-owned and are not established by this source review**.
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

The ledger belongs to one original `FeedbackOperation`, spanning its internal
retries. A deliberately new native revision after full OFF and separate admission
creates a new operation; no persisted whole-pending-turn budget is required.
Initial predicted acquisition retains its separate existing `MAX_WAYPOINTS` bound
and shared active time. The 25-plan ledger counts local correction plans. Recovery
must not restart the predicted route, but fresh optically anchored local plans may
use existing contained fast motion when the observed displacement warrants it.

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
| Requalification | Verified dark transition, fresh three-frame fit, unchanged identities, fresh actual-pose spot | Old spot loses current measurement/correction authority. It may remain an explicitly historical first-light containment hint under the existing dual-envelope guard; no movement or predicted travel before fresh board-wide optical reacquisition. A coherent image shift alone cannot prove camera–laser rigidity. |
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
| Geometry helper `16806f3` | Conditional source approval | Owner reports 10 new + 35 existing tests; inspected, not independently rerun during physical baseline. Combined adapter must darken before assessment, enforce shared budgets, invalidate old spots/predictions, reacquire actual-pose optical anchor, and terminate on failed replacement validation. |
| Optical expiry helper/seams `943188b` | Source approved; recovery integration pending | Inclusive 600 ms ceiling and four original clocks preserved. Invalid/future clocks remain ordinary failure. All three expiry seams precede anchor/certificate publication. Owner reports 18 focused tests; source/tests inspected. Outer recovery is not supplied by this commit. |
| Optional renewal budget/fourth expiry seam `bf4509b` | Source approved; hold integration pending | Reviewer independently ran all 40 age/pose/lit-renewal focused tests on clean exact commit. Deferred optional work starts only from a current finite ordinary result; proposal/commit expiry stays rejected; final publication remains 600 ms. Hold owner must implement bounded deferral and root's 2-second geometry reserve. |
| Native terminal ordering `ef22e4e` | Source approved pending queued native guidance tests | Valid active/OFF receipt consumed before timeout; invalid thermal terminal receipt still fails. |
| Host admission/status `0fb532c` | Source approved pending paired native checks | Actual thermal token/generation/epoch published additively; GA-only receipt wait 14 s, others 12 s; no ambiguous-command retry. Owner reports 17 focused checks. |
| Native admission grace `ba36928` + repair `4b180f4` | Source approved pending queued native guidance tests | Reported healthy state-epoch defect corrected. Fixed token/generation, advancing epoch reseeds liveness, no episode/deadline reset. Owner reports 312,346 pure assertions; not independently rerun during baseline. |
| PG23 evidence schema `7c881be` | Static schema-only approval | No evidence emission or decision bypass exists yet. Full approval requires actual pixel producer/consumer, provenance propagation and conflict-mutation tests. Metadata-only controls do not establish classifier quality. |
| Root helper integration host `cad26b0`, native `d270ee1` | Merged helper source approved | Host merge is the exact union of reviewed geometry and temporal runtime changes; stage-aware renewal and requalification APIs both retained. Native runtime files match reviewed `4b180f4`. Reviewer independently ran 67 combined focused host tests, all passed. Hold/recognition integration remains pending. |
| Frozen hold `82540e1`, integrated host `f07affd` | Changes requested at dispatch/publication boundaries | Core bounded loop reviewed; root's PREPARE→DARK fix retained. Reviewer and root independently found command deadline check before actual writer boundary; reviewer reproduced it with production GatedController and a fake delayed writer. Adequate save has a related check-before-lock/mark-after-publication gap. |
| Hold boundary repair `40adedf` | Prior boundary findings resolved; one final current-safety check requested | Actual prewrite validates operation budget; gated adequate save validates evidence and marks completion atomically. Whole held step shares the existing retry owner and nested RS scope. Reviewer independently ran 31 boundary/recovery/budget tests, all passed on clean exact commit. Latest independent cached hand/camera safety must also be checked inside adequate publication. |
| PG23 producer experiment `397fb74` | Source approved as offline/unwired experiment only | Original unmasked reference-wood/two-rail predicate retained; explicit original capture time and immutable image/reference identity. No production consumer or pipeline wiring approved. Final original-timestamp replay and real controller integration tests remain required. |
| Final current-safety guard `04d2134` | Source approved; final host finding resolved | Latest cached hand/camera evidence checked inside adequate save. Actual runtime-gate tests replace clear evidence with hand/stale evidence before publication, and verify no adequate, budget pause or optical-expiry retry. |
| A1 raw-write revocation `13129ec`, integrated `8ce91a1` | Source approved | Token/generation revocation remains immediate; physical OFF attempt defers only until the rejected non-reentrant raw writer unwinds. Post-validator authority check blocks cancellation that returns normally. No OFF acknowledgement is invented, including partial delivery and failed OFF. |
| PG23 full chain through `993b8a2` | Production source approved pending combined native integration/installation | Actual capture→producer→metadata-preserving transforms→narrow PhysicalAI neighbor exemption reviewed. 572 native checks and 30 original-timestamp producer checks reported passing; real-controller suite source inspected. Physical improvement remains unmeasured. |
| Host-only `8ce91a1` + installed native `fb4697c` | Source approved for attended O17 test with A2 explicitly open | Existing native accepts additive thermal fields and retains its 12-second admission deadline. New host correction/clearance does not depend on native adequate status. Root must complete packaging/paired acceptance and fresh attended readiness. No claim that A2 is fixed. |
| A2 host `c24478c` + native `2adde6c` | Source approved for paired commissioned feedback deployment | Immutable original optical clocks, deadlines and exact scope survive publication and heartbeat; native checks actual proof only for the first acceptance cue. Missing/stale proof cannot become current through status refresh. Legacy paths without causal proof receive no acceptance cue. |
| Combined host `74d0b83` + native `d014c63` | Combined source approved; final root checks pending | Host Firmware matches reviewed A2 source exactly. Native A2 guidance, cue tests and paired fixture match reviewed A2 source exactly; reviewed PG23 remains in the same tree. Final native change is version/build metadata only. |

### Final combined A2 review

The approved host pin is `74d0b83ad037ee69fb8e8c2e97ca27610a3cbfb3`;
the approved native pin is `d014c63b2f4b07e81e10b7c4f9f9ecfed51c15a4`.
The reviewer compared the final integrated source with the reviewed branches.
Host Firmware has no differences from `c24478c86191081c4cea1d5c34b739a7885d220a`.
Native A2 guidance, accepted-click tests and paired fixture have no differences
from `2adde6cdeb6eae86b8cc70cc396d5eb001890e62`; the remaining production changes
are the previously approved PG23 chain and version 0.269/build270 metadata.
Tracked source is clean; the host contains a root-owned untracked `Camera checks`
artifact that this review did not alter.

The host copies the actual sample's four original capture/arrival/publication
clocks, stream/frame identity, full target/request scope and controller identity.
Its deadlines are derived from the original clocks, never from status writing.
The proof is frozen as a JSON string in the feedback tuple; the existing final
rename snapshot fence includes that immutable value. A delayed write or later
heartbeat may still carry historical adequate state, but cannot make its optical
proof younger. Current independent hardware authority checks remain unchanged.

Native checks exact producer, request sequence, target, camera context, stream and
controller identity, all four 600 ms ages and the original derived deadlines at
cue consumption. Only the acceptance-cue condition consumes this new proof.
Missing optional proof or well-formed stale/mismatched proof suppresses the cue
without changing motion, darkening, faulting or consuming the once-per-move cue;
a later current proof can still announce the target. Malformed present JSON
continues through the existing decode-error path; this approval does not claim
that every structurally invalid record is handled as cue-only.

The new consumer intentionally gives no acceptance cue for legacy/non-feedback
paths that lack genuine causal optical proof. The approved pairing is the
commissioned v44 feedback route. No timestamps or controller proof are fabricated
for older paths. State-epoch advances do not rewrite optical evidence; controller
session and control generation remain bound.

Owner results are 95 focused host tests and 62 native accepted-click checks. The
reviewer independently ran `test_adequate_wire_evidence` on clean `c24478c`:
**2 tests passed**, covering actual worker publication, delayed writing and a
heartbeat with expired original proof. The paired fixture SHA-256 is
`859f466b8793a018ac11c3fdfd6fc7570ecbfe538768804d9cf7d3f9e1af5e4e`.
Root owns the final combined native suites, full host suite and paired acceptance.
No new physical acceptance or installation follows from this source approval.
The earlier host-only decision below records the narrower historical release
decision; its open-A2 condition is superseded only for the approved paired source.

### Hold dispatch and publication boundary findings

At `f07affd`, the work budget wraps `GatedController.operation_check`, which
`healthy()` invokes **before** acquiring `raw.condition` and the serial writer.
The actual `before_write` callback checks session safety but not the work budget.
An independently reproduced hardware-free case calls production GatedController
with a valid budget at29.95 seconds, simulates100 ms of scheduling/lock delay, and
records `PSW1591` dispatch at30.05 seconds after the30-second deadline. The next
health check raises only after dispatch. The independent600 ms lease can remain
valid throughout this short boundary crossing.

Required correction: enforce the bounded operation check at actual pre-write,
alongside existing session validation and generation/lease checks. A test using
the production GatedController path must inject delay before that callback and
assert no axis dispatch, rather than calling the hook directly in a fake command.

The final adequate path similarly checks health before entering the runtime's
generation gate, publishes adequate, and only afterward calls `mark_adequate()`.
A gate delay across the deadline can publish a cue then immediately fault. This
does not establish unsafe beam authority, but contradicts the stated no-expired-
adequate contract and can produce a misleading completion cue. Coordinate the
bounded budget check/completion with the actual gated status save. An alternative
explicit completion-at-verified-result policy would need matching implementation
and tests; the current publish-then-fault behavior is not an intentional policy.

**Resolved in `40adedf`:** production `before_write` composes existing session
validation with the bounded operation callback, without raw health/IO. Runtime
`emit` supports a bounded `before_publish` callback inside its generation gate;
the held adequate callback checks budget, controller scope, geometry, illumination,
causal motor age and all four original optical clocks before marking completion.
The entire held step now uses the original recovery owner. A late valid-clock
optical expiry obtains a new board-wide observation rather than retrying the same
sample; nested observation shares the same mutable scope for acknowledged RS.
Production-adapter lock-delay tests and the own-RS-plus-late-publication case pass.

**Remaining at `40adedf`:** the adequate callback does not yet consult the latest
independent cached gameplay camera/hand safety. A newer obstructed safety frame
can arrive after the pre-emit `healthy()` call while publication waits for the
gate, even though the older optical sample remains under600 ms. Request the
existing memory-only `gameplay_guard(require_clear=True)` at the gated publication
boundary. Current hand/unknown/stale safety must prevent adequate and remain an
ordinary authority failure, rather than being classified as expired optical work.

**Resolved in `04d2134`:** the existing memory-only cached gameplay guard now runs
inside adequate publication with `require_clear=True`. Reviewer independently ran
the production publication-boundary and A1 raw-write suites on exact integrated
`8ce91a1`: **12 tests passed**. No tracked source differences were present; an
unrelated untracked `Camera checks` item was left untouched.

### Host-only approval and the remaining A2 wire-age issue

The host-only release retains a pre-existing gap: runtime status publication can
refresh its envelope timestamp while carrying an older adequate state, and the
installed native app does not receive the original optical proof age. Therefore a
click or UI status can be later than the underlying optical acceptance. Source
approval does not waive or close this issue.

The relevant installed native consumers were inspected: `PhysicalLaserGuidance`
lines818–824 use adequate to invoke `onTargetIndicated`; `ExperimentModel`
lines656–659 connect that callback only to `aiMoveClick.indicate()`. Native point
intent and host movement/light authorization continue to use independent current
camera/hand, lease, controller/thermal, target and geometry checks. The new hold
loop does not take a native adequate status as permission to move. Its gated host
adequate publication is stricter than the baseline, preserving original optical
age and latest safety at that boundary.

Thus A2 is an existing end-to-end optical-status/cue truthfulness defect, not a new
hardware-authority expansion caused by the bounded hold recovery. A host-only
attended O17 test with native0.268/fb4697c is supportable while A2 remains explicitly
open. Observe the actual beam and root-owned run evidence; do not treat the click
as proof of contemporaneous acceptance. This conclusion is based on the source
authority paths, not the user's limited attendance window. A2's separate repair
must carry original scoped optical timestamps through the wire and check them at
native consumption rather than retimestamping old proof.

PG23 is approved separately at source level but is not part of that narrow
host-only test. Its `993b8a2` consumer exempts only a low-confidence EMPTY expected-
empty neighbor with its own same-image positive wood/two-rail proof. Unknown or
nonempty readings, covering geometry, target offsets, legal additions, temporal
witnesses, dark evidence and game-clock rules retain their existing checks.
Actual original capture time is passed by the pipeline; redraw/processing fallback
does not create receipts. The later retained photograph and synthetic controller
sequences cannot establish a measured improvement to the original R16 delay.

### Independent focused checks after attended baseline

The reviewer independently ran these hardware-free tests sequentially with
`OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1`, using Python unittest and
`PYTHONPATH=Firmware:'Firmware/Host tests'`:

- Clean temporal worktree `74ed60b`: `test_feedback_result_age`,
  `test_feedback_pose_evidence`, `test_admission_envelope` — **21 passed**.
- Clean geometry worktree `16806f3`: `test_geometry_requalification`,
  `test_fixed_optical_geometry`, `test_lit_geometry_renewal`,
  `test_optical_failure_evidence` — **57 passed**.
- Clean temporal worktree `bf4509b`: `test_feedback_result_age`,
  `test_feedback_pose_evidence`, `test_lit_geometry_renewal` — **40 passed**,
  including the exact retained 528.9565 ms optional-renewal timing case.
- Clean root integration host `cad26b0`: `test_geometry_requalification`,
  `test_fixed_optical_geometry`, `test_lit_geometry_renewal`,
  `test_feedback_result_age`, `test_feedback_pose_evidence`,
  `test_admission_envelope` — **67 passed**.

Native owner subsequently reports **399 real guidance/standby checks passed** on
`4b180f4`, including valid/invalid terminal boundaries, firmware-style epochs,
12/16-second limits and stale/mismatched monitor controls. Root confirms these
results. The reviewer inspected exact native integration source equivalence;
native compilation was performed by the owner in the root-coordinated build slot.

No native compile, camera, serial or installation was performed by this reviewer.

### Exact attended cases added to combined review

Root's run `1795681719870529000` confirmed durable startup-anchor recovery and six
real lit renewals, then exposed two distinct remaining cases:

- Sequence23, frame34694: post-pose freshness passed at **528.9565 ms**, followed by
  `Lit geometry renewal exceeded600ms evidence window` before observation
  publication. Optional proof consumed the remaining age; this is a fourth expiry
  seam beyond the initial three changed by `943188b`.
- Sequence26: a fresh observation at actual pose `[1801,2344]` had error
  **0.208727 cell**, triggering `Monitored indication left accepted intersection`
  after 32 accepted observations. This directly exercises the hold-boundary policy.

Exact result files remain in the root-owned run's `events` directory under
`~/Library/Application Support/Physical Go/LaserDriverLogs`. Root verified full
OFF at1795681933.7643583. These are runtime failure cases, not completed physical
acceptance of the proposed fixes.

The proposed fourth-seam fix uses an optional-proof budget hint before spending
100 ms, deferring renewal if insufficient time remains while publishing the
ordinary spot only through the unchanged final 600 ms checks. Actual proposal and
commit expiry remain typed failures. Review conditions: malformed/future clocks
cannot become deferral; late publication after skip still rejects; repeated
deferrals must fall back to dark refresh before another five-frame batch exhausts
the existing geometry/light lifetime. Scheduling estimates grant no authority.

### Admission state-epoch counterexample

`PhysicalMotorAdmission.Monitor.sameController` in `ba36928` requires epoch equality,
and `observeMonitor` permanently rejects the episode on a mismatch. Firmware
`GameplaySupervision.h:updateGameState` increments `gameEpoch` whenever state code
**or torqueMask** changes. During normal cold GA, `beginHold` enables the two axes
separately while `gameEngaging` keeps phase B. A native observer can see a fresh
admissible bootstrap sample at B/epoch2 followed by fresh B/epoch3 or epoch4 during
engagement. This healthy progress disables grace permanently; the positive tests
use only a fixed epoch and miss it.

Requested correction: retain exact controller token and control generation; treat
a strictly advancing state epoch as a new evidence segment requiring fresh
two-sample progress, without changing the original cold origin or 16-second cap.
Epoch regression, replaced session/generation and stale/invalid evidence still
deny grace. Add a firmware-style multi-epoch positive control. This is a functional
reliability defect in the proposed grace, not an unsafe authority expansion.

**Resolved in `4b180f4`:** implementation now fixes token/control generation,
accepts strictly advancing epoch as a new liveness segment, and requires its next
advancing same-epoch sample without resetting the cold origin. Pure tests include
B epochs2→3→4 and regression rejection. Source approval includes the correction;
the uncorrected `ba36928` alone is not approved. A state transition exactly at the
12-second boundary can still conservatively deny grace before the second sample;
this is an explicit provisional policy limitation to observe, not a physical law.

Offline approval will identify source revisions and evidence explicitly. It does
not establish physical reliability, installation, a sustained-light acceptance
result, or a full-board calibration. Canonical integration status remains owned by
the issue coordinator and root.
