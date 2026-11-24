# Combined marker test session

Historical fixture/review results. Holding and marker software are now integrated;
physical coverage remains incomplete. Current installation and test sequence are
in [the checklist](IntegrationChecklist.md) and [physical plan](NextPhysicalTestPlan.md).
The runtime identities and interim test totals below remain dated evidence.

Prepared November 22, 2026, as a focused review of ambiguous-placement and
captured-stone guidance while monitored motor holding is being implemented.
This is an offline test plan and fixture description, not a physical pass.
The maintained status remains in `IntegrationChecklist.md`.

Interim validation: all 80 scenario/fixture checks passed against the completed
shared app runtime `038e9e2a5547b8b6e11b252717c57c3bc3dc65747b15861b395ee92bd169d7a2`.
That runtime predates the final holding-review fixes, so root must still include
this suite in the final aggregate. Four typed physical fixture sets were exported
under the integration session's `pre-gameplay-hold-checkpoint/marker-fixtures`.
No physical device or live game was accessed.

## Coverage added

`PhysicalMarkerScenarioTests.swift` uses the real AI controller, legal SGF board,
laser guidance and schema-2 status types. It fills a gap between the existing
controller capture tests (bridge-disabled recognition) and the existing direct
laser capture contract tests (schema 1).

The new scenarios cover both prisoner colors, ordinary AI placement before
prisoner indication, suppression of unrelated centering during capture cleanup,
hand entry into retain-only dark holding, rejection of a raw lit-frame removal,
out-of-order removal, uncertain remaining prisoners after a hand visit, and the
existing multiple-capture clock hold. A separate two-disk case checks measured
fractional centers, stable selection when detections arrive in a different order,
transfer to the remaining black/white disk, silent markers and unchanged history.

The suite can export four repeatable 19x19 setups by setting
`PHYSICAL_GO_MARKER_FIXTURES` to an isolated artifact directory when it runs.
Each directory contains:

- `fixture.json`: a real `PhysicalAI.Snapshot` with an already selected legal AI
  capture pending physical placement, loading paused.
- `fixture.sgf`: the production SGF serializer's legal history.
- `setup.json`: exact board setup, AI destination, expected prisoners, resulting
  board, colors and clock policy.

Every fixture is replayed through the actual legal-move engine and checked for
the exact captured set, even when export is disabled. The test also checks the
loaded paused state and the single/multiple-capture clock behavior on Resume.
The fixture generator never touches the live application's game directory.

## Ready-to-place capture setups

These are canonical app coordinates. Verify the app/physical orientation after
calibration; do not infer orientation from where this document is displayed.
Place only the listed stones before resuming the corresponding fixture.

| Fixture | Black stones before the capture | White stones before the capture | AI move to place | Prisoners to remove |
|---|---|---|---|---|
| `one-white-prisoners` | A18, T1 | A19, C19 | Black B19 | White A19 |
| `one-black-prisoners` | A19, C19 | A18, T1 | White B19 | Black A19 |
| `two-white-prisoners` | B19, B18 | A19, A18 | Black A17 | White A19, A18 |
| `two-black-prisoners` | A19, A18 | B19, B18 | White A17 | Black A19, A18 |

The color-swapped histories start with a black pass, so the captures remain legal
without editing board colors or bypassing the rules engine. No physical stone
represents that pass. The AI is the capturing color; the human is the next player.
The final capture is already in the saved legal history but remains physically
unplaced, exactly as an ordinary received AI move does while awaiting placement.
This makes the test deterministic without depending on the fast AI choosing a
particular move.

## One session, with clear checkpoints

Root remains the sole hardware operator. Start only after the short dark
hold/full-OFF test and fresh moved-setup calibration pass. Back up the current
game and clocks before loading a throwaway fixture. Pause and confirm full OFF
before rebuilding a physical fixture; resume only when its listed setup matches.
Restore the original game afterward, keeping test histories separate.

1. **Ordinary moves and clearance.** With centering disabled, play several normal
   fast-AI moves. Check hand entry, lingering hand, withdrawal, correct placement,
   the cue at first light and Pause/full OFF. Watch both temperatures and holding
   status. This distinguishes ordinary recognition issues from optional markers.
2. **Centering and ambiguity.** Enable centering. Gently offset an already
   recorded black stone by roughly one-third of an intersection, then do the
   same with white. The wiggle should mark the observed disk. Next place an extra
   disk halfway between two empty intersections: it must not become a guessed
   move. Approach it, verify darkness while the hand is present, and remove it.
   Repeat with two ambiguous disks; removing the first should select the remaining
   measured disk. Neither the hint nor its removal may append a move or switch
   clock ownership. Centering is silent.
3. **Single captures, both surfaces.** Load each single-prisoner fixture in turn.
   The AI destination must be indicated first. After placing the AI stone and
   withdrawing, the remaining captured stone is marked with the screen's removal
   instruction. Visit it with a hand without removing it, withdraw and confirm
   it is still pending; then remove it. The next-player clock intentionally runs
   throughout this single-capture placement/cleanup. The capture marker must not
   replay the AI arrival cue.
4. **Two prisoners and partial cleanup.** Load `two-white-prisoners`. Place the
   AI stone, leave both prisoners, and note which one is indicated. Remove the
   other prisoner first, then withdraw. The remaining count must become one;
   the still-present prisoner must not be accepted as a new reply. The clock
   remains paused. A hand visit without removal must not reduce that count.
   Remove the last prisoner and withdraw: only stable full-board agreement ends
   cleanup and resumes the next-player clock.
5. **Black prisoners and simultaneous cleanup.** Use `two-black-prisoners` to
   verify the other optical surface. After AI placement, remove both prisoners
   in one hand visit. There should be no invented intermediate move or required
   removal order. If time permits, repeat partial removal and Pause/Resume here;
   the logical remaining set survives while optical evidence must be refreshed.
6. **Return to play.** Pause/full OFF, restore the saved game and rebuild its
   physical position before resuming. Continue monitored play to collect actual
   temperature trends. A successful marker session does not establish a two-hour
   heat plateau or online-opponent support.

## Interpretation and limits

- The centering target's integer row/column identifies a calibrated cell; the
  fractional `stoneCenter` is the aim. It is not an intended-intersection guess.
- Captured-stone indication currently selects one legal prisoner at a time and
  is silent. Its meaning comes from the removal instruction and capture context;
  it must not be mistaken for another AI move. Optical accuracy on black and
  white stone tops remains a physical measurement.
- A hand extinguishes the beam; a healthy stationary hold may remain. That is
  distinct from Pause or disable, which require confirmed motor-power OFF.
- Unknown or ambiguous prisoner occupancy after hand entry cannot complete
  removal or authorize renewed illumination. Positive dark observations are
  required. A suspected change in an illuminated frame can request darkness,
  but cannot by itself update the prisoner-removal ledger.
- Removing an unrelated stone is a board mismatch, not another capture. Putting
  a stone back after completed cleanup must not resurrect capture guidance.
- Ko/suicide diagnostics are a separate proposed feature. They must not relabel
  ambiguous disks or still-present prisoners as illegal moves. Existing move
  legality and capture evidence remain authoritative.

Record actual version/setup, marker target, observed spot, cue count, before/after
history and clock state, temperatures and any interruption. Preserve relevant
recordings; neither a protocol receipt nor this offline suite proves optical
accuracy or hand-clearance latency.
