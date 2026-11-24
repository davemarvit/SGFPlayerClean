# Physical Go: current conversation handoff

Updated November 23, 2026. **Setup is incomplete; hardware is fully OFF while
software work proceeds.** The current root agent retains sole hardware ownership.
Check the latest checklist before treating this checkpoint as current authority.

## Read first

Read [AGENTS.md](/Users/dave/SGFPlayerClean/AGENTS.md),
[IntegrationChecklist.md](IntegrationChecklist.md), the latest
[LivePositionIssues.md](LivePositionIssues.md) entries and
[NextPhysicalTestPlan.md](NextPhysicalTestPlan.md). Read the **primary** shared
[outgoing handoff](</Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware/AI play integration reply.txt>)
and [incoming handoff](</Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware/AI play integration response.txt>);
worktree copies can be stale. [AgentGuide](AgentGuide/README.md) supplies subsystem detail.

## Installed, preserved and observed

- **Installed:** Physical Go **0.258/build 259**, compiled source `87fc4a9`;
  firmware **v44**. Production driver stopped; no new gameplay binding activated.
- **Last completed check:** `post-boundary-stop-initial-spot-02`, host
  `54589c335e5d5502402a6d7994244eec9ac6a3ac`, branch
  `codex/calibration-prelight-reobservation` in
  `/Users/dave/DYNAMIXEL-Go-Pointer-worktrees/calibration-prelight-reobservation`.
  Two weak fresh B images were rejected; the third passed full verification
  within the unchanged **two-second/three-attempt** limit. Exact rejected images
  were retained after shutdown. This physically validates bounded reobservation,
  not full calibration. Source and all six saved game files were unchanged.
- **Last confirmed full OFF:** Unix **1795498218.83076**; process exited.
  Latest optical observation was motor pose **2297/2401**, board coordinates
  **[16.135067, 1.863926]**, just outside the existing fresh-start box **[2,16]**.
  These identify recorded evidence, not permission to move from an assumed pose.
- **User instruction:** Dave confirms **nothing has been touched** and wants
  motor-driven pointer movement only. Do not request a power-cycle, manual joint
  movement or housing re-aim; these could disturb the webcam.
- **Saved practice:** paused empty Human Black, fast AI, zero moves/clocks,
  `EA70E983-9FAF-40ED-8939-312ED10A1A68`. Original five-move game
  `3D20B55B-DBE7-42E1-847E-3B82E60FF65A`, its clocks and earlier three-move checkpoint
  remain preserved; Return to saved game is available. Backup:
  `/Users/dave/Documents/SGF PLayer/work/ai-laser-integration/stone-session-20261123/before-0258-install`.
- **Camera/app:** empty board; app-owned FULL HD WEB CAM `0x11000000bda0567`,
  1920×1080. Use native broker images, not screenshots. Connect laser bridge is
  ON for passive publication/OFF requests; recording/warnings OFF, timing logs ON.

## Next work and remaining uncertainty

1. Finish implementation and independent review of the **explicit fresh-start
   inward recovery**, in a new isolated laser branch. It permits at most **eight
   actual axis steps**, with fresh camera checks, to enter the existing [2,16]
   box. It is not yet a physically validated route. Historical response may guide
   provisional tiny probes but cannot grant current steering authority. Root
   selects the reviewed revision and verifies current ownership/pose before use.
2. After successful inward recovery, run **fresh five-target fitting and all nine
   independent validation checks**. The earlier three-fit-target partial run has
   no supported continuation model. Do not reuse old geometry, manufacture a
   partial-fit checkpoint or silently activate a binding.
3. Keep the **separate app-lease expiry** unresolved: a prior startup observed
   approximately 190 ms request-open plus 93 ms manifest-open windows before
   renewal. Exact filesystem/scheduling cause remains unproven. Later successful
   polling/reobservation does not fix it; calibration's experimental 10 s camera /
   0.5 s cache settings do not transfer to ordinary gameplay.
4. After complete qualification and confirmed OFF, review final artifacts, prove
   current native camera context, create a new binding and establish one production
   owner. Then test fast AI, slow hand withdrawal/darkness, ambiguity hints off/on,
   centering, captures and monitored holding. Preserve games and clocks throughout.

Raw evidence is under
`/Users/dave/Documents/SGF PLayer/work/ai-laser-integration/laser-position-recovery-20261123`.
Use a beep whenever Dave must look for a spot. Before changing chats, update this
checkpoint and the primary handoff with the final run/ownership state. Never start
a competing serial client or infer current hardware authority from an old source
hash, pose or OFF receipt. Historical attempts remain in the issue log.

## Short starter prompt

> Continue Physical Go from `/Users/dave/SGFPlayerClean/PhysicalGo/Documentation/NextConversationHandoff.md`.
> Read its linked current checklist and primary laser handoff first. Coordinate
> with the existing hardware owner before device access. Preserve saved games and
> clocks; use motor-only inward recovery after review, then fresh full calibration.
> Do not manually re-aim/power-cycle the pointer or reuse old geometry.
