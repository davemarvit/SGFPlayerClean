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

### Predicted dark acquisition: final source review

Runtime `845b9fad58db4086db71b795240e79861fe49600` is approved for root's
integration checks under the explicit `pinned_dense_dark_acquisition_v1` binding
policy. The primary three-point model and pinned dense coefficients remain
unchanged. A fresh measured origin translates the model-only initial proposal;
both absolute and translated nonlinear corridors must be enclosed. Interval
subdivision covers the asynchronous motor rectangle mathematically rather than
sampling only a synchronized trajectory. It is not a physical model-error bound.

The acquisition proof remains separate from the measured anchor through actual
coarse settlement, recenter, causal prelight and post-POSE checks. Only successful
current-generation optical publication clears it. First post-coarse detection is
board-wide and retains competing-cluster/newest-frame checks. A large unique
on-board miss proceeds to ordinary measured correction rather than an error-size
abort. No model-predicted location is published as an observed spot.

Review found and the owner repaired three concrete issues. Unavailable fast
proposals now have a typed decline: before travel, retain the measured start;
after partial travel, reacquire its actual location before local correction.
Malformed models and unsafe actual receipts still fault. Acquisition commands
cap their waits to the remaining approach allowance and check the deadline before
reacquisition. Finally, the local guard needs 10 pixels of endpoint clearance
(existing 5-pixel uncertainty plus 5-pixel retained margin), although the dark
model corridor needs 5. Candidate generation, every actual receipt and prelight
now enforce that transition requirement. The planner may try a point within the
existing 0.20-cell target radius; actual optical acceptance is unchanged. The
existing inward recovery remains available after a far observed edge miss.

Reviewer independently verified all 12 production hashes in each frozen cohort:
361/361 targets reached from the saved anchor, 361/361 from center, 70/72 from
opposite perimeter and 54/72 under repeated drift/residual stress. The two normal
perimeter refusals precede any command or observation, matching existing initial
prelight constraints. Stress stops retain deadline, local envelope, actual
landing-headroom and drift protections. No sampled 5-pixel margin breach occurs.
The exact historical D4 start/destination uses two dark waypoints, four motor
commands and two optical observations with no local corrections. Its reported
12.84 seconds is an observation-cycle model, not measured physical latency.

PG02's separate `78d8c73` residual audit distinguishes 86 fit observations,
11 interspersed nonfit observations and 71 later chronological endpoints. On the
later legs, observed-origin nonlinear translation reduces median pixel residual
from 4.805 to 1.712 and maximum from 10.701 to 5.865. Reviewer inspected the
formulas and artifact; these compare predictions with recorded actual poses and
pixels, not a model round-trip with itself. The longest retained leg is 3.053
cells. Correlated short trajectories and model-consistent simulations do not
establish a global physical jump guarantee or continuous physical-path accuracy.

The owner reports 79 focused passing tests, including 13 acquisition tests.
Reviewer ran no build or tests. This approval covers the bounded acquisition
source; root owns integration, installation and attended practical timing.
Persistent same-target learning/cache is not implemented by this checkpoint and
is not claimed complete here.

Final durable acquisition evidence is committed as `cbfbfab`, with readability
follow-up `996e912`, under `Firmware/Experiments/PredictedDarkAcquisition/`.
Reviewer matched all five saved cohorts' twelve hashes to the frozen runtime and
verified the separately pinned PG02 residual artifact hash. No runtime code
changed while those final cohorts ran. This completes the finite source/evidence
review for predicted acquisition; physical timing and same-target memory remain
distinct subsequent work.

## Subsequent native recovery and arming episodes

Root requested two narrow native repairs from this reviewer, with independent
root review before integration. `7269977` permits disabled recovery only after an
explicit recheck, a fresh matching real hardware OFF and current clear post-OFF
camera evidence. Its scoped OFF pump remains alive until recovery; the separate
physical-switch confirmation and normal placement evidence are unchanged. The
reviewer-run continuity suite passed 263 checks. Root subsequently reported
physical dark-only confirmation of already-placed White D4 without a point cue.

`02818a0` fixes an arming timer that retained the entire age of a healthy motor
session. A later legitimate cold restart after a hand stop could immediately
trip the old 12-second deadline. Matching admissible stable health now completes
an admission episode; a later current matching arming receipt starts another.
Unfinished cold episodes still span revision churn, and full OFF resets them.
The 12-second arming and 3-second transition limits are unchanged. The reviewer
reproduced the false timeout using the new test against the installed 0.263
shared runtime. Root's matching candidate passed 379 standby plus 263 continuity
checks, and root reported subsequent physical hand-stop/rearming success in
0.264. Baseline runtime/test hashes and command are durable under
`Tests/Fixtures/GuidanceHandRearming/baseline-control.json` in that source commit.

## Runtime geometric registration and exact failed dark batches

Approved host `a854f675adbf59bee6412fc098d5610341d1d036` for root integration and
attended acceptance. Runtime `SetupBinding._check_prepared` now uses a dedicated
geometric admission policy across initial checks, warm admission, alignment
preparation and dark qualification. Generic registration/calibration defaults
remain unchanged. ECC is an optional transform proposal and diagnostic score;
brightness alone no longer vetoes a geometrically supported runtime mapping.

Each selected transform retains the 25-pixel displacement limit and ORB inlier
residual checks, plus independent forward/backward tracks at commissioned grid
neighborhoods: at least 40 total, six per quadrant and three per outer edge,
with median/p95 residual limits of 0.5/1 pixel. This is spatial observability,
not proof every board surface pixel is unobscured. Native hand/alignment/grid
checks, existing temporal dark-to-lit checks, geometry lifetime and final
600-millisecond optical proof remain. No model or calibration is refitted.

The constructor now retains the attempted new three-frame batch and median when
registration/qualification fails before assignment. It does not borrow the old
geometry's transform or frames. Missing/nonfinite transforms remain diagnostic
null; existing full-OFF/quiescence ownership controls disk writes. Capture starts
after the three sources have been prepared and is not an all-fault capture claim.

The reviewer inspected final source/tests and independently matched all five
runtime hashes, the replay runner, all 16 recorded inputs and live-failure
provenance. The owner reports 155 passing tests. Durable replay in
`Firmware/Experiments/DarkGeometryAdmission/` records nine accepted controls and
four geometric rejections, including exposure/shadow/occupied-edge positives and
blank/large-shift/major-occlusion negatives. Complete legacy registration also
accepts later frame 7714 (`baseline_error:null`). The exact failed Q17 dark batch
is unavailable: this later image does not reproduce or explain that failure.
No reviewer hardware, camera, UI, installation or benchmark action occurred.

A separate initial no-blocker assessment of visible-fine `fc6747e` was superseded
when the assigned second reviewer identified missing preflight enclosure of
firmware-permitted in-flight overshoot/held-axis drift. Its repair and final
approval belong to that reviewer; this geometry approval does not approve the
unrepaired visible-fine checkpoint.

## Temporal grid-aliasing repair — frozen f3b8d43

Independent source review approves host `f3b8d4366b6f948a63283e94d5c7ecb5358262b0`
for root integration. Both production files were independently confirmed identical
in root integration `5de5479de732c68518f22c433fbb40cbef42d4a0`. No remaining
source blocker was identified. Root reports 112 affected tests and mandatory
paired checks passed; the reviewer did not rerun those suites or use hardware.

This failure has exact retained evidence: frame 21221 and dark batch 21188–21190
from feedback-62 in run 1795593238703871000. Original raw tracking reproduces
140/160 valid tracks, median 0.069 px and p95 53.709 px, with 13 grid-period
outliers. Diagnostic robust fitting supports a small coherent displacement but
is not used to admit runtime frames. The final change normalizes each grayscale
tracking input with global board-ROI 5th/95th percentiles. Raw feature selection,
original pyramid level 2, 85 percent global retention, six tracks per quadrant,
0.5/1 px median/p95 limits, native-grid/current metadata checks, geometry lifetime
and final 600 ms optical gate remain unchanged. Cached normalization uses a
separate image. No runtime refit, robust outlier filter, brightness veto or new
local survival threshold is introduced.

Normalized exact tracking retains 147/160 with median 0.077 px and p95 0.207 px.
Five ambiguous tracks remain; the unchanged p95 policy tolerates this minority.
The result reduces mismatches rather than eliminating all grid ambiguity.
Provisional shallower-pyramid and per-quadrant 50 percent proposals were discarded
after an existing occlusion regression and benign-exposure failure respectively.

The final recorded cohort accepts the exact frame, 3 percent exposure adjustment
and local 3 percent shadow, and rejects all 22 motion/visibility negatives,
including half/full/multiple board-pitch shifts, rotation, blank frames and
major quadrant/edge occlusion. The existing synthetic covered-quadrant control
also rejects. These are transformations of retained images with fixed native
corners, not independent physical observations or a universal motion guarantee.

The reviewer inspected source, tests and durable artifacts in
`Firmware/Experiments/TemporalGridAliasing/`; independently matched the replay
runner, four replay runtime hashes, four evidence hashes, four installed artifact
hashes, benchmark source/runner and all eleven benchmark inputs, four whole-path
runtime hashes and five inputs, and the supplemental whole-path provenance.
The exact failure bundle's ten retained files also matched its evidence manifest.
Recorded full-reuse median overhead is 0.61–0.84 ms, superseding provisional
shallower-pyramid timings. Production read_spot replay accepts post-gate ages
399/456/525 ms and rejects 829 ms. That finite replay uses repeated retained images
and injected capture/POSE delays, not live independent camera frames.

Per-call motion diagnostics now reach the existing failure capture before a
throw, including bounded finite outlier vectors and fresh coverage/displacement
statistics; no stale prior-frame proof is borrowed. Existing OFF/quiescence
ownership of evidence writes remains. Physical acceptance is still root's
attended preflight/run responsibility; no reviewer camera, controller, UI,
installation or benchmark action occurred.

## Exact dark-refresh residual repair — frozen 4dd6b58

Independent source/artifact review approves
`4dd6b58d72cde60bd6b801dc25c4ca7980470c8f` for root's single authorized attended
retry. Runtime bytes match integrated `968ba538d457c03fc34ed0b17b0d59e853817838`.
The only runtime changes are the two forward/back LK calls in the already-aligned
dark-registration validator, pyramid level 1 to 0, with an explanatory comment.
The temporal tracker remains normalized level 2. Existing ORB fit/residual gates,
25 px transform cap, distributed edge/quadrant support, 0.5/1 px residual limits,
native grid, hand checks, geometry lifetime and final 600 ms guard are unchanged.

Run 1795595051454342000, feedback-74 retained the exact failed dark frames
39377–39379. All fourteen retained files independently matched their manifest.
Actual 77-inlier ORB support passed: ECC candidate ORB median/p90 0.721/1.400 px,
but its aligned grid p95 was 1.178 px (ORB candidate 1.198 px), with spurious
neighboring-line jumps. The new local residual check accepts the unchanged ECC
homography with 328 tracks and p95 0.554 px. Full real registration passes each
source and the median; the complete constructor passes native-grid mismatch
1.831 px against 6.349 px, and source-to-median temporal p95 0.081/0.076/0.084 px.
The old post-H pyramid reproduces the failure. Committed replay uses actual ORB
matches, unlike the explicitly exploratory initial triage.

Owner reports 97 tests passed, including two exact regressions. Existing thirteen
saved-image controls preserve nine accepts and four rejections, including covered
edge/quadrant, blank and large movement; false-transform and concentrated-support
tests pass. The prior temporal level-zero covered-edge weakness is not ignored:
that control class still rejects for distributed visibility in this distinct
ORB plus aligned-grid path. This does not establish arbitrary-occlusion coverage.

Reviewer inspected `Firmware/Experiments/DarkResidualAliasing/` and independently
matched its exact replay's two source hashes, six evidence hashes, setup and
runner, plus the control replay's five source hashes, sixteen inputs and runner.
Root owns integration checks, installation and the single attended retry. These
are offline retained-image results, not physical acceptance. No reviewer test,
benchmark, hardware, camera, UI or installation action occurred.

## Overnight PG36 final-OFF receipt — 82e1113

Independent source review approves host
`82e1113e06069d7aa0b7390d251aa5f1a114575c`, based on installed `968ba538`.
No concrete source blocker was found. Producer and launcher must be packaged
together: version-1 final receipts are intentionally no longer accepted.

BridgeRuntime.close returns an OffReceipt only after worker/thread quiescence,
fresh backend OFF confirmation, matching generation-gate acceptance, publication
and successful backend close. The child serializes that actual returned proof;
no shared status alone can manufacture it. Producer checks exact final processed
identity, gate timestamp and shutdown interval. Parent checks child PID, version2,
exact v44 OFF, matching timestamp, successful close and publication/exit ordering.
Schema1 may omit motor fields only with this proof; explicit contradictory fields
and schema2 omissions reject. Historical failed receipts are not promoted.

The reviewer traced actual firmware disarm: laser and POWER_PIN go low before OFF
reply; STATUS reports the resulting OFF state. The existing host barrier requires
fresh OFF/DONE followed by a separately cursor-fenced exact STATUS response.
Owner reports 111 focused tests passed. Reviewed new regressions exercise real
runtime close, barrier, publication and child receipt with a fake serial peer,
including stale batches, wrong status, gate rejection, nonquiescence and backend
close failure. No reviewer tests, devices or installation were used.

## Overnight PG23 ambiguity metadata — 55c2ba3 static assessment

Static review of `55c2ba3f5569598881512914f8ec408fe29b6915` found no change to
placement or laser admission. Fit score searches and acceptance guards remain;
callbacks retain already-computed initial-outline/placement outcomes. Capture
occurs before witness reset; verification provenance is separate metadata.
A frame identity is included only for the exact current capture timestamp/epoch,
never substituted from a newer broker frame. Archive encoding and disk writes
run on the existing utility queue, with two files, eight representative events
per episode and a two-megabyte bound. The feature is diagnostic evidence, not a
recognition fix or complete tracker replay.

Performance is not zero-cost: initial fitting retains bounded attempt metadata,
and each rejected ambiguity frame constructs a local record before utility-queue
deduplication. It also recomputes assignmentOffsets already calculated by consume;
root requested a narrow follow-up to reuse that exact result before integration.
No new cache or decision logic is requested. No additional vision search
or image encoding is introduced. No runtime timing benchmark was supplied.

Owner's 1,426 subset checks cover storage/identity and exact retained-image
readings/footprints/placement-fit equality. Full PhysicalAI/Guidance integration
and the new app-level regression have only syntax checks so far. Final native
integration approval remains conditional on root's shared-module/full native
compilation and PG23 regression run. Reviewer performed source review only;
no native build, installation or hardware action.

PG23 follow-up `7ac2f6a3592a0d79d7cf60ad2b1b8351ab7608e3` was subsequently
reviewed and approved at source level. The live controller binds its existing
assignmentOffsets dictionary once, uses it for the unchanged ambiguity decision,
and passes that exact result into metadata capture. The standalone optional
fallback remains; no cache, new decision or payload expansion was introduced.
A new assertion checks that supplied offsets are retained. Owner frontend parse
and diff checks passed; that assertion and full runtime integration still await
root's coordinated native build. This resolves the duplicate-computation finding
without claiming zero metadata cost.

## PG26b accepted-target click — 36b0265

Independent source/test audit approves
`36b0265cdffed1d5c25dff9bcd2848fafe1b50d1` for root's combined native validation.
Production changes only the eligible state from approaching/adequate/refining to
adequate, plus its explanatory comment. Current point action, matching revision,
connected hardware, positive illumination confirmation, ordinary-purpose intent
and once-per-move identity guards remain. Action admission still checks current
clearance, session/thermal state, cancellation and recovery before the cue branch.
Acquisition/refinement no longer consumes the move's eventual click.

Owner reports 28 focused subset checks passed and the unchanged baseline fails
at acquisition-before-acceptance. Reviewed coverage includes both schemas,
first accepted light, repeated receipts, supersession/cancellation, wrong
producer/session, stale/future time, missing confirmation, darkness, simulation,
special-purpose silence, same-move retry and new-move/session identity. Broader
AI-laser expectations and the injected blocked-audio trigger now use adequate;
root owns the combined full-runtime run. The compatibility diagnostic string
first_light remains, while actual eligibility is accepted illumination. Dedup
remains memory-only across app restart. Host double-beep policy is separate.
No reviewer compile, audio playback, hardware or installation occurred; audible
onset timing still requires attended observation.

## Combined native validation closes metadata/cue build condition

Root reports combined native source `1f6fb91` passed all eight relevant suites
against shared runtime `07e065a48183`: accepted click 28, continuity 263,
ambiguous placement 57 (real PhysicalAI metadata case), standby 379, diagnostics
1,427 with retained R16 fixture and offset reuse, stone tracking 82, geometry 27,
and AI-laser 325; 2,588 total checks. This fulfills the outstanding full native
integration condition for reviewed PG23 metadata/reuse and PG26b accepted cue.
These are root-run results; reviewer performed no duplicate compile or audio,
UI, camera or hardware action. Optimized application build/installation and
physical acceptance remain separately owned by root.

## Temporal correspondence repair — frozen e5ffa0d

Independent source/artifact review approves
`e5ffa0decdb60ce6e6f7c5ef820f75efb2538980` for offline integration, with no concrete
remaining blocker. Release packaging must include new `bridge_correspondence.py`
and hash it with the integrated runtime. The frozen candidate is based on host
`968ba538`; combining other host changes remains root's integration responsibility.

This is an explicit fallback for an already-rejected temporal frame, not deletion
of disagreeing features. Original normalized pyramid-2 tracking, coverage and
coherent median motion gates run first. Only a passing median with failing p95
can attempt repair. Every originally valid track above one pixel must receive an
independent unique 41-by-41 half-resolution patch match in a bounded broad search,
including the observed alias and projected neighboring half/whole-grid locations.
Distinct-peak and reverse searches plus local subpixel/FB verification must all
pass. No suspect may be dropped; a last-suspect failure returns no partial result.
Original points, valid mask, denominator and anchor remain immutable. The original
0.5/1 px motion gates are reapplied to all original valid tracks, followed by
unchanged native-grid/current-context checks. No transform refit or anchor chaining
occurs. Fixed peak 0.8 and distinct-margin 0.1 qualify replacements only on the
already-rejected path, not ordinary-frame brightness. Missing alternatives,
flat/tied/nonfinite matches, reverse disagreement and refinement escape reject.
Count32 and measured100 ms work bounds fail closed; neither extends optical age.

The reviewer inspected owner tests for the above boundaries, native-grid/age
checks, coherent-motion/coverage no-call behavior, count/time budgets and exact
failure replay. Owner reports 133 focused tests passed. Independently matched
replay's five runtime hashes, 44 input hashes and runner, and whole-path replay's
six runtime hashes, seven inputs and runner. Durable evidence is under
`Firmware/Experiments/TemporalCorrespondence/` in the candidate tree.

The 62 recorded image cases yield nine accepts and 53 rejects. All 44 original
synthetic motion/occlusion negatives remain rejected. The only formerly rejected
cases rescued are exact57014 and its benign local-shadow variant. Exact57014
retains the same146/160 tracks; all nine suspects are repaired, final median
0.0603 px and p95 0.1227 px. Exact21221 still passes the ordinary path. The actual
dark39377–39379 constructor, native grid and all source checks also pass. A small
opaque patch remains accepted on21221 by both baseline and candidate; this is an
explicit sparse-visibility limitation, not a silently omitted negative. Perfectly
identical repeated-pattern images cannot prove absence of motion.

Twenty warm repeats record fallback median30.47 ms/p95 32.51 ms versus roughly4 ms
baseline rejection; ordinary-path differences are noise, not a claimed speedup.
The actual read_spot-path replay requires repair on all five repeated images:
nine nominal cases pass at447–577 ms after publication and three stale cases
reject at873–899 ms. The worst accepted replay has only23 ms below the unchanged
600 ms gate. It uses synthetic cadence/timestamps, repeated exact lit pixels,
three copies of the retained dark median and emulated controller/response calls;
it is not five independent physical observations or a live latency guarantee.
No reviewer heavy tests, hardware, camera, UI or installation were performed.
