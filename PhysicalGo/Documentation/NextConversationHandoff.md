# Physical Go handoff

Start with [IntegrationChecklist.md](IntegrationChecklist.md), the single issue
register; [NextPhysicalTestPlan.md](NextPhysicalTestPlan.md) gives the next sequence.
Do not maintain another competing list here. Updated Nov24,2026 after18:22 PST.

Hardware fully OFF at1795573364.868653, no fault; no active driver/PTY/READY.
All seven benchmark locations now have successful observations across separate
runs. Gameplay is NOT activated: PG-33 remains unimplemented. Native app remains
0.261/build262, firmwarev44. Current user request: keep an explicit checklist and
check items off only when their stated scope is actually complete.

Frozen physical source: host `2da3c29785aa7337871b299380dd3dc289437332` in
`/Users/Dave/DYNAMIXEL-Go-Pointer-worktrees/feedback-indication-stop`.
Final run `three-point-feedback-20261124-182047-85434`: P15 continuation6.96s,
7.93px; K18 95.71s,0.73px;117.389440s READY-to-OFF. Earlier K2/S10 passed13.42s/
69.39s, then native alignment=false stopped P15; hand=false. No serial timeout
in these runs. Preserve interrupted timings and previous optional-refinement policy.

PG-31 replay: exact rejected image + reconstructed user-baseline anchor reproduces
native border counts18/18/1/18; independently measured grid moves0.493px.
Native investigation worktree `alignment-profile-jitter` from0628a33 currently has
no code edits. Do not claim a fix. Camera-only image evidence is in
`work/attended-recheck-20261124-105259/alignment-rejection-1815`.

Root asked the existing `frame_diff_analysis` agent to continue the user's earlier
parallel performance request. Its isolated `feedback-optical-latency` worktree is
based on2da3c29. First measurement: complete correction cycles~6.42s; many cycles
plus combined capture/analysis/motor waits, not only native analysis. No agent has
hardware authority. Track its outcome under PG-06b/PG-24, not as an installed fix.

Current webcam ID0x21000000bda0567; OpenRB-150 port/dev/cu.usbmodem1101. User
confirmed only USB reconnect, equipment unmoved, and captured a fresh empty
reference. Read live metadata before reuse. Preserve the original97 observations,
three-point model coefficients and historical reference bytes. The explicit
reconnect path adopts a fresh reference only after measured geometry correspondence.

Warnings and diagnostic image saving are off. No desktop screenshots taken.
Preserve old games and clocks; retain AirPod Pro3. Keep the canonical documentation
repositories separate from frozen runtime worktrees. Commit/push meaningful updates.
