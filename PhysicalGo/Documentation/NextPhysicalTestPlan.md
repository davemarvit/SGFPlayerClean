# Next physical test session

Prepared November 23, 2026. Start with camera recognition and fast AI, keeping
the laser off. These tests do not depend on finishing laser calibration.

**Installed: 0.258/build 259, compiled source `87fc4a9`.** Package/signature/source
and paired-host acceptance are independently verified. See
[build evidence](IntegratedPhysicalTestCandidate.md) for source-scoped test receipts.
All planned features in this document ship; physical tests remain pending.

## Before starting

The board is now empty. A separate **paused empty-board Human Black practice** is
loaded with fast AI, zero moves and zero clocks. Original five-move game/clocks
and the three-move checkpoint are preserved; the practice backup is byte-exact.
Load and relaunch persistence have been checked. Do not Resume an old position
unless the physical board has deliberately been restored to match it.

**Connect laser bridge is OFF; production driver stopped; hardware OFF.** Direct
webcam preflight passed on the correct camera. Start bounded diagnostic recording
when the physical test begins; images and warning feedback are currently off.
Bounded native latency logging is on for this launch. Screen captures are not
camera evidence. Use direct webcam frames for board/calibration checks.

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
The practice loader is installed and passed166 persistence/controller checks;
empty-position loading, exact original backup and paused relaunch are verified.
Use its controls rather than editing a live snapshot. Screen-only illegal feedback
passed69 actual-controller checks and is installed; it adds no laser pattern or cue.
Physical capture and illegal-placement validation remain pending.

The table below uses canonical fixture coordinates. **Follow the app's displayed
instructions when the view is rotated.** At this installation's orientation,
single is Black S19/A1, White T19/T17, play T18 and remove T19; double is Black
T18/S18, White T19/S19, play R19 and remove T19/S19. Re-read the UI after rotation.

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

## Laser session — blocked until recovery and calibration qualify

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
