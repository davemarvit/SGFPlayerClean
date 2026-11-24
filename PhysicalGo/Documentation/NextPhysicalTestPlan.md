# Next physical test session

Prepared November 23, 2026. Start with camera recognition and fast AI, keeping
the laser off. These tests do not depend on finishing laser calibration.

**Build status: 0.258/build 259 integration candidate; combined verification,
installation and physical validation are pending.** Source through `9b51d45`
includes the reviewed 0.255 recovery, calibration-progress and optional latency
work, 0.257 ambiguity guard/fast-test idle reuse, named stone-set Setup controls
and screen-only illegal-move feedback. The merged four-position practice loader provides empty Human Black, empty Human
White, single capture and two-stone capture. Root must record the final source/build receipt before installation. The [integration checklist](IntegrationChecklist.md)
is the current installation/status authority; installed app at preparation is
0.253/build 254 with v44 firmware.

## Before starting

**Do not press Resume on the current board.** The app is paused at five moves,
with an unplaced AI Black stone. Dave most recently reports **eight Black
stones** on the physical board; the earlier retained photo showed seven Black
and one displaced White. Current colors/positions have not been freshly verified.
Neither report establishes agreement with the paused game.

Root first backs up the failed five-move game, the earlier good three-move
checkpoint, clocks and installed app, then installs and visually verifies the
selected signed candidate. The intended first test is a **new paused empty
Human Black practice game**, after preserving the original. Deliberately clear
the physical board to match; use other separate practice positions later. Preserve the original games; clearing the real board must not silently
rewrite their histories. Confirm selected camera, grid and orientation.

For this camera-only pass, turn **Connect laser bridge OFF** and leave the
production bridge stopped and hardware off. The setting is currently ON for
passive broker publication; turn it off before these tests.
Start bounded diagnostic recording only when the actual tests begin.

## First five minutes — recognition and ambiguity

Times are session priorities, not promises about engine or recognition latency.
Use a disposable human-Black fast-AI game for ordinary alternating play; repeat
human-placement checks in a disposable human-White game where needed to exercise
both colors. Record the actual game/color rather than changing an existing game.

| Step | Action | Expected pass | Record / stop if |
|---|---|---|---|
| 1. Clear board and hand | Observe empty board, cover part with a hand, hold, then withdraw slowly. | Fresh camera view, correct grid, hand wait while obstructed; clear board returns without a phantom move or lingering hand flag. | Record withdrawal and clearance frames. Stop this sequence on false acceptance or persistent obstruction. |
| 2. Ordinary stones | Place a centered legal human stone; place the AI's indicated stone; repeat one turn. Exercise Black and White. | Human move accepted once after clearance. Screen target identifies the AI move; mirroring it physically does not append it again. | Note coordinates, history length and elapsed clocks before/after. Stop on wrong color, wrong point, duplicate or unexpected turn. |
| 3. Halfway stone, hints off | On the human turn, place a stone halfway between empty intersections. Withdraw, then remove it. Repeat and center it deliberately on one legal crossing. | No guessed move while ambiguous; removal preserves history. Centering produces exactly one legal acceptance. | Retain the ambiguous and corrected frames. Stop immediately if the original wrong-intersection failure recurs. |
| 4. Halfway stone, hints on | Repeat step 3 for both colors with centering hints enabled. | The preference does not weaken acceptance. Ambiguity remains uncommitted; a centered stone is accepted once. | Record hint preference and color. Screen behavior alone does not establish laser wiggle or corrected optical center. |

If time is short, prioritize the previously failing halfway placement and its
removal/centering recovery after confirming ordinary recognition. Do not add
capture cases while the basic recognition sequence is failing.

## Next ten minutes — continuity, profiles and captures

| Step | Action | Expected pass | Record / stop if |
|---|---|---|---|
| 5. Pause and warm AI | After an AI answer has completed and the board matches, Pause, wait, Resume, then play another ordinary move. Compare first and subsequent replies. | Paused elapsed balances stay fixed; no duplicate move or charged pause time. Completed idle fast-test worker may be reused. Active search still cancels when paused. | Record acceptance-to-answer windows separately for cold, uninterrupted warm and post-pause turns. A speed improvement has no predetermined passing duration. Stop on state/clock corruption. |
| 6. Named stone profile | In Setup → Camera & board → Stone set, use New set… / Edit… to create two names and switch between them. Leave thickness unknown, then optionally enter known Black/White mm; clear White back to Unknown. Reopen settings. | Selected name and per-color values persist; clearing White does not change Black. “Saved for calibration” does not change recognition, game or camera geometry. Unknown remains valid. | Record saved values and selection, including after relaunch when root schedules it. Stop on lost values, unintended game change or a claim that storing thickness activates optical correction. |
| 7. Practice positions — after loader integration | In AI Setup or Play, open **Practice tests** and choose **Empty board — you play Black/White**, **Single capture**, or **Two-stone capture**. Confirm **Load test position**, match the displayed board, then Resume. Use **Return to saved game** while paused. | Original five-/three-move games and clocks remain recoverable. Each test has its own identity and starts paused. Empty tests use their named human color; capture tests have four moves and Human Black. Fast mode and board agreement precede Resume. Returning restores the preserved game paused. | Record original and practice identities. Stop if loading silently overwrites the preserved game or starts against a mismatch. |
| 8. Single capture | In the single fixture play Black B19, leave White A19 briefly, then remove it. | Exactly one capture; next player's elapsed clock continues for a single prisoner. Positive empty evidence clears cleanup; White C19 remains. | Record prisoner set, history and clocks. Removal must not become a phantom move. |
| 9. Two captures | In the two fixture play Black A17. Remove A18 first, leaving A19; then remove A19. On a fresh copy, reverse order. | Both clocks remain held while either prisoner remains; partial/out-of-order removal tracks the true remainder. Complete agreement releases cleanup. | Record both intermediate states. Hand entry without removal is not cleanup. Stop on premature release, wrong prisoner or lost state. |
| 10. Screen-only illegal feedback | Use an explicitly prepared suicide/ko example under the displayed rules. Remove the rejected stone and restore the legal position. | Authoritative reason and remove × appear; prematurely removed ko stones get restore rings. No illegal history entry or opponent reply; restoration clears the diagnostic. Ambiguous disks and pending prisoners are not mislabeled illegal. | Record rules, legal history, reason and restoration. Skip unsupported cases rather than inferring an illegal-move laser feature. |

The capture kit at source commit **f0009e9** supplies deterministic positions.
Practice candidate `4c78d82` is implemented but pending merge and verification.
The loader must pass combined persistence/return checks
before shipping. Do not substitute ad hoc edits of the live game if it is omitted.
The illegal-feedback integration adds no laser pattern or cue; its actual
controller suite and combined acceptance still need to pass before installation.

| Fixture | Initial Black | Initial White | Human Black plays | White prisoners |
|---|---|---|---|---|
| Single | A18, T1 | A19, C19 | B19 | A19 |
| Two | B19, B18 | A19, A18 | A17 | A19 and A18 |

Use the [capture run card](</Users/dave/Documents/SGF PLayer/work/ai-laser-integration/attended-capture-kit-20261123/RUN_CARD.md>)
for canonical orientation, partial-cleanup Pause/Resume and extra cases. These
fixtures test White prisoners captured by Human Black. Black prisoner surfaces
and AI placement-before-capture priority need separate prepared cases. After
complete cleanup a legitimate AI reply may add the next move; distinguish it from
a phantom removal move.

## Laser session — blocked until calibration qualifies

The latest laser run stopped on predicted-versus-settled response disagreement,
not a timeout. All **nine held-out accuracy checks** remain pending; there is no
qualified new gameplay binding. Review [LaserMovementCheckpoint.md](LaserMovementCheckpoint.md)
before resuming. A new app version does not solve that steering problem.

| Order | Action once its prerequisite is met | Expected pass / evidence |
|---|---|---|
| 1. Calibration and progress | Resolve/review the steering approach, reverify empty-board setup and run fresh qualification plus all nine held-out checks. | Progress displays actual stage/target and meaningful stopped/stale states. Preserve the frozen fit and separate validation evidence; activate a binding only after review. |
| 2. Ordinary indication | Request a known move, observe spot and cue, place the stone; enter/withdraw a hand during another indication. | Correct point, one acceptance, cue dispatched alongside light without intentional delay; beam dark on obstruction and returns only after fresh clearance. Record optical/acoustic onset separately from software acknowledgement. |
| 3. Centering | Test offset and halfway stones with hints off/on, then center or remove them. | Wiggle indicates the observed disk without choosing an intersection; no guessed move. Hand entry makes it dark; correct placement/removal ends the hint. |
| 4. Captured-stone markers | Repeat single/two capture cases; remove the non-indicated prisoner first. Add an AI-capture case when prepared. | Pending AI placement takes priority, then remaining prisoners individually and silently; removed stones are not marked again. Capture guidance outranks centering. Clock policy matches the screen-only pass. |
| 5. Holding and recovery | Play normally with monitored holding; Pause/Resume and observe temperatures. | Pause releases hardware and preserves game/clocks. Existing policy: cooling at either motor ≥45°C; resume holding only after both are below 40°C for 30 seconds of qualifying measured evidence; hard OFF at ≥50°C. Record maxima and transitions actually observed. |

Do not deliberately heat the motors to prove a transition during this short
session. A cool run leaves cooling recovery untested; the 50°C trip trigger is
not a measured absolute temperature ceiling. A formal two-hour run is optional.

## Evidence and completion

Root records the final version/source, integrated features, game identity,
rules/colors, hint/profile settings and each step's pass/fail/skipped result.
Keep bounded camera recordings and actual AI game/SGF, clocks and recognition
trace together. Continuous “next game” recording arming is Local-only in the
earlier app: verify recording is actually active for AI tests. Preserve a failure
before changing the camera, clearing stones or resetting a game. For reported
malfunctions, follow `AGENTS.md`: stop recording and warning feedback first,
retain useful frames, and diagnose without altering history/clocks/calibration.

Named profile storage, optional thickness and diagnostic geometry studies do
**not** enable parallax correction, adaptive-map learning or edge-based center
correction. Mark those absent unless a separately reviewed implementation and
physical test explicitly establish otherwise. Update this plan's build line and
the canonical checklist after the session; do not turn skipped cases into passes.
