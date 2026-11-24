# Physical Go: current conversation handoff

Updated November 23, 2026. **Hardware fully OFF; no active run. Setup is incomplete.**
This chat is preparing a handoff and will perform no further hardware work.
The continuing root may assume sole ownership after checking that no prior
commissioning/production process owns the serial port or driver lock. At handoff,
no matching process or open driver-lock holder was found. The empty lock file
itself remains. Read current records before using saved evidence as authority.

## Read first

Read [AGENTS.md](/Users/dave/SGFPlayerClean/AGENTS.md),
[IntegrationChecklist.md](IntegrationChecklist.md), the latest
[LivePositionIssues.md](LivePositionIssues.md), [laser checkpoint](LaserMovementCheckpoint.md)
and [test plan](NextPhysicalTestPlan.md). Read the **primary** shared
[outgoing handoff](</Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware/AI play integration reply.txt>)
and [incoming handoff](</Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware/AI play integration response.txt>);
worktree copies can be stale. [AgentGuide](AgentGuide/README.md) routes to source detail.

## Current checkpoint

- **Installed:** Physical Go **0.258/build 259**, compiled source `87fc4a9`;
  firmware **v44**. Production driver stopped; no gameplay binding active.
- **Latest run:** `moved-setup-full-calibration-03`, host
  `acea4b341fcc78777556c3f56b14344aa1834de8` in
  `/Users/dave/DYNAMIXEL-Go-Pointer-worktrees/midpoint-line-profiles`.
  It stopped after the first dark probe on fresh B boundary disagreement:
  **3.989569 px from A / 4.049711 px from original**. Full OFF confirmed at
  Unix **1795500739.5855656**; process exited.
- **Position distinction:** last optical pose **2293/2391**, grid
  **[15.816780, 2.415560]**; later actual settlement **2312/2391 was unobserved**.
  Do not treat the earlier spot as the latest physical location.
- **Diagnosis:** saved images reproduce N1/O1 feature-selection instability and
  native/fitted sampling-guide mismatch. Other 70 points changed ≤0.159 px;
  whole-board registration ≤0.053 px. This does not support a four-pixel board
  movement. The architecture proposal, quantitative study and staged consumer
  audit are now saved in [accuracy policy review](CalibrationAccuracyPolicyReview.md).
  **No production change yet; no new run before implementation and verification.**
  **The proposed full-pipeline B comparison has not run.** All relevant agents
  have finished their handoff; no replay process or active agent dependency remains.
  See the laser checkpoint for exact artifacts.
- **Passed scope:** midpoint source passed 120 tests plus both seven-case reviews;
  stationary observation and four-command inward recenter passed physically.
  Full five-fit/nine-check calibration remains incomplete. No old-map or partial-fit
  continuation is approved. Separate startup app-lease timing expiry is unresolved.
- **User instruction:** nothing was touched; use **motor-only pointer movement**.
  Do not request a power-cycle, manual joint movement or housing re-aim that could
  move the webcam. Beep when Dave must look for a spot.

**Accuracy clarification:** Dave's three-pixel figure was an arbitrary final
spot-to-intersection preference. Initial error beyond it followed by correction
is fine; final error above it is probably fine without a whole-system stop.
The existing correction loop already permits initial error above three pixels;
final-report rejection at ≥3 px and separate prediction/boundary aborts are under
review. Distinguish aiming quality and recoverable measurement uncertainty from
hazard/control checks; three servo counts are a different unit. No code policy
has changed merely because the requirement was clarified. Global-only evidence
misses local altered-line controls; retain meaningful local visibility checks.

## Preserved application state

Paused empty Human Black fast practice has zero moves/clocks:
`EA70E983-9FAF-40ED-8939-312ED10A1A68`. Original five-move game
`3D20B55B-DBE7-42E1-847E-3B82E60FF65A`, its clocks and earlier three-move checkpoint
have preserved backups; Return to saved game is available. **Root verified all
six saved-game hashes unchanged after full03.** Backup:
`/Users/dave/Documents/SGF PLayer/work/ai-laser-integration/stone-session-20261123/before-0258-install`.

Board is empty; app-owned FULL HD WEB CAM `0x11000000bda0567`, 1920×1080. Use
native broker images, not screenshots. Connect laser bridge is ON for passive
publication/OFF requests; recording/warnings OFF, timing logs ON. Camera-only
practice can proceed separately with bridge setting OFF and production stopped.

## Next actions

1. Read [accuracy policy review](CalibrationAccuracyPolicyReview.md) and its
   reproducible evidence. First compare using the same full geometry verifier
   for A and B, with fitted-map movement checks and explicit local uncertainty.
   Then implement/review one bounded slice; final aiming quality and recoverable
   progress need shared versioned contracts. Proposed cell tolerances are offline
   candidates only. No competing serial client or automatic hardware retry; do
   not preserve every three-pixel stop as a user requirement.
2. Root obtains fresh pose/optical qualification, then completes **five fitting
   targets and nine independent checks** with fresh data. Old geometry, poses
   and response estimates are not current movement authority.
3. Review successful final evidence, confirmed OFF and native-context geometry
   before creating a new binding and one production owner. Calibration's 10 s
   camera / 0.5 s cache experiments do not transfer to gameplay. Then follow the
   ordered AI/hand/ambiguity/capture/holding tests, preserving games and clocks.

## Short starter prompt

> Continue Physical Go from `/Users/dave/SGFPlayerClean/PhysicalGo/Documentation/NextConversationHandoff.md`.
> Read the current checklist, CalibrationAccuracyPolicyReview.md and primary laser
> handoff. Hardware is OFF; verify exclusive ownership before hardware work.
> Preserve games/clocks. Implement and verify the revised accuracy/recovery policy
> in bounded steps before new calibration. Use motor-only movement; do not assume
> a saved pose is current or request manual re-aim/power-cycle.
