# Offline cross-change safety review — November 24, 2026

This is a review record, not a competing issue register or activation authority.
[IntegrationChecklist.md](IntegrationChecklist.md) remains root-owned. Reviewer
used source, retained owner reports and test artifacts only: no hardware, camera,
UI, screenshots, builds or test execution. This isolated documentation worktree
does not alter installed or frozen runtime trees.

## Reviewed source and conclusion

PG33 host candidate **f2a75319f36d1257b6e9e272960ae19a2a30bbd5**,
`codex/feedback-gameplay`, is suitable for root's combined offline integration
and paired testing subject to the conditions below. This is not approval to
activate gameplay. Three findings were corrected during independent review:

1. Actual pose/containment was checked before PREPARE, although PREPARE changes
   gains; later illumination initially lacked a final actual-settlement check.
   `Firmware/bridge_feedback.py:145` now validates post-PREPARE actual pose within
   three counts of measured settlement, and bounds the resulting optical point
   using the measured anchor/response. `move` at line228 validates actual final
   settlement; every SWEEP and TRACK passes `prepare_light`.
2. A first repair queried POSE after PREPARE. Installed v44 rejects that command
   in its cue loop (`AimControl.ino:120–147`). `prelight_pose` at line166 instead
   requires a causal thermal pair whose preceding host ACK was dispatched after
   READY, with current generation, dark R state, held motors and stationary
   actual positions. Existing750ms thermal limits remain independent of the
   gameplay600ms camera limit. No firmware whitelist was weakened.
3. DARK can release motors under cooling policy (`AimControl.ino:584–587`).
   `ensure_ready` at line132 now queries actual state and resumes C through the
   supervised RS path before fresh actual-pose checks. Unknown/O/H cannot
   silently rearm. This path supports cooling; it is not a cold-only policy.

`read_spot` at line187 checks the optical frame's capture/arrival/publication
ages after processing and pose acquisition. Fresh independent safety metadata
cannot renew an old optical observation. Historical anchors retain their
timestamps and only bound reacquisition; clearance, lease, generation, actual
pose and thermal checks remain current. No calibration timing override enters
gameplay. Runtime retains cancellation and full OFF ownership.

## Evidence inspected, not rerun by reviewer

Owner reports240 passing Python checks:19 new feedback checks,134 existing
gameplay checks and87 other available bridge checks. The added cases explicitly
reject an optical sample aged601ms despite healthy independent metadata and
reject cache publication after generation revocation. Broad discovery also
reported16 missing retained-image fixture errors in the isolated tree; those
are an unresolved coverage limitation, not passing tests.

Reviewer inspected the actual-v44 harness source and
`/tmp/pg33-feedback-native-review/review-results.json`:249 feedback-light,
422 feedback-cooling and101 illegal-POSE-negative assertions passed in the
owner's ASan/UBSan run. The harness freezes production firmware, adds observation
probes only, and simulates USB/motors/time. Its callback waits for a genuine
emitted thermal pair with causal ACK dispatch at or after READY before each
initial SWEEP, repeated SWEEP after dark GOTO/reprime, and final TRACK. It checks
dark GPIO before proof, current generation, held stationary actual pose,
cooling DARK/RS and final beam-off/motor-power-off. The negative control confirms
POSE during PREPARE still fails before light.

Reviewer independently matched source SHA-256 values to that artifact:

- AimControl.ino: `f163dff26b1b435c19a8f6fa9865fd8fd8eafb673d1d0c3a2d359623a770d39b`
- GameplaySupervision.h: `2f1b714f5e1c2d193cd4ecdc7c4afd2e09247ddd1aa63c73b08c720237e1b0a4`

These hashes describe unchanged v44 before PG08's candidate firmware patch.
Combined-source tests must identify their own manifest. No optical accuracy,
sustained600ms freshness, physical thermal behavior or installed result follows
from this simulator evidence.

## Required integration conditions

- Merge PG33 with optical optimization7d8b530 preserving **both** changes to
  `bridge_hardware.acquire_spot`: pass the cached `observation` to `detect`, and
  use `near=project(H,[near])[0] if near is not None else None`. Dropping the
  latter breaks first whole-board acquisition; dropping the former loses reuse.
- PG06b1d2770f's pure `feedback_step_plan` is **not adopted** by PG33f2a7531;
  its wrapper retains the conservative15px edge proposal. Explicitly integrate
  the shared planner if its benefit is part of the batch. Static review found
  no blocker in its convex independent0..2-axis response envelope,5px error
  allowance,40px travel cap and original fallback. Physical response and speed
  remain unverified.
- PG08 firmware71e8df6 restores `coolingPolicy=true` when a released motor
  reheats to40–44C after a completed below40C/30s dwell. Static review found no
  blocker; the state epoch changes with the policy and existing v44 protocol
  remains compatible. Without this fix, stale CN10 can permit persistent
  holding without a new cool dwell. Starting cold alone does not exclude the
  later trigger. PG33's automatic C-to-RS is incompatible with an unpatched
  cold-only workaround unless an explicit guard rejects all cooling recovery.
  Root chose to prepare the PG08 firmware build/rollback offline; no upload or
  installed fix is claimed here. Final activation still requires that decision
  to be concretely implemented and verified.
- PG09/17's `PhysicalAI.pause()` source change was independently inspected:
  freezing phase/clocks before cancellation matches the guidance-fault path,
  makes nested pause inactive and preserves saved pending/capture state.
  No static blocker found. Coordinator reports211 owner-run checks and a
  baseline-failing timing regression; exact candidate commit was pending when
  this record was written.
- PG32c590b44's independent diagnostic sinks retain initiating fault evidence
  if optional history/trace fails; static review found no cross-change blocker.
  The original serial timeout cause remains unresolved. PG06a9dcb5ab adds
  blocked-delivery regressions rather than changing the600ms runtime policy.
- PG31 alignment002e4c7 remains under its separate independent vision review.
  This report does not substitute for that review or claim physical acceptance.

Root still owns final source manifests, combined paired acceptance, explicit
reviewed binding, installation/rollback and attended READY. The existing paired
standby result alone does not validate the new feedback point route. Native
first-light click remains once at the first acquisition flash; host final-target
two-beep feedback is separate, as confirmed by the PG26b owner.

## Subsequent combined-host inspection

Root requested a fresh read-only review of
`/Users/Dave/DYNAMIXEL-Go-Pointer-worktrees/issue-integration-20261124`.
Reviewed HEAD was `b434aa6f2c8d9cd09635c8b777224b5217bd4589`, plus root's
uncommitted `bridge_feedback.py` planner wrapper and corresponding documentation.
No new source blocker was found. The combined tree contains the PG08 firmware
repair, optical reuse, PG32 diagnostics, PG06a/PG07 tests, PG06b planner and PG33.

The integration correctly passes cached `observation` together with nullable
`near` to `detect`. Root's wrapper now calls `feedback_step_plan` directly with
the same six arguments and four-result contract; unlike standalone PG33 above,
this snapshot adopts PG06b. Larger proposals still pass current actual-pose
drift, fine18/10 or coarse108/58 movement limits, actual settlement containment,
post-PREPARE causal pose proof and fresh optical consensus. The convex response
envelope remains conditional on its stated model/uncertainty assumptions; it
does not prove physical response or latency. Runtime, lease, thermal-session
and cancellation implementations are unchanged by this combined diff.

Reviewed file SHA-256 values:

- bridge_feedback.py: `feb4e11c3280810982090929bc5cb70b0b6ca940c87db4ca0b5a0056eaff2a05`
- bridge_hardware.py: `c5e10a885eaa68753479671599cd544a6089fdb74ad2b7626c4a8f0da3defdf1`
- feedback_step_policy.py: `3ba8b5ce00306b8fb656a10c682f23b978d403359ea0a716e15d7079cdc79eb7`
- GameplaySupervision.h: `e6f7b0aecee94308b8ee74d4990a098d1595a006600d38e608475a7bac63ba65`

PG08's repair is now present in source, resolving that source-policy dependency;
this does not establish a firmware upload. Root's planned combined tests, final
commit/source manifest, paired acceptance and actual firmware/app installation
remain necessary. Reviewer ran only source/status/hash/whitespace inspection,
and did not run a build or test against the integrated tree.

## Full-board domain review and finite defensive follow-up

**Defensive source approved; full-board activation remains blocked.** Root's
subsequent integrated host `4c650ed6061b559cee2cb9cd220b6650b8b3c7cf` includes
uniform planner64983d0 and actual-pose/prelight4019f80. Reviewer inspected both
changes and matched the integrated runtime/helper hashes to the combined domain
audit: bridge_feedback.py `e915565d573e0473e3d69c30144d02901c2de33dad92e9bbbce9292b38560fba`;
feedback_step_policy.py `cb34b8ab0cdb70d10f1cfb8ab96e7336bc72d4b96fd2c0194ec0754e71ef3053`.

The initial PG06b envelope guarded only expanded edge proposals. The follow-up
now applies independent0..2 axis gains plus5px optical uncertainty to **every**
proposed step, including interior/fallback paths. It shrinks or rejects rather
than relaxing uncertainty. PG33 rechecks that same envelope at initial anchor,
fresh actual movement start, each coarse/fine settlement and recenter, optical
pose brackets, and post-PREPARE actual prelight pose. No source blocker found;
owner reports45 focused checks and baseline failures for three new regressions.
Existing clearance600ms, thermal750ms, cancellation, held-pose monitoring and
full OFF remain unchanged. This finite review adds no new hold-control design.

Seven physically observed targets are evidence, not a mathematical requirement
to commission each intersection separately. `SetupBinding.prepare` is currently
the explicit target allow-list gate. The feedback algorithm otherwise accepts
any admitted integer coordinate0..18, using the three-point model as a response
seed and measured corrections rather than a predicted final landing. A broad
allow-list would authorize attempts; it would not certify361 landings.

The necessary domain criteria are fixed valid grid/reference/context; finite,
conditioned seed response; a qualified actual acquisition anchor; contained
proposed and actual poses under the declared response assumptions; current
clearance/lease/thermal evidence; fresh optical consensus before0.20cell
adequacy; and bounded failure to full OFF. Current code supplies dynamic guards,
not proof that the physical response always satisfies0..2 gains plus5px error.
In particular, prelight containment predicts from the last optical anchor;
actual optical containment is measured after light. Correct encoders cannot
detect an incorrect optical response before that measurement.

Reviewer inspected owner-run combined reports under
`/tmp/pg06b-domain-combined-*.json`, using the exact frozen three-point seed,
fresh reference/grid, and saved anchor pose2069/2388 at image988.505432/160.051682.
The historical dense model is a **diagnostic simulated plant**, never a new fit,
live steering model or physical measurement. The6.42seconds-per-observation
timing is an explicit simulated budget, not measured candidate latency.

| Simulated plant and start | Reached | Failed closed | Margin violations | Minimum actual path margin |
|---|---:|---:|---:|---:|
| Seed plant, saved anchor,361 destinations |361|0|0|11.789px|
| Dense diagnostic plant, saved anchor,361 |358|3|0|7.389px|
| Dense diagnostic plant, center,361 |345|11|5 landing|−12.276px|
| Dense diagnostic plant, opposite perimeter,72 |42|28|1 landing +1 dark path|0.487px|
| Dense diagnostic plant, saved anchor,72 with2-count residual/3-count drift |20|52|0|9.755px|

These counterexamples prevent promoting conditional guard consistency into a
full-board containment claim. They are not reported physical failures. An
observed anchor5–10px inside the polygon also legitimately fails subsequent
uniform admission, because the uncertainty allowance requires10px nominal
clearance. Rejections must remain distinct from reached targets.

The minimal startup objective remains the existing three-point seed plus
feedback during play. No new model tour or per-intersection commissioning is
logically required by this review. The next finite action belongs to PG02/PG06b:
investigate the retained response mismatch and define a supported admission
domain or locally justified response bound without raising tolerances. Do not
expand to361 merely because the saved-anchor sweep mostly passes; subsequent
game targets start elsewhere. Root retains the paused game and activation block
while that explicit domain condition remains unresolved.

## Dense-response correction and attended-attempt recommendation

**This subsequent review supersedes the preceding domain block for the new
dense-response candidate.** On the user's explicit request to finish the
movement correction, reviewer recommends integrating runtime
`71fe9379ce73141eaa6a15a59f456c8f8d9ad9bf` with provenance helper272e4c9,
documentationf9dde4f and explicit policy115710f (candidate cherry-picks
f07f5c4/5d74355/a62f700). No concrete source blocker remains. The recommendation
is supervised attempts at all361 coordinates under `attended_full_board_v1`,
not a claim of361 physically validated landings or guaranteed completion.

The correction uses the frozen dense model only as a local response prior,
evaluated at the independently observed encoder pose. Measured optical pixels
remain the anchor; target landing and adequacy still require optical feedback.
It removes secant carryover and refreshes the derivative after every accepted
observation, including initial acquisition and prelight. It does not refit the
model or change the frozen three-point benchmark. The qualified dense model
SHA-256 is `adf8ace866254af7a82cdcfecb984ce539490689794d119357a85fb6fdcb42fa`:
86 fit observations from97 retained observations, with71 later chronological
endpoint measurements used for response evaluation, not fitting. Those legs are
correlated trajectories, not71 independent whole-board experiments.

PG02's independent audit reports the dense derivative covers all71 measured
endpoint responses under the unchanged0..2-axis/+5px envelope; maximum distance
outside the nominal response hull is2.047px, within the5px allowance. This
addresses the prior observed4/71 defect. Missing corner measurements remain
extrapolation uncertainty rather than a reason to require per-point calibration.

Reviewer found and verified repairs to two provenance gaps: changing grid
geometry and rehashing a binding could initially inherit an old setup proof;
swapping the historical PNG could likewise inherit fresh-geometry metadata.
The helper now pins the approved report to the full semantic fresh setup,
excluding only reference filepath for relocation, and requires the approved
fresh PNG hash. Original model/setup identities are retained rather than
rewritten. It loads copied parameters once per binding and performs no live
fitting. Both negative cases have owner-run passing regressions.

The observed motor hull is now explicitly a diagnostic in attended mode. A
separate optional strict policy still rejects extrapolation. Both modes enforce
finite poses, original motor bounds, exact provenance and derivative conditioning.
The original uniform optical response envelope and actual-pose, clearance,
thermal, cancellation and full-OFF guards are unchanged. Runtime logs extrapolation
with stage and actual pose. Reviewer also verified the new response calculation
precedes the final600ms optical-age check and cache publication; a delayed-response
regression is included. Owner's final focused set reports66 passing checks.

Earlier fixed comparison cohorts for dense actual-pose response without secant
carryover showed361/361 reached from the saved anchor,361/361 from center,
70/72 from opposite perimeter with2 bounded failures, and34/72 under drift stress
with38 bounded failures. None had a simulated5px margin breach; minimum margins
were12.959px,14.412px,10.575px and18.797px respectively. Hard hull gating instead
produced282/361 saved-anchor successes and79 coverage-only refusals; PG02 found
82 excluded diagnostic endpoints. These restrictions describe absent retained
coverage, not demonstrated unsafe responses outside the hull, and would make
ordinary play impractical. Final production-helper, source-pinned cohort
artifacts are being completed by PG06b; these earlier comparisons are not
misrepresented as those final runs.

The reviewable minimal first-game path therefore remains the retained qualified
response prior and three-point calibration, current setup/anchor checks and
measured corrections, with an explicit361-attempt binding. Root owns final integration/manifests,
installation, current same-geometry/anchor checks and fresh attended READY.
Known bounded failures remain failures; extrapolation is recorded, not relabeled
as physical validation. No additional calibration tour, arbitrary tolerance
increase, inaccurate fallback or hold-control redesign is required by this
review. No physical operation was performed by the reviewer.

### Final frozen-source evidence confirmed

PG06b committed the final production-helper artifacts as `d56d749`, under
`Firmware/Experiments/DenseResponseFeedback/` in the host repository. Reviewer
inspected `README.md`, `results.json`, runner code and the exact final source.
All four final runtime cohorts pin
`a288718604cf5f62eb512bf4b2184818526cce59` (71fe937 plus a docstring correction).
Reviewer independently hashed all ten listed production files and confirmed
every cohort matches the current candidate; the observed-leg artifact's helper
hash also matches. No reviewer test execution was performed.

The final production runs confirm the earlier table:361/361 from the actual
saved anchor,361/361 from center,70/72 opposite-perimeter with2 prelight refusals,
and34/72 repeated-drift stress with38 bounded refusals. All have zero sampled
margin violations. All seven previous center/opposite containment counterexamples
are explicitly included and now reach their targets. The production-helper replay
confirms0/71 endpoint violations, maximum gain-hull distance2.0471879349px.

This completes the finite source/evidence review. There is no remaining concrete
movement-response counterexample in the reviewed fixed cohorts. The recommendation
is to integrate and prepare the explicit attended361-attempt policy, retaining
the stated model-consistency, extrapolation and sampled-path limitations.
Physical use remains root-owned and requires fresh READY; this report does not
claim installation, actuation or a physically completed game.

## PG06a optical processing and fixed dark geometry review

This follow-up is an offline source/artifact review of the candidate based on
installed host `3f5802f5d773e5b5464c3c9f49260a74cf8f7cfd`. The reviewer performed
no camera acquisition, controller access, application change or test execution.
Root retains installation and physical acceptance authority.

The exact five-frame median (`f7bd508`) preserves pixel values, float64 result
type, source immutability, selected-subset behavior and existing fallback counts.
Owner tests cover all 3,125 ordering/tie patterns and additional byte, layout and
dtype cases. The corrected benchmark explicitly records requested OpenCV threads
1 versus reported 10; it does not claim verified single-thread timing. Median
acceleration alone cannot resolve the logged 0.513–1.632 second registrations.

The geometry candidate moves full reference registration into dark preparation.
Its immutable baseline is the exact median of three distinct, ordered dark
frames, with source IDs/hashes and a homography fitted to that median. Every
subsequent decoded image is independently checked against the original anchor:
current identity/clearance/native grid, forward/backward feature tracking with
spatial coverage, and fixed photometric comparisons. There is no transform
chaining, illuminated replacement baseline, reused hand verdict or retimestamped
optical result. The trusted BrokerStream verifies each exact decoded frame before
passing it to detection; transformation admission also matches frame object and
snapshotted metadata, preventing mutated metadata from borrowing an old proof.

Review identified and the owner repaired geometry expiry between image analysis
and trailing POSE: geometry and all four optical ages are now checked after POSE
and again inside current-generation anchor publication. The 600 ms optical limit
is unchanged. The 10-second geometry lifetime is separate; a 4-second refresh
reserve is a scheduling heuristic, not a worst-case guarantee. Any overrun raises
and follows existing runtime cancellation/full OFF instead of accepting stale
geometry. In-gate checks are in-memory and introduce no file or image I/O.

Hold refresh uses explicit DARK, approaching/laser false, existing QG/RS cooling
recovery, qualified dark preparation and silent TRACK. Adequate status returns
only after a new accepted observation. Installed native source `c53ac050` admits
this lifecycle without restarting cold arming, repeating the target click or
changing game clocks. Faults retain the existing interruption path. A full-path
replay also exposed a pre-existing duplicate `observed_at_uptime` keyword in
observation logging; the candidate preserves the sample timestamp using a
dictionary merge, with a regression and successful real `read_spot` replay.

A transformed-image control displaced only a narrow top-rail strip by 8 pixels.
Both original full registrations also accept this edit (root independently
reproduced 1,524/2,160 inliers); it does not establish a regression in fixed reuse.
An attempted 6-by-6 tile rule rejected a benign 3% exposure change at genuine
0.948 correlation, introducing a false rejection rather than correcting numeric
error. That extra rule was withdrawn. The reviewed contract retains whole-board
and quadrant photometric checks, feature tracking and all current native guards,
without claiming detection of every synthetic local deformation. Recorded
dark-to-lit images remain a positive control. These are saved-image workload
tests and transformed-snapshot controls, not newly captured physical motion or
independently observed live frames.

### Frozen PG06a source and evidence approved

The final owner checkpoint is `0ed9ed01d6989fb7adc93c89b8918eb807bcb210`,
following median checkpoint `f7bd508`. Reviewer independently verified all four
production source hashes and the runner hash in
`Firmware/Experiments/OpticalFreshnessPG06a/fixed-geometry-replay.json`, then
confirmed those production hashes also match root integration
`ab1e4bdd8fef892f3a41343c755a9f153a761bb1`.

All nine modeled normal cases pass at 407–546 ms after gated publication; all
three deliberately overloaded cases reject at 829–856 ms. The repeated cases
inject 180/260 ms image delivery lag and 68/101/145 ms trailing POSE delays.
The seven required transformed-snapshot negatives reject for pixel/coverage
reasons: 2/8 pixel global translation, 0.5-degree rotation, blank image, covered
quadrant, covered edge and a localized rectangle reduced to 45% brightness.
Unchanged occupied lit pixels, global 0.97 gain/+2 offset and localized 3%
shadow all pass; their minimum correlations are respectively 0.999087,
0.998599 and 0.978650. The narrow rail edit remains an explicitly documented
baseline-and-candidate accepted control, with no runtime test-image exception.

The owner reports 171 focused passing tests, including expiry during collection,
after POSE and at publication, metadata mutation, cold/warm lifecycle distinctions
and failed refresh without relighting. Reviewer inspected source, tests and
artifacts but did not execute tests. The offline runner exercises real decoding,
per-frame geometry, detector, event logging, final optical checks and publication;
motor response, supervisor and timing inputs are modeled. Its repeated composite
images are not the unsaved lit batches from the physical failures.

No concrete source blocker remains. This checkpoint is approved for root's
integration and installation checks, preserving the 600 ms limit and full-OFF
contracts. Root's paired checks, independent replay and attended live timing
acceptance remain distinct. The final finite replay has about 54 ms minimum
headroom and does not establish scheduling-tail reliability. The review does not
claim installation or physical closure of PG06a; the coordinator separately owns
the audit of the original safety-delivery I/O repair.

### Attended follow-up: first-lit photometric rejection

The next root-owned physical attempt on integrated `ab1e4bdd` failed at
`Fresh optical geometry photometric mismatch`, before any target travel or
600 ms expiry. The exact report is
`LaserDriverLogs/1795583944716588000/events/1795583991301794000-feedback-31/result.json`.
Dark geometry qualification and fresh prelight checks passed. First lit frame
29205 passed fixed-anchor feature tracking and native-grid checks, then rejected
about 225 ms after capture. The failed PNG and individual regional correlations
were not retained, so the visual cause cannot be reconstructed or asserted.
Root subsequently reported direct full OFF; PG36 receipt handling is a separate
integration issue owned by root.

The unmasked 0.95 threshold in every quadrant is a new restriction. Existing
`AlignedView.reuse` has no correlation gate; original full registration uses a
global 0.95 fit after optional bounded foreground exclusion, retaining at least
85% total and 70% per-quadrant coverage. These are different admission policies.
The bounded follow-up therefore evaluates the actual baseline contract and
retains exact rejected-frame evidence rather than lowering a number or treating
the unsaved failure as a diagnosed exposure event. Evidence retention must remain
bounded memory before cancellation, with raw-image encoding and persistence only
after confirmed full OFF and quiescence.

The user subsequently clarified that brightness similarity must not independently
veto otherwise measurable geometry. The agreed candidate therefore makes current
whole/quadrant correlation diagnostic-only, including unavailable/nonfinite
diagnostic values. This intentionally changes the lit-frame admission policy;
it is not described as preserving the former photometric contract. Initial dark
registration, original fixed-anchor feature tracking, spatial support, current
hand/native-grid checks, frame ownership and freshness remain required. Detected
board/camera movement still rejects; this change does not implement shifted-board
remapping or claim compensation for a changed coordinate system.

The reviewed repair is now frozen as
`dce8955d5cec9d342e0239fdfb68cd6a3ae71ac6` in the host repository. Reviewer
independently matched the four production hashes and runner hash in
`Firmware/Experiments/OpticalFreshnessPG06a/PhotometricPolicyRepair/replay.json`
to that clean worktree. Owner reports 119 unique passing focused tests. The
source and tests explicitly cover low/NaN/failed correlation as diagnostics,
preserved shifted-geometry refusal, exact immutable failure snapshots, strict
full-OFF/quiescence flushing, exclusion of new operation admission during disk
work and preservation of OFF on diagnostic write failure.

Failure retention is bounded to two terminal operations, each at most 128 MiB.
It captures exact broker PNG/metadata, decoded image, immutable dark baseline,
reference, transforms and available diagnostic scores. A failure before score
calculation records that stage rather than fabricated correlations. Capture does
no encoding, hashing or disk I/O. The sole operation coordinator flushes after
the real OFF barrier and before admitting another worker; the priority-stop lock
is not held during image persistence. This path does not currently retain a
successfully acquired batch that later fails only the post-POSE age check.

The final workload replay accepts all nine modeled nominal cases at 400–538 ms
post-gate age and rejects all three stale cases at 816–824 ms. Six motion/support
controls reject: whole-board 2/8 pixel translation, 0.5-degree rotation, blank
image, covered quadrant and severe localized shadow. Covered-edge and thin-strip
edits pass with sufficient remaining feature support; this visibility limit is
explicit, not an assertion of complete pixelwise visibility. Occupied lit,
97% gain/+2 offset and localized 3% shadow controls pass. Diagnostic correlation
does not admit a frame whose geometry or current hand/grid evidence failed.

No concrete source blocker remains for `dce8955`. Reviewer approves root
integration/installation checks under the user's explicit photometric policy.
Physical acceptance remains open: the failed live image cannot be replayed, the
finite timing cases are synthetic and repeated composite images, and actual
shift compensation is separate work. Reviewer performed no tests, image
acquisition, app changes or hardware operations.

### Held indication: bounded SWEEP fixes the warm DARK acknowledgement

Root's next physical attempt produced 16 valid optical observations, nine dark
corrections and an adequate point indication before `No reply for DARK` at the
first held-geometry refresh. The reviewed report is
`visibility-repair/live-dark-refresh-stop/run/events/1795585249455797000-feedback-43/result.json`.
This failure is distinct from optical freshness or brightness admission. Root
reported full OFF and owns current-anchor refresh; the reviewer did not change
calibration, response coefficients, cached anchors or hardware.

Actual v44 source explains the acknowledgement failure. In `AimControl.ino`,
`heartbeatOnly` consumes DARK while `markerActive` (TRACK), switches the laser
off and, when cooling policy is false, returns without `VIEW DONE`. The cooling
branch schedules a later acknowledgement. SWEEP instead leaves `markerActive`
false: idle monitoring queues DARK for the normal command handler, which emits
`VIEW DONE` after optional cooling. GA already admits the corner-session SWEEP
mode. No new firmware behavior is required.

Reviewed host checkpoint `802537a290321e93011a604737e9dd7014e2b754` changes only
the two hold illumination calls: initial `enable_target(target, False)` uses
existing purpose-dependent cue behavior with SWEEP, and renewal uses silent
SWEEP. Fresh dark preparation, causal prelight pose, current optical acceptance,
truthful dark/approaching/adequate states, cooling QG/RS, generation cancellation
and full OFF remain intact. Native target-click deduplication and game clocks
receive the same status transitions; no cold arming is reintroduced. Each light
interval also retains the existing firmware 60-second SWEEP limit, while normal
geometry renewal occurs much sooner.

Reviewer inspected the actual firmware harness, not just mocked host tests.
Its negative control injects serial DARK during real idle `monitor` processing
and reproduces TRACK's missing receipt. Positive scenarios execute three repeated
six-second SWEEP/DARK/PREPARE cycles in both warm and cooling/RS states and assert
the required receipt; another asserts timeout and full OFF. All four production
firmware hashes match `bounded-hold-offline/review-results.json`. Owner reports
1,850 assertions passing under ASan/UBSan across these four scenarios and 41
feedback plus seven cue/capture host tests. Reviewer performed no build or test.

No concrete blocker remains for this bounded host-compatible fix. Source review
approves root integration/installation checks; actual held-refresh acceptance
remains a root-owned physical check. Firmware source and installed firmware are
not modified by this checkpoint.

### Historical startup seed and fast-acquisition design

Reviewer approved root's concrete startup-anchor candidate with SHA256
`42a193f22c4b76dbc045b4eea91706f5c3584361a4c3e41f0059164522f9ea08`.
Compared with installed `d9a5642/artifacts/binding.json`, only
`feedback_first.initial_anchor` changes. Its pose [2551,2197] and reference pixel
[1322.1947021484375,698.7677612304688] exactly match the last accepted observation
of frame 42341 in result SHA256
`1298809ee0cae6f3adc09f4985f3426cd6e8de2f5b7b335fc42bde2d10faf40f`.
Only DARK follows that observation in the report. Root owns the separate full-OFF
receipt and links it in external release provenance. This is a historical
acquisition seed, not fresh optical evidence, a target command or a model refit.
Actual-pose guards and fresh observation still precede correction.

No code requires an empty intersection at the acquisition anchor. A later genuine
point request can briefly observe the current pose on the newly occupied point
before moving to its new target. Separately, native resume restores pending
placement and can permit its cue on uncertain occupancy; positive stone evidence
suppresses that cue. Root was advised to keep pointing inhibited through dark
verification of the user's confirmed White-at-D4 placement, rather than treating
the seed update as a guarantee against another pending D4 request.

The design checkpoint `5bd77c4` is approved to proceed to implementation review,
not installation: restore a distinct predicted dark acquisition using the pinned
full dense model, then freshly observe and correct. Keep real motor bounds and
command spans, actual settlement/recenter checks and a continuous nonlinear
model corridor for asynchronous-axis travel. The corridor is a model enclosure,
not a certified physical error bound. Neither the local 0..2-axis envelope nor
the measured 5.865-pixel short-leg residual certifies an arbitrary whole-board
jump. Acquisition needs its own explicit policy/proof context through prelight
and post-POSE checks; predicted pixels must never replace an observed anchor.

First post-coarse reacquisition should examine the board-wide candidate set:
a successful near-only search can conceal a competing spot outside its radius.
Retain temporal consensus, newest-frame support, ambiguity rejection, current
600 ms evidence and 0.20-cell final acceptance. A large unambiguous on-board
initial miss is recoverable, not an error-size-only abort. Finite evidence should
include the exact D4 journey, existing corner/perimeter cohorts, retained landing
residuals, large-miss recovery, competing reflection, actual-settlement drift and
interruption. Command counts and optical cycles are distinct from live latency.
Same-target remembered poses may later improve initial guesses under their own
versioned provenance and mandatory remeasurement; no global learner or blanket
per-intersection commissioning requirement is approved or introduced here.
