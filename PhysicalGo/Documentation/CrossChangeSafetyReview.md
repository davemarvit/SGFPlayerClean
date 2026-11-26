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

## PG37 pure motor admission — 9a6e5f3 plus 54e4180

Independent source review approves `9a6e5f3` with test-only follow-up `54e4180`,
based on native `1f6fb91`. Existing possible-power, cold-admission and handoff
assignments map directly to pure reducer events. The 12-second timeout remains
before full-OFF consumption, the three-second handoff remains independent,
transient recovery suppresses only cold timeout, authenticated active receipts
finish cold admission, and disabled release clears only possible power. Play
session changes clear only handoff. The ordered typed blocker preserves the old
ten-input conjunction. Receipt authentication and all command/game authority
stay in the guidance facade. Optional trace events use the existing bounded,
nonblocking utility writer; keying now includes power/action and deadline starts.

Owner reports 4,096 four-event sequences, 1,024 gate combinations and explicit
boundaries passed (312,326 assertions). Reviewer found a new unrun facade fixture
accidentally expired thermal evidence while testing stale camera: 100+710 ms
exceeded750 ms. Follow-up54e4180 publishes fresh holding status at the advanced
clock while leaving the camera old; no production change. Eight new facade
assertions and existing standby/continuity integration remain root-owned. Four
retained evidence hashes independently matched. Historical persistent-OFF cause
is explicitly unproven; this extraction does not claim to fix that live cause.

## PG34 board-check help — 2c79bde plus c7d471c

Independent source review approves `2c79bde` with
`c7d471ca4d9f02145f30d8b47775e6ceeb5bdc8d`, pending root's full controller/view
compilation and integration suite. Presentation waits three seconds and at least
three fresh assessments, lists at most eight correctly oriented points and
refreshes at most once per second. It retains waiting history across alternating
ambiguous/stable observations without changing recognition witnesses, move
acceptance, timing or laser admission. Existing navigation opens Camera & setup;
no reference capture or recalibration is performed by this feature.

Two concrete reviewer findings were repaired. First, zero accepted moves during
a human turn may include a visibly placed but ambiguous first stone; advice now
uses empty-startup wording only in checking phase, consistent with the existing
startup-empty requirement. A first-human-move regression confirms no empty-reference
advice, no premature accepted move and eventual normal recovery. Second, actual
ExperimentModel pre-consume interruptions use camera_hand_obstruction,
camera_waiting_for_dark_evidence and camera_alignment_rejected. These now clear
help/grace directly; regression cases exercise all three real reason strings,
not only synthetic hand observations passed into consume.

Owner's standalone helper passed54 checks; full controller/view integration and
new repair regressions are not yet run by the reviewer. The 600-frame retained
startup metadata source hash independently matches. It does not reproduce pixels
or diagnose a bad reference. PG34 and PG37 source changes have no conflicting
authority: one is presentation only, the other preserves authenticated admission
bookkeeping. No reviewer build, hardware, camera, UI or installation occurred.


## Supervision file-I/O isolation — e57e341 plus 9594381

Independent source review approves the frozen host isolation and origin-fence
follow-up in supervision-io-isolation-20261125. Periodic binding hashes and
metadata reads run in a separate file-only daemon. Publication under the lease
gate checks generation, request identity, admission object, reader, binding,
scope, hash and stop state. Lease-only renewal remains valid. A new admission
gets a separate persistent reader and nonblocking reader lock; old completion
cannot overwrite newer hand evidence. Persistent readers retain their existing
independent safety-channel and frame-order checks.

The supervisor consumes cached evidence through the unchanged 600 ms age gates
before thermal service. A stalled refresh therefore expires authority rather
than extending it. File-only threads are excluded from actuator quiescence and
shutdown joins; cancellation and publication fences reject their late work.
Optional thermal JSONL work uses a bounded best-effort daemon queue with visible
drop/failure counters and no shutdown join. Neither file daemon owns a controller
or grants movement authority. This removes identified synchronous file paths; it
does not establish the historical live fault's cause or guarantee live latency.

Reviewer independently ran all 12 initial test_supervision_io tests (1.138 s),
then reproduced a concrete diagnostic race: an old session's service completion
could update replacement-session maxima and be logged under the new identity.
Follow-up9594381 snapshots session and statistics key together, publishes new
session/key under the same lock, discards replaced-session completions before
statistics/log-state mutation and queues the captured immutable identity.
Controller service and log offering remain outside that lock. The constructor
placed under the lock performs no controller or file I/O. Reviewer inspected the
final diff and independently passed its new origin-race regression. Root reports
27 focused checks and 301 combined host checks passed in integrated2f8c4da.
The separate timeline utility in that integrated commit was not independently
reviewed here. No source blocker remains for the isolation/origin-fence change.

## Native integration and PG34 wording follow-up

Root reports all nine combined native suites passed after PG37 and PG34 repairs:
motor admission312326 assertions, standby387, continuity263, checking helper54,
checking controller30, ambiguous placement57, AI-laser325, accepted click28 and
diagnostics1427. This fulfills the previously pending full-runtime integration
condition for the reviewed production changes. These are root-run checks, not
independent reviewer builds.

Reviewer also approves copy-only79be6e5830ab5f87b5322d7866c952ce975178a4.
Nonempty recovery now says “Leave the stones in place and keep hands clear.”
The first-human ambiguity regression asserts that exact prefix. It avoids
implying removal of a visible but not yet accepted stone and changes no decision
logic. Root's final0.266 integration3fe6290 is rebuilding with this wording;
installed0.265 remains unchanged pending root's checks. No reviewer hardware,
camera, UI, installation or heavy build occurred.


## PG37 cold OFF transition liveness — a24572e

Independent frozen source/artifact review approves a24572e based on native
3fe6290. The production change adds nine lines only in matchedTransition.
A schema2 OFF handoff may advertise a nonempty setup before native has adopted
any setup. The exception requires OFF action, not ready, no possible motor
session, no adopted setup, the existing capability and exact nullable session,
camera context and epoch. The caller still authenticates producer, revision,
mode and age. Successful matching supplies liveness only: uncertain illumination
remains unsuitable for recognition, no setup is adopted and no motor permission
is granted. The existing three-second transition deadline remains unchanged.
Only a subsequent genuine full OFF completes setup admission or cancellation.

The fixture generator exercises the production host parser, lease gate and
publisher from installed2f8c4da using a fake command sink, two OFF writes and no
threads or worker. It is explicitly not the missing raw live status. Retained
native trace transitions precede the context latch, but cannot establish all
fields of that live status. Reviewer independently matched four host source
hashes, two native input hashes and both validation log hashes. Exact baseline
3fe6290 fails “Actual host cold OFF transition must not latch
standby_context_changed”. Candidate runtime ef06b96b41ea passes74 new checks;
owner reports existing387 standby and263 continuity checks,724 total.

Tests cover repeated current transitions without revision churn or authority,
eventual OFF adopting a different setup, rejection after setup becomes known,
foreign/stale revisions and identities, absent capability, simulation mode,
malformed optical claims, three-second timeout, nullable closing scope and
explicit Retry. No remaining source blocker was found. No reviewer builds,
installation, camera, UI or hardware operations occurred; physical validation
remains root-owned.


## Standby completion and post-image motor proof — 6c11b8f / c235548

Independent frozen source review approves host standby fence6c11b8f. Unchanged
production firmware can answer QG inside SB's monitor before standby completes:
normal RN10 precedes HN10, and a cooling-release query at61 ms yields BP10 before
CP10. Only an explicit current pending handoff may wait through dark, powered R
or cooling-policy B. The original two-second deadline shrinks, never renews.
The barrier still checks lease, worker quiescence, camera and controller health;
QG validates session and control generation. Intermediate states cannot publish
darkness or holding. Final H/C requires matching fresh thermal proof; O retains
full-OFF fallback. BN10, unsolicited R/B, lit/moving and foreign states reject.
Owner reports113 host tests and444 actual-firmware fake-transport assertions;
installed baseline fails the focused replay at the original error site. Reviewer
inspected the actual native reproducer and host negative controls, without
compiling or running hardware. The unretained live QG response is not claimed
to be RN10; this fixes a proven source race consistent with that error site.

Independent frozen source review also approves causal encoder candidatec235548.
The original session/telemetry/generation is pinned before premeasurement POSE.
After image processing, only a stationary illuminated two-axis telemetry pair
whose referenced ACK dispatch is at or after both newest capture and pre-POSE
completion can supply actual encoder positions. Reviewer inspected production
thermalService: ACK advancement restarts the whole pair and staging requires
matching acquired ACK and epoch. No sample is relabeled or predicted.

The existing three-count pre/post drift, response envelope,600 ms four-clock
optical checks and750 ms thermal age remain. Waits also retain geometry and
original55-second light deadlines. Publication is gate-authorized and holds
session.lock across identity/age/light checks and anchor assignment, preventing
a supervisor session-end from interleaving with commit. The helper takes
session then telemetry locks and releases them before gate checks, waits or I/O.
Reviewer requested and verified pre-POSE pinning, final light-budget enforcement
and atomic publication. No remaining lock-order or motion-authority blocker
was found. Packaging must include feedback_pose_evidence.py.

Root reports14 new plus67 existing tests passed. Reviewer inspected all new
cases including real thread interleave, original-scope replacement, cancellation,
stale/old/bootstrap ACK, wrong motor state, drift and expired publication. The
recorded485.378 ms image work completion plus203.465 ms tail regression fails
original read_spot and passes with an eligible already-arrived pair using injected
time. It demonstrates removal of a serial dependency, not replay of missing
failed pixels or measured new physical latency. Detector CPU optimization is a
separate review. No installation or physical acceptance is claimed here.


## Exact optical work budget — ac2b1a8 plus 5a95218

Independent source/artifact review approves detectorac2b1a8 and evidence/test
correction5a95218. The detector constructs the same full-resolution admission
mask and processes its bounding rectangle, retaining the original even2x2 block
origin. Only exterior pixels already masked to zero disappear. Global integer
coordinate sums reconstruct component centroids before division; component area,
ordering, consensus, newest support and final weighted centroid remain unchanged.
The seven-frame uint8 median uses a fixed comparison network; binary exhaustion
and other dtype/count fallback checks preserve exact output. Small per-frame
read/decode/verification timing records add attribution, not evidence authority.

Owner caught and repaired an odd-origin equal-area label-order issue before
freeze. Reviewer requested and inspected all-candidate comparison across the
connected-component parallel row threshold, so an unchanged rejection cannot
hide reordered competitors. Reviewer independently matched both benchmark
source hashes and17 historical input hashes. Owner reports105 combined checks
and18 focused checks after the final evidence correction. No heavy benchmark
was independently rerun.

Reviewer found the frozen README incorrectly described one OpenCV thread; the
artifact actually recorded ten despite requesting one. Follow-up5a95218 records
requested1/reported10, corrects the README and makes the row-threshold regression
use actual reported concurrency. Runtime bytes and measured timing values are
unchanged. Final historical five-frame image work is102.46→46.27 ms; seven-frame
work is432.62→49.90 ms. Full-board search gains little. These are retained-image
CPU comparisons with exact outputs, not frame1605, a single-thread benchmark or
a live timing guarantee. Collection/decoding/current geometry/motor work are
excluded and the600 ms safety limit remains unchanged.

No remaining source blocker was found across standby6c11b8f, causal posec235548
and detectorac2b1a8+5a95218. Root still owns combined host/paired acceptance and
packaging; these reviews do not authorize hardware testing or claim sustained
physical play. No reviewer camera, UI, device or installation activity occurred.


## Physical wood boundary and native sampling — fb4697c

The authorized independent native subreview approves combinedfb4697c source,
subject to root's combined suites. It byte-matched edge runtime toffef7ed and
profile/sampling/pipeline to a22b4df (dependenciesc55f0b0/2912146; edge docs4620d2e).
Review repaired canonical vertex order, persisted required-profile absence to
unknown, interior-only visibility support, actual3x3 image-footprint side
clipping and finite/projective-horizon checks before integer conversion. A valid
extreme-perspective calibration exposed the latter crash; its regression now
uses normal constructor data. Ordinary stone-recognition sampling is unchanged.

The new inactive-entry texture veto is explicitly a changed policy:12 interior
samples, reference variance>.0001, correlation>.99, slope.6–1.4 and luminance/
chroma residual<=.025. Outside texture cannot supply its count or statistics.
Active hand clearance and outside-only versus shallow-interior evidence were
reviewed separately. Owner reports110651 final profile/image assertions, including
retained-image full CameraAnalysisPipeline checkAlignment=true exterior black,
white and red controls. Reviewer inspected source/tests/logs, did not compile.

The profile is separate from BoardCalibration/context. Source image hash is
measurement provenance; runtime identity binds camera, reference calibration
and dimensions. A valid load persists a requirement so subsequent missing files
cannot silently restore legacy mode. Never-configured legacy mode remains explicit.

Final artifact review found generator width/height scaling disagreed with native
width−1/height−1 sampling by under one pixel. Root regenerated grid-space vertices
from the same saved frame29197 and edge fits, without new acquisition or model
refit. Corrected profile SHA256:
28bc46ff3836a66a0b742a8040093ac2830c798e65db4c62a6eb9acfb5cd55a7.
Actual native reprojection matches measured wooden-top corners within2.3e−13 px.
No remaining source/artifact blocker; physical fingertip/edge recall is not
universally established by these offline controls.

## Board-contained temporal core and lit renewal — 2359f35 / ee306ef

Independent source review approves core2359f35 and lifecyclee816057+95ae5af+
ee306ef, combined247ebb3, pending final whole-path budget/integration evidence.
The temporal path conditions outside printed-grid pixels before filtering,
resizing, normalization and tracking. Features are selected with complete
56-half-pixel interior support; this is a changed spatial baseline, not identical
coverage. An early draft lost an old shifted top-strip negative. Final source
adds64 fixed one-row-inward probes with contained full-resolution15x15 level0
tracking after the mandatory interior proof, restoring that unchanged negative.
Both proofs retain fixed denominators,85%/40 total and six per quadrant/edge,
.5/1px residual gates. Neither sparse proof guarantees visibility of every pixel.

Masked renewal internally runs the full unmasked proof first, then adds a local
14-half-pixel-footprint masked proof and edge veto. It cannot rescue failure or
remove masked features from the denominator. Independent actual board-wide
5/7-frame spot consensus supplies bounded component+12px halo, maximum36px radius
and1% area; no predicted target supplies a mask. Edge clipping cannot expand
the authoritative domain. Pixels used for hand, occupancy and subtraction remain
unmasked. Original dark bytes/H/capture time/feature anchor remain unchanged.

Fresh certificates advance a separate qualified_at using exact source capture
time only after current gate/session/600ms/750ms/light checks. Old certificate
must still be valid. No partial proposal grants time. Declined supplemental
support uses existing DARK renewal; mandatory unmasked failure remains fatal and
now retains exact rejected pixels through bounded capture. Review prompted repairs for
an accidental undefined variable in movement, failure misclassification and
missing post-acquisition fatal capture. Original55s host/60s firmware illumination
limits remain; normal holding begins dark renewal at53s with no cue duplication.
The optional100ms compute budget is new, not a relaxation of600ms freshness.

Reviewer matched four core source hashes,28 retained inputs and the executed
runner. Artifact includes50 image cases (six positives/44 negatives), six exact
current/anchor exterior invariances, eight masks, two contained alias controls
and the unchanged strip negative. Owner reports153 core tests and lifecycle
controls including20 synthetic seconds of exposure/shadow variation with immutable
dark subtraction, center/edge/corner masks, deadline and cancellation rejection.
Initial stage timings were contended and explicitly not acceptance. Final hashed
production-path budget replay remains root/owner-owned. Initial and fallback
dark registration is separately reviewed; temporal invariance alone is not a
whole-gameplay-path claim. No reviewer hardware, camera, UI or installation.


## Final dark registration and combined source — f38ba2d / 4ca1241

Independent source/artifact review approves dark registrationf38ba2d, production
SHA2562acf3c0529713a363181f1b301721e9e5286f8b4201f70c6853cf5c6716e86cf.
It conditions exterior pixels before ORB/ECC and, following reviewer findings,
before image warping. Warped source-support interpolation is intersected with
reference support; normalization and complete p/q/back tracking footprints use
that shared mask. Artificial boundary features may propose H, but at least35
ORB correspondences must have real contained descriptor/pyramid support.

All361 literal grid intersections remain. The largest supported full-resolution
15px/radius10 or9px/radius7 stencil is chosen before tracking; failed large-window
tracking is not retried with a smaller one. Distribution40/six per quadrant/three
per outer edge and .5/1px residual limits remain. A bounded third homography
proposal refits the already contained ORB correspondences without proposal-border
bias; it must pass the same grid/native/25px displacement gates. ORB residuals
are fit-consistency checks, not held-out validation. No brightness threshold
was added. This is an explicit changed support/stencil policy.

Owner reports57 focused tests, all13 retained controls (nine accept/four reject),
12 exterior invariance cases and exact3dark-source+median/full-constructor passes.
An intermediate occupied-edge positive exceeded1px and was not promoted; final
contained-only fit passes at about.532px with the original limit unchanged.
Reviewer inspected final source and independently matched36 input/source hash
checks across these artifacts. Source review found and repaired the raw-current
warp footprint leak; final nonidentity tests include translation3,2 and native
grid following known motion, with identical H across six exterior variants.

The exterior runner uses approximate wood coordinates. Reviewer additionally
projected root's exact corrected profile through the saved setup and confirmed
ZERO raw-support pixels outside actual wood for both tested board translations
0,0 and3,2. This connects the conditioned support to the final physical-boundary
artifact without claiming arbitrary untested geometry or physical acceptance.

All seven changed host runtime files in combined4ca1241 were independently
byte-matched to approved core2359f35, lifecycle through ee306ef and darkf38ba2d.
No remaining source blocker. Root reports nativefb4697c nine suites and profile
110651 assertions passed, with signed0.268 built. Reviewer did not compile.

Lifecycle evidence85f6bd8 was independently checked against seven runtime source
hashes, six retained input hashes and the executed runner. Eight actual read_spot
renewal simulations pass at final image ages352.9–548.0ms, worst52ms below600ms;
extra proof46.4–56.0ms. Retained pixels are repeated with synthetic cadence/time;
motor/lease/hand are mocked, so no physical latency guarantee follows. Original
dark/H/source identity and continuous-light origin assertions pass. Because this
run predates the new dark constructor, root is rerunning the same finite replay
on final combined4ca1241, followed by full host and paired acceptance. Those
results remain required before installation. No reviewer hardware/UI/camera or
installation activity occurred.
