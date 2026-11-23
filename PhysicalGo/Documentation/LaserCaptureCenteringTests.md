# Captured-stone indication and centering hints

Review date: November 22, 2026 (Pacific time).
Current status: captured-stone indication is implemented in installed Physical Go
0.252 and the updated host source. Physical centering and capture-marker tests
remain pending fresh calibration and clearance checks. The implementation passed
42 state, 47 laser-contract and 37 full-controller checks plus 29 host tests.
Root owns hardware operation; production bridge is stopped.

The original audit/design below is retained as rationale. Its statements that
capture-purpose support is absent are historical, superseded by 0.252. The current
implementation supports positive dark prisoner evidence, placement-first priority,
silent one-at-a-time capture targets and partial-removal protection. It preserves
legitimate combined cleanup/reply when positive removal evidence permits it.
Older saves without explicit capture context are not automatically migrated.

Current physical order: ordinary fast-AI moves/hand clearance first, then C1–C5
centering tests, then controlled P1–P4 capture tests. Temperature-protected gameplay
holding must be implemented before claiming this is a persistent-hold session;
a formal two-hour stationary endurance test is not required.

## Historical pre-implementation audit

Sources are in `/Users/dave/SGFPlayerClean`, unless a laser-project path is shown.
Line numbers reflect the working tree at review time; the named methods are the
stable anchors while the root agent finishes fast AI test mode.

| Finding | Source |
|---|---|
| Optional centering already exists; it aims at the observed fractional disk center, not a chosen intersection. It requires repeated strong evidence, at least three observations spanning 0.45 s. | `PhysicalGo/Sources/PhysicalAI.swift:243`, `observeCentering`; target construction at 281 |
| Centering is limited to human/checking phases, no pending AI point, and no multi-capture cleanup. | `PhysicalAI.swift:244` |
| Existing centering uses a bounded horizontal wiggle, advancing only on a fresh optical measurement within 3 px; nominal offsets 0.12 intersections, capped at 5 image pixels. | Laser project `Firmware/bridge_centering.py:14`, `CenteringWiggle` |
| The bridge accepts only ordinary move targets or `purpose="centering"`; no capture-purpose request exists. | Laser project `Firmware/bridge_lease.py:59`, `Request.parse` |
| An AI destination remains `pendingPoint` while `pendingPlacement` is true. That flag is cleared only when the entire board equals the legal resulting position, including prisoner removal. | `PhysicalAI.swift:113`, `consume` at 372–381 |
| `captureCleanupPending` deliberately means two or more captured stones. It is a clock policy, not a general indication that some prisoner remains. | `PhysicalAI.swift:114`; `commit` at 424–432 |
| A positive stone at the pending AI point suppresses the laser before the dark-evidence gate. This condition currently does not discriminate target purpose. | `PhysicalAI.swift:307`, `consume` |
| `syncGuidance` currently selects pending AI placement ahead of all other guidance. | `PhysicalAI.swift:457`, `syncGuidance` |
| Target identity distinguishes centering, but otherwise identifies only source/session/move. Multiple capture points would collide unless identity changes. | `PhysicalGo/Sources/PhysicalLaserGuidance.swift:25`, `Target.id` |
| The first-illumination callback excludes centering but would include a newly added capture purpose unless narrowed. It currently produces the move-arrival click. | `PhysicalLaserGuidance.swift:283`; `ExperimentModel.swift:643` |
| The protocol accepts `source="online"`, but the inspected native camera/laser publication and observation path is gated to AI play. No online laser target producer was found. | `ExperimentModel.swift:1280`, `receiveCameraFrame`; 1442–1451, `analyze`; ordinary target producer `PhysicalAI.swift:465` uses `source:"ai"` |

The online finding is an implementation gap to resolve before claiming online
laser functionality or timing, not evidence that online screen guidance is absent.
`PhysicalOnlineBoard.swift` already has board mismatch/capture-aware inference,
but server authority and orientation must be carried into a laser path explicitly.

## Original capture lifecycle design

This section records the design that informed 0.252; use the current-status note
and IntegrationChecklist for implementation and validation status.

1. On an authoritative legal move, derive the captured set and original colors
   from the before/after legal boards. Never use the generic mismatch `remove`
   list: that can contain misplaced or extra stones that were not captured.
2. Persist a small capture-guidance context for every capture, including a single
   capture: originating move number and acceptance time. Reconstruct captured
   coordinates from legal history. Do not overload `pendingCaptureCleanup`, which
   intentionally governs only the two-or-more-stones clock pause.
3. Keep an independent, ephemeral witness that the AI destination is physically
   occupied by the correct stone. Require fresh, unambiguous dark observations
   under the existing stability policy. This witness enables the switch from
   placement guidance to capture guidance without clearing `pendingPlacement` or
   advancing the game early. Camera/context changes invalidate the witness.
4. Select guidance in this order: unplaced opponent move; remaining capture;
   optional centering. A human capture has no opponent-placement stage. Suppress
   centering while any capture-guidance context is pending, including one stone.
5. Indicate one remaining captured stone at a time. Retain the selected point
   while it is still positively observed in its original color; otherwise choose
   the next eligible point in deterministic board order. UI text should say
   `Remove the marked captured stone` and show the remaining count. Do not use a
   timer to claim removal or sweep automatically over unknown board evidence.
6. Hand entry requests immediate OFF. After confirmed OFF and buffered-frame
   exclusion, obtain fresh dark evidence. A removed point becomes complete only
   with positive, stable empty evidence. Unknown/ambiguous occupancy neither
   completes removal nor authorizes illumination. If the currently indicated
   stone disappears without a detected hand, a raw suspected removal may request
   OFF, but only subsequent dark evidence confirms it.
7. Partial removal updates the remaining set but does not advance the game.
   Complete, stable agreement with the full legal board closes capture guidance
   and uses the existing board-confirmation path to advance. A closed capture
   must not reopen if someone later puts an extra stone on an old capture point.
8. Pause, disconnect, fault, changed camera/context and end-game clear the active
   laser operation. Pause preserves the logical capture context; resume derives
   the legal set again and obtains fresh physical evidence before indicating.
   Never trust persisted camera witnesses after restart.

An old save containing a pending AI placement or explicit multi-capture cleanup
can reconstruct a pending capture. Older single-human-capture saves lack a
separate cleanup marker; do not invent a new active capture from every historic
lastCapturePoints value. Screen mismatch guidance remains a fallback until fresh
state is reconciled or a new, explicitly tracked capture occurs.

## Protocol and integration changes needed

- Add `purpose="capture"`, capability `capturedStoneIndication`, and a capture-
  specific verifier that requires positively observed prisoner occupancy. An old
  driver without the capability stays OFF and retains screen guidance.
- Give each capture point identity `source/session/move/capture/row/col` so changing
  prisoners invalidates the old generation. Preserve leases, serial ownership,
  OFF confirmation and camera timestamps exactly as for existing operations.
- Use the captured stone's color in the capture target. Keep the original AI/
  online decision timestamp unchanged. For human-origin captures, record the
  actual move-acceptance timestamp explicitly; do not fabricate an AI decision
  event or use guidance dispatch time to change a clock. Document purpose-specific
  timestamp semantics when extending the target schema.
- Narrow `stone_seen_at_target` suppression to ordinary placement targets, then
  add capture-specific suspected-removal OFF handling. Otherwise the already
  placed AI stone suppresses every capture target while pendingPlacement is true.
- Refactor `syncGuidance` around the explicit priority above. Do not clear or
  rewrite the logical pending-move flags merely to select another optical target.
- Narrow the move-arrival callback and audible move cue to ordinary move guidance.
  Capture/centering operations must not announce another opponent move or switch
  clocks. The initial capture implementation can remain silent with explicit UI
  removal instructions; a distinct capture sound/pattern would be a separate UX
  choice, not an accidental replay of the placement cue.
- Existing steady-point firmware may be sufficient for one-at-a-time indication;
  this is a proposal, not validation. Verify optical behavior on both black and
  white stone tops: an empty-board calibration alone does not establish this.
- For online play, add an authoritative server-event target producer and canonical
  camera/server orientation conversion, then connect the camera/hand/laser path.
  The online server's clocks remain authoritative; do not apply AI practice's
  local capture-pause policy to a live online game.

## Required offline tests before hardware

| ID | Test | Required result |
|---|---|---|
| O1 | Legal capture set versus arbitrary board mismatch | Only legally captured coordinates are eligible; misplaced/extra stones never enter the capture queue. |
| O2 | AI stone placed but prisoners remain | Switch to capture guidance only after dark positive destination evidence; pendingPlacement remains true and no next move is accepted early. |
| O3 | Single human/AI capture | Guidance works despite captureCleanupPending=false; next player's elapsed clock continues as today. |
| O4 | Two/four prisoners, partial and out-of-order removal | Queue reflects only current positive evidence; pause persists until whole-board confirmation. |
| O5 | Hand, stale/duplicate frames, uncertain occupancy, changed epoch | OFF/no admission; no false removal, no old-witness reuse, no spontaneous fault rearm. |
| O6 | Purpose capability, malformed point/color/timestamp, old driver | Reject invalid requests, old driver stays OFF; screen guidance remains usable. |
| O7 | Change target during pending motor/camera work | Late worker cannot relight or mark an earlier prisoner; OFF handshake completes before replacement. |
| O8 | Pause/restart/end/new game and already completed capture | Preserve logical context only when pending; no historical capture resurrection or changed decision receipt. |
| O9 | Capture callback/audio and clocks | No second move-arrival click, no move commit/clock switch from laser acknowledgment. |
| O10 | Online authority and four view rotations | Correct canonical intersections, no duplicate server moves, server clock state untouched. |

Existing native centering tests cover default off, single-frame rejection, stable
fractional center, toggle-off cancellation, hand suppression, removal/centering
clearance and unchanged history. Existing host tests cover wiggle geometry and
protocol rejection. These do not replace the physical tests below.

## Physical test matrix

Prerequisites: resolve the current motor faults; complete fresh calibration;
validate ordinary hand clearance; reset private-calibration camera evidence and
capture a fresh dark empty reference. Root is the sole hardware operator.
Record app/build, setup ID, board orientation, actual expected point, command/
illumination acknowledgment and observation timestamps, hand-entry/OFF interval,
physical spot result, and clock/history before/after. Keep image recording bounded
and intentional; a controller acknowledgment is not proof of optical accuracy.

| ID | Action | Pass observation |
|---|---|---|
| C1 | Leave centering disabled; place an off-center stone | No centering laser. Ordinary move/recognition behavior remains available. |
| C2 | Enable hint; offset a clearly seen black stone, then white stone, about one-third intersection | After stable evidence the bounded wiggle marks the actual disk; neither app nor laser chooses its intended intersection. |
| C3 | Place a disk halfway between neighboring empty intersections | Hint remains at the fractional observed center; no guessed move or clock/history change. |
| C4 | Approach the indicated disk, center it and withdraw | Beam extinguishes on hand entry; fresh dark confirmation clears the hint after centering; no premature relight during the hand. |
| C5 | Remove the indicated disk instead of centering it | Hint disappears after dark verification; no ghost target. |
| C6 | Two eligible off-center disks; then an opponent move arrives | Selection stays stable; opponent placement takes priority; no beam travel through a hand. |
| C7 | Edge/corner disk, glare/low-confidence view, changed display rotation | Hint remains on the disk and within calibrated area; insufficient evidence stays OFF; display rotation does not rotate hardware coordinates twice. |
| C8 | Toggle hints off, pause, stop camera, simulate a stale stream | Prompt OFF; recovery follows existing explicit gates, with no retained lit-frame evidence. |
| P1 | Controlled single capture, human capturing and AI capturing | Correct prisoner marked; AI destination is indicated first when unplaced. Single-capture clock behavior unchanged. |
| P2 | Controlled two-stone capture; leave both, then remove only one | Both are tracked, one is indicated at a time. Removed stone is not re-indicated; clock stays paused for incomplete cleanup. |
| P3 | Remove the non-indicated prisoner first; remove all at once in a second run | Fresh evidence selects the true remainder or clears all. No required removal order or fabricated extra capture. |
| P4 | Enter hand without removing; then remove and withdraw | First case returns to the still-present prisoner only after dark clearance; second case advances only on positive removal evidence. |
| P5 | Remove a nearby noncaptured stone or place an extra stone | Report board mismatch; never relabel it as a captured stone or complete the turn incorrectly. |
| P6 | Pause/restart during partial cleanup | Same saved legal position and clocks; fresh reconstruction of remaining prisoners; no stale beam. |
| P7 | Captures at board edges and black/white stone surfaces | Optical spot lands on the intended prisoner, not its neighbor or a reflection. |
| P8 | Capture complete, then put a stone back on an old prisoner point | Generic mismatch handling; completed capture guidance does not silently reopen. |
| P9 | Online opponent capture after online laser integration exists | Correct server/camera orientation, pending placement first, remaining prisoners indicated; no local server-clock manipulation. |

For repeatable physical capture setups, use a deterministic legal fixture rather
than hoping the real AI selects a capture. On 19x19, the legal sequence B19, A19,
B18, A18, A17 captures the two white stones at A19/A18 on the final black move.
For one prisoner, use A18, A19, T1, C19, B19, which captures A19. This
is the 19x19 equivalent of the existing native single-capture fixture. Assign Black to human or scripted AI as needed. Fixture loading/scripted
move selection is test infrastructure; it must not bypass physical confirmation.

## Recommended implementation order

1. Native capture lifecycle and pure tests O1–O5/O8/O9.
2. Capture-purpose capability/parser/identity, bridge tests O6/O7 and optical
   target handling. Preserve legacy move/centering behavior.
3. Controlled physical C1–C8, then P1–P8 after calibration/clearance prerequisites.
4. Online target producer and camera wiring, O10 then P9; report separately from AI.

No item in this file is a physical pass. Root should update the maintained
IntegrationChecklist only after actual implementation/test evidence exists.
