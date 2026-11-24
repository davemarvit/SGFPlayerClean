# Historical movement checkpoint — November 23

Superseded by [LaserMovementCheckpoint.md](LaserMovementCheckpoint.md). Saved poses,
versions and next steps below are historical evidence, not current motion authority.

# Laser movement checkpoint — November 23, 2026

**Hardware fully OFF; calibration incomplete.** No calibration or production
driver is active and no gameplay binding is activated. This chat is handing off;
the continuing root must check exclusive ownership before hardware work. This is the
single current checkpoint. Earlier attempts, pilot measurements and rejected
approaches remain in [LivePositionIssues.md](LivePositionIssues.md) and raw reports;
they are not current pose, geometry or movement authority.

## Latest run and evidence

| Item | Current record |
|---|---|
| Run | `moved-setup-full-calibration-03` |
| Host | `acea4b341fcc78777556c3f56b14344aa1834de8`, `codex/midpoint-line-profiles`, `/Users/dave/DYNAMIXEL-Go-Pointer-worktrees/midpoint-line-profiles` |
| Stop | After first dark probe: fresh B boundary moved 3.989569 px from A and 4.049711 px from original reference. |
| Final state | Full v44 OFF at Unix **1795500739.5855656**; process exited. |
| Last optical observation | Motor **2293/2391**, grid **[15.816780, 2.415560]**. |
| Later actual settlement | Motor **2312/2391**, **not optically observed**. |
| Result SHA-256 | `25a7e7d32ec314f8d6188509840d0e9465db1de235fb071680f6fc0fdb4dd48b` |
| Installed app/firmware | Physical Go **0.258/build 259**, source `87fc4a9`; **v44**. |

[Raw result](</Users/dave/Documents/SGF PLayer/work/ai-laser-integration/laser-position-recovery-20261123/moved-setup-full-calibration-03/result.json>)
and [boundary diagnosis](</Users/dave/Documents/SGF PLayer/work/ai-laser-integration/laser-position-recovery-20261123/moved-setup-full-calibration-03/boundary-jump-analysis/README.md>)
retain exact source/image provenance. The full03 six-saved-game comparison is
complete: root verified all six saved-game hashes unchanged after this run.

## What the image analysis establishes

N1 and O1 selected inconsistent local line features. Production A/reference and
B used different native/fitted sampling guides; small pixel differences also
flipped competing peaks even with one guide held fixed. The other **70 points
changed at most 0.159 px**; independent whole-board registration changed at most
**0.053 px**. This is evidence of localized measurement instability, not a
four-pixel whole-board shift. The existing cross-frame guard rejected the
inconsistency under its current policy. Selecting whichever guide passes would
not establish valid geometry. The N1/O1 discrepancies are approximately
0.072/0.059 grid cells. Global-only evidence misses local altered-line controls;
this finding does not justify removing all local visibility checks.

**User requirement clarified:** three pixels was an arbitrary final aiming
preference, not a universal system-stop threshold. Initial landing beyond it
followed by correction is acceptable; final error above it is probably acceptable
without stopping the whole system. The current correction loop already permits
initial error above three pixels. Its final report rejects ≥3 px, while separate
prediction and boundary gates can stop before observation. Those different roles
must be reviewed separately; three servo counts are not three image pixels.

Architecture and quantitative reviews and the staged consumer audit are saved
in [accuracy policy review](CalibrationAccuracyPolicyReview.md). No new production
policy is implemented. First compare consistent full A/B geometry measurement;
then implement a reviewed bounded slice and versioned aiming/recovery contracts.
Local negative controls identify missing evidence, not necessarily physical
hazards. The physical cause of changing local peak contrast remains uncertain.

## What has passed, and what remains

The midpoint source passed **120 tests** and both independent **seven-case**
reviews. Its stationary observation and **four actual axis-command** inward
recenter passed physically, reaching grid [15.818993, 2.420984] before full03.
Earlier bounded weak-image reobservation also passed physically. These successes
qualify their specific operations; they are not a complete five-fit/nine-check
calibration or evidence that the later settlement has been observed.

Dave confirms nothing was touched and wants **motor movement only**. Do not
power-cycle, manually move joints, re-aim the housing or disturb the webcam.
Before further hardware work, root selects the reviewed fix and establishes fresh
ownership, actual pose, image identity and optical qualification. Use a beep when
Dave must locate a spot. Do not reuse older maps or invent partial-fit continuation.

Then complete fresh **five-target fitting and all nine independent checks**,
review model/domain/provenance, confirm OFF and establish final native context
before creating a binding. Calibration completion does not activate gameplay.
The separate earlier startup app-lease expiry remains unresolved; calibration's
experimental timing allowances do not transfer to gameplay.

The paused empty Human Black practice and original five-/three-move checkpoints
are described in the [current checklist](IntegrationChecklist.md). Preserve game
and clocks, complete the latest preservation comparison, then follow
[the physical test plan](NextPhysicalTestPlan.md) when its prerequisites hold.
[Next-chat handoff](NextConversationHandoff.md) contains the short continuation prompt.
