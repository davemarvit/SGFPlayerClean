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
