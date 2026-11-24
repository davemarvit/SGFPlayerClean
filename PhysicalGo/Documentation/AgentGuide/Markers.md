# Markers and physical corrections

[Start here](README.md) · [Current status](../IntegrationChecklist.md)

A marker tells the human what needs attention. It must not invent an intended
intersection, accept a move, remove a prisoner from history or reset a clock.
Keep screen feedback, camera evidence, logical captures and laser targets distinct.

## Existing AI marker priority

`PhysicalAI.syncGuidance` prioritizes **AI placement → captured stone → optional
centering**. The next lower priority can proceed only when its evidence and phase
permit it. Read [PhysicalAI.swift](../../Sources/PhysicalAI.swift),
[PhysicalCaptureGuidance.swift](../../Sources/PhysicalCaptureGuidance.swift),
[PhysicalAIView.swift](../../Sources/PhysicalAIView.swift) and
[PhysicalLaserGuidance.swift](../../Sources/PhysicalLaserGuidance.swift) together.

| Marker | What it points at | What authorizes it |
|---|---|---|
| Ordinary AI placement | The canonical legal move intersection | Accepted AI move plus fresh clear, verified target evidence and hardware calibration admission. |
| Captured stone | One positively observed legal prisoner | The legal capture set, current original-color evidence and confirmed placement of the AI stone when required. |
| Centering hint | The observed fractional disk center | Repeated strong unambiguous disk evidence; no guessed intended intersection. |
| Screen correction | Required place/remove/reposition locations | Mismatch between physical observation and expected board; see `PhysicalBoardMismatch`. |

Ordinary move indication has the move cue. Capture and centering guidance are
silent. The host capabilities `capturedStoneIndication` and
`stoneCenteringWiggle` gate their respective wire purposes. An older driver must
fall back to screen guidance rather than receiving an unsupported purpose.

## Capture evidence and clocks

The engine determines prisoners from the legal before/after position. The capture
guidance state has an identity per game/move, original prisoner colors, observed
removals and independent AI-placement evidence. Its stable witnesses require at
least three distinct observations spanning 0.45 seconds; unknown classifications
are not removal evidence. Illuminated images and hand-obstructed frames cannot
advance that evidence.

Prisoners are indicated individually. Partial or out-of-order removal can select
another positively present prisoner without accepting a phantom move. A reply on
a former prisoner point requires prior positive removal there, and all other
prisoners need current stable empty evidence. A saved removal ledger alone cannot
prove that other locations are still empty.

Guidance covers a one-stone capture even though AI practice pauses its clock only
for captures of two or more stones. Do not merge marker completion and clock
completion into one Boolean. [GameAIClocks.md](GameAIClocks.md) explains the timing
boundary. Old saves lacking explicit capture context do not gain markers from
stale history.

## Ambiguous and off-center placement

An off-center disk can be physically visible without its intended intersection
being known. `observeCentering` uses the measured disk center, repeated evidence
and eligible human/checking phases. It yields to placement/capture work. The host
[bridge_centering.py](</Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware/bridge_centering.py>)
defines the bounded wiggle; motion/optical freshness and hand checks still apply.

After a hand enters, darkness and fresh stable evidence are required before a
hint can resume. Moving or removing the disk must invalidate the old hint. A
wiggle is an attention cue, not a commitment to the nearest grid intersection.

## Illegal-move feedback: screen implementation, laser proposal

[IllegalMoveMarkerDesign.md](../IllegalMoveMarkerDesign.md) records the design and
isolated precursor. The promoted `Sources/PhysicalIllegalMoveWarning.swift` is
installed since 0.258 and retained in 0.260. Stable qualified additions can produce
the authoritative rule reason plus removal crosses/restoration rings without
changing accepted history, clocks or laser targets. The ordinary legal inference
path remains strict; ambiguity and prisoners are not illegal-move evidence.

The tracked experiment remains outside the app build; its promoted source is the
runtime implementation. A distinct silent illegal-move laser pattern still needs
its own capability and physical validation. See [GameAIClocks.md](GameAIClocks.md)
for rule ownership and [the test plan](../NextPhysicalTestPlan.md) for physical gaps.

## Tests and the physical session

Use the controlled fixtures and C1–C5/P1–P4 cases in
[LaserCaptureCenteringTests.md](../LaserCaptureCenteringTests.md). Its initial
pre-implementation audit is historical; the header explains what 0.252 superseded.
The current order is ordinary moves/hand clearance, centering, then controlled
single/multiple captures. Random AI play is an inefficient way to reach a specific
capture case.

Offline entry points: `--capture-state-test`, `--capture-laser-test`,
`--capture-controller-test`, `--ai-laser-test`, `--marker-scenarios-test` and
`--laser-standby-test`. The new scenario suite joins actual AI/capture controllers
with schema-2 dark receipts; availability and results are recorded in the
checklist. Physical tests must still check both stone colors, hand entry,
partial/out-of-order removal, combined cleanup/reply and preserved clocks.
