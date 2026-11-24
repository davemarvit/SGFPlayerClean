# Camera and stone-placement session — laser off

**Historical first-session plan.** The zero-move/color/readiness facts below were
recorded before the attended session and must not be used to Resume now. Current
state is in [IntegrationChecklist.md](IntegrationChecklist.md): the saved practice
is paused at 12 plies with E3 pending, but the physical board is now empty.
Use [NextPhysicalTestPlan.md](NextPhysicalTestPlan.md) for current qualification
and a reversible new practice. No old color/stone-count note below is current evidence.

Prepared November 23, 2026 from read-only source, saved-game and broker checks.
Root owns app setup and physical operation. This plan does not activate hardware,
change the saved game, or require completion of laser calibration.

## Readiness checkpoint

- Installed app is **0.253/build 254**. The camera/AI test can use its existing
  behavior; optional newer candidates are separate installation decisions.
- Saved 19×19 Japanese-rules game `3D20B55B-DBE7-42E1-847E-3B82E60FF65A` has
  zero moves, zero elapsed time and fast AI test mode enabled. Its SHA-256 is
  `6ca3728c88fa9fc7aeba9675715543a1b02f37dafd5b134daa9ebeec8a972f09`.
- **The saved human is White, AI is Black.** Preserving this game means Resume
  first produces an AI Black screen target, then the user places Black and plays
  White. A human-Black → AI-White reply test needs a separate throwaway game with
  `You play: Black · first`, after backing up the current game/clocks. Root can
  prepare that before the session; do not silently reinterpret the saved colors.
- Read-only broker check found camera `0x11000000bda0567`, fresh advancing frames,
  alignment valid and hand clear. Root must recheck the actual empty board and
  lighting when testing begins. Old `status.json` is stale and is not current
  hardware evidence; use root's latest confirmed full-OFF receipt.
- Leave **Connect laser bridge off**, the production bridge stopped and laser
  power off. All nine held-out laser accuracy targets remain pending. Screen AI
  placement instructions work independently of the laser.

## Short staged pass

| Stage | User action | Expected signal / checkpoint |
|---|---|---|
| 1. Empty board | Leave board empty and hands away. | Fresh selected-camera view, grid on the real intersections, no phantom stones; readiness settles. No history/clock changes while paused. |
| 2. Hand clearance | Put a hand over the board, hold briefly, then withdraw slowly. Repeat once. | `Possible hand obstruction — waiting for a clear board view.` appears while obstructed, then clears. Empty board returns without a phantom move or lingering false hand. Record the withdrawal rather than guessing its latency. |
| 3. Ordinary Black stone | In a prepared human-Black game, place one Black stone clearly at an interior legal intersection and withdraw. | Exactly one human move is accepted after clearance; then fast AI produces a blue ring and `Place White at …`. In the preserved human-White game, first Resume and place the AI's Black stone at its blue ring instead. |
| 4. Opponent placement / reply | Place the indicated AI stone, withdraw, then make one ordinary human move. | Physical placement clears the blue instruction without appending the AI move again. Next turn follows only after board verification. The first AI answer may include engine startup; compare subsequent warm replies separately. For the preserved game, play a White stone after the initial AI Black placement, then follow the next Black target. |
| 5. Ambiguous placement | On the human turn, put a new stone halfway between two empty intersections. Withdraw; remove it; repeat and center it deliberately on a legal intended intersection. | No guessed move while ambiguous. Removal returns to the same legal history. A centered legal stone is accepted once after fresh stable evidence. Observe the screen/recognition diagnostics; laser-off mode does not promise a laser-centering ring or wiggle. |
| 6. Pause / Resume | Pause with the physical and recorded board matching; wait several seconds; Resume without moving stones. | Both elapsed clocks stay fixed during Pause. Resume verifies the same position and does not append a duplicate move or charge paused time. |
| 7. Optional single capture | Only after stages 1–6 pass, use one controlled single-prisoner fixture. | AI destination first, then the screen's removal instruction; hand entry alone does not remove a prisoner, and positive dark empty evidence completes cleanup. Single-capture elapsed time intentionally continues. |

For the shortest initial pass, stop after stage 4 if any acceptance/clearance
failure appears; diagnose it before adding ambiguity or capture cases. Do not
restart the camera or recalibrate reflexively before preserving the failure.
Hand entry and ordinary placement do not themselves pause AI elapsed time: clock
ownership changes at human acceptance or AI answer receipt, not physical mirroring.

Controlled capture fixtures and exact stone locations are in
[MarkerScenarioReview.md](MarkerScenarioReview.md). The exported files are under
the integration session's `pre-gameplay-hold-checkpoint/marker-fixtures/`.
Back up the live game/clocks before loading a separate fixture and restore them
afterward. There is no need to wait for a random AI capture.

## Recording and evidence

Immediately before the actual test, root opens **Advanced settings… → Diagnostics
mode → Continuous diagnostics → Record continuous camera images**. Confirm
`Saving diagnostics · N images` (accessibility label: `Diagnostic image recording
active`). **Start continuous recording with next game is Local-only; it does not
arm an AI session.** Keep recording off while waiting for the user. Recording
continues during Pause, so stop it after the final useful step.

Retain the bounded recording using **Keep this recording — exclude from
rotation**. Its installed destination is
`/Users/dave/SGFPlayerClean/PhysicalGo/Captures/Diagnostics/`; keep its `session.json`,
`events.jsonl`, images, reference and calibration assets together. Note each test
step and the actual stone coordinate/color. Save the AI `current.json`, UUID SGF,
and `recognition-trace.json` promptly at each failure/end; the trace is bounded to
recent events. Preserve `hand-clearance-stall.json` and its previous snapshot if
present. Do not assume diagnostic `initialSGF` is the AI game: that field currently
comes from the separate local recorder, so preserve the actual AI files explicitly.

If a malfunction is reported, root first runs
`osascript PhysicalGo/Tools/pause_recording_for_diagnosis.applescript` and verifies
image saving/warnings are off, following `AGENTS.md`. That script preserves game,
clocks and calibration. Keep the event and clearance frames; trim only a proven
repetitive tail under the existing diagnostic procedure.

No additional software or laser calibration is a prerequisite for the core
camera/AI pass. Actual blockers are an unverified/frozen camera view, failed board
alignment, persistent false hand clearance, inability to save the game, or an
AI startup error. Those should be diagnosed from the retained evidence rather
than bypassed.
