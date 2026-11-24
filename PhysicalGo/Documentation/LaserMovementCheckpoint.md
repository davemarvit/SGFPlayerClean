# Laser movement checkpoint — November 23, 2026

**Current followup — recovery and A10 passed, next settlement stopped:**
Hosta84faa5 requalified fresh position/two-axis response and measured A10 within
1.111px. PlannedGOTO1860/2294 passed2.919px prediction agreement; actual1860/2292
failed3.450899px. The final pose was not observed during that run. Subsequent stationary
`initial-spot-02` now verified1860/2292, original-frame pixel757.97327/398.66919.
The frozen model was1.46px from observation; the old local estimate was5.10px
away. That latest check finished fullOFF1795494545.537726, rawreportSHA
`bb938bc23833cd6cedb3942d4132b3609953d48b7583d31a9267cdcc3110d4b8`.
FullOFF1795493870.3991501, maximum temperatures14/15°C, no controller/timingfault,
source and saved games unchanged. Eight targets not reached; no binding.
Settlement-aware planning is now being repaired. The observed-anchor recovery
code itself is implemented and physically passed; fullboard validation is incomplete.
Report: laser-position-recovery-20261123/observed-validation-01/result.json,
SHA256 `071dc8ad5fe5f39f8b537ca97cdae9494ded5b88d8242172c8c424aed1d999b0`.

**Earlier followup — stationary position verified:** installed Physical Go
0.258/build 259 and v44 completed `initial-spot-01` using reviewed host42e5022.
The direct webcam saw the spot at held pan1681/tilt2287, pixel592.132/487.443 in
that run's frame, near the image-left board edge. Full OFF confirmed at Unix
1795492387.674151. No GOTO/PTO/TTO travel was sent. Dave heard the beep and
accepts the camera evidence; repeating solely for visual confirmation is unnecessary.

This is position evidence, not qualified steering or a gameplay binding. App
restart changed the camera stream epoch; a generic explicit reference-registration
and fresh live requalification path is being implemented and independently
reviewed. The frozen95-sample fit remains unchanged. All nine accuracy targets
remain pending. Connect laser bridge is ON only for passive camera publication
and app OFF/no-target requests; production driver remains stopped. Root owns
hardware. Source/registration/planner work continues offline while hardware is OFF.

Evidence: [stationary report](</Users/dave/Documents/SGF PLayer/work/ai-laser-integration/laser-position-recovery-20261123/initial-spot-01/result.json>),
SHA256 `2b828043e0cc2f35620d4583179c6f24a09a5e939fa8efec732d313288120e7a`.

**Earlier followup — attended manual-validation-01:** stopped after approximately
102 seconds on post-settlement model/local prediction disagreement (3.172px,
limit3px), before completing A10. Fresh position/steering had passed. Planned
[1681,2289] was admitted at2.143px disagreement; actual coarse settlement
[1681,2287] failed the recheck. Last optically observed pose[1704,2284].
159 samples retained; all nine validation targets remain. Full OFF confirmed
Unix1795478146.9190755; process reaped; no timing/controller/supervisor fault,
source change or saved-game change. Report SHA256:
`82b063a6c6e246c24d9b724b1201a79ee441aa2c88a36b9f88eb8a36cdc52b84`.
Standalone reviewed `bed3c52` was used. At that checkpoint root prioritized stone-placement tests;
settlement-aware planning was under offline investigation. The pilot05 details
below are historical; its saved pose must not be treated as the current pose.


Laser work was paused at the earlier checkpoint to prioritize stone-placement testing.
Dave subsequently requested recovery so the next tests can use laser guidance.
Use the [stone-placement session plan](StonePlacementSessionPlan.md) for that
session; camera, hand, stone, screen guidance and clock checks can proceed with
the laser off. The [integration checklist](IntegrationChecklist.md) remains the
authority for subsequent changes. This page preserves the exact laser stopping
point, rather than granting permission to resume from old observations.

## Recovery policy review — November 23 (implemented and physically entered)

Independent firmware and architecture reviews separated two different policies.
The established host42e5022 policy checks the actual held pose, the existing
strict 3px steering agreement and 5px endpoint margin, fresh A/B camera evidence,
current lease/hand/identity and firmware/thermal supervision. It does not claim
that every position permitted by the firmware holding guard stays on the board.

A proposed stronger policy bounds the entire possible holding region. Offline
negative witnesses show that a pose-centered ±13-count region cannot fit at any
of the four edge targets, even with the frozen model treated as perfect. Knowing
firmware anchors and using ±6 still fails the 5px margin at three edge targets.
These results invalidate that additional containment guarantee; they do not
invalidate ordinary baseline calibration. Dark travel is separate from beam
admission and keeps mechanical, command, session and firmware guards.

Root selected explicit observed-anchor bootstrap: source-bound registration,
fresh same-session position and two measured directions. Strong region checks
can protect this interior qualification. An explicit, reported transition may
then enter the established ordinary nine-target validation policy, with no
change to its 3px steering rule or frozen fit. Qualification alone grants no
accuracy approval or gameplay binding. The source passed34 independently rerun tests; the physical run above passed
requalification and entered this baseline policy before the next planning stop. No firmware change is required
merely to preserve the baseline policy. A future observation-only recovery after
steering disagreement is a separate proposal, not an enabled automatic retry.

## Installed system and historical pilot state

At the historical pilot checkpoint, Physical Go **0.253/build 254** and
**AimControl v44** were installed. Current app installation is **0.258/build 259**. The production
bridge is stopped; no newly qualified full-board laser binding is active. The
paused game and clocks were preserved. Newer app candidates are described below;
their existence does not mean they are installed.

The earlier physical run **interior-pilot-05** used laser source
`44aeb5e3892d41999d591f229580f04000843a39` on
`codex/pilot-probe-extension`. It completed both diagnostic legs, confirmed
`AimControl v44 OFF` at Unix **1795474672.1551886**, and exited successfully. No
controller or supervisor fault was reported. That pilot’s final observed motor pose was
**pan 1820, tilt 2248**; the observed board position was
**[4.169881, 9.453444]**. Maximum reported motor temperatures were **14/14°C**.
These are historical measurements, not proof of the present pose, temperature or
unchanged equipment. Root remains the sole hardware owner.

## What the larger-move experiment established

Fresh position and measured two-axis steering qualification passed. A weak but
optically consistent tilt observation received one additional bounded five-count
probe; the measured basis and unchanged residual checks then passed. This did
not relax the ordinary eight-count pan/five-count tilt step limits.

| First accepted landing | Outbound | Return |
|---|---:|---:|
| Requested span, intersections | 2.500 | 2.322 |
| Measured span, intersections | 2.322 | 2.148 |
| Target error, intersections | 0.190 | 0.188 |
| Candidate prediction residual at actual motor pose, pixels | 3.700 | 2.115 |
| Motor goal error, pan/tilt counts | +1 / +2 | −1 / −2 |
| Commanded motor pose | 1768 / 2204 | 1821 / 2250 |
| Actual settled/observed motor pose | 1769 / 2206 | 1820 / 2248 |

The return target was the original optical position; its requested span therefore
used the actual outbound landing, rather than assuming the full 2.5-space move
had occurred. Return missed that origin by **7.276 pixels**. Both landings were
recorded before camera-directed correction. Each coarse leg also primed the
reported settled pose with a second GOTO before PREPARE raised gains; neither leg
was literally one wire command.

This is a completed diagnostic, **not an accuracy pass**. Two directed legs do not
establish a systematic distortion, backlash model or repeatability. All 144
observations were retained: 134 inherited observations and ten acquired in this
run. None trained or activated a new map.

| Host timing window | Outbound | Return |
|---|---:|---:|
| Travel dispatch → settled receipt | 1.241 s | 1.228 s |
| Settled-goal prime → receipt | 0.625 s | 0.550 s |
| PREPARE → READY receipt | 0.568 s | 0.471 s |
| READY → light dispatch | 0.965 s | 1.070 s |
| Light dispatch → ON acknowledgement | 0.107 s | 0.137 s |
| Travel dispatch → light dispatch | 3.410 s | 3.324 s |

These are host command/receipt windows, not pure motor travel, first visible light,
sound onset or ordinary gameplay latency. Calibration includes additional optical
proof and measurement work.

## Frozen fit and retained evidence

Full-calibration-04 passed five fit targets: K10 2.21 px, A19 1.76 px, T19 2.31 px,
T1 2.58 px and A1 2.86 px. Its **95-observation candidate remains frozen and
unvalidated**. Fit residuals are median 2.493 and p95 5.188 motor counts; those
training residuals are not independent pointing accuracy. **All nine held-out
validation targets still need to pass.** Pilot observations and future held-out
checks must not be silently added to fitting data. No binding was modified.

The local evidence directory is:

`/Users/dave/Documents/SGF PLayer/work/ai-laser-integration/fresh-board-20261122-133741/calibration-resume-20261123/`

| Artifact | Identity / purpose |
|---|---|
| [Raw pilot report](</Users/dave/Documents/SGF PLayer/work/ai-laser-integration/fresh-board-20261122-133741/calibration-resume-20261123/interior-pilot-05/result.json>) | Authoritative observations, commands, provenance and final OFF. SHA-256 `034883c595c2f4a6fc4cc66f974b233e2535de3e8e290799a54428a66ea2356c`. |
| [Pilot summary](</Users/dave/Documents/SGF PLayer/work/ai-laser-integration/fresh-board-20261122-133741/calibration-resume-20261123/interior-pilot-05-summary.json>) | Derived metrics used in the tables above. |
| [Frozen candidate](</Users/dave/Documents/SGF PLayer/work/ai-laser-integration/fresh-board-20261122-133741/calibration-resume-20261123/full-calibration-04/fit-only-candidate.json>) | Setup `aab3e2159895c940`; SHA-256 `1b083a14534d79d45ad23c5dd35109bb667e5cb2fb2d5641789e9e47cbfaa7e9`. Preserve the original report/reference/setup alongside it. |

The pilot used explicit stationary experimental camera/cache allowances of
**10 s / 0.5 s**. Normal defaults remain **0.6 s / 0.25 s**. A 279 ms polling
refresh gap occurred, including approximately 159 ms request and 94 ms manifest
read windows; camera and original app lease remained valid. It did not cause a
failure. Earlier polling-cache expiry and a separate serial-completion deadline
failure remain distinct incidents; their exact underlying scheduling/I/O causes
are not established. No automatic fault retry was exercised or authorized by
this successful pilot.

## Source checkpoints and offline work

App documentation baseline for this checkpoint is `0fc6a7e` on
`codex/monitored-gameplay-holding`. Laser integration is isolated in
`/Users/dave/DYNAMIXEL-Go-Pointer-worktrees/workflow-review-integration`, branch
`codex/workflow-review-integration`; the inspected checkpoint is **f9101f2**.
The following additions are **offline software evidence, not a physical rerun**:

| Integrated commit | Change / evidence |
|---|---|
| `ec1bd6a` | Explicit manual continuation from a clean completed pilot. Fresh ownership, OFF, actual pose, scene, position and independent steering are required; all nine validation targets rerun with the original frozen fit. Offline selected suite: 91 checks, zero skips; independent manual review: 12 checks. |
| `913a5c7` | Confirm DARK/ready before successful diagnostic persistence; defer failure images until confirmed full OFF and quiescence. |
| `75af994` | Reuse registration only for verified identical immutable calibration reference/baseline sources. All 54 saved-image comparison pairs matched; measured replay savings are not live speedup measurements. |
| `99887f5` | Bounded open/read/close/decode diagnostics. Reader and deadline policy unchanged; passive comparisons did not justify replacing or parallelizing reads. |
| `c64e655` | Bounded legacy timing importer; missing boundaries remain unknown. |
| `7cf5216`, `f9101f2` | Distinguish pre-write deadline-check timestamps from attempted OS writes and limit interval claims to the measured window. |

Opt-in runtime tracing `95f033a` on `codex/workflow-runtime-tracing` was still
separate at this snapshot; do not assume it is enabled or integrated. Consult the
[workflow review](</Users/dave/DYNAMIXEL-Go-Pointer-worktrees/workflow-review-integration/Firmware/Documentation/WorkflowOptimizationReview.md>)
and current checklist before selecting a combined revision.

The installed app can be retained for the stone session. Signed app candidates
**0.254/build 255** (app `64a1b77`, paired laser `11d3855`) and optional
**0.255/build 256** (app `939fe27`, paired host `45ed952`,
`codex/overnight-reviewed-candidate`) are preserved separately, not installed at
this checkpoint. See [overnight results](OvernightSoftwareResults.md).

Rollback means selecting a preserved source/app checkpoint in an isolated
worktree and requalifying any later hardware session. It does not mean resetting
the shared checkout, restoring an old active binding, or treating a former pose
as current. Preserve installed 0.253, candidate artifacts, the paused game and
clock backups until the selected replacement is verified. The physical pilot's
exact source remains available at `codex/pilot-probe-extension` / `44aeb5e`.

## Earlier pilot resumption sequence (superseded for the current stopped pose)

The sequence below documents the older clean-pilot entry path. Do not use it
to bypass the current settled-pose failure. The generic initial-spot recovery
path remains under implementation/review; consult the current checklist first.

1. Finish the camera/stone session first. Save its results and preserve game and
   clocks; a successful screen-only test is not laser qualification.
2. Root selects and records the reviewed laser source revision, checks that its
   focused/merged offline acceptance is complete, and reserves the hardware and
   CPU window. Stop competing heavy replays. Keep firmware, app and host identities
   explicit; no silent installation or learning.
3. With Dave present, establish an empty board, paused app and current camera/grid
   evidence. Check whether board, camera or pointer moved. Recheck source/reference
   identities; changed setup requires fresh calibration rather than inherited fit.
4. Follow [manual validation requalification](</Users/dave/DYNAMIXEL-Go-Pointer-worktrees/workflow-review-integration/Firmware/Manual%20validation%20requalification.md>)
   with the exact pilot directory/report hash and a new output directory. Obtain a
   new exclusive session and confirmed OFF. Read actual integral pose; the new
   manual path requires it within three counts per axis of the saved anchor.
   A mismatch stops before illumination; this mode has no guessed dark-return
   fallback. Historical evidence alone grants neither movement nor light.
5. Requalify the original scene, fresh optical position and independently measured
   steering. Use only the reviewed bounded probes. Old Jacobians or pilot success
   cannot substitute for this session's observations.
6. Run all nine held-out targets against the unchanged 95-sample candidate. Retire
   previous validation records; retain failures and first landings honestly. If
   interruption, pose uncertainty or a guard failure occurs, confirm full OFF and
   investigate. Do not replay an interrupted command from its presumed goal.
7. Review accuracy and provenance before separately activating a binding. Rebuild
   fresh dark camera evidence for gameplay, then test ordinary placement/light,
   hand-triggered darkness, centering hints and captured-stone indication. Keep
   screen-only recognition results distinct from these optical tests.

Broader directed-move research and adaptive learning remain optional later work.
They are not prerequisites for the immediate stone-placement session and do not
silently alter the frozen fit.
