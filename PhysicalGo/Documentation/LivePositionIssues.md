# Live position issues, reviews, and clocks

Date: 2026-11-11 (America/Los_Angeles)

Status: all four batches completed in 0.157 / build 158. Full regression and
signed-build verification passed. Capture timing retains its configurable policy. See the
implementation and validation record below for coverage and limitations.

Latest follow-up: 0.180/build 181 installed and verified before moving locations.
A19 recognized White in all 64 live validation frames (previously 0/56 in replay).
Camera and diagnostics stopped; 21 saved moves, White next, both clocks paused
and unchanged. A19 remains an unsaved physical stone. Recording, calibration,
preferences and jade-board evidence backed up outside .build. Safe to pack up.
Physical acceptance remains 16/27; darker jade A1 remains open. Next session:
calibrate the new empty board and start a separate test recording.

## Purpose and scope

Resolve discrepancies automatically whenever the evidence supports doing so.
Mark an intersection on **Live position** only when a player has a useful action
or decision to make. Clicking that marker opens the action appropriate to its
issue. A marker, placement ambiguity, or open review is not itself a reason to
stop clocks.

This specification governs local physical play. Online play must respect the
server's authoritative moves and clocks; local capture holds cannot stop a server
clock. Do not change online behavior as a side effect of this work.

## Terms

- **Image observation:** what our software interprets from a particular camera
  image, including uncertainty and the image's actual capture time. The camera
  supplies images; it does not decide what moves occurred.
- **Established position:** the accepted game history, plus clearly distinguished
  retained pending moves. A later image disagreement does not erase that history.
- **Turn evidence:** evidence that a player completed a move, its timing boundary,
  and which player follows. This may be established before the exact intersection.
- **Issue:** an unresolved discrepancy or task. It can be under automatic
  reconciliation, require player action, or require a timing hold. These are
  separate properties, not equivalent states.
- **Marker:** an actionable indication on an intersection. An absent stone can
  require marking its expected intersection. Multiple intersections can refer to
  one issue. The ordinary last-move indicator is not an issue marker.

## Numbered cases

Keep these case numbers stable in future discussion and tests. Case 2 is an
initial disagreement, not a diagnosis; cases 3, 4, 8, or 9 may explain it.

| # | Case | Automatic reconciliation first | When to mark | Click action | Clock policy |
| --- | --- | --- | --- | --- | --- |
| 1 | Brief obstruction or detection flicker | Retain the established position; use subsequent clear observations. | No actionable marker for a transient discrepancy. A persistent unresolved discrepancy becomes case 2. | None while automatic reconciliation suffices. | Continue through ordinary hand movement and flicker. Apply case 10 only if reliable turn tracking is lost. |
| 2 | Image disagrees with established position | Compare observations with accepted and pending history, legal captures, observed movement, and subsequent images. Clear the discrepancy when a consistent explanation is established. | Only if disagreement remains unresolved and player input would help. | Explain the specific disagreement; offer confirmation that the recorded position is correct, or identify a physical change. Do not assume the record needs editing. | Continue while new moves and turns remain reliably observable. Pause only for the independent reasons below. |
| 3 | Stone nudged between intersections | Retain identity and intended location when supported by history and movement. Do not count repositioning as another move. | When centering is needed for reliable tracking or intended placement remains uncertain. | Show where to center the stone, or confirm its intended intersection. | Continue if timing is reliable; centering an existing stone does not switch clocks. |
| 4 | Stone accidentally moved or removed | Identify the recorded location and exclude supported legal captures; use movement evidence where available. | When persistent displacement or absence needs restoration or explanation. | Guide restoration or let the player explain a different event. | Usually continue. A physical correction that interrupts play, or loss of reliable turn tracking, requires an explicit hold. |
| 5 | New move has uncertain location | Use successive images, geometry, legal play, and later moves to resolve placement. Preserve established turn evidence independently. | When multiple plausible locations remain and player input is needed. | Select and confirm the intended intersection. | Switch clocks at the established completion boundary without waiting for location resolution. Preserve applicable capture policy. |
| 6 | Missed move | Recover automatically when retained evidence uniquely establishes the legal move/sequence; retain uncertainty otherwise. A static board and alternation alone do not prove individual timestamps. | When history recovery needs confirmation or missing information. | Review the proposed recovery and confirm or correct it. Preserve earlier pending moves. | Continue if timing and turns were retained; hold for timing review if they cannot be accounted for. Never invent missed time boundaries or increments. |
| 7 | Uncertain move order | Reconcile observed events, alternation, captures, and legal sequences. Distinguish assigning locations to known timed turns from uncertainty about the turns themselves. | When multiple plausible sequences remain. Group the affected intersections into one issue. | Resolve the sequence while preserving established history and turn evidence. | Location/order assignment can remain unresolved while clocks run. Uncertain current turn or unaccounted timing requires a hold. |
| 8 | Possibly incorrect recorded move | Check history and observations; dismiss the suspicion when the record is supported. A single image disagreement is not proof of a bad move. | When a genuine unresolved question about accepted history needs review. | Review evidence first. Preview an actual correction and its effect on later moves before explicit acceptance. | Inspection alone does not pause. A correction that interrupts play or invalidates current timing/turn state requires a hold. |
| 9 | Incomplete or uncertain capture | Compute legal capture/removal obligations and track physical removal across fresh images. Keep one capture identity through partial removals. | When removal or clarification is needed; transient expected removal can use capture progress guidance instead of a new ambiguity. | Show the capturing move, captured intersections, and remaining removals; verify completion or clarify a different event. | Follow the configured capture policy described below. A qualifying incomplete multi-stone capture can already have both clocks stopped before any click. |
| 10 | Camera, alignment, or processing outage | Recover/reconnect and reconcile retained timestamped evidence. Preserve accepted history and pending events. | Use a global status/action rather than marking arbitrary stones. Mark specific intersections only if a separate local issue remains. | Retry/reestablish the view or review timing, according to the actual problem. | Continue only while timing remains trustworthy/recoverable. Hold at a supported boundary when reliable turn tracking is lost; do not charge a blind interval. |

## Reconciliation and marking requirements

1. History constrains interpretation; it does not prove a stone is still physically
   present. A brief unsupported disappearance is not a capture, but persistent
   clear absence must not be suppressed merely because the record contains a stone.
2. Reconcile before asking for intervention. Use independent fresh observations;
   repeated processing of one image is not additional temporal evidence.
3. Do not force a diagnosis. A missing stone may be obscured, moved, removed, or
   captured. If unresolved, present that uncertainty rather than opening a record
   editor as though a correction were established.
4. Every issue marker must have a reason and a useful action. Resolve overlapping
   explanations into a shared issue; do not create duplicate reviews. Clicking any
   intersection in a capture or sequence opens the same relevant issue.
5. The highlighted-intersection button and board clicks use the same policy.
   Placement-ambiguity counters need not count every issue, but the UI must not
   imply that zero placement ambiguities means no other action is needed.
6. Clear a marker when evidence or an accepted action resolves its issue. Opening,
   closing, or canceling a review does not itself resolve it. If the underlying
   issue resolves automatically while its review is open, show that outcome and
   disable obsolete actions.
7. **Recorded position is correct** acknowledges the current discrepancy without
   rewriting SGF, adding a move, changing colors, switching clocks, or changing
   balances. Retain the evidence and re-evaluate recognition. Scope confirmation
   to the issue and position; it must not permanently mask later displacement,
   capture, a new stone, or a changed view. Persistent tracking failure becomes an
   appropriate recognition-recovery task rather than a repeated identical prompt.
8. Photograph annotations for recognition testing remain separate from game
   correction. A game action has a clearly named confirmation and reports its
   result. Saving a testing label must not pretend to accept a game correction.

## Clocks and capture policy

Keep three facts separate: established turn/timing, established placement/history,
and physical board readiness. Uncertainty in one does not automatically invalidate
the others. Applying retained timing to finalized moves must happen exactly once,
without charging again or granting duplicate increments/byoyomi resets.

Legitimate holds include unreliable turn/timing evidence, a qualifying configured
capture hold, an explicit user pause, a physical correction that interrupts play,
and existing integrity protections such as failed persistence. Merely marking a
stone, opening a review, or encountering unresolved placement is not a hold reason.

Opening a review must allow tracking to continue if clocks continue. Do not simply
remove pause calls while leaving detection frozen or edits tied to a stale game.
Use revision-aware proposals: revalidate or refresh them if play advances. An
actual mutation that requires stopped play must explicitly enter a hold before
application. Canceling inspection must not pause or resume the game as a side effect.

Preserve existing local **Automatically pause for captures** choices: Off, two or
more (default), three or more, five or more. This is a clock policy separate from
the scoring-rule selection. Do not infer a new policy from a ruleset's name.
This spec does not assert what any named tournament regulations currently require.

For a capture qualifying under the configured policy:

- Establish a legal capture and a supported start boundary before entering a
  removal hold. Expected partial removals are progress within that capture.
- Neither player is charged for the verified held removal interval. Completion
  and the following turn use the configured completion boundary, with retained
  timing and no duplicate clock switch.
- Verify all required removals and the resulting position using fresh evidence.
  Unknown, obscured, stale, or contradictory observations do not prove completion.
- A click may open a capture already on hold; opening it must not add another hold,
  clear the original reason, or independently authorize resumption.
- Preserve explicit pauses and unresolved timing-review requirements. Camera loss
  during removal invalidates freshness, not saved history or the capture identity.
- If capture start/removal was hidden, do not invent or refund an unobserved
  interval. If evidence contradicts the presumed capture, require timing review
  where its earlier hold affected accounting.

With capture pausing off or below the threshold, do not introduce a removal hold
just because several images show an incomplete capture. Preserve the existing
move-completion contract; do not silently choose placement-time versus completed-
removal timing in this refactor. Audit that contract and document tests before
changing it. Any additional ruleset-specific options are a separate decision.

For outages, retain the existing freshness protection while improving recovery.
The baseline has a 1.5-second processing/observation-gap safeguard; that is an
implementation threshold, not a guarantee that every shorter outage is safe.
Timing uncertainty crossing expiry requires review, not an automatic loss caused
by delayed placement confirmation. Show the current hold reason and resume
prerequisite, preserve manual pauses, and avoid pause/resume loops.

## Baseline audit and remaining work

Baseline: Physical Go **0.156 / build 157**, commit `9926f42aa4afb824e7e1564b7c25e50047cc101a`,
branch `codex/physical-go-maintainability`. Repository on the development Mac:
`/Users/Dave/SGFPlayerClean`; app sources are in `PhysicalGo/`.
`/Users/Dave/Documents/SGF PLayer` is not this repository.

Already present: issue-specific click routing, retained pending chronology during
manual recovery, protection against silently discarding that chronology, retained
provisional clock events, capture holds, freshness safeguards, and automatic
camera recovery. Existing functionality still needs assessment against this spec.

Gaps identified at baseline (addressed by batches 1–2 below):

- `Sources/RecordingClarity.swift` routes an established-stone discrepancy to a
  historical-placement editor; it has no dedicated current-issue acknowledgment
  that the recorded position is correct.
- `Sources/RecordingView.swift` pauses for pending-placement and recorded-placement
  review and missed-move recovery. Review presentation/editors also assume paused
  work in several paths. Opening must be separated from applying changes.
- Marking, interpretation warnings, capture progress, and review state are spread
  across several components; a shared issue decision should drive their behavior.
  Do not assume the whole marking policy already matches the table.

Relevant sources: `RecordingClarity.swift`, `RecordingView.swift`,
`BoardAdjustmentMonitor.swift`, `InterpretationDetectionMarks.swift`,
`ReviewPresentation.swift`, `GameRecorder.swift`, `MoveObservationHistory.swift`,
`AutomaticCapture.swift`, `CaptureReviewPlan.swift`, `CaptureReviewView.swift`,
`LocalGameClock.swift`, `LocalClockEngine.swift`, and `CameraAnalysisPipeline.swift`
(all under `PhysicalGo/Sources`).

A prior manual recovery discarded two pending moves and saved only the third.
That regression was fixed in 0.156. The affected test game was recovered separately
to 89 legal moves with its original preserved and clocks left paused. Do not use
that old test state as an assumed current game or alter a user's live game as part
of implementing this spec.

## Implementation batches and acceptance

Implement in reviewable batches, retaining working behavior and testing each:

1. **Shared issue decisions and marking.** Model evidence, affected intersections,
   automatic reconciliation, user action, and independent hold reason. Test all
   ten cases, mixed cases, issue identity, delayed/obscured images, and automatic
   clearing. In particular, neither retain a false marker nor hide a real removal.
2. **Issue-specific review without automatic pausing.** Add the record-correct
   acknowledgment and separate viewing from mutation. Test live moves arriving
   during review, stale acceptance, cancellation, duplicate confirmation, and
   issue resolution while open. Test button and board routes, absent-stone markers,
   and zero placement counters with another actionable issue.
3. **Timing and capture integration.** Preserve established timing during placement
   and chronology review. Test rapid alternating moves, missing timing, delayed
   recognition near expiry, explicit pauses, persistence, and restart. For captures
   test Off and each threshold (below/at threshold), partial multi-stone removals,
   completion, contradictory evidence, hidden start, camera loss, cancellation,
   restart, and following moves. Verify balances and turn transitions exactly once.
4. **Full verification and handoff.** Run all registered regression suites and
   Python build checks; inspect native UI flows. Build and verify the signed app
   and source hash before installation. Report fixture/synthetic coverage separately
   from actual live-camera testing. Update this document with implemented batches,
   remaining decisions, validation, and the final commit.

Use existing fixtures for the lost pending sequence, rapid play/G18, near-expiry
placement, captures, and resume loops. Add focused tests of behavior, not snapshots
of implementation details. Keep illegal-history, stale-write, and storage-failure
guards. If a shared policy is extracted, keep it independent of presentation and
diagnostic strings, without a wholesale rewrite of the recorder.

Run from `/Users/Dave/SGFPlayerClean`:

```sh
python3 PhysicalGo/Tests/test_build.py
python3 PhysicalGo/build.py --list-tests
python3 PhysicalGo/build.py --all-tests
python3 PhysicalGo/build.py
```

`PhysicalGo/scripts/test_suites.py` is the authoritative registry. Native UI tests
need a macOS GUI session; scoring integration needs the configured KataGo. The
0.156 baseline passed all 82 Swift suites (81 in the full run, then an updated
wording/routing test) and six Python checks. This documentation change does not
constitute a new application regression run. The `.build/StorageFlow/regressions.py`
shared-module runner used previously is a local scratch tool, not a tracked
dependency required to continue in another checkout.

Before implementation, inspect current Git state and preserve existing work; the
user requested a committed/pushed baseline before large changes. Do not silently
change capture policy, remove timing safeguards to keep clocks running, or claim
live-camera validation from fixture tests.

## Implementation and validation record (2026-11-11)

Baseline was clean at `bf2c763d39be8400216d37d58b454aed2b2973ef`, already pushed
and matching `origin/codex/physical-go-maintainability` before implementation.
Verified release: **0.157 / build 158**.

### Batch 1 — Shared issue decisions and marking

`LivePositionIssue` separates evidence, affected intersections, reconciliation,
actions, and hold reasons. `RecordingClarity` uses those decisions for markers,
board clicks, and the highlighted-intersection action. Capture and sequence
issues claim their intersections before generic disagreements; global holds do
not mark arbitrary stones. Red pending-location rings remain distinct from orange
discrepancy rings, and use actionable shared issues rather than raw low confidence.

Fresh capture timestamps gate discrepancy debounce and review witnesses; repeated,
stale, future, or out-of-order frames cannot count as independent observations.
Fresh agreement clears resolved markers. Unknown readings alone cannot prove a
missing stone restored. Accepted recovery clears its obsolete affected markers.

### Batch 2 — Live inspection and explicit correction

Established-stone disagreements open a dedicated evidence inspector. **Recorded
position is correct** acknowledges the current position, point, and observed
reading without modifying SGF, move colors, turn events, or clock balances.
Persistent disagreement becomes a recognition task. New position/evidence or a
view interruption expires the acknowledgment. Duplicate confirmation is harmless;
changed or resolved issues reject stale confirmation.

Pending-location, chronology, saved-position browsing, and historical-correction
previews keep tracking active. Revision-aware proposals reject obsolete acceptance
and offer refresh/reopening. Actual changes validate source history and legality
before explicitly holding play. Canceling inspection neither pauses nor resumes.
Photo annotations remain separate from explicit game confirmation.

Capture inspection shows the capturing point, captured intersections, and remaining
removals. It preserves an existing automatic hold; converting that hold to manual
recovery remains a separate action. Off/below-threshold captures also have removal
guidance and shared click routes, without creating a clock hold.

### Batch 3 — Timing and capture integration

The audit found that the old deferred-history fallback could keep clocks running
from static alternation without individual completion times. It now holds at the
last supported established-board observation and requires timing review. Delayed
recognition near expiry cannot manufacture an automatic loss. No missing presses
or increments are invented. A known physical restoration/removal is not a turn.
Fully retained timed moves can be assigned to SGF exactly once without demanding
a new clock correction; existing correction requirements remain in force.

The Off / 2 / 3 / 5 settings and completion contract remain unchanged. With Off or
a below-threshold capture, the first supported clear placement establishes the
next turn while physical removal continues. For qualifying holds, the capturing
player is charged through the supported placement boundary, neither player pays
the verified removal interval, and the following player is charged from the first
supported completed-removal view. Each move receives one applicable increment.
Partial removals retain one capture identity. Obscuration, contradictions, hidden
starts, interruption, explicit pause, and restart retain the existing safeguards.

### Batch 4 — Verification and handoff

The authoritative registry now contains **83 Swift suites** plus **seven Python
build checks**. Aggregate commands use the tracked, content-addressed
`scripts/shared_regressions.py` compiler and run native executables serially;
the former `.build/StorageFlow/regressions.py` scratch script is not required.
The shared runtime cache includes production source bytes, compiler version,
architecture, and optimization mode. Individual suites still support standalone
compilation.

The first full run passed 80/83 Swift suites and all Python checks. Its failures
identified an obsolete archived move-39 no-hold expectation, backward synthetic
capture timestamps after resume, and a real red placement-ring rendering regression.
The tests now require a supported timing hold instead of invented timestamps,
keep timestamps monotonic, and verify the restored red ring. All five targeted
reruns passed: issue/timing, workflow UI, clock review, marker visibility, and
capture clocks. The final focused run passed 57 issue/timing checks, 417 capture
checks, and the 75-check local-clock suite. Capture-progress views for Off and
two-or-more settings and the dedicated disagreement inspector were visually
inspected. The repeat full registry run passed **84/84 aggregate entries**:
**all 83 Swift suites and all seven Python checks**. `git diff --check` is clean.

Final validation commands, run from `/Users/Dave/SGFPlayerClean`:

| Command | Result |
| --- | --- |
| `python3 PhysicalGo/Tests/test_build.py` | 7/7 passed |
| `python3 PhysicalGo/build.py --list-tests` | 83 registered Swift suites |
| `python3 PhysicalGo/build.py --all-tests` | 84/84 aggregate entries passed |
| `python3 PhysicalGo/build.py` | Signed 0.157 / build 158 produced |
| `codesign --verify --deep --strict 'PhysicalGo/.build/Physical Go.app'` | Passed |
| Independent hash over resolved build sources | Matches bundle source hash |

Local verification logs are `/tmp/physical-go-final-all-tests.log`,
`/tmp/physical-go-signed-build.log`, and `/tmp/physical-go-build-verification.txt`.
They are session artifacts, not required repository dependencies. Native images
include `.build/TestArtifacts/live-position-issues/disagreement.png`,
`capture-0.png`, and `capture-2.png`; the review queue and correction suites also
rendered their native views.

Coverage includes all ten policy cases and mixed issues; delayed/obscured views;
acknowledgment scope and automatic clearing; live moves during review and stale
acceptance; retained pending-prefix recovery; rapid G18 play; near-expiry timing;
manual pause, storage failure, persistence/restart; and each capture threshold at
and below its limit with exact balances and following-turn checks. Native review
windows and sheets are exercised and rendered in isolated recordings. The scoring
suite uses the configured real KataGo engine.

These are synthetic, saved-observation, recorded-image, and native-host tests.
They are **not actual live-camera validation**. The installed application is open
with a recording; tests and builds use isolated state and leave that session and
recording untouched during implementation. Installation and launch were subsequently
verified below; physical live-camera gameplay checks remain outstanding.

`python3 PhysicalGo/build.py` succeeded. The app at
`PhysicalGo/.build/Physical Go.app` verifies with `codesign --verify --deep --strict`
and its existing Developer ID identity (team `4H3MZNGDCC`). An independent SHA-256
calculation over all 134 resolved build sources matches `PhysicalGoSourceHash`:
`aab177e1fd843f87b358329169fc173584f96057ce3c39d87611e7b655496f7e`.
The build emitted the existing vendored Kokoro optional-coercion warning; no build
or signing errors occurred.

Remaining policy decisions: none introduced by this implementation. Any new
ruleset-specific timing choices remain a separate decision, as specified above.

Final implementation commit: `d2d988191b95a4f2ab96c25d582a86aabf84ab08`.
This documentation-only follow-up records the verified implementation commit;
application and test sources are unchanged.


## Installation and next tests (2026-11-11)

At the user's request, installed the verified 0.157 / build 158 bundle at
`/Users/Dave/Applications/Physical Go.app` and launched it with the current
`Physical Go recovered pending sequence 20261111-211954.sgf` recording.
Installed signature, executable bytes, and embedded source hash match the verified
build. Native UI shows **89 saved / 0 pending**, the same per-player move counts,
and **Review clock times · clocks stopped**. Camera startup reached **Live · Dave11
Camera**. Camera availability is a launch smoke check, not gameplay validation.
The SGF remains byte-for-byte identical to the preserved original; decoded clock,
pending-history, and review sidecars also match, including clock balances and the
existing timing-correction requirement. Play was not resumed.

Recording backups and a verification manifest are under:
`/Users/Dave/Library/Application Support/Physical Go/Backups/Install-0.157-20261111-231211`.
The old signed bundle is retained under `.build/InstallBackups/`.

### Finding during graceful shutdown

The old 0.156 app's normal quit flushed all moves and clock state correctly, but
its SGF export replaced the recovery provenance/root timing comments and added
BL/WL/OB/OW timing annotations to moves 87–88 despite timing still needing review.
All 89 moves and the entire clock sidecar were unchanged. Both before/after
exports were retained; the original recovered SGF was restored before installing
and reopening. This is an outstanding SGF serialization issue, not a verified fix
in 0.157; its shutdown/export path has not been changed by this installation.

### Prioritized acceptance tests

Use a separate test recording or a copy of this recording. Keep the preserved
89-move game out of destructive play/correction tests. For clock checks, record
observed placement/removal boundaries independently and compare persisted events,
turn transitions, balances, and increments—not only the displayed countdown.

| Priority / test | Exercise | Expected result |
| --- | --- | --- |
| 1. Recovered-game save/quit/reopen | On an isolated copy, save and quit with pending timing review; reopen twice. Compare all SGF properties and sidecars, including comments and moves 87–89. | Move history, recovery provenance, unknown timing, balances, and review requirement survive. No unreviewed times are exported as established facts. The installation finding above currently needs a regression/fix. |
| 2. Review while moves arrive | In a timed 9×9 game, open a placement or chronology review, play the next legal move, cancel, then try accepting an older proposal. Also browse Saved moves during play. | Tracking and clocks continue; one press/increment per move; browsing stays on its selected position; stale acceptance refreshes/rejects without altering history or pausing. |
| 3. Disagreement and acknowledgment | Briefly cover a recorded stone, then clearly remove/displace it. Inspect the absent intersection, acknowledge the recorded position, clear the view, and change the evidence again. | Brief obstruction has no actionable marker; persistent absence has a useful route. Acknowledgment changes no SGF or clock data, recognition follow-up is scoped, and changed evidence is not permanently masked. |
| 4. Capture policy matrix | Test Off and thresholds 2/3/5, one below and at each threshold. Remove prisoners in several trips; open/close progress; obscure a remaining point; make the following move. | One capture identity and accurate remaining-removal guidance. Below threshold, no removal hold. Qualifying removal time is uncharged; only fresh complete evidence resumes the next turn; each move receives at most one increment. |
| 5. Rapid play near expiry | Play rapid alternating moves with one uncertain location, first with retained timing and then with an intentionally unobserved interval. Resolve locations later. | Retained turns preserve their boundaries; a static later board cannot invent presses. Unaccounted timing triggers review rather than a false automatic loss. Earlier pending moves survive recovery. |
| 6. Outage, explicit pause, restart | Interrupt the camera during ordinary play and during a capture. Repeat after manually pausing; restart with pending locations or a capture hold. | Saved/pending history survives. Blind time is not charged without evidence, manual pauses persist, stale images cannot finish removal, and recovery does not loop or resume without its prerequisites. |

The automated 83-suite run already covers fixture/synthetic versions of most of
these behaviors. These next tests target real camera/hand timing and native user
interaction, plus the newly observed shutdown metadata regression. They have not
been performed on a physical game in this installation session.


## Guided physical-board run and speech correction (2026-11-11)

The user began a separate 19×19 test recording,
`Physical Go B6933674-65CD-48ED-AF06-FE53CFD44B73.sgf`. Its actual saved setup is
Fischer **1 minute + 30 seconds**, not the initially proposed 5 minutes + 2 seconds:
the attempted accessibility text-field edits had not committed to the setup model.
The actual settings were checked in the clock sidecar before interpreting results.
The earlier 89-move recording and its recovery provenance remain preserved.

Observed on the physical board, with user reports checked against the saved state:

- One Black stone at the center saved as `B[jj]`; White's clock began. There is
  exactly one timed move and one 30-second Fischer increment.
- A brief hand obstruction left one saved move, White's turn, and no lingering
  marker. SGF and timed-move events remained unchanged.
- Removing the center stone produced an orange ring; replacing it cleared the
  ring. One saved move and White's turn remained. SGF and clock events did not
  change, and no timing correction was required.
- **Speech failed:** the user heard obsolete instructions continue after the
  marker cleared, without a recovery acknowledgment. The journal confirms a
  7.7-second warning that finished after the discrepancy was gone. This particular
  warning used the system fallback; the walkthrough instructions used Kokoro.

The walkthrough paused on the one-move test game for the 0.158 / build 159 fix. Verified recovery now has an explicit speech lifecycle: fresh agreement
cancels pending or audible obsolete recording instructions; an episode whose
warning was heard gets one **Board position verified** acknowledgment. If clocks
are paused, it says **Clocks remain paused**. It neither changes nor resumes clocks.
Silent episodes, duplicate/stale observations, unresolved issues, mute, renewed
disagreements, and session changes must not produce stale recovery announcements.
Both acknowledgment phrases are bundled in Kokoro.

0.158 validation passed: seven Python build checks; 313 voice-asset checks (147
cached phrases plus uncached synthesis); and the five relevant regression suites
(`live-position-issues-test`, `recovery-guidance-test`, `obstruction-feedback-test`,
`workflow-ui-test`, `clock-feedback-test`). The expanded recovery-guidance suite
passed 44 checks, including the exact model/recorder removal-and-return sequence,
no extra move or clock event, paused restoration, stale/duplicate/unclear evidence,
unheard/muted/queued prompts, session changes, and interruption of real muted
audio. The first attempt found a test-only compilation error comparing non-Equatable
clock events; the test now compares their complete sorted-key encoded data and
passes. These five suites used the debug shared runtime; the installed release
was compiled optimized and separately signed and verified. This is focused
regression coverage for the speech fix, not a new full 83-suite run.

Installed and launched **0.158 / build 159** with the same one-move test recording.
SGF, complete clock state, and pending history remained unchanged after reopening;
shutdown also created an empty review sidecar, containing no reviews. The native
UI remains paused with one saved move. Source hash:
`2deef37585103d18cdee32c270215023d8b83607a687908b6a96b2cfe6bcb6e8`.
The signature and installed executable match the verified build. Recording and
prior-app backups are retained; the recording backup is
`~/Library/Application Support/Physical Go/Backups/Install-0.158-20261111-234747`.
The user repeated the physical removal/restoration test on 0.158: the warning
stopped and the recovery message played. Every journaled clock state from initial
resume verification until the user's explicit Pause remained running; there was
no automatic hold or automatic restart during removal/restoration. The only
failure was pronunciation: Kokoro spelled “verified” letter by letter.


### Pronunciation follow-up: 0.159 / build 160

The pinned lexicons contain “verify” but not “verified”; the offline G2P fallback
therefore emitted letter names. `Resources/KokoroPronunciations.json` now supplies
the application's pronunciation override. Resource preparation layers it onto the
bundled dictionary while keeping the upstream vendor files unchanged. Both short
recovery clips are regenerated, with tests checking the actual synthesis phonemes
rather than only nonempty audio. The user listened to both regenerated clips and
confirmed that “verified” now sounds correct.

Validation passed: 317 speech/asset checks, seven Python build checks, 44 recovery-
guidance checks and 38 layout/offline-voice checks. No clock or recorder Swift code
changed in this follow-up. The optimized signed build was installed and launched;
its signature, executable, dictionary, and two corrected clips match the verified
build. The independently resolved 134-file source hash remains
`2deef37585103d18cdee32c270215023d8b83607a687908b6a96b2cfe6bcb6e8`.
Native UI confirms one saved move, White next, camera live, and both clocks paused
at 5:00. Complete clock, pending, and review sidecars survived unchanged. Normal
shutdown added only an accurate SGF root comment about the explicit clock
correction after move 1; the saved move and its timing annotation are unchanged.
Before/after snapshots and the previous app are retained; recording backup:
`~/Library/Application Support/Physical Go/Backups/Install-0.159-20261112-000449`.
The original 89-move recording remains byte-for-byte unchanged.

Before continuing the guided tests, both test-game balances were explicitly
adjusted to **5:00**, retaining White to play, the single saved Black center move,
and the paused state. This is a deliberate test allowance, not a refund inferred
from the removal interval; the before-adjustment state is retained in the guided
session artifacts. The original 89-move recording remains separate.

Guided Saved moves test **passed**: the user observed two saved moves and Black’s
clock running, then manually paused. Saved state confirms `W[pp]`, exactly one
additional timed move and one 30-second increment, Black next, no pending or
provisional moves, and no timing correction required. This checks continued play
while viewing Saved moves; historical cursor pinning and stale proposal acceptance
remain untested on the physical board.

Next guided test: resume, remove the center Black stone until warning speech
starts, manually pause while it is absent, then restore it. Expect two saved moves,
Black next, the missing-stone marker cleared, and “Board position verified. Clocks
remain paused.” Both clocks must remain stopped. **Failed:** the orange ring stayed and no
recovery acknowledgment played after restoration. The journal confirms fresh
exact agreement with the two-stone saved board and stopped clocks. Before Pause,
the prolonged absence crossed the 12-second escalation and created a missing-only
review. That saved review still interpreted the center as empty after restoration;
the short-removal regression never crossed this path. Failure artifacts are
preserved in `.build/GuidedTests/step-07-failure`.

### Prolonged missing-stone restoration: 0.160 / build 161

A single unresolved missing-only review now reconciles automatically after at
least five independent exact views spanning 0.8 seconds show the entire saved
position again. The same path runs during recording and explicit pause, before
restoration could be mistaken for a new deferred move. It preserves the original
review identity, before/after camera snapshots, and evidence folder as a resolved
zero-move section. It does not call the explicit history-approval/clock-finalization
path, rewrite SGF, add an increment, or release a manual pause.

The guard excludes later retained sections, proposed move sequences, uncertain
views, hand obstruction, turn disagreement, provisional/live clock events, timing
review, capture holds, finished/scored games, and persistence errors.

The expanded recovery-guidance suite passed **58 checks**, including the actual
long-absence escalation with two stones, manual pause, repeated frames, hand
re-entry, uncertainty, evidence preservation, save/reopen, running restoration,
and refusal to erase later moves or proposals. Seven Python build checks passed.
The seven related suites also passed: live-position issues, review queue, recovery
lifecycle, capture clocks, workflow UI, session resume, and storage flow. These
eight focused suites used the debug shared runtime; they are not a new full
83-suite run. The optimized signed build was verified and installed as **0.160 /
build 161**. Independently computed source hash (134 files):
`8a72ba6a440199ceaddad7d6f5baac4c407c3d440b3a673d2f53d6ae46a7ac90`.
Installed executable and signature match the verified build. Backup:
`~/Library/Application Support/Physical Go/Backups/Install-0.160-20261112-002043`.

On launch, fresh live camera views of the user’s restored two-stone board resolved
the existing review automatically. Native UI reports zero attention points, two
saved moves, Black next, and both clocks paused. SGF, the complete clock sidecar,
and pending sidecar are unchanged; the review retains its original identity,
before/after snapshots, and evidence folder, marked resolved with zero moves.
The separate 89-move recording remains byte-for-byte unchanged. This verifies the
actual failed saved review against the live board; the subsequent full physical
retest is recorded below.

The user repeated the **20-second** center Black removal, manually paused while
it was absent, then restored it: **PASS**. The ring cleared, “Board position
verified. Clocks remain paused” played correctly, both clocks stayed stopped, and
two saved moves remained. Saved SGF and timed-move events match the pretest
baseline; the second missing-only review resolved with zero moves, Black next,
and no timing correction required. The complete physical speech/restoration
sequence is now verified on 0.160.

Paused camera restart **passed**: the user left both stones untouched and clicked
**Restart camera**. Camera returned Live, two saved moves and Black next remained,
both clocks stayed stopped at unchanged times, and no orange ring appeared. Saved
SGF and the entire clock sidecar match the pretest baseline exactly.

Running camera restart **passed**: the user reports Black resumed automatically,
with no speech. Journal confirms a **1.434-second** automatic hold, with Black’s
balance identical at automatic pause and resume; no camera-hold time was charged.
SGF and timed-move events remain unchanged, with no duplicate increment or timing
review. The user subsequently paused.

Silence follows the current paired-announcement policy: the automatic-pause
warning is delayed one second and was canceled before actual playback when the
board recovered. A resume announcement is owed only if pause/alignment/lighting
guidance was audible. This quick restart produced neither audible warning nor
resume speech; it is not a speech failure. The longer audible-interruption check
is recorded below.

Longer camera stop/start **passed**: the user heard the pause warning, then
“Clocks resumed. Black to play” after starting the camera. Black resumed
automatically; the user manually paused with two saved moves. The journal records
both utterances starting and finishing, and a **16.744-second** automatic hold
with identical Black balances at pause and resume. SGF and timed moves are
unchanged, with no timing correction. This checks explicit camera stop/start;
physical disconnect and reconnect remain untested.

Historical-position browsing **passed**: the user stepped back to move 1, placed
Black at a vacant corner star point, and saw the history display stay on move 1
while the third move was saved and White’s clock started. Live position showed
all three stones; the user paused. Saved `B[dd]`, exactly one new timed move and
one 30-second increment, White next, no provisional moves or timing review.


### Overnight handoff and remaining acceptance work (2026-11-12)

Paused at the user's request; no next test started. Installed 0.160 / build 161.
Current test recording has `B[jj];W[pp];B[dd]`, White next, clocks stopped:
Black 227.714432 seconds, White 298.658434 seconds. The native display rounds up
these values. Preserve this game; compare the physical board with Live position
before continuing. An overnight copy of SGF/clock/pending/review files is in
`.build/GuidedTests/overnight-after-step-12`; session details are in
`.build/GuidedTests/session.json`. The original 89-move recording remains separate.

For a concrete working count, the live acceptance matrix now has **9 distinct
passed scenarios and 18 remaining**, approximately **one-third complete**.
Setup, repeated attempts, and retests after fixes are not separate passed scenarios.
This is a planning breakdown, not an earlier fixed test count; discovered defects
may add retests. The 83-suite automated baseline and subsequent focused suites
are separate from this manual acceptance count.

Passed scenarios: normal move/turn/increment; brief hand obstruction; running
missing-stone restoration/speech; recording while viewing Saved moves; prolonged
removal restored during manual pause; paused camera restart; running quick camera
restart; longer camera stop/start with paired speech; historical cursor stays put
while a new move arrives.

Remaining physical scenarios:

- Reviews and discrepancies (4): placement review while a move arrives/cancel;
  chronology review with stale acceptance; recorded-position acknowledgment and
  changed evidence; nudge/displacement and restoration.
- Capture policy (7): Off with multiple prisoners; threshold 2 with 1 and 2
  prisoners; threshold 3 with 2 and 3; threshold 5 with 4 and 5. Include removal
  in trips, opening/closing progress, an obscured remaining point, and the next
  move in these scenarios.
- Rapid play near expiry (2): retained turn timing with uncertain locations;
  intentionally unobserved interval requiring timing review.
- Outage/restart variants (5): outage during capture; outage during manually
  paused capture; app reopen with pending locations; app reopen with a capture
  hold; physical camera disconnect/reconnect.

One additional agent-led regression/fix remains for recovered-game SGF metadata
and unknown timing across save/quit/reopen, using an isolated copy of the original
89-move record. That is separate from the 18 remaining physical-board scenarios.
Suggested first morning test: recorded-position acknowledgment, with a baseline
snapshot and explicit no-change checks for SGF and clocks.


### Morning continuation: changed lighting preflight

User resumed the walkthrough with the three stones still in place, game paused,
and possibly changed lighting. Saved SGF and complete clock sidecar match the
previous night's snapshot exactly. Native UI reports camera stopped with “Camera
could not recover a usable live image”; the displayed saved position and old
observations cannot establish current lighting or recognition quality.

First action: keep stones untouched and clocks paused, click **Restart camera**,
wait for **Live** and five seconds of clear view, and report any lighting/alignment
warning or marked intersection. Await fresh evidence before continuing the planned
recorded-position acknowledgment test. This is a setup preflight, not an additional
passed acceptance scenario; count remains 9 passed / 18 remaining.


Morning preflight **passed**: user reports Live, three saved moves, White next,
clocks stopped, and no rings or lighting warnings. SGF and the entire clock
sidecar match the preflight baseline. Fresh observations identify all three
recorded stones; there is limited uncertainty at empty intersections, so this
is not a claim of perfect recognition across the entire board.

Next acceptance scenario, acknowledgment part A: keep game paused, lift center
Black, wait for its orange ring, click the marked intersection on Live position,
and choose **Recorded position is correct**. Leave the physical stone absent and
the panel open to inspect the result. Expect confirmation without any saved-move,
turn, or clock change; the unresolved physical absence may remain marked. If the
button is unavailable, inspect the actual panel before taking a different action.
Baseline saved; awaiting user result. Restoration, open-panel stale-action checks,
and changed evidence after acknowledgment will follow before counting this
scenario as passed.


Acknowledgment part A **passed**: user screenshot shows “Check recognition” and
“Recorded position confirmed. No moves or clock balances changed,” with the
acknowledgment button disabled. Saved SGF, complete clock JSON, and review JSON
match the baseline exactly. The center stone remains physically absent; this
partial result does not complete the acknowledgment/changed-evidence scenario.
Screenshot retained in `.build/GuidedTests/step-14-acknowledgment.png`.

Part B: leave the recognition panel open and game paused, restore Black at center,
and clear hands for five seconds. Expect the panel to report the issue resolved
or position changed and disable the old correction action. The panel's static
highlight is not itself the live-issue marker; assess its state text and actions.
Baseline saved; awaiting user observation before closing the panel or testing
fresh disagreement again.


Part B functional behavior **passed**, but presentation **failed** user review:
the correction actions disabled and resolution text appeared, yet the panel still
said “Check the current disagreement” and kept an orange ring at K10. SGF and the
complete clock sidecar remain unchanged. User requested a large **RESOLVED** label
at the top and explicitly required that the board not move during the transition.
Screenshot: `.build/GuidedTests/step-15-resolved-presentation-failure.png`.

### Resolved-panel presentation: 0.161 / build 162

The panel distinguishes an active disagreement, acknowledged recognition check,
verified resolution, and changed/stale evidence. Only verified agreement after
the recorder clears its marker produces **RESOLVED**; stale or newly contradictory
evidence instead shows **POSITION CHANGED**. Resolved/stale selections have no
orange highlight or enabled correction/acknowledgment action. The earlier camera
report is labeled as an original report rather than a current observation.

All heading and explanation variants reserve identical layout space; only the
current content is visible and accessible. Acknowledgment details occupy that
same explanation area. The result row reserves space before acknowledgment too,
keeping board dimensions and sheet position stable across the normal transition.
Native screenshot regression checks board pixel bounds and window bounds across
active, acknowledged, resolved, and changed states, as well as ring removal and
preservation of the explicit pause. **65 live-issue checks and 38 layout/offline-
voice checks passed**, along with seven Python build checks. In the native panel
snapshots, board bounds remain `(20, 146, 440, 440)` and window bounds are identical
in all four states. The resolved snapshot has zero orange-ring pixels. The new
screenshot detector initially assumed an overly narrow RGB range for macOS system
orange; it was calibrated against the rendered native color before rerunning both
suites successfully. These are focused UI regressions, not a new full-suite run.
Optimized **0.161 / build 162** was signed, independently source-hash checked,
installed, and launched. Source hash (134 resolved files):
`4b76007e598d52f2e148ea215cee7d1a608834bda947c87b4d8cffe547289ca1`.
Installed executable and signature match the verified build. The open old panel
was closed to allow normal app shutdown; no force termination was used.
SGF, complete clock, pending, and review sidecars survived shutdown and reopening
unchanged. Native UI confirms three saved moves, White next, paused clocks
(Black 3:48, White 4:59 displayed), camera Live, and no attention points.
Recording backup: `~/Library/Application Support/Physical Go/Backups/Install-0.161-20261112-121000`.

Next physical retest: while paused, remove center Black, open its marker,
acknowledge the recorded position, then restore it with the panel still open.
Expect prominent **RESOLVED**, no orange ring, disabled obsolete actions, and
no board shift or resize. Baseline saved; awaiting user feedback. The changed-
evidence follow-up remains outstanding before counting the acceptance scenario
as complete.


0.161 physical panel retest **not run yet**: user reports changed lighting and
flickering circles while **Live feed** is selected. Recent observations alternate
between known/uncertain readings for center Black and White, with additional
uncertain empty intersections; alignment checks report insufficient support on
some outer rails. No persistent live adjustment points are recorded and the
global `lightingBlocked` flag is false. These facts do not establish that lighting
is the sole cause; the user inspecting the live image also suspects lighting.
Saved SGF and the complete clock sidecar still match the pretest baseline.
Diagnostic tail retained in `.build/GuidedTests/lighting-flicker-evidence.json`.

Next recovery step: keep game paused and camera/board/stones fixed; make lighting
even, reducing bright reflections or deep shadows (shade direct sunlight if
present), clear hands, and observe for ten seconds. Await steady detection before
resuming the panel retest. No grid, reference, or detector thresholds changed.


### Occupied-board lighting baseline investigation

User adjusted lighting but still sees flickering; requested refreshing the baseline
using the three known stones or confidence across time. Captured a diagnostic
sample at `Captures/Samples/Lighting refresh 3 stones 20261112` (ignored local
artifact). The image visibly contains all three stones and uneven reflection.
Offline comparison using the captured calibrations: existing empty-reference
comparison correctly classified all 361 intersections; appearance-only detection
classified all three stones correctly but left 24 empty intersections uncertain.
This single image does not establish behavior across changing frames.

Used **Reestablish grid** to refresh geometry/tracking from the occupied view while
preserving the original empty-board reference. Saving a sample freezes the view;
explicitly resumed the camera afterward. Native UI confirms Live, 3 saved moves,
White next, manually paused. A subsequent 30-second window contained 90 processed
observations: 88 exact full-board matches; two had only empty intersection index
167 uncertain. All three occupied intersections matched throughout. No persistent
adjustment points or lighting blocks appeared. SGF bytes and complete clock JSON
remain identical to the overnight baseline. Evidence saved at
`.build/GuidedTests/lighting-after-grid-refresh.json`.

This is a tracking refresh, **not a newly implemented adaptive lighting baseline**.
Remaining flicker is not declared fixed. A future occupied-board lighting refresh
should learn exposed wood from multiple independently confident frames, exclude
stones/obstructions/uncertain regions, retain the original empty reference, and
use known stones as validation rather than overwrite contradictory observations.
Temporal confidence must not teach a removed stone, hand, or newly placed stone
into the baseline. Validate with changed-light replay sequences, removal and new
placement after refresh, moving shadows/occlusion, and geometry shifts. Live feed
currently draws per-observation uncertainty directly; it can flicker without a
persistent recording issue. Physical resolved-panel retest remains not run.


### Live feed switches between flattened and raw perspective

User clarified the flicker is the entire board alternating between the flattened
grid view and the unflattened camera image. The earlier 88/90 observation summary
counted emitted board observations, not rejected alignment frames, and therefore
did not establish display stability. Alignment logs confirm intermittent rejects:
all three known stones match, profile error about 0.016 (limit 0.04), but one outer
rail has only 1–2 matches (minimum 3). The display pipeline returned no rectified
image for any rejected alignment; ExperimentModel then replaced the flattened
view with raw pixels. Full-grid search also cleared the displayed transform.

0.162 implementation under test: preserve the last established transform for
presentation of current camera pixels when alignment is unverified, and retain
presentation during full-grid search. An overlay says “Checking grid alignment ·
recognition paused” without changing the camera canvas layout. Recognition
markers remain hidden and unverified frames supply no observations/moves. No
alignment thresholds or stone evidence requirements are relaxed. This addresses
the perspective jump; intermittent alignment rejection remains a separate issue.

Regression coverage being run: alternate clear real photos and obscured frames,
assert stable display geometry, current rather than stale pixels, absent
recognition on rejected frames, unchanged SGF and clock engine, retained display
through failed full-grid search, recovery, and explicit raw-view toggle. Existing
occupied-board alignment and recovery lifecycle/guidance suites also run.
Physical panel retest remains pending; no additional physical scenario credited.


0.162 targeted validation passed: 1,377 grid/UI checks (including the new
alternating rejected/accepted-frame and failed-search regression), 18 occupied-
board recovery checks, 58 recovery guidance checks, 16 recovery lifecycle checks,
and all 7 Python build-registry tests. Native `GridResetUI/alignment-checking.png`
visually inspected: flattened current pixels with checking label and no recognition
markers. Production build/install pending; physical result remains unverified.


Installed and launched **0.162 / build 163** after optimized build, independent
134-source hash check, and strict/deep Developer ID signature verification.
Source hash `5cbce794193e72d2bdd1f693c263ec4a77ad2ad1c97688b74a0e54cf4cf6f9a8`.
Backup: `~/Library/Application Support/Physical Go/Backups/Install-0.162-20261112-132604`.
Normal quit and relaunch preserved SGF bytes and complete clock, pending, and
review JSON. Original 89-move game also remains unchanged. Native UI: camera
Live, 3 saved, White next, manually paused, Black 3:48 / White 4:59; selected
Live feed for the user's check. Awaiting a 15-second physical observation of
whether perspective stays flattened; a checking label may still appear because
this release does not relax alignment checks. Panel retest remains pending.


### 0.162 physical result and position-informed glare follow-up

User confirms all text/boxes stable and image remains flattened: perspective
switching retest **PASS**. A few amber circles still flicker within the shiny patch.
This is not a pass for glare recognition or the still-pending resolved-panel test.
A fresh 60-second log sample contained 248 observations, all three known stones
correct throughout, no extra detected stones, no persistent adjustment markers,
and no logged alignment rejection in that window. Empty index 109 was uncertain
in 247 observations; 147, 148, 167, 186, 204, and 166 were intermittently uncertain.
SGF and complete clock JSON still match the overnight baseline. Evidence:
`.build/GuidedTests/stable-perspective-glare.json`.

User explicitly points out that known stone locations and number played should
inform glare thresholding. Confirmed implementation gap: saved positions inform
alignment and established-stone tracking, but reference-backed local brightness
classification does not receive the expected position or temporal confidence.
Expected occupied count must come from the reconstructed position (accounting
for captures and passes), and should guide the lighting model without imposing a
maximum number of visible stones while a new move is being made.

Saved current real image/reference/calibration at ignored sample folder
`Captures/Samples/Glare known three stones 20261112`; viewed the image and resumed
the camera after Save sample froze it. Offline replay: original-reference detector
has one uncertain empty point (109), all three stones confidence 1; local appearance
has 35 uncertain empty points but all three stones correct. The two methods do
not fail at identical points. No threshold/baseline changes installed yet.

Next requested diagnostic capture: with the game still paused and original three
stones untouched, place one extra White on an empty intersection within the
shiny patch, clear hands, and leave it for capture. This will supply a real new-
stone counterexample under the same lighting before tuning expected-position
background estimation. Capture that view, then ask the user to remove only the
extra White and capture restoration. Saved game must remain at three moves.
This diagnostic detour does not add an acceptance-plan pass.


Extra White diagnostic captured after user confirmed placement and cleared hand:
`Captures/Samples/Glare extra white 20261112` (ignored local artifact). Inspected
photo confirms the added White within the reflection, with original three intact.
Raw reference-backed reading at canonical index 185 changed from empty to White
(confidence score 0.8214). Original Black 60/180 and White 300 remain correct at
confidence 1. Empty indices 109, 147, and 167 remain uncertain in this sample.
Native UI correctly reports 3 saved / 0 pending / 1 detected outside saved history;
SGF bytes and complete clock JSON still match the overnight baseline. Camera
resumed after sample capture. Thirty-second observation tail saved at
`.build/GuidedTests/glare-extra-white-evidence.json`.

This supplies a real positive stone example under the glare, rather than an
edited or synthetic image. Position-informed thresholding must preserve this
new White despite the saved position containing only three stones. No detector
changes installed. Next: remove only the temporary White, leave the original
three in place, remain paused, then capture the restored empty intersection.


Restoration captured at `Captures/Samples/Glare restored three stones 20261112`:
actual extra White removed, original three intact. Raw index 185 returned to
empty (score 0.9643); only empty index 54 uncertain in that snapshot. SGF and
complete clock JSON unchanged, camera explicitly resumed after capture. Added
real three-image fixture `Tests/Fixtures/KnownPositionGlare` with original empty
reference and per-frame calibrations. The recorded sequence is empty → White →
empty at 185; repeated frames in temporal unit tests use synthetic timestamps,
not a claimed physical video test.

### Position-informed local lighting baseline (0.163, under validation)

Added `KnownEmptyLighting` on the camera analysis queue. Expected occupancy is
reconstructed from the saved position; known occupied stones must agree in color
and confidence. Eight independent empty readings (score at least 0.8) over at
least 1.4 seconds can establish a local baseline at a saved-empty intersection.
The baseline stores sixteen brightness/chromaticity patches plus the intersection
center; bounded noise tolerance can resolve a later *uncertain* classification
when current pixels still match. Explicit Black/White readings always pass through
and invalidate that intersection's empty baseline. The saved stone count is never
a cap on visible stones. This learns from raw observations only; a resolved output
cannot refresh its own baseline. Independent confirmation expires after 30 seconds.

Invalid alignment, hands, manual corrections, camera gaps, changed game/position,
and substantial grid displacement invalidate baselines. Occupied disagreements
also clear learned background. Original reference/camera images remain intact;
diagnostics retain unadapted readings and the list of prior-resolved points.
No deployment yet. Targeted replay plus existing lighting, glare, stone tracking,
recovery lifecycle, and native grid/UI suites are being checked. Residual glare
that never supplies enough independent empty evidence will remain uncertain.


0.163 validation complete: **6/6 targeted Swift suites passed**: 22 new local-
baseline checks, 86 lighting checks, 82 established-stone checks, 16 recovery
lifecycle checks, 1,377 native grid/UI checks, and existing recorded-glare suite
(real Empty→White→Empty plus six synthetic photographed-stone transfers). All
7 Python build checks passed. The new suite verifies expiry without self-training,
small central occlusion, weak White evidence, missing known Black, context and
position changes, stale/invalid frames, duplicate timestamps, and shifted grid.

Installed **0.163 / build 164**, independently verified 135-source hash and strict/
deep Developer ID signature. Source hash `00625f3b01548100fea7e02bd1b01ce341b6d433c47be7c6502189fa3b68f4fa`.
Backup: `/Users/dave/Library/Application Support/Physical Go/Backups/Install-0.163-20261112-145044`. Normal quit and relaunch preserved exact SGF plus semantic
clock, pending, and reviews JSON. Original 89-move recording remains unchanged.
Live feed selected; original three-stone test game remains manually paused.
Await user 20-second hands-clear observation of glare rings. This is a conservative
baseline for recurring uncertain empty readings, not a claim that all glare is
resolved. Original resolved-panel acceptance retest remains pending.


### Residual glare at O14, P14 and C17 (0.163 physical follow-up)

User reports stable amber O14, intermittent P14, occasional C17. Captured a real
19-second/82-analysis diagnostic sequence while paused, at
`Captures/Diagnostics/Diagnostic 2026-11-12 14-53-36 1A1F48B6`. Capture is pinned.
Temporarily protected all 180 existing unpinned archives against rotation, selected
1 GB allowance (813 MB available granted), stopped after 312 MB, restored the
original 10 GB setting and all previous pin states; **zero archives rotated**.
Camera/game remained live/paused; original three stones untouched.

With display rotation 3, O14/P14/C17 are canonical indices 260/279/54. All 82
frames retain the three stones correctly. Learned empty count ranges 276–299.
O14 is uncertain in all 82 raw frames and thus never seeds a reference-based
baseline. P14 is empty in 64/82 frames at score 0.75, below the 0.8 learning gate;
18 remain uncertain. C17 has 31 raw uncertainties, 11 resolved by baseline,
20 remaining. G16 (129) has 71 raw uncertainties, all resolved. This establishes
partial benefit, not completion of the glare fix.

User asks whether thresholds should adapt to lighting across different board
regions, and whether discontinuities/edge detection can help. Current local-
appearance replay on sampled frames sees O14 as empty at 0.75, P14 at 0.875, C17
at 1.0. These use a local wood brightness/color plane plus printed-line contrast;
the stale-reference branch is the source of these remaining disagreements.
Existing detection also checks radial stone boundaries and grid coverage. A
stone-like boundary alone is insufficient because reflections can have edges;
combine shape, grid occlusion, current wood appearance, and saved-position context.

Under test: allow repeated independent current-image empty evidence (local wood
plane plus both visible grid axes) to establish a saved-empty baseline when the
reference comparison is uncertain or weak. Explicit stone readings still win.
A pixel change challenging an existing baseline blocks appearance-only relearning
until an independent reference-empty reading clears the challenge. Actual temporal
fixture `Tests/Fixtures/ResidualGlare` contains 16 distinct captured frames with
original capture timestamps and unadapted readings. Regression also challenges
all three reported points with synthetic photographed Black/White transfers.
No new deployment yet. Original resolved-panel retest remains pending.


The user further asks about edge/discontinuity evidence. The current-image path
uses local contrast across the two grid axes, together with a fitted nearby wood
brightness/color plane. It leaves existing radial-rim and grid-coverage stone
checks intact. No global brightness threshold was loosened. This is an additional
independent evidence source, requiring the same eight fresh frames / 1.4 seconds
and saved-position validation; it does not relabel an uncertain point from the
saved position alone.

Full 82-distinct-frame replay passed: the final six frames have zero uncertainties
at O14/P14/C17 (raw counts 6/2/3). 237 residual-glare checks passed, including new
photographed Black/White transfers at each of the three points, both after
learning and at cold start. 32 baseline-policy checks passed, including ten
repeated central-obstruction frames with the appearance path enabled. Synthetic
transfers are separately labeled and are not physical placements. The compact
16-frame committed fixture is also being run with broader regressions. Preparing
0.164/build165; no installation yet.


0.164 verification: **6/6 targeted suites passed**, including 171 checks on the
compact real residual-glare sequence and synthetic cold/warm new-stone challenges,
53 known-empty checks (including all 21 occupied-fixture stones and grained White),
86 lighting, 82 stone-tracking, 16 recovery-lifecycle, 1,377 grid/UI, and recorded
recovery-glare tests. All 7 Python build checks pass. Full 82-frame local replay
also passed earlier (237 sequence checks). No entire-suite rerun is claimed.

Installed **0.164 / build 165**, verified optimized build, strict/deep Developer
ID signature, and independent 135-source hash `378467addc6dcfee7e8498112deab588352066d9b6e160c0c7ce2688a720b8bd`.
Backup: `/Users/dave/Library/Application Support/Physical Go/Backups/Install-0.164-20261112-151227`. Exact SGF and complete clock/pending/review JSON match
before/after quit and relaunch; original 89-move recording unchanged. Live feed
selected for a 20-second hands-clear O14/P14/C17 retest; game remains paused with
3 saved moves, White next. Await physical result. Original resolved-panel
acceptance test and the remaining acceptance matrix are still pending.


### 0.164 live observation: remaining brief shadow-boundary uncertainty

User reports the three stones look correct, with no amber circles on them. Brief
flickers near B18 initially cleared; subsequent reports include B17, G17, F17,
C17 and D17, all appearing briefly and disappearing. User observes these at
higher-contrast shadow boundaries. Do **not** mark glare recognition completely
resolved. First checked 30-second window: 123 emitted observations, all three
stones correct, no persistent adjustment points; C17 uncertain in five frames and
D17 in one. SGF bytes and entire clock sidecar remain at the overnight baseline.
Evidence: `.build/GuidedTests/glare-0164-settled.json`; subsequent shadow-edge tail:
`.build/GuidedTests/glare-0164-shadow-edge.json`.

A shadow edge can also supply a discontinuity; stone recognition must combine
boundary shape, interior color/appearance, grid coverage, and temporal evidence.
An uncertain frame should not become a stone merely to eliminate an amber marker.
Current remaining issue is brief empty-point uncertainty, pending further physical
challenge of the new learned background. Next guided step: while paused, place a
temporary White at O14 (canonical260), leave the original three untouched, clear
hands, and leave it for capture. Expect White recognition and one detected outside
saved history, with three saved moves and unchanged clocks. Then capture and
remove only the temporary White. Original resolved-panel retest still pending.

Follow-up 60-second window: 250 observations; transient uncertainty at F17 (8),
C17 (15), D17 (9), G19/B19/H16 (one each). Zero extra stone observations, zero
known-stone mismatches, zero persistent adjustment frames. SGF and clock JSON
unchanged. This supports the brief-uncertainty classification for this window,
without claiming every future shadow is harmless.

### 0.164 physical new-White challenge at O14

User placed a temporary White at O14, cleared hands, and reported one detected
outside saved history, three saved moves, both clocks paused. Saved actual sample
`Captures/Samples/Glare O14 White 0164 20261112`: O14 (canonical260) reads White
with heuristic confidence 1.0; all three original stones also read correctly at
1.0. Photo confirms four physical stones. One other point, D17 (73), is uncertain
in this sample; this does not establish complete shadow-flicker resolution.
The learned-background change did not hide the real added White in this test.
Exact SGF and full semantic clock, pending and review JSON remain equal to the
overnight three-move baseline. Resumed camera after the sample capture; game stays
manually paused. Next step: remove only temporary White O14, leave the original
three untouched, clear hands, and verify return to zero detected outside history.
Restoration remains pending; original acceptance counts are unchanged.

O14 restoration **PASS**: user removed the temporary White and reports zero
detected outside saved history. Native UI confirms Live, three saved, zero pending,
zero outside, White next, manually paused. Actual sample
`Captures/Samples/Glare O14 restored 0164 20261112` reads O14 empty at heuristic
confidence 0.80645, all original stones correct at 1.0, and no uncertain points
in this captured frame. Exact SGF and full semantic clock/pending/review JSON
still match the overnight baseline. Camera resumed after capture. This completes
the physical new-White placement/removal challenge, not the broader shadow-flicker
investigation. Original acceptance counts remain nine passed / eighteen remaining.
Return next to the deferred resolved-panel retest: while paused, lift center Black
K10, open its orange marker in Live position, acknowledge recorded position as
correct, and leave the panel open for restoration on the following guided step.

0.164 resolved-panel retest, acknowledgment stage **PASS**: user removed center
Black K10, opened its orange ring, chose “Recorded position is correct,” and left
the stone off with the panel open. Native UI confirms “Check recognition” and
“Recorded position confirmed. No moves or clock balances changed.” Three saved,
White next, manually paused; exact SGF and semantic clock/pending/review JSON
match the baseline. Next: restore K10 while leaving the panel open, clear hands,
and check large RESOLVED heading, orange highlight removal, unchanged board size
and position, and clocks remaining paused. Restoration result is pending.

Resolved-panel restoration **PASS** on 0.164: user confirms prominent RESOLVED,
orange ring gone, board unchanged in position and size, three saved moves, both
clocks paused; panel left open. Native UI independently confirms RESOLVED, camera
agreement at K10, zero attention points, White next, and manual pause. Exact SGF
and full semantic clock/pending/review JSON remain unchanged. The presentation
defect is physically verified fixed. Next, with the same panel open and clocks
paused, replace center Black K10 temporarily with a spare White and clear hands.
Expect POSITION CHANGED rather than RESOLVED, obsolete acknowledgment/correction
actions disabled, stable board geometry, and no saved-move or clock changes.
This checks changed evidence after acknowledgment; result remains pending before
counting the combined acceptance scenario complete (still nine / twenty-seven).

Changed-evidence stage **PASS**: with temporary White physically at K10 and the
same panel open, user reports POSITION CHANGED, disabled actions, stable board
geometry, three saved moves and paused clocks. Native UI confirms POSITION
CHANGED and identifies the diagram as “Recorded game at move 3 of 3”; exact SGF
and full semantic clock/pending/review JSON are unchanged. User notes the diagram
still shows Black K10. This is expected for the saved-position diagram, but the
distinction from the current camera observation needed explanation during testing.
Next restore original Black K10, removing only the temporary White; keep panel
open and clocks paused. Expect RESOLVED again with no orange ring, geometry or
recording changes. Final restoration pending before closing this scenario.
Recent observation journal independently reads White at canonical180 (K10), with
adjustment point180 present, confirming the camera sees the changed color while
the diagram preserves saved Black.

Final restoration **PASS**: user restored original Black K10 and reports RESOLVED,
no orange ring, three saved moves and paused clocks, panel still open. Native UI
confirms resolution and zero attention points. Exact SGF and full semantic
clock/pending/review JSON remain identical to the overnight baseline. The combined
recorded-position acknowledgment / changed-evidence acceptance scenario is now
complete, including the physical resolved-panel layout retest. Updated original
matrix: **10 of 27 passed, 17 remaining (about 37%)**; three review/discrepancy
scenarios remain. Lighting diagnostics are not counted as additional matrix passes.

Next scenario: nudge/displacement and restoration. Close the panel, resume play
(White to play), slide the existing center Black halfway from K10 toward L10,
clear hands for five seconds, then manually pause and leave Black off-center.
Expected: no additional saved move or increment, no turn switch, White clock
continues until the explicit pause; record any centering/ambiguity guidance.
Unlike the previous paused checks, White's balance should decrease by actual
running time. Await observation before restoration and before counting a pass.

Nudge stage: **history/timing PASS, centering guidance unresolved**. User slid
Black halfway K10–L10; three saved moves remained, White clock ran until manual
pause. No orange marker appeared in Live position, while Live feed shows amber
circles at both K10 and L10. Recent observations read both canonical180/199 as
uncertain, with no adjustment points. Exact SGF is unchanged; the sole semantic
clock-sidecar change is White remaining time, down 17.603399625 seconds to
281.055034459. No move, press evidence, increment or turn change occurred.
Saved actual off-center sample `Captures/Samples/Nudge K10 toward L10 0164 20261112`
for investigation; resumed camera afterward. Lack of actionable centering guidance
is an open finding, not a complete scenario pass. Next restore Black to K10 while
paused, clear hands, verify the two local amber circles clear and three saved /
White next / paused clocks remain. Post-nudge preservation baseline is
`.build/GuidedTests/after-nudge-paused-0164`. Count stays ten passed / seventeen
remaining until restoration and the guidance finding are addressed.

Restoration **PASS**: user centered Black K10 again; both local amber circles
cleared, three saved moves, White next, clocks paused. Exact SGF and semantic
clock/pending/review JSON match the post-nudge pause baseline. Remaining finding:
uncertain observations at an established stone deliberately do not create an
action marker, and the halfway stone has no accepted occupancy/outline at either
intersection. Investigating warning-only bounded-outline evidence for a disputed
disk, without assigning occupancy, changing history, or treating glare/unknown
pixels alone as a displacement. Game remains paused with original three restored.

Preparing 0.165/build166: preserve warning-only geometry for two adjacent uncertain
intersections with strong same-color candidate pixels and a bounded outline
(quality ≥0.94, normal stone radius). The real image yields one Black disk centered
at canonical (8.92,9.52), quality 0.9874. Both occupancy readings stay uncertain.
A centering marker requires exactly one nearby recorded stone of the same color,
no hand/manual override/lighting failure, and the existing fresh-frame debounce.
It cannot create a stone, a move, an increment or a clock hold. The issue opens
“Check stone centering,” gives the saved coordinate and preserves the correction
route if the record is wrong. Real fixture `Tests/Fixtures/HalfwayNudge` retains
the off-center photo plus an earlier centered photo; repeated test feeds are
explicitly synthetic timestamps, not a claimed video sequence. Tests and signed
production build are running; no new installation or physical pass yet.

New nudge suite **61 checks passed**: real off-center/centered photos; all 16 real
glare frames produce no displaced-disk evidence; no advice from uncertainty alone,
hands, manual labels, lighting failure, empty history, wrong color or ambiguous
recorded neighbors. Synthetic timestamp feeds verify fresh-frame debounce,
running and paused guidance/clearing, unchanged SGF/turn/increment/clock state,
and the native K10 centering review. Native panel screenshot inspected at
`.build/TestArtifacts/nudged-stone-guidance/centering.png`. Seven Python build
checks pass. Related regressions and optimized signed build remain in progress.

0.165 verification complete: **9/9 targeted suites passed**, comprising the new
61-check nudge suite and eight related suites: live-position issues (65), known-
empty/residual glare (53+171), recovery guidance (58), capture-clock (417 plus
113 uncertainty, 103 conflict and 75 clock checks), established tracking (82),
lighting (86), crowded placement (63, including 24 real consecutive frames), and
displaced neighbors (27 lighting/alignment cases). Seven Python build checks pass.
No full-suite rerun is claimed. Native centering panel and stable-layout regression
passed; physical centering-prompt retest remains pending.

Installed and launched **0.165 / build166**, optimized Developer ID signed build;
strict/deep signature and independent 135-source hash verified:
`a77f3f6e3a81bf6972b87a6c4290cdcb5e54687f6e9ef087b4f991796144e764`.
Backup: `/Users/dave/Library/Application Support/Physical Go/Backups/Install-0.165-20261112-161910`.
Exact SGF and semantic clock/pending/review JSON match before quit, after quit and
after relaunch. Original 89-move SGF remains unchanged. Native UI confirms camera
Live, Live position selected, three saved, zero pending/outside/attention points,
White next, manually paused (Black 227.714432125, White 281.055034459 seconds).
Next guided step: stay paused, slide Black halfway K10 toward L10, clear hands
five seconds; expect orange K10 marker and centering explanation. Click the marker
and leave the stone off-center/panel open for inspection before restoration.
Acceptance count remains ten passed / seventeen remaining until this retest.

0.165 physical centering prompt **PASS**: user screenshot shows “Check stone
centering,” the conditional explanation for a bumped stone, original camera
report uncertain at K10, and the saved Black K10 highlighted in orange. Native
UI and storage checks confirm three saved, White next, manually paused, with
exact SGF and semantic clock/pending/review JSON unchanged from the post-nudge
baseline. Screenshot retained at `.build/GuidedTests/nudge-0165-physical-centering.png`.
Next restore Black K10 with this panel open, without acknowledging or previewing
a correction; expect RESOLVED, no orange ring, stable board position and size,
and unchanged paused game. Final restoration still pending before counting the
nudge/displacement scenario complete.

0.165 final nudge restoration **PASS**: user reports RESOLVED, orange ring gone,
board unchanged in position/size, original Black centered K10, three saved,
White next and both clocks paused. Native UI confirms RESOLVED and zero attention
points; exact SGF and full semantic clock/pending/review JSON match the post-nudge
pause baseline. Combined nudge/displacement scenario complete, including earlier
running-clock/no-extra-move check and the new physical centering-guidance retest.
Original acceptance matrix now **11/27 passed, 16 remaining (about 41%)**;
two review scenarios remain, plus seven capture, two rapid-timing, five outage.

Next: saved-placement correction preview while a new move arrives, then cancel.
Close resolved panel, select Saved moves (move3), Resume clock and recording,
open Correct move… without changing/confirming the preview, then place White at
D16 (canonical72; expected fourth SGF move W[pd]) with the preview still open.
Clear hands five seconds, Cancel the preview, then Pause. Expect four saved
moves, Black next, White-to-Black clock transition with one White increment;
preview/cancel itself must neither pause tracking nor alter the first three moves.
The preview should report that play advanced. This tests the saved-placement
preview route; chronology/stale-acceptance testing remains separate.

Saved-placement preview / move-arrival / cancel **PASS**: user reports four saved
moves while Saved moves initially showed three stones; Live position showed all
four. Switching views subsequently showed D16 in both. Saved browsing retains
its selected historical move; selecting Saved moves again explicitly selects the
latest move. Thus the reported transition is consistent with move3 remaining
selected during recording and move4 being selected on returning. User did not
observe “Play advanced”; that text belongs inside the open correction preview,
not the main board. Its physical visibility is unverified, not claimed passed.

Native UI confirms four saved, Black next, manual pause. SGF is precisely the
original B[jj];W[pp];B[dd] plus W[pd]. Earlier timed moves are unchanged; move4
has one applied camera hand-bracket boundary and exactly one 30-second White
increment (238.586720791→268.586720791). Black ran 10.060562916 seconds after
the move before manual pause; balance217.653869209. No timing correction or
provisional move remains. Matrix: **12/27 passed, 15 remaining (about 44%)**.

Next scenario is chronology review with stale acceptance. Select Live position,
Resume, open Order missed moves…, and select Black passed inside that draft only.
Then physically play Black Q4 (canonical288; expected fifth move B[dp]) and clear
hands five seconds, leaving the draft panel open without pressing Accept yet.
Verify the live fifth move independently before testing stale acceptance. The
draft pass must never become a recorded pass. This stage leaves clocks running;
inspect promptly, then test rejection and Cancel/Pause in the next guided stage.

Chronology preflight interrupted **before draft or fifth move**: user selected
Live position and Resume, but saw checking/clocks stopped. Native UI showed the
camera stopped with “Camera could not recover a usable live image. Check the
phone or cable, then choose Restart camera.” Last camera observations were from
the earlier pause; Resume correctly withheld clocks without fresh verification.
No particular phone/cable failure cause is established. Agent pressed Pause board
checking to cancel automatic-resume intent, then Restart camera. Camera returned
Live; fresh observations see exactly four stones (60B,72W,180B,300W). Exact SGF
and semantic clock/pending/review JSON match the pre-chronology snapshot, balances
Black217.653869209 / White268.586720791, manually paused. This is setup recovery,
not an extra acceptance pass. Next leave stones untouched, Resume, check Black
countdown, then Pause again before continuing the chronology scenario. Usability
observation: generic checking status did not convey the stopped-camera reason
clearly to the user; the concrete error was in the Camera section.

Resume preflight after camera restart **PASS**: user confirms Black countdown
started, then manually paused again with all four stones untouched and four saved.
Native UI and storage check confirm paused/Black next; SGF, earlier timed moves
and press evidence unchanged. Only Black elapsed time changed during this explicit
running interval. Updated baseline: `.build/GuidedTests/before-chronology-after-camera-0165`.
Return to the pending chronology test: Resume from Live position, open Order
missed moves, stage Black passed in the draft, then physically play Black Q4.
Leave the panel open without accepting so the actual fifth move can be verified
before testing stale-proposal rejection. No new matrix pass is counted for setup.

Chronology draft/new-move stage: user staged Black passed, physically played Black
Q4 and left draft open without accepting. Storage independently confirms fifth
move B[dp], prior four timed moves unchanged, one Black increment
(196.158551416→226.158551416), White running and no timing correction. User reports
White countdown updates in several-second jumps. Journal observations continue
around 0.2-second intervals and persisted elapsed-time accounting is consistent
so far; display responsiveness remains an open finding. Native AX inspection was
slow with this panel open. Next promptly click Accept 1 moves and pause on the
old draft, expect “The saved game changed. Cancel and start the sequence again.”
Then note the message, Cancel, and Pause. Verify five moves/no recorded pass before
counting stale rejection passed; inspect display timing separately after pausing.

Chronology/stale acceptance **PASS**: user received the exact saved-game-changed
rejection, then Cancel/Pause; five saved moves, White next, clocks stopped. Storage
confirms no recorded pass, old four timed moves unchanged, fifth B[dp] and exactly
one Black increment. Paused balances Black226.158551416 / White67.544576042;
White elapsed201.042144749 seconds since the fifth-move boundary while the draft
and rejection test were in progress. Updated preservation snapshot:
`.build/GuidedTests/after-chronology-paused-0165`. Matrix **13/27 passed, 14 remain**
(seven capture, two rapid timing, five outage variants). Do not resume further
tests yet: investigate reported several-second clock-display jumps with the draft
open, using paused profiling and an isolated timer test if needed. All five stones
remain in place. The display finding is separate from the passed stale guard.

Clock-jump investigation: 461 retained running observations include 116 changes
in displayed engine balance; some changes are separated by 2–6.61 seconds, with
corresponding elapsed deductions (largest sampled debit6.779 seconds). This is
not evidence of free or double-charged time. Paused main-thread samples with
panel closed/open show substantial SwiftUI layout work; no causal explanation
has been established. Samples: `/tmp/physical-go-paused-main-sample.txt` and
`/tmp/physical-go-paused-draft-sample.txt`. Reopened an empty Order missed moves
panel while paused for profiling; no draft selections/acceptance. SGF and all
sidecars remain identical to post-chronology baseline. Asked whether jumps were
seen with Physical Go frontmost or another app active; response pending.

Next short diagnostic: Cancel that empty panel, keep Physical Go frontmost,
Resume for ten seconds with all five stones untouched, observe White countdown,
then Pause before returning to chat. White has67.544576 seconds at this baseline;
avoid another extended running inspection. Compare ordinary foreground countdown
before attributing the jumps to modal review, background scheduling, or rendering.
No source change or new build has been made for this finding.

Foreground countdown diagnostic: user confirms individual seconds appear unevenly
even with Physical Go frontmost (5…4…3,2…1). Five moves unchanged, White next,
manually paused; balances Black226.158551416 / White51.871717375. Snapshot:
`.build/GuidedTests/after-foreground-paused-0165`. No further real-game clock time
is used for software diagnosis. Original acceptance count remains13/27.

Isolated native UI probe (five synthetic stones, private storage/defaults, camera
discovery disabled) exercises main board and move-order sheet with5Hz fresh
observations. Existing clock callback p95 gaps0.154/0.158 seconds versus a direct
main-queue DispatchSource timer0.105/0.105 seconds; large multi-second jumps did
not reproduce. This supports trying direct dispatch delivery, not a complete
root-cause claim. Candidate0.166 replaces the common-run-loop Timer plus Task hop
with a100ms main-queue timer (5ms leeway), retaining monotonic elapsed accounting
and all hold/expiry guards. Adds actual-scheduler regression for cancellation,
resume, configure, delayed-callback accounting, expiry and camera-gap protection.
Verification/install/physical retest pending.

0.166 targeted verification **PASS**: six suites,885 checks (actual scheduler14,
live issues65, processing gaps24, recovery guidance58, capture uncertainty113,
capture conflicts103, local arithmetic75, capture policies417, recovery lifecycle16),
plus7 Python registry/build checks. Native isolated UI probe after change:120 clock
publications in each12-second main-board/sheet interval; p95 gaps0.152/0.156s,
max0.156/0.159s. Actual clock p95 is similar to the original probe, despite the
dummy direct-dispatch timer being steadier; this does not establish that the
physical display defect is fixed. No multi-second stall reproduced in either
isolated run. Logs `/tmp/physical-go-0166-tests.log` and
`/tmp/physical-go-0166-cadence.log`. Optimized signed build underway; physical
countdown comparison remains required.

0.166/build167 optimized Developer-ID-signed build **installed and launched**.
Source hash `64189058182306bf6ae000d8052c9c2e251f5f14585d1da38d8f6f6ee806b5d7`,
135 resolved sources; strict/deep signature and installed executable/assets verified.
Backup: `/Users/dave/Library/Application Support/Physical Go/Backups/Install-0.166-20261112-194829`.
Exact active SGF and complete semantic clock/pending/review JSON match before quit,
after quit and after relaunch. Original89-move SGF remains unchanged. Native UI:
camera Live, Live position, five saved, zero pending/outside/attention, White next,
manually paused. Balances remain Black226.158551416 / White51.871717375 seconds.
Known existing vendored Kokoro Lexicon optional-coercion compiler warning remains.

Next single physical check: keep Physical Go frontmost and all five stones
untouched; with camera Live, Resume for about eight seconds, then Pause before
returning to chat. Report evenly spaced seconds versus bunching/jumps. Kokoro
guide prepared. This is a diagnostic retest, not another original-matrix pass;
13/27 passed,14 remaining. Do not claim the display defect resolved until observed.

0.166 foreground countdown physical retest **PASS**: user reports evenly spaced
seconds. Five saved moves and all timed move records unchanged; manual pause,
White next, no pending/timing review. Complete clock JSON differs only in White
remaining time:51.871717375→42.937384084 (8.934333292 seconds elapsed). Black
remains226.158551416. SGF/pending/review state unchanged. Snapshot:
`.build/GuidedTests/after-even-countdown-0166`. This verifies the short foreground
case, not extended background or open-review-panel cadence. Original matrix still
13/27 passed,14 remaining; this diagnostic retest is not a new scenario.

Next begin capture-policy matrix using existing threshold2. First test a single
prisoner (below threshold, no automatic removal hold). Keep the existing five
stones. Planned legal sequence from White next: W A1, B B1, W A3, B A2 captures
only White A1. Guide each step separately and pause between setup placements;
the final capturing placement/removal will be observed while running. Immediate
next step only: Resume, place White A1, clear hand until6 saved/Black running,
then Pause. Do not place the remaining setup moves yet.

Single-prisoner capture setup, step1 **verified**: user placed White A1, saw6
saved/Black running and paused. Storage confirms sixth W[aa], earlier five timed
moves unchanged, exactly one30-second White increment, Black next, no timing
correction. Paused balances Black221.767975333 / White68.380774833 seconds.
Snapshot `.build/GuidedTests/after-capture-setup-a1-0166`. Next step only: Resume,
place Black B1 beside White A1, clear hands until7 saved/White running, then Pause.
Leave White A1 in place; no capture yet. Matrix remains13/27, setup in progress.

Single-prisoner capture setup, step2 **verified**: user reports done; storage
confirms seventh B[ab] (Black B1), prior six timed moves unchanged, one30-second
Black increment, White next, paused, no timing correction. Balances
Black246.451423500 / White66.361338792 seconds. Snapshot
`.build/GuidedTests/after-capture-setup-b1-0166`. Next final setup move only:
Resume, place White A3 leaving A2 empty, clear hand until8 saved/Black running,
then Pause. Do not remove stones or play the capturing Black A2 yet.

Single-prisoner capture setup, step3 **verified**: user confirms8 saved, Black
started, manually paused, White A3 and empty A2. Storage confirms eighth W[ca],
prior seven timed moves unchanged and one30-second White increment; no correction.
Balances Black244.044331584 / White92.869749583 seconds. Snapshot
`.build/GuidedTests/before-single-capture-0166`. Capture threshold remains2.

Next perform the below-threshold capture: Resume, play Black A2 and clear hands,
leaving captured White A1 physically in place for about five seconds. Observe
whether White starts and keeps counting (expected; no automatic removal hold).
Then remove only White A1, clear hands for five seconds and manually Pause before
reporting. Expect9 saved, White next, eight physical stones, exactly one Black
increment and unchanged prior timed moves. Do not wait in chat with clocks running.
Physical result pending; matrix13/27 until capture and follow-up verified.

Single-prisoner threshold2 capture, clock/removal **PASS from collected evidence**.
User saw9 saved but did not watch clock onset; no repeat needed for that question.
Journal excerpt `.build/GuidedTests/single-capture-0166-observations.json` contains
156 observations plus four events across uptime1005790–1005830. `position` is the
camera observation signature (GameRecorder.trace), not the saved-position diagram.
At1005799.041004 the observed-turn clock press switches to White, backdated to
supported placement1005798.221510; camera still sees White A1, Black A2, White A3.
48 observations show White running while A1 remains White:92.050255459 seconds
at1005799.041004 down to80.146841084 at1005810.945621. No automatic hold or
interruption is recorded during this interval. First clear A1-empty observation
at1005812.395423,13.354419 seconds after the first White-running observation,
shows White78.890417959. Move9 accepted at1005813.427383 with White still running.
Manual pause appears at1005823.916574. One Black30-second increment, original
eight timed moves unchanged, ninth B[ba], White next and no timing correction.
Paused balances Black270.486141041 / White67.303668792. State snapshot:
`.build/GuidedTests/after-single-capture-0166` (four state files; journal excerpt
retained separately).

Separate guidance finding: while the prisoner remained, the journal emitted
“recording warning: new unsaved stone” at1005803.851688 and an ambiguity tone
at1005812.395423, clearing on acceptance. This did not hold or restart the clock,
but capture-specific removal guidance needs review; do not claim all UX passed.
Following White move remains to verify continuation before counting this original
matrix scenario complete (still13/27 fully completed). White A4 can serve as that
follow-up and begin a later two-prisoner setup; do not move stones until guided.

Next guided continuation check: nine-move SGF and complete paused clock JSON
still match the post-capture snapshot. Resume, place White A4 adjacent to White
A3, clear hands until10 saved/Black running, then Pause. Keep A1 empty and all
other stones unchanged. Verify one White increment, no repeated increment for
Black's previous capture, and no stale capture hold/review. This completes the
clock/continuation part of the single-prisoner scenario if successful and starts
the physical setup for a two-prisoner capture; guidance finding remains separate.

Single-prisoner threshold2 continuation **PASS**: user reports ready; storage
confirms tenth W[da] (White A4), prior nine timed moves unchanged, exactly one
White30-second increment, no repeated Black increment, Black next, paused, no
pending sequence or timing correction. Black balance was unchanged across this
White move, then counted down until manual pause. Paused balances
Black259.954716459 / White93.685539708. Snapshot
`.build/GuidedTests/after-capture-followup-a4-0166`. Functional below-threshold
clock/removal/continuation scenario complete: **14/27 passed,13 remaining**
(six capture variants, two rapid timing, five outage variants). Separate
delayed-removal warning/ambiguity guidance finding remains open, not declared fixed.

Next two-prisoner capture at threshold2, using connected White A3/A4. Planned
sequence: B B3, W D10, B B4, W Q10, B A5 captures exactly White A3/A4. Guide
setup placements one at a time with pauses. Immediate next step only: Resume,
place Black B3 beside White A3, clear hands until11 saved/White running, Pause.
Keep all stones in place; no capture yet. Qualifying capture will later test
automatic hold, partial removals and fresh completion separately.

Two-prisoner threshold2 setup, Black B3 **verified**: user confirms11 saved,
White started and manual pause, stones unchanged. Storage confirms eleventh
B[cb], previous ten timed moves unchanged, one30-second Black increment,
White next, no pending sequence/timing correction. Paused balances
Black286.193785600 / White91.117743483. Snapshot
`.build/GuidedTests/after-two-capture-setup-b3-0166`. Next step only: Resume,
place White D10 away from the corner group, clear hands until12 saved/Black
running, then Pause. Keep all existing stones in place. Matrix remains14/27.

Two-prisoner threshold2 setup, White D10 **verified**: user confirms12 saved,
Black started and manual pause, other stones untouched. Storage confirms twelfth
W[jd], previous eleven timed moves unchanged, one30-second White increment,
Black next, no pending sequence/timing correction. Paused balances
Black284.447758497 / White118.259819836. Snapshot
`.build/GuidedTests/after-two-capture-setup-d10-0166`. Next step only: Resume,
place Black B4 beside White A4, clear hands until13 saved/White running, then
Pause. Leave White A3/A4 and every other stone in place; no capture yet.
Matrix remains14/27.

Two-prisoner threshold2 setup, Black B4 **verified**: user reports done; storage
confirms thirteenth B[db], previous twelve timed moves unchanged, one30-second
Black increment, White next, paused, no pending sequence/timing correction.
Paused balances Black310.826737934 / White114.902653024. Snapshot
`.build/GuidedTests/after-two-capture-setup-b4-0166`. Next final setup move only:
Resume, place White Q10 away from the corner group, clear hands until14 saved/
Black running, then Pause. Leave White A3/A4 and all other stones in place;
do not play capturing Black A5 yet. Matrix remains14/27.

Two-prisoner setup interrupted **before White Q10**: user returned after an
absence, reported clocks stopped / board unreadable, then identified nearly all
uncertainties in the previously troublesome glare area. Still13 saved; all12
remaining physical stones recognized. Live readings show roughly19–24 uncertain
empty intersections clustered around G14–P19. No move, clock balance or review
state changed relative to the paused B4 baseline. User tried Resume during the
block; clocks correctly remained stopped. Subsequently manually paused.

Saved sample `Captures/Samples/Unreadable thirteen moves 0166 20261112` contains
current frame, calibration/readings and empty reference. Saving froze the camera;
agent explicitly resumed camera using the camera control (not game Resume).
Native UI confirms Live and game paused. Exact SGF and semantic clock/pending/
review JSON match B4 baseline: Black310.826737934 / White114.902653024. No Q10 stone
is present in the sample. Automatic23-frame clip:
`/Users/dave/Library/Application Support/Physical Go/Move Evidence/Diagnostic 2026-11-12 21-12-08 C7EB7F8A`.

Photo visibly shows broad reflection over the affected wood. Current grid is
accepted using12 known-stone matches and exposed lines; no hand/global exposure
block. All sampled stones confidence>=0.96875. Cold-start replay of this single
image (12 repetitions with explicitly synthetic0.21s stamps, diagnostic only)
leaves25 of31 raw uncertain points: independent current-image empty checks fail
mostly because one or both printed grid axes lack sufficient contrast. Thus a
fresh instance of the existing local-baseline learner does not resolve this
frame. Probe `/tmp/GlareReturnProbe.swift`; no thresholds or source code changed.
Next physical recovery step: keep clocks paused, stones and camera fixed, redirect
the light causing the reflection, clear hands five seconds and report whether
circles settle. Recheck before continuing White Q10. Matrix unchanged14/27.

Clarification after user challenged the lighting workaround: **a room-lighting
change is not established, and changing the lamp is not a demonstrated necessity**.
The previous recommendation was a practical workaround, not a proven cause/fix.
Journal shows zero unreadable points through20:49:53.614 PST, then a1324.437-second
(22m04s) gap in observations; first returning observation21:11:58.051 has19.
Camera restart events occur at21:11:55. The long observation gap/restart discards
temporary KnownEmptyLighting state (gap>1.5s clears entries; revision resets it).
This establishes a recovery transition; it does not prove why camera input ceased.

Same current detector, threshold0.13, same camera ID/resolution/mode and byte-identical
empty-reference PNG (SHA256 c9cb45072f150d090327593b7d969774033df8992cc530e4d8c00552d6f83192):
earlier restored0.164 sample yields0 raw uncertain points; current sample31.
Calibration swap diagnostic: old image with new calibration yields2 raw/1 after
cold local learning; new image with old calibration yields23 raw/19 after learning.
Thus calibration contributes, but the changed image still fails with the older
calibration; this is not simply a disabled fix or lost learned baseline. These
are offline single-frame comparisons with synthetic repeat timestamps, not live
acceptance tests. Exposure, focus, subtle alignment, and physical illumination
have not been isolated. Probe `/tmp/GlareCalibrationProbe.swift`.

Superseding next step: keep lighting, stones and camera unchanged and game paused
to retain this reproducible failure for recognition/recovery diagnosis. Do not
require the user to change the lamp or place Q10 yet. No source changes or new
build;13 saved and test count14/27 remain.

User explicitly deferred physical acceptance testing to prioritize investigating
and resolving glare recovery. Preserve13 moves, White next and manual pause;
no user lighting/camera/stone adjustments requested. Investigation now probes
line sampling and local-baseline learning with the retained23-frame restart clip.
Initial experiment:3×3 square averaging substantially attenuates thin rails in
the reflective area; averaging along the rail recovers contrast at unchanged
0.045 line threshold. Candidate fallback is limited to independent appearance
evidence used by the temporally verified known-empty learner. Original detector
and game/clock acceptance thresholds remain unchanged. Candidate is provisional:
full sequence and new-stone/obstruction checks are required before installation.

Investigation isolated a more direct cause: the retained grid passed coarse known-
stone/exposed-segment checks while remaining several pixels displaced from the
actual thin rails. Calling the existing outer-rail refinement on the same saved
image changes31 raw uncertainties to0, without altering illumination, reference
or occupancy thresholds. The provisional line-sampling changes were discarded.
The known-stone tracking fallback now attempts that tightly bounded four-rail
refinement, then requires independent stone matches and line support before
accepting it. A covered border still retains the original stationary fallback.

New regression fixture preserves12 distinct unedited frames from the23-frame
incident, with original timestamps/reference/anchor and image hashes. Initial
replay reduces32–40 raw uncertainties to1 on the first frame and0 on every
subsequent frame, retaining all12 stones and inventing none. Blank-view rejection
and repeated-frame calibration stability are checked. Broader alignment, covered-
border and recording/clock regressions are running before installation0.167.
No assertion is made about why the camera stopped or what physically displaced
the image; saved labels validate neither blank pixels nor an imagined stone.

Validation before installation: new optimized glare-grid suite64 checks; nine
related suites all passed (known-empty53 + residual-glare171; live issues65;
occupied resume18; capture uncertainty113 + conflict guidance103 + local clocks75
+ capture timing417; recovery lifecycle16; established tracking82; covered
border40; camera bump161; grid detection71). Total1,449 checks, plus7 Python
build-registry tests. Regression logs: `/tmp/physical-go-0167-glare-test.log` and
`/tmp/physical-go-0167-regressions.log`. Unchanged detector tests include real
White placement/removal and explicitly synthetic new-stone challenges against
learned empty points. Covered-border test retains exactly the prior calibration;
wrong colors, shifted intersections, two covered borders and blank images remain
rejected. Camera/clock lifecycle tests preserve manual pause and game history.

Installed and launched signed **0.167 / build168**. Strict deep signature
verification passed; installed executable/Info.plist/voice assets match the build.
Source hash185ffee3a210ef5e7449788ba25b36f7a6936d3099bd4d81f1096de26cb5bbbb
(135 source files). Backup:
`/Users/dave/Library/Application Support/Physical Go/Backups/Install-0.167-20261112-215043`.
Normal quit and postlaunch comparisons preserve exact SGF and semantic clock,
pending and review JSON. Original89-move record also unchanged. Current13 moves,
White next, manual pause, Black310.826737934 / White114.902653024.

**Live confirmation remains pending:** the Mac session is locked
(`CGSSessionScreenIsLocked=true`); the launched app restored the game but has no
fresh postlaunch camera observations. Do not count the restored-game journal
entry's zero uncertainty as recognition evidence. No attempt to unlock the Mac
or advance play. On return, check Live with the same stones/lighting and clocks
paused. Physical acceptance tests remain deferred at14/27; next play, once the
user chooses to resume testing, is White Q10 in the two-prisoner threshold2 setup.

Follow-up: user correctly noted that interrupted input need not imply changed
lighting. Previously both a>1.5s observation gap and every analysis revision
erased the local lighting learner. Implementing dormant retention within the
running app: preserve fully trained entries through camera stop/restart, freeze,
invalid frames and gaps; discard incomplete training. Require3 distinct fresh
matching observations over>=0.4s before resolving uncertainty again. Keep the
original patch fixed and preserve its prior observed age: downtime neither
matures training nor renews the30s independent-evidence expiry.

Separate lighting identity from transient analysis revision. Camera/game/view
identity, detection/reference changes, meaningful grid shifts and contradictory
known stones still invalidate old evidence. Current pixels must match level,
color and center tolerances; new stones remain visible. This is session memory,
not persisted across quitting the app. Tests in progress for2s/22min/8h gaps,
partial learning, duplicate timestamps, freeze/alignment loss, changed pixels and
added/removed stones. Physical test sequence remains deferred.

Baseline policy checks90 and residual-glare checks171 passed, including retained
evidence after2s/22min/8h synthetic gaps,3-frame revalidation, duplicate timestamp
rejection, incomplete training discarded, no expiry renewal, actual fourth White
and removed Black, and a weak newly placed White that must remain uncertain.
Pipeline integration15 checks passed for no alignment/no result, freeze,
independent analysis revisions, restored baseline and camera/reference/game
identity isolation. Gap durations in these policy tests use repeated real
photographs with synthetic timestamps, not newly captured long-duration footage.

**0.168 / build169 installed and launched**, with strict deep signature and
installed-binary/resource verification. Eight targeted suites passed: baseline90
+ residual171, pipeline15, glare-grid64, processing-gap24, recovery lifecycle16,
recovery guidance58, capture uncertainty113 + conflicts103 + local clocks75 +
capture timing417, plus native reference-feedback/layout checks. Seven Python
build-registry tests passed. Logs: `/tmp/physical-go-0168-lighting.log`,
`/tmp/physical-go-0168-regressions.log`, `/tmp/physical-go-0168-lifecycle.log`.

Source hashcc80d04cc3ca2ec25e3185f63d35ad9890b6d0f18b65dbbaec5b98d04a265637
(135 source files). Backup:
`/Users/dave/Library/Application Support/Physical Go/Backups/Install-0.168-20261112-220118`.
Postlaunch exact SGF and semantic clock/pending/review JSON equal preinstall
state; original89-move recording unchanged. Still13 saved, White next, manually
paused, Black310.826737934 / White114.902653024. Mac remains locked, so fresh
live confirmation is pending. No physical test advancement; count14/27 unchanged.

Live confirmation after unlock,0.168: user reports unchanged stones/lighting and
paused clocks. Native UI says Live · Dave11 Camera,13 saved,0 pending,0 outside
saved history. After initial return settled,367 consecutive fresh observations
over89.198s match the exact12 remaining stones, with0 uncertain intersections,
0 extra detections and no lighting block. Both clocks stayed stopped. ExactSGF
and semantic clock/pending/reviews still equal paused B4 baseline. Evidence:
`.build/GuidedTests/glare-cleared-live-0168`. This validates live glare recovery;
it does not separately prove warm-baseline retention, since the app was restarted
for installation. The physical reflection itself need not have disappeared.

User requests resuming capture testing. Guide final setup move only: Resume,
White Q10, clear hands, wait14 saved and Black's clock running, Pause. Leave all
stones in place. Then separately guide Black A5 and the expected automatic hold
for two captured Whites A3/A4. No new scenario counted yet:14/27.

Two-prisoner threshold2 setup, White Q10 **verified** in0.168: user reports
everything worked. Storage confirms move14 W[jp], previous13 timed moves
unchanged, one30-second White increment and Black next. Both clocks manually
paused: Black303.972568413 / White140.844613878. Snapshot:
`.build/GuidedTests/after-two-capture-setup-q10-0168`. Threshold remains2.
Next capture step only: Resume, Black A5, leave captured White A3/A4 physically
on the board and clear hands. Expect both clocks to stop automatically for
removal; report the hold/message before removing either prisoner. If either
clock still runs after5s, manually Pause and report. Matrix remains14/27.

Black A5 / two-prisoner threshold2 **automatic hold verified**: user confirms
both clocks stopped before either White A3/A4 was removed. Storage holds14 saved
moves with capturePosition retained, no running anchor; Black299.965191162 /
White140.844613878 remain unchanged during inspection. Removal/completion are
still untested; scenario count remains14/27. Snapshot:
`.build/GuidedTests/two-capture-held-before-removal-0168`.

Two UX findings: first removal instruction used the system voice, later repeats
Kokoro; button below stopped clocks still said Pause. Journal corroborates first
request1794550645.26335 → system start1794550646.995665, then next request
1794550675.517676 → Kokoro1794550675.528236. Root cause is the1.5s synthesis
deadline; cold Kokoro completed too late but cached the phrase for repeats.
Preparing0.169: recovery guidance waits for selected Kokoro synthesis (fallback
only on failure/unavailability); clock/countdown announcements retain deadlines.
Cancellation still suppresses obsolete delayed audio. Capture transport will
show Paused for stone removal, with a Pause automatic checking action, while
manual pause retains Resume. Tests/build pending. Preserve the current capture
in the running0.168; install after completing this capture, not mid-hold.

0.169 validation:14 new capture-feedback checks pass using delayed synthesis
through the real audio playback path (silent test WAV): no1.5s system fallback
for recovery, exactly one Kokoro start when ready, obsolete late audio cancelled,
actual synthesis failure falls back, and time-sensitive clock speech retains its
deadline without duplicate late audio. Capture UI lifecycle checks cover active
hold, manual pause/Resume, partial removal and verified completion. Native
render inspected at `.build/TestArtifacts/capture-hold-feedback/paused-for-removal.png`;
Paused for stone removal is legible, with Pause automatic checking beneath it.
Existing recovery guidance58, capture uncertainty113/conflicts103/local-clock75/
capture timing417, and clock-review28 + local-clock75 also pass. Seven Python
build-registry checks pass. Final feedback log `/tmp/physical-go-0169-feedback-test.log`;
related suites `/tmp/physical-go-0169-tests.log`. Initial build was discarded after
a source edit during compilation; final-source regression runtime rebuilt.

While the signed build finishes, next physical step issued (also via Kokoro):
remove White A3 only; leave White A4 and other stones. Both clocks should remain
stopped with1 prisoner left. If a clock starts, Pause. Awaiting user report; no
partial-removal pass claimed. Current running0.168 is unchanged.

**0.169 / build170 verified and ready, not installed.** Optimized build and strict
deep signature verification passed; source hash5160d3c9e61ac429922e9a4870c1c544d79db9f18d2dcf9ed26254b9936d9563
(135 sources) matches final source. Install is intentionally deferred until this
physical capture completes and the user pauses, preserving the current hold in
running0.168. Prepared installer requires15 saved moves, stopped clocks and no
capturePosition. Changes are ready for review; first live guidance/hold-label
acceptance in0.169 remains pending installation and a later capture.

Two-prisoner partial removal **verified, opposite order is valid**: user removed
White A4 rather than A3 and restarted the camera because the live feed was not
up. Fresh post-restart observations show A3 White, A4 empty, A5 Black. Native UI
says Live and1 prisoner remaining. Both clocks remain stopped with exactly the
held balances Black299.965191162 / White140.844613878; still14 saved, no clock
review requirement. Snapshot `.build/GuidedTests/two-capture-a4-removed-0168`.
This also demonstrates the hold survived the reported camera restart; no cause
for the absent feed is established. Matrix remains14/27 until completion.

User questioned translucent Black A5 with orange ring. Existing rendering shows
an observed stone outside saved history translucent while the capture awaits
completion; capture action markers include its point. Fresh reading is definite
Black at A5, not uncertain. Explain pending capture rather than wrong placement;
do not ask user to move A5 or replace removed A4. Next inspect step: click A5's
orange ring, leave Capture progress open and White A3 in place; verify remaining
removal and stopped clocks.0.169 remains built/verified but not installed.

Capture inspection **verified**: user screenshot identifies Black A5, captured
A3/A4, and only A3 still awaiting empty verification. User requested temporary
reminder silence specifically during testing. Agent closed the inspection,
opened Info & settings → Camera recovery and turned off Speak when the camera,
board, or lighting needs adjusting, then closed settings. Defaults confirms0.
Both clock balances and automatic capture hold remain unchanged, with14 saved;
closing inspection did not pause/resume clocks. This is an existing setting,
not a new permanent mute feature. It also silences recovery/resume speech for
now; countdown settings remain untouched. **Restore this toggle to true after
this capture completes and user pauses, before installing0.169.**
Next step: remove remaining White A3, clear hand, wait15 saved and White clock
running, then Pause. Await user completion; no scenario completion claimed yet.

Two-prisoner threshold2 **capture completion verified**: user reports15 saved
and White clock starting after roughly1–2s. Journal measures1.581859s from first
final-empty observation to first White-running observation. Saved15th moveB[ea]
(A5) captures A3/A4; all14 prior timed moves unchanged. Black received exactly
one30-second increment (299.965191162→329.965191162); White was not charged
during removal. User then manually paused: White132.810077879. CapturePosition
cleared, no timing-review requirement. Snapshot:
`.build/GuidedTests/after-two-capture-complete-0169`. Following-move confirmation
still required before increasing the full-scenario count; remains14/27.

Temporary recovery speech mute restored totrue through native Info settings,
then signed0.169/build170 installed and launched. Backup:
`/Users/dave/Library/Application Support/Physical Go/Backups/Install-0.169-20261112-230113`.
Strict deep signature checks and installed asset/source identity passed.
Source hash5160d3c9e61ac429922e9a4870c1c544d79db9f18d2dcf9ed26254b9936d9563
(135 sources). Normal-quit/postlaunch comparisons preserve exactSGF and semantic
clock/pending/reviews; original89-move recording unchanged. Fresh postlaunch
observations match all12 remaining stones,0 uncertainty/extra stones,15saved,
clocks stopped. First live0.169 capture voice/hold-label retest awaits a later
capture; do not claim it from this completed0.168 capture.

Next one-step continuation test: Resume, place White D12 (empty, away from the
corner capture), clear hand, wait16saved andBlackclockrunning,thenPause. All
otherstones unchanged. Check oneWhiteincrement and no duplicateBlack increment.

Two-prisoner threshold2 continuation **PASS**: user reports all fine. White D12
saved as move16 W[ld]; all15 earlier timed moves unchanged, oneWhite30-second
increment, no duplicateBlack increment. Blacknext,manualpause,balances
Black323.535505642 / White159.848265900. Snapshot:
`.build/GuidedTests/after-two-capture-continuation-d12-0169`. Full scenario now
complete: **15/27 passed,12 remaining** (5 capture-policy,2 rapid timing,5 outage/
restart variants). Prior incidental restart during removal remains supporting
evidence rather than an extra independently counted scenario.

Next use existing threshold2/game for manually-paused capture across a camera
interruption, also validating0.169initialKokoro/holdlabel. Upper-left corner
setup, legal sequence: B B18,W A19,B B19,W A18,B A17 captures A18/A19. Guide
one placement at a time with manual pauses; first only B B18,wait17saved/White
running,Pause. At the later capture check new feedback,remaining-point obstruction,
manualpause then camera interruption/restart; verify pause retained. No new moves
or settings changed by agent. Other threshold settings are next-game settings
in the current UI; retain this game for outage checks before changing policies.

Paused-capture outage setup, Black B18 **verified**: user reports expected
behavior; storage confirms17thB[rb],previous16timingsunchanged,oneBlack30s
increment,White next,manualpause,no capturehold/timingreview. Balances
Black346.941236996 / White154.577450004. Snapshot
`.build/GuidedTests/after-paused-capture-setup-b18-0169`. Next only White A19
at upper-left corner: Resume,place,clearhand,wait18saved/Blackrunning,Pause.
Otherstones unchanged;matrix15/27.

Paused-capture outage setup, White A19 **verified**: user reports done/allfine.
18thW[sa],previous17timingsunchanged,oneWhite30s increment,Blacknext,manualpause.
Balances Black341.138407080 / White179.370137295. Snapshot:
`.build/GuidedTests/after-paused-capture-setup-a19-0169`.

**Pacing preference updated:** user explicitly wants all tests retained but
routine setup batched to avoid unnecessary pauses/chat turns. From now on group
several ordinary legal alternating setup placements into one Resume cycle.
Clear hands and wait for each saved count/next-player clock before the next
placement;Pause only at the batch end. Keep behavior-specific checkpoints
(capture onset,partial removal,manualpause,camera interruption,fresh completion)
separate where needed to establish causality. This changes pacing,not coverage.

Current objective: manually paused two-prisoner capture survives camera
interruption/restart without clocks resuming; also check0.169holdlabel and first
Kokoro instruction. Next remaining setup batch: Resume,B B19→19saved/White
running,W A18→20saved/Blackrunning,Pause. Leave A17 empty; the following B A17
is the capture under test. Matrix15/27 unchanged.

### 2026-11-12 — A18 recognition/preview stall during capture setup

Black B19 saved as move19. White A18 did not register; the user reported that
waving a hand refreshed the live camera picture and made the stone appear.
The user paused. Saved history remains19,White next; Black365.874617037s,
White123.836699629s, no active capture. White A18 is unsaved on the physical board.
Do not infer or rewrite its missing completion time.

A continuous diagnostic replay while paused captured removal/replacement of A18:
222 observations delivered and19 frames gated by hand detection. A18 changed
White→empty→White; the user confirmed the translucent live-position marker
disappeared/reappeared. The long original stall was not reproduced. The original
journal has a roughly49s observation gap ending around manual Pause/hand-wave;
without original camera frames it cannot distinguish a latched hand gate from
a source-camera stall. Capture: `Captures/Diagnostics/Diagnostic 2026-11-12 23-41-07 827B3979`,
kept from rotation. Capture stopped at its1GB bound; original10GB setting restored.

Confirmed code defect: hand-gated analysis updated raw pixels but returned before
updating the flattened preview; marginal alignment retry also retained old pixels.
0.170 moves preview publication after revision/freshness checks and before recognition
gates, clears stale overlays for those gated frames, and preserves recording/clock
safety checks. Adds hand start/clear transitions to the normal journal and hand
evidence to continuous diagnostics. This fixes a demonstrated stale-preview path;
it does not yet establish the cause of the original long registration stall.

Validation passed:11 real-photo preview checks and60 diagnostic integration
checks against the optimized runtime; clock catch-up59 plus7 recorded incident
checks; capture suites113/103/75/417; recovery lifecycle16;7Python registry tests.
The initial debug image runs failed their real-time readiness/freshness checks;
optimized runs passed. The new preview suite defaults to optimized compilation.
It verifies current flattened hand pixels, no stale overlays, unchanged paused
history/clocks, explicit Freeze, stale-buffer rejection and clear-board recovery.

Installed signed0.170/build171, source hash
`361aa18470cd502371cc4d10b8e07bc39287b3da57ba08a8ce7eb3401f0f6903`
(135sources). Backup: `~/Library/Application Support/Physical Go/Backups/Install-0.170-20261112-235517`.
Postlaunch SGF is byte-identical; clock/pending/review JSON are semantically identical.
Original89-move recording verified unchanged. Camera Live;19saved,White next,
both clocks paused; WhiteA18 recognized as one stone outside saved history.

Next physical checkpoint: while paused remove only unsaved WhiteA18; wait for
its marker to disappear, Resume, replace WhiteA18 and clear hands. Expect20saved
and Black clock running, then Pause. Leave BlackA17 empty for the capture test.
Physical matrix remains15/27; original long-stall cause remains unconfirmed.

### 2026-11-13 — A18 retry isolates false hand-outline obstruction

0.170 preview fix worked, but WhiteA18 still did not register. The user could
see the physical stone in the fresh live feed while the banner said waiting for
hands. The normal journal now proves hand obstruction began at1794556669.201
and persisted while White clock ran. Clocks manually paused at19saved,White next:
Black365.874617037s,White42.846810545s. A18 remains physical and unsaved.

Continuous capture `Diagnostic 2026-11-12 23-59-29 3690CDF3` shows reliable
hand-pose output with no hands, but the outline tracker reports a visible hand
at edge0/depth2.35. Photos independently show no hand. Second capture
`Diagnostic 2026-11-13 00-01-31 5EA26833` includes user removal,5seconds clear,
and replacement while paused. User reported the banner cleared. Offline replay
of frames205–310 reproduces late clearance: frame254 is visibly clear but the
tracker stays obstructed until270. Investigating the foreground component before
changing recognition; no threshold relaxation or timeout-based clearance yet.
Both captures kept; continuous capture stopped and10GB limit restored.
Physical matrix remains15/27. No physical test marked passed by this replay.

Root cause reproduced offline: the foreground component includes the newly
placed WhiteA18 (center approximately17,0), so loss of hand-pose recognition
leaves that stone classified as the departing hand. With no strong chromatic
hand model, the difference mask also responds to the new white disk. This can
keep the outline latched indefinitely; brief missing components in the replay
occasionally let the two-clear-view rule release it.

0.171 fix implemented, validation/build in progress: compute this frame's raw
board detection before hand-outline tracking. Only white footprints with current
shape quality≥0.95 and occupancy confidence≥0.95 supply candidate masks; the
outline tracker independently requires a bright neutral core at nine locations.
Masks remove only the fitted disk plus0.15grid-space fringe, and only when hand
pose reliably reports clear. History, adaptive lighting, elapsed time and a
missing pose do not authorize clearance. Existing foreground/texture checks and
two-clear-view confirmation still apply. Black-stone masking is not generalized
without a corresponding incident/test.

Regression fixture `Tests/Fixtures/A18HandOutline` preserves39 grid-sampled frames,
original timestamps/poses/current white fits, and three original photographs plus
reference for pipeline integration. The fixed tracker clears by256 rather than270,
while retaining the real hand through252. This low-chroma sequence supplies no
qualified motion estimate; the test explicitly requires that no clock press be
invented. Existing recorded withdrawal/error-band checks remain applicable to
their separate sequences. New safety checks reject bare-wood/covered-core hints
and retain fingers beside a verified white stone, including a narrow rim finger.

The full photographed pipeline initially exposed a remaining rim-lighting patch
with the stone mask applied. Two related corrections are included in final0.171:
component depth is bounded laterally by the actual board rectangle (a patch
beyond a corner cannot count as over the board), and low-contrast grain near
the rim can establish clearance through5×5 spatial averages. That fallback
requires≥100 texture comparisons, variance>0.0001,correlation>0.985 and a bounded
brightness transform. Every original pixel still has the tighter0.04 residual
limit, with0.0004 per-cell mean-square residual limit; averaging cannot simply
hide a fingertip. No elapsed-time fallback clears a hand.

Pre-install checks now passed:73 synthetic outline/safety checks,21+6 existing
recorded-outline checks,21 new A18 sequence checks,7 full photographed pipeline
checks. Pipeline test uses repeated before/hand/after photographs to isolate
wiring and the static rim patch; the39-frame test separately preserves original
timestamps. Low-contrast rim shadow, opaque fingertip within that shadow, narrow
finger beside a verified stone, and a patch wholly beyond the corner are covered.
Final signed build and clock/capture regression rerun underway.

Final0.171 validation passed:73 outline safety checks;21+6 existing recorded
outline checks;21 A18 recorded-sequence checks;7 photographed pipeline checks;
15 lighting-interruption,11 preview,59+7 hand-clock checks;capture suites
113/103/75/417;7 Python build-registry tests. Initial pipeline failure exposed
the rim component and was resolved before installation; the final test results
above refer to the final sources.

Installed signed0.171/build172, source hash
`106c45179120ee84a097f6eff4c7a8c4faf23c2333f54c4165914fffc555fc68`
(135sources). Backup: `~/Library/Application Support/Physical Go/Backups/Install-0.171-20261113-003239`.
Postlaunch SGF is byte-identical; clock/pending/review JSON semantically identical
to the pre-quit snapshot. Original89-move record verified unchanged. Current19
moves,White next,manual pause;Black365.874617037s/White42.846810545s.
Mac is locked, so fresh postlaunch camera verification has NOT passed yet.
Ask user to unlock with stones unchanged; then verify Live/paused state before
retrying A18. Spoken retry instructions are prepared but not played while locked.
Keep physical matrix15/27 until the actual capture cases pass.

### 2026-11-13 — Fresh-camera verification after unlock

Camera startup had exhausted recovery while locked; started Dave11 Camera again
without resuming play. Camera Live,19saved,White next,both clocks stopped at
Black365.874617037s/White42.846810545s. After initial recognition settled,62 fresh
observations in15seconds exactly matched the saved board plus unsaved WhiteA18;
no unknown points in that sample and no waiting-for-hands banner. This verifies
the fresh paused view, not yet the A18 placement/clock transition.

Started bounded5GB continuous diagnostics for the retry:
`Diagnostic 2026-11-13 00-39-38 8B04A502`. Next result: stop capture,keep evidence,
and restore10GB limit. Kokoro retry instructions played: while paused remove
only WhiteA18; wait for marker to disappear; Resume,replace WhiteA18,clear hands;
expect20saved and Black clock running,then Pause. LeaveA17empty. Matrix15/27.

### 2026-11-13 — Live A18 retry passed

User: “all worked well.” SGF now has20moves,WhiteA18 (`W[ra]`) saved. First19
clock moves are unchanged. White received exactly one30second increment:
37.949604253s→67.949604253s. Black clock started,then user manually paused
at358.030700538s;White67.949604253s,Black next,no active capture.
Journal: hand began1794559617.019742,cleared1794559619.968922;move20
accepted1794559620.815379;manual Pause1794559627.311493. Clock press used
the supported clear-frame boundary1022837.374010,not invented hand-motion timing.

The bounded continuous capture reached its5GB limit at1794559493.273619,
before this retry; do not claim the retry's hand sequence was filmed. The normal
observation/hand/clock journal and user report support the result. Capture kept;
continuous recording off and original10GB limit restored. Snapshot:
`.build/GuidedTests/after-a18-retry-0171-20-paused`.

The fix is location-independent, not keyed toA18 or this recording. Its white
stone exclusion intentionally requires strong current white-shape/core evidence;
black-stone exclusions remain unimplemented. Board-corner bounds and the strict
rim-texture test apply generally. It does not guarantee every hand/lighting
condition is solved. Setup complete; next actual test is BlackA17 capturing
WhiteA18/A19 with both prisoners left in place to inspect the automatic hold,
initialKokorovoice and hold label before manual-pause/camera-interruption steps.
Physical matrix remains15/27; this was a fix retest/setup move.

Capture-onset instructions issued after confirming fresh Live observations:
20saved,Black next,manual pause,threshold2;A17empty,A18/A19White,B18/B19Black.
Resume and placeBlackA17;leave both captured Whites in place and clear hands.
Check both clocks stop automatically,button says “Paused for stone removal,”
and the first reminder usesKokoro. Leave prisoners for the next checkpoint;
manually Pause only if a clock continues after5seconds. Kokoro walkthrough
prepared. Result pending;matrix15/27.

### 2026-11-13 — A17 capture onset and0.169 feedback verified

User reports correct behavior, delayedKokoro reminder,orange rings atA17/A18/A19,
and translucentA17. Agent confirms actual automatic capture hold,20saved,no
clock correction;Black352.627141162s/White67.949604253s,neither running.
Button accessibility: “Paused for stone removal. Pause automatic checking”.
The markings match the pending capture: both White prisoners remain and the
new capturing Black is not finalized into saved history until completion.

Hold began1794560359.382002. First speech requested1794560363.960660,started
1794560374.634175 withengineKokoro:15.252s afterhold,10.674s afterrequest.
No system-voice fallback in this capture. User considers delay probably acceptable;
log latency for future improvement without blocking this test. Both clocks stayed
held throughout. Snapshot: `.build/GuidedTests/a17-capture-automatic-hold-0171`.
Automatic diagnostic clip saving reports archive capacity occupied by kept
evidence; this result uses user report/nativeUI/normaljournal,not a new camera clip.

Next checkpoint groups manual pause and camera interruption: with all stones
unchanged,click hold transport to Pause automatic checking (button becomesResume),
Stopcamera,wait5seconds,Startcamera. Expect20saved,pending capture,unchanged
clock balances and neither clock running. Do not remove either White yet.
Full scenario remains pending;matrix15/27.

### 2026-11-13 — Manual pause survives capture camera interruption

User confirms transport still saysResume and orange box saysRemoving captured
stones afterStop/Start camera. Agent verifies cameraLive,freshA17/A18/A19=BWW,
recorder statepaused,20saved,capturePosition retained,engineanchor absent and
exactly unchanged Black352.627141162s/White67.949604253s. The capture box is
expected pending-work guidance; Resume reflects the independent manual pause.
Manual-pause event1794560636.450916. Snapshot:
`.build/GuidedTests/a17-capture-manual-pause-camera-restart-0171`.

Next checkpoint: staypaused,remove onlyWhiteA18,leaveWhiteA19 and all other
stones,clearhand,openCaptureprogress. Expect onlyA19 still to verifyempty,
20saved and both clocks stopped. Leavepanelopen. Remaining-point obstruction
and final completion/following move are still pending;matrix15/27.

### 2026-11-13 — Partial removal reveals another hand-gate stall

User removedWhiteA18 but live-position retained white/orangeA18/A19 and an
empty-looking orangeA17. Agent found no new board observations for90seconds,
latestA17/A18/A19=B?W,with hand-obstruction event1794560825.463273. Capture
and manual pause retained;20saved and exact held clock balances unchanged.
The scene later recovered: another hand-begin1794561045.668310,clear1794561049.659954.
The cause of recovery is not established. Continuous images started after that
clearance,so they do not document the original stalled outline.

`Diagnostic 2026-11-13 01-09-52 5AAE7B22` confirms current reliable no-hand pose,
clear outline,BlackA17/emptyA18/WhiteA19,all three raw confidences1.0. Kept;
its1GB limit stopped recording. The previous5GB waiting-only capture
`Diagnostic 2026-11-13 00-39-38 8B04A502` was moved intact out of the managed
archive to `.build/GuidedTests/PreservedDiagnostics/` to free capacity without
deleting evidence. Its KEEP and contents are preserved.

Started bounded5GB replay capture `Diagnostic 2026-11-13 01-11-40 2FFF3C9F`.
Asked user,while paused,to replaceWhiteA18,clearhand5seconds,removeA18again,
and leaveA19/allothers unchanged. If it sticks,leave the scene untouched for
evidence. Do not count the delayed partial removal as a clean pass or infer
that0.171 covered this case. No new code changes yet;matrix15/27.

### 2026-11-13 — A18 removal recognized; paused instruction was stale

User reports solid White A18 and translucent Black A17 after the replay.
The retained live board includes the saved White until capture acceptance;
Black A17 is correctly provisional. Inspection confirms “Still to verify empty:
A19,” while its separate instruction incorrectly says “2 captured stones.”
Do not classify that retained board appearance alone as failed recognition.

The 01-11-40 replay records empty A18 with confidence 1.0 from frame 191 onward,
with clear hand outline and observations delivered to the paused recorder.
Removal clear frame 190 at 1794561138.297440 is followed by delivery at frame 191,
1794561138.549908. Separately, replacement was falsely blocked at frames 127–185
(~12 seconds); frame 160 visibly has no hand. This is additional outline evidence,
not proof the removal itself stalled. The original earlier removal stall remains
unexplained. Keep this hand-detection issue open; this release changes no thresholds.

Replay retained with KEEP. Continuous capture stopped at archive capacity;
original 10 GB per-capture limit restored. No scene reset or move acceptance.
Snapshot: `.build/GuidedTests/paused-capture-guidance-before-0172`.

0.172 updates paused capture instructions and their spoken remaining-point list
from fresh, clear observations. Manual pause still prevents move acceptance,
completion evidence accumulation and clock restart. Completed removal explicitly
requests Resume for verification; speech no longer promises automatic restart
while manually paused. Regression first failed on the old source with “Paused
capture panel and instructions disagree about removed prisoners.” New checks
cover removal/replacement, uncertain prisoners, hand-covered/stale frames, exact
clock balances and fresh completion proof after Resume. Validation passed: capture
clock suite (427 capture/timing, 113 photo uncertainty, 103 conflict guidance,
75 local-clock checks), 65 live-issue checks and 14 capture feedback checks.
An isolated copy of the actual 20-move recording also restored the pending A17
capture, updated A19-only guidance, and preserved SGF and both paused balances.
Build-registry checks also passed (7). Signed build and installation passed.

The stopped replay was moved intact, including KEEP, to
`.build/GuidedTests/PreservedDiagnostics/Diagnostic 2026-11-13 01-11-40 2FFF3C9F`
to free the automatic diagnostic archive for subsequent tests. No evidence was
deleted. A18 replacement shape qualities at frames 129/160/180 were about
0.936–0.939, below the existing 0.95 hand-mask eligibility threshold. This helps
explain why the white exclusion was unavailable, but is not sufficient reason
to lower the threshold without further hand-safety replay tests.

### 2026-11-13 — 0.172 installed with pending capture preserved

Signed version 0.172/build173 installed and launched. Source hash:
`d8e5b823f7c473266773905d5579c83a7daae5e42de8926d2a3b5a605f165366` (135 sources).
Backup: `~/Library/Application Support/Physical Go/Backups/Install-0.172-20261113-012919`.
The first normal-quit attempt was canceled while the inspection sheet was open;
closing the sheet allowed normal shutdown. No force quit or game mutation.
Postlaunch: exact SGF and semantic clock/pending/review sidecars preserved;
previous 89-move recording also unchanged. Camera Live, current B.W at A17/A18/A19,
20 saved, no clock correction, Black352.627141162s/White67.949604253s stopped.
Native capture panel now says both “Still to verify empty: A19” and “1 captured
stone.” Manual Resume requirement remains visible. Panel left open.

Next combined checkpoint (Kokoro walkthrough prepared): close panel; Resume
with White A19 still present, expecting both clocks held. Remove White A19 but
keep the intersection hand-covered for five seconds: remain at 20 saved and
both stopped. Clear hand: expect 21 saved and White running. If successful,
play White C19: expect 22 saved and Black running, then Pause. If the capture
completes while covered, Pause and report instead. C19 legality and coordinate
orientation were checked against the actual retained game after A17 capture.
Result pending; do not increment the physical matrix (15/27) yet.

### 2026-11-13 — A19 removal stalls, then recovers spontaneously

User removed White A19, covered the point for several seconds, then withdrew;
reported no update and subsequently spontaneous recovery. Journal shows hand
obstruction1794562357.820838 through1794562424.828331 (67.007493s), followed by
capture completion1794562426.070371. The first-clear boundary was
1025642.273310209. No camera reset, recognition change or successful transport
click by the agent caused clearance; an attempted hold-button click found no
matching control after state changed. The agent only inspected settings.

21 saved, White next; Black received exactly one30s increment to382.627141162s.
The hand-gate wait was uncharged. White ran only after the supported clear-frame
boundary and was manually paused at1794562437.406133 with54.895708878s.
Capture hold released, no timing correction, C19 not played. Snapshot:
`.build/GuidedTests/a19-delayed-capture-0172-21-paused`.

Automatic clip `~/Library/Application Support/Physical Go/Move Evidence/Diagnostic
2026-11-13 01-32-20 B46E3B3B` retained with KEEP, but it ends1794562345.328103,
before the hand entry, so cannot diagnose the stalled outline. Need a bounded
continuous replay of A19 replacement/clear baseline/removal while manually
paused. Do not classify delayed completion as a clean test pass; matrix15/27.

Started bounded5GB continuous replay `Diagnostic 2026-11-13 01-36-54 3830D2E0` (KEEP).
Next requested: keep paused, replace only White A19, clear hand5seconds and
leave it in place for baseline verification before removal; do not play C19.

A19 replay baseline verified: user replaced White A19; continuous capture
frames702–707 have reliable no-hand pose, clear visual reference, and
BlackA17/emptyA18/WhiteA19 with confidence1.0, delivered to the paused recorder.
21 saved, exact paused Black382.627141162s/White54.895708878s unchanged.
Next: while paused remove onlyWhiteA19, cover its intersection with the hand
for5seconds, then withdraw completely and leave the scene untouched. Report
whether the detected extra stone clears promptly or remains stuck; no camera
restart/hand wave, noC19. Continuous capture remains active.

### 2026-11-13 — Prompt replay removal; overnight checkpoint

User reports A19 disappeared promptly, but clocks did not restart. This is the
correct manual-pause behavior for the diagnostic replay; it does not reproduce
or fix the earlier67-second stall. Capture frame1001 begins the removal hand
at1794562815.059659; frame1037 verifies visible exit at1794562822.248986 after
the instructed5-second cover. Subsequent readings are BlackA17/emptyA18/emptyA19,
all confidence1.0. 21 saved, no additional move or increment; exact paused
balances Black382.62714116240386s/White54.89570887829177s unchanged.

Continuous capture stopped at its storage limit after recording the replay.
KEEP retained; moved intact to
`.build/GuidedTests/PreservedDiagnostics/Diagnostic 2026-11-13 01-36-54 3830D2E0`.
Restored original10GB continuous limit. No threshold/code changes this turn.

User is going to bed and will change lighting shortly. Camera stopped while
leaving the app/game manually paused; no quit or recording replacement.
Snapshot: `.build/GuidedTests/overnight-2026-11-13-21-paused`.
Leave every physical stone unchanged: A17Black, A18/A19empty, C19empty.
Morning preflight: start camera, keep paused, establish fresh agreement with the
21-move position under the new lighting and check alignment/warnings. Do not
Resume before that check. C19 following move remains pending; original hand
stall is still open and full capture-interruption scenario is not a clean pass.
Physical matrix remains15/27.

### 2026-11-13 — Overnight investigation of the67-second hand gate

User explicitly requested offline overnight investigation after stopping live
tests. Keep installed0.172, camera stopped, recording paused; do not restart
camera or play test speech while the user sleeps/changes lighting.

Confirmed boundary: the recorder receives no observations while the hand gate
is true. The67.007493s interval is not a configured capture or reminder delay;
normal complete-position verification then took about1.24s. The original
interval has no camera footage, so residual foreground/shadow, erroneous pose,
or stale camera imagery cannot be distinguished from those logs. The original
reopening also has no recorded hand-motion estimate. Do not claim a root-cause
fix or relax recognition thresholds based on that missing evidence.

Extracted58 sampled frames980–1055 of the successful A19 removal into
`Tests/Fixtures/A19RemovalHandOutline`, including original poses/timestamps and
manual last-visible-hand/clear PNGs. Current tracker blocks the visible hand at
1034 and verifies exit at1037;19 new recorded-outline assertions pass alongside
73 synthetic,21 general photo,6 clock-loss and21 A18 photo assertions.
A separate offline fault-injection experiment replaces all poses after entry
with no-hand results; it still retains visible fingers and clears by1041
(~0.8s later), not67s. This altered-input experiment is not footage of the failure.

Found a diagnostic coverage gap: hand-gated frames return before move-event
triggers, so the prior unrecorded-stone clip ended before removal and no new
clip covered the stall. Added opt-in unusual-move evidence for three seconds
of outline obstruction with a reliably clear pose, plus a separate recovery
clip. Each episode emits at most one onset and one recovery event, using the
existing bounded PNG buffer/storage policy. Any continuous hand gate also
triggers after15seconds, even with unavailable/present pose data, to retain
possible stale imagery or false poses. These are recording triggers only, not
clearance timeouts. Unknown pose/gate, repeated frames,
actual visible poses, interruptions, disabled diagnostics and stop/reset are
handled without declaring physical clearance. No changes to hand thresholds,
move acceptance, capture completion or clock timing. Final tests/build passed;
see verification below.

The measured67.007493seconds includes the user's intentional hand cover. Without
images of withdrawal, the exact post-withdrawal delay is unknown. The successful
replay has a hand-bracket estimate; the original reopening has no recorded hand
estimate. That difference is consistent with weak tracking or reinitialization,
but does not establish which happened. No67-second release timer exists in the
hand/capture path; do not label a hypothesized visual cause as confirmed.

Prepared guarded installer `.build/GuidedTests/install-0173.py` for the next
attended session. It requires the current21-move paused recording with no pending
capture and exact overnight balances, verifies the signed build/source hash,
backs up all sidecars and preserves the prior recording. Do not run overnight:
launching the replacement app could start the camera under changed lighting.

### Overnight verification and handoff — 0.173/build174 staged

Final production source hash:
`e7d549b04e805a802a72d12f96c2b167bb09eedf6605faf6d044f3894ea3068d`
(135 sources). Strict code-signature verification and source-hash comparison
passed for `.build/Physical Go.app`. Build manifest:
`.build/GuidedTests/0173-staged-build.json`.

Validation passed on final diagnostic code: automatic evidence capture tests
(including three-second disagreement, fifteen-second visible/unknown-pose gates,
67-second bounded onset/recovery, original camera timestamps, duplicate/unknown
frames, interruptions, disabled collection, and existing archive constraints),
11 camera-preview checks, and capture/clock suites (427 capture/timing +113
uncertainty +103 conflict guidance +75 local-clock checks). Outline suites pass
73 synthetic +21 general recorded +6 clock-loss +21 A18 +19 new A19 checks.
Build-registry tests:7 passed. An initial archive test counted `.rotation.lock`
as a capture; the assertion was corrected to count actual event directories.

The live app was not replaced or restarted. Current SGF is byte-identical to the
overnight snapshot, and clock/pending/review JSON matches semantically. All21
moves and exact balances are preserved. No camera start or spoken walkthrough
was issued overnight. The separate89-move recording is unchanged as well.

The new evidence policy is not a verified fix for the original visual stall.
It records early blocked frames and the reopening rather than depending on a
move being accepted. Camera/space/writer limits still apply; trigger metadata
is explicitly not ground truth. The recorded successful replay and the separate
pose-loss perturbation must not be mislabeled as a reproduction of the failure.
Morning: use the guarded installer, check the changed lighting while paused,
and continue diagnosis if the gate stalls again. Do not increment15/27 yet.

### 2026-11-13 — Quick comparison: FULL HD WEB CAM

User requested a quick alternative-webcam recognition check and selected
FULL HD WEB CAM (USB ID0x21420000bda0567). Kept installed0.172/build173 so
recognition code remains the same during comparison; staged0.173 is still pending.
Backed up original Dave11 empty reference, preferences and all recording files in
`.build/GuidedTests/new-webcam-comparison` before switching cameras. Game stays
manually paused with21saved; SGF and semantic clock/pending/review sidecars match.

New webcam supplies1920×1080, all four board corners visible. It acquires a grid
using existing stones/exposed lines. Retained capture:
`Diagnostic 2026-11-13 12-00-50 EF6C00FB` (KEEP). Across100 consecutive analyzed
frames over20.198720s, all11Black+5White stones match their saved locations every
frame, no false extra stones, and0–6 empty intersections are uncertain. All100
frames delivered to the paused recorder; mean reported confidence at saved
stones1.0. This supports basic static recognition, not equivalent dynamic/hand
performance or a controlled same-lighting hardware comparison.

Bounded1GB capture stopped at its limit; restored10GB setting. Next quick test:
whilepaused placeWhiteC19, clearhand3seconds (expect1detected outside history),
removeit and clearhand3seconds (expect0).21saved and stopped clocks throughout.
Do not save a move or resume clocks for this camera comparison.

Static capture archived intact under `.build/GuidedTests/new-webcam-comparison`
to preserve it outside managed rotation. Started a fresh continuous capture
`Diagnostic 2026-11-13 12-07-19 68E45BAB` (KEEP) for the paused C19
placement/removal check. Live position selected; user guidance issued.
Dynamic result pending; no acceptance-matrix increment.

### 2026-11-13 — Clock display sides

User deferred the webcam placement/removal test and requested Switch sides in
Clock options. Added a persistent presentation preference that swaps the clock
cards and their corresponding move/ambiguity summaries together. Normal and
large clocks share it; Switch sides is available in both menus. Player colors,
turn, clock balances, game history and board orientation are untouched.
Version0.174/build175 includes the previously verified0.173 diagnostic changes.
Build/verification pending; native interaction is currently unavailable while
the Mac is locked. The webcam dynamic capture stopped at its storage limit;
footage remains retained and the C19 test remains pending.

Verification complete: production build and strict signature/source-hash checks
passed; existing workflow UI suite passed (including75local-clock checks,
29workflow/native-render/preservation checks and its board-recovery/speech suites),
and7build-registry tests passed. Installed and launched0.174/build175. Source hash:
`8c25cc9d6f4519944a216110bea3ff477f95f82e57a24f0236f2760a7fc1d17e`.
Backup: `~/Library/Application Support/Physical Go/Backups/Install-0.174-20261113-122658`.
After launch, current SGF is byte-identical and clock/pending/review JSON matches
before-quit data; the previous89-move recording is also unchanged.21saved, White
next, manually paused: Black382.62714116240386s, White54.89570887829177s.
Direct interaction with Switch sides remains to be checked when the Mac is
unlocked; the existing suite does not exercise the new menu command. Expected:
White and its counts move left, Black and its counts right; a second invocation
restores the arrangement, and large clock/relaunch retain the preference.

### 2026-11-13 — FULL HD WEB CAM placement/removal passed

User completed the paused White C19 placement/removal check and reported:
“Both changes appeared promptly.” Together with the earlier static recognition
check, this passes the requested basic webcam trial. Dynamic timing is a user
observation, not a measured frame latency; the earlier continuous capture had
already stopped. This does not establish equal performance under all lighting,
resolve the original67-second stall, or advance the27-scenario acceptance matrix.
The webcam can remain selected for subsequent testing. Clock-side menu interaction
remains a separate pending check.

### 2026-11-13 — Evidence-based camera comparison

Compared first raw PNG and first100recorder observations in the retained webcam
static capture and Dave11 successful A19 replay. Both inputs1920×1080, both
windows retained all16saved stones with0falseextras. Webcam recorder window:
20.55s,0–7question-mark intersections; Dave11:25.90s,0question marks. These are
separate earlier/later scenes, not a controlled camera benchmark. The webcam
recorder window differs from the earlier100-analysis-frame0–6uncertainty sample.

Visible raw-image differences: Dave11 sample has crisper grid/wood detail and
warmer rendering, with a pronounced reflection on the right half; webcam sample
is softer/cooler with much more even board illumination. Lighting and camera
angle differ, so neither glare nor sharpness differences isolate hardware quality.
Grid edge lengths imply roughly40–49pixels/intersection for webcam and45–52for
Dave11 in these placements. Both have adequate spatial detail for the verified
stone recognition. Observation intervals include app processing and cannot be
reported as camera frame rate or movement latency. Earlier67-second stall is
not established as a camera fault. Basic webcam trial passes; no overall winner
established. Continue with the USB webcam for broader capture/lighting trials.

### 2026-11-13 — Resume physical tests with FULL HD WEB CAM

User chose to retain the USB webcam and continue. Storage confirms21saved,
White next, no clock anchor and no pending capture. Next checkpoint completes
the previously deferred following move: Live position → Resume; wait for White
clock, play White C19, clear hand, expect22saved/Black running, then Pause and
leave C19 in place. If resume or recognition stalls, pause and report banner.
This is continuation after the earlier capture, not a replay/pass of its delayed
removal. Result pending; acceptance matrix remains15/27.

### 2026-11-13 — Following move passed; next capture setup

User reports C19 continuation all okay. Saved SGF ends W[sc],22timed moves,
Black next, no clock anchor/capturePosition; balances Black378.22664855851326,
White81.76870206533931. This completes the deferred following move but does not
turn the earlier67-second capture-removal stall into a clean pass. Matrix15/27.

Next distinct scenario: camera stop/start during automatic capture hold without
manual pause. Keep threshold2. Batched setup from22: BlackS1, WhiteT1, BlackS2,
WhiteT2; allow each move to save/switch clocks, then Pause at26, Black next.
Do not place BlackT3 yet. Replayed actual SGF with independent liberty checks:
all four setup moves legal/no captures; subsequent BlackT3 captures exactly
WhiteT1/T2. User setup result pending.

Setup verified:26saved ending B[ar] W[as] B[br] W[bs], Black next, no pending
capture or clock anchor; Black421.56691599835176s/White132.6516899173148s.
Next grouped checkpoint: Resume, BlackT3, leave WhiteT1/T2 physically present;
confirm automatic stone-removal hold. Without manual Pause, Stop camera for5s,
Start camera, wait for Live. Expect26saved and both clocks held throughout;
prisoners remain. If a clock runs unexpectedly after hold, Pause/report.
Capture/removal and outage result pending; no matrix increment.

User reports automatic capture hold and Stop/Start camera all okay. Storage
confirms26timed moves, pending capturePosition and no clock anchor; held balances
Black415.3372931232443s/White132.6516899173148s. Journal retains these balances
in capture hold after setup/resume. Next combined completion: remove WhiteT1/T2
together, clear hand; expect27saved and White running. Play WhiteR3, clear hand;
expect28saved/Black running, then Pause. R3 is clear with open adjacent points.
Leave all other stones in place. Full scenario pending until completion verified.

### 2026-11-13 — USB webcam corner capture removal uncertainty

User confirms both WhiteT1/T2 physically removed; instructions flicker between
one/two prisoners. Journal shows fresh frames T1uncertain,T2empty/uncertain,
T3Black, with occasional both-empty frames; not a hand gate. Camera photo confirms
empty corner/grid and hand outline says clear. Both clocks held at unchanged
Black415.3372931232443/White132.6516899173148;26saved,capturepending.
Agent manually paused to prevent unexpected resumption while diagnosing.
WhiteR3 has NOT been played. No capture scenario marked passed.

Saved full recording snapshot and retained diagnostic in
`.build/GuidedTests/t1-t2-removal-uncertain-0174` (capture13-44-55 B1E65557).
Original automatic clips were storage-blocked; moved the earlier stopped webcam
capture intact outside managed rotation to make room, then recorded this state.
Continuous capture ultimately stopped at its storage limit; retained with KEEP.
Two unmodified frames committed as WebcamCornerRemoval regression fixtures.

Offline replay confirms visible cross and exposed wood can independently prove
emptiness where a local wood plane is unavailable/unstable beside an edge cluster.
Added fallback for uncertain readings only, using existing exposedWoodConfidence
checks; no history-imputed emptiness or changed capture completion thresholds.
Also distinguish uncertain captured points from definitely present prisoners in
status and speech.209appearance/empty-board checks pass including actual corner
frames; broader lighting/capture tests pending. Live app not yet replaced.

Broader checks passed:171residual-glare +90known-empty-lighting,
113capture-uncertainty +103capture-conflict guidance +75local-clock +429capture/
hand-clear timing;7build-registry checks. New uncertain-prisoner status/speech
checks preserve the manual Resume requirement. Additional pipeline checks/build
in progress.

Exact-session offline replay (100 archived frames): original readings show both
captured points empty in9frames, new detector in68; no detected stones erased or
invented. First five clear views spanning0.8s available at1.06067s. Reopening an
isolated copy of the actual26-move capture preserves both balances and the hold;
ten paused observations do not advance it. After explicit Resume, original
readings remain stuck26; new readings complete27 at1.06067s, White runs, Black
445.3372931232443 (exactly one30s increment). Original files untouched by replay.
Logs: `/tmp/physical-go-0175-corner-replay.log`, harnesses `/tmp/ReplayCorner.swift`
and `/tmp/ReplayCornerCapture.swift`. These compare the same post-removal saved
images; they do not measure the unrecorded physical withdrawal instant.

Final targeted pipeline checks passed:73synthetic +21general +6clock-loss
+21A18 +19A19 hand-outline checks,11camera-preview checks and86lighting checks.
Prepared a guarded0.175 installer that requires this exact26-move pending capture
and its held balances. Unlike the earlier21-move installer, it explicitly expects
and preserves the capture source. Existing capture-reopen tests and isolated
actual-session replay verify retention and manual Resume semantics.

Installed0.175/build176; strict signature/source-hash checks passed. Source hash:
`c5d2bc2597036b2fe5146b2942494464ea372b51449bbf0d65ba55662aa3e2bf` (135sources).
Backup: `~/Library/Application Support/Physical Go/Backups/Install-0.175-20261113-135756`.
After launch, SGF byte-identical; clock/pending/review sidecars semantically exact;
previous89-move record unchanged.26saved,pendingcapture,manuallypaused,exactheld
balances retained. FULL HD WEB CAM returned Live automatically.

Initial postlaunch readings were still intermittently uncertain (first45views:
14bothclear; later231views longestclear run4), so no premature user retry issued.
Captured194freshframes in13-59-37 A03A09AC, then stopped capture explicitly and
archived under the same retained diagnostic folder. No camera reset or manual
recalibration applied. New-frame replay matches logged classifications exactly
for30frames (including checks with PNG/sRGB/DeviceRGB interpretation); alignment
remains supported. Later100live observations over25.107s:65bothclear,longest11
consecutive clear, BlackT3 retained. Enough fresh evidence for the unchanged
completion rule, though not every individual reading is certain. The cause of
the weaker initial window is not established; do not claim exposure settling as
proven. Capture/clock state remains unchanged while manually paused.

User retry: Resume with WhiteT1/T2 absent and BlackT3 present; expect27saved and
White running. Then WhiteR3, wait28saved/Blackrunning,Pause. If it struggles again,
Pause/report and retain evidence. Physical scenario still pending,15/27 unchanged.

### 2026-11-13 — 0.175 live retry slow; preserve and stop

User reports substantial twitching before capture resolved, impractical for live
play. Then WhiteR3 recognized and clocks switched correctly; user paused.
Journal: Resume1794607401.368294, capture complete1794607427.663032:
26.294738seconds from Resume to completion, with prisoners already removed.
WhiteR3 followed; paused1794607447.83644 at28saved, Black next, no capturePosition
or clock anchor. Balances Black436.78069856076036/White149.74118993780576.
Responsiveness remains FAIL; do not mark capture/outage scenario passed.

User explicitly requested no detailed/lengthy adjustments now and image retention
before lighting changes. Preserved recording/sidecars/journal and extracted events
under `.build/GuidedTests/corner-removal-slow-0175`. Pinned automatic clips
`Diagnostic 2026-11-13 14-03-26 FA018B51` (30frames) and
`Diagnostic 2026-11-13 14-03-47 6415B300` (34frames) in Move Evidence. These are
bounded clips, not continuous coverage of the whole delay.

Started a current28-move board/lighting capture14-05-21 9638B253. Native AX stop
and Done actions stalled; canceled those helper processes, closed the settings
sheet using its Escape shortcut and quit the app normally. No force quit. The
first normal-quit attempt with the sheet open was canceled. Capture finalized
and was moved intact with KEEP under the snapshot folder; exact path/frame count
in session.json. App left closed, recording preserved byte-for-byte and semantic
clock/pending/review JSON unchanged from pre-exit snapshot. No code, recognition,
stone or clock-setting adjustments. User also requested commit and push.
Next session inspect retained evidence before the next fix/test; lighting may
have changed. Resume from28saved,Black next,WhiteR3 present,T1/T2empty,T3Black.

### 2026-11-13 — New environment: old-game expectations block setup grid

User reports Looking for grid after changing board/stones/location. Camera photo
shows an empty19x19board fully visible. Retained83-frame diagnostic17-28-16
F6BE8802 (stopped explicitly; archived under before-new-board-20261113) records
repeated: Grid found, but known stones do not verify its alignment. recoveryExpected
still takes the paused28-move game's stones while UI is in next-game Setup.
Thus this was not failure to detect the new grid. Workflow defect remains open.

Backed up all prior recording files under `.build/GuidedTests/before-new-board-20261113`,
returned to prior game, ended recording through normal End game confirmation
(no inferred result), returned to Setup. Grid aligned immediately. Empty-board
readiness initially had152uncertain points; attempted empty-reference action but
control was already gone. Subsequent UI showed new saved setup; agent did not
successfully invoke reference capture or Save game setup. Active recording:
`Physical Go 52814471-C0DD-4625-800C-709CDBEB9CDD.sgf`.
Fresh journal now shows0unclear and lightingBlockedfalse;0saved,Black next,
paused at60s each. Previous28-move SGF byte-identical to snapshot; retained under
session.previousGuidedRecording, with active testRecording updated to new game.
No source/build changes. No physical test-count increment.

### 2026-11-13 — New-board White O3 missed (investigation)

User confirmed physical sequence White P4, Black P3, White O3, Black P2. P4 is
already move4; the next three moves require recovery. Saved SGF and sidecars
before intervention under `.build/GuidedTests/new-board-white-o3`. Canceled
inspection without edits and explicitly paused board checking/clocks. Two Black
stones are real, not duplicate detections. White O3 is visible in the raw image.

Retained `Diagnostic 2026-11-13 17-42-15 264A828E` under the same snapshot folder:
760 frames,657 processed observations; O3 uncertain640,white17. Both Black P2/P3
and saved White P4 recognized in all657 observations. Reference-backed detection;
clear hand outline, supported alignment, no lighting block. The recorded-image
replay reproduces the failure with and without an empty-board reference. The
white stone's body is slightly darker than reference wood; investigating the
fixed brightness allowance and independent bounded shape evidence. No move
history, clock balance, or recognition-setting edits yet. No test-count increment.

Diagnosis: O3 is slightly darker than the yellow reference wood. The existing
absolute -0.06 luminance allowance rejects enough body pixels to break both
classification and outline fitting. Instrumented replay also shows faint-rail
coverage alternating true/false. A new fallback considers only uncertain points
with existing partial white-color evidence, no blocked geometry/ownership or
surviving-cross contradiction, and requires a separate white disk with quality
>=0.94, normal radius and center. Its color evidence still requires strong loss
of wood tint; the luminance floor is relative (75% of reference wood). Empty
readings are not promoted by this fallback. No history labels are visual proof.
Actual frame1/frame13 fixtures added with all seven stones annotated; first725
photo/empty/shadow assertions passed. Broader regressions and signed0.176/build177
are running; installation pending.

History repair completed through normal review UI using the user-confirmed
B P3, W O3, B P2 sequence and camera-snapshot correction. Verified exact seven
SGF moves; review committed. White next, clocks paused, exact balances unchanged:
Black129.1243270211853 / White92.07860514544882. Move5 retains its known clock
boundary; no times or increments were inferred for moves6–7. SGF labels manual
entries and the clock-history boundary. Do not describe the displayed balances
as reconstructed times for the missed turns.

Longer offline replay: first100 consecutive processed frames from the preserved
clip, exact original calibration/reference. Old O3 White2/100; new100/100, no
missing/recolored real stones and no extra detections across all361 points.
Five consecutive O3 White readings reached at1.054702seconds; longest run100.
Worst measured detector time0.092901s in this replay. This is offline evidence;
live installation/verification and physical removal/replacement remain pending.

Validation complete:8/8 selected suites passed (`shaded-white-test`,
`known-empty-lighting-test`, `camera-preview-test`, `lighting-test`,
`touching-shadow-test`, `geometry-test`, `appearance-test`, `test`), plus7 Python
build-registry checks and clean diff whitespace. Full signed build0.176/build177
verified. Logs `/tmp/physical-go-0176-{regressions,build,o3-replay,install}.log`.
Existing touching-shadow suite still documents its3 preexisting small/striped
wood-cover limitations; this change does not claim to resolve those.

Installed normally with backup `Install-0.176-20261113-175541`. Source hash
`9f55852af44afd4da58019787a1ae59af77f7072c06ea121a0e6f78302b93fd9`,135 production
sources. Exact SGF and semantic clock/pending/review sidecars preserved across
quit/install/relaunch. Live verification50 successive fresh observations over
approximately10s: exact7stone position every time, O3 White,0unclear,0extras,
7saved/White next/clocks stopped. Evidence saved at
`.build/GuidedTests/new-board-white-o3/live-0176.json`.

Next physical check: while paused remove only White O3, clear hand and leave it
off. Expect a prompt missing-stone ring,7saved and stopped clocks; then separately
replace White O3 and verify recognition/ring clearance. Not yet reported by user;
no physical matrix-count increment.

User confirmed the 0.176 White O3 removal check: orange ring appeared immediately. Replacement/ring-clearance check is next. Move count and clock state were not explicitly reconfirmed in this reply; no matrix-count increment.

User confirmed White O3 replacement: ring cleared promptly,7 saved moves and both clocks stopped. O3 removal/replacement regression PASSED on installed0.176. This closes the new-board O3 recognition incident; broader physical matrix remains15/27 (additional regression, not a previously uncompleted matrix case).

Next broader test uses the new board's existing Black P2/P3 group. Verified with
SGFPlayer from the actual7-move SGF: W O2, B D16, W Q2, B K10, W P1, B K16
are legal and make no captures. User can do all six setup moves in one Resume
cycle, clearing hands and waiting for each saved move/turn change; Pause at13,
White next. Q3 must remain empty. Subsequent W Q3 captures exactly Black P2/P3
at threshold2. Capture placement and removal will be separate checkpoints to
measure hold/completion. Setup is instructed, not yet reported complete.

### 2026-11-13 — New-board capture setup: grid interruption and O2 warning

User reports a brief grid loss and a well-positioned stone ring that resolved.
Journal confirms this affected clocks, not just display. WhiteO2 saved as move8;
then grid gate repeatedly failed distributed/outer-rail support (one border only
0–2 matches; minimum3) despite low profile error. Hold began1794624688.729383.
Moves9–12 (B D16,W Q2,B K10,W P1) recovered together1794624708.222299 without
complete clock boundaries; clock needsCorrection true,Black next,12 saved.
Exact held balances Black126.54032706283033/White117.28732356149703. No inferred
increments/times. WhiteO2 (canonical248) was marked uncertain, then live ring
cleared. Current photograph has no BlackK16; asked user whether placed.

Saved complete recording sidecars/journal and recent-event extraction under
`.build/GuidedTests/new-board-setup-grid-0176`; bounded current camera clip
`Diagnostic 2026-11-13 18-53-21 0C2AB14F` stopped and archived there with KEEP.
The clip is after the reported event, not footage of the entire earlier outage.
Setup and capture test remain incomplete; do not play WhiteQ3 yet. No source
changes, clock corrections, or test-count increment in this investigation.

Post-event clip analysis:77 saved frames,68 processed observations. O2 was White
in43 and empty in25; this is ongoing unstable recognition despite the warning
ring clearing. Do not call the issue resolved or proceed to capture on the basis
of the cleared ring alone. The preserved images support independent diagnosis.

User confirmed WhiteP1 present and BlackK16 unplayed. During offline diagnosis,
recording remained active despite timing hold; O2 flicker generated7 unresolved
review tabs, then one more before camera stopped. All8 differ only atO2 between
White and empty. Stopped camera and quit normally; backed up before-review-cleanup.
Verified zero-move resolution on a copy via normal GameRecorder.resolveReview
APIs, then applied to active record. All8 resolved, exact12-move SGF and balances
preserved; timing review remains required. Restored app paused. A missing stone
alone escalating to chronology reviews after12seconds is an additional defect:
these should remain recognition/restoration issues, not repeated move-order tabs.
No production changes for O2/grid/review proliferation yet.

0.177 candidate fixes under test (not yet installed):
- Near-equal brightness no longer wins over partial white color plus positive
  disappearance of at least2 previously visible ink samples on each axis, with
  no surviving samples. This path needs a separately fitted White disk>=0.90;
  failed shape evidence stays uncertain. Positive exposed wood still wins.
- Shaded-white outlines can mask the exterior portion covered by independently
  recognized neighboring stones. Body votes remain unmasked (>=92% agreement),
  at least half the exterior ring must remain visible, and centers stay separate.
  This also handles raw O3 uncertainty beside the newly placed O2: all68 raw
  observations in the post-event clip had O3 uncertain, previously retained by
  the established-stone tracker. Do not mislabel that as reliable raw recognition.
- Faint OUTER anchor rails may use a lower relative contrast floor only with a
  centered valley and both flanks, then matching fresh normalized profile shape.
  All4 outer borders, distributed support and existing movement rejection remain.
- Without an existing unresolved chronology, a removal-only observation cannot
  start a move-order review. Persistent absence keeps its normal actionable
  discrepancy. Existing deferred sequences and actual additions retain reviews.

New two-photo FaintBoardO2 fixture, exact reference/anchor, all12stones annotated:
731 checks passed before final neighbor-mask filtering; full rerun underway.
New prolonged missing/restored-stone test reproduces review creation on0.176.
Full selected regression batch and signed0.177/build178 compiling.

### 2026-11-13 — 0.177 verified and installed; false review queue cleared

All18 selected suites passed: faint-board731, review-flicker21, shaded-white725,
glare-grid64, known-empty90/residual-glare171, live-position65, resume-alignment18,
camera-preview11, capture-clock113+103+75+429, recovery-lifecycle16,
physical-review87/review-queue218, lighting86, covered-grid108 variants,
visible-grid27 variants, touching-shadow27 variants, geometry27 cases,
automatic-grid71, vision373 (includes placement199 and rectification47).
Build registry7 and whitespace checks passed. The first review-queue run raced
an asynchronous clock write when reopening a recorder immediately after capture
confirmation. Unmodified reruns passed on both0.176 and0.177; corrected the test
to call flushStorage before simulated restart, matching normal app shutdown.
No clock production behavior changed for this test correction.

Full68-frame clip: O2 now White68/68 (formerly43), O3 White68/68 (formerly all
uncertain), no extra stones, no new missing readings. First five O2 matches span
1.094s. A separate PREEXISTING P1 edge-reading issue remains: empty13/68, identical
frames to original0.176 readings. Initial strict all12 replay failed on these13;
subsequent comparison explicitly checks them against the old readings, rather
than claiming perfect recognition. This limitation is not fixed by0.177.

Installed signed0.177/build178, source hash
94d29bf48448487e751e2fdfd486c8e0df67d3547f39020aec2bef05f4ed0e9b.
Backup Install-0.177-20261113-191812. Exact SGF and semantic clock/pending/review
sidecars preserved across normal quit/install/relaunch. Live verification100
observations: O2/O3 White100/100, P1 White78/empty22, all other points match,
no unresolved reviews. Evidence: new-board-setup-grid-0176/live-0177.json.
Do not describe this as a clean full-board camera pass. Camera live, recording
paused,12 saved,Black next, balances126.54032706283033/117.28732356149703.
Clock review still required; no clock correction or invented timing performed.
Resolved review tabs remain as historical evidence and need no user action.

Next work: diagnose P1 edge readings, then user clock review and BlackK16 setup
move13 before the separate WhiteQ3 capture checkpoint. Exact earlier grid outage
is not captured in the retained post-event clip; physical confirmation remains
necessary. No increment to15/27 physical acceptance count.

### 2026-11-13 — P1 edge recognition investigation (0.178 candidate)

User requested diagnosis before continuing capture. Reproduced P1 empty in
frames10/16 using the unchanged0.177 runtime. At canonical(row14,col0), initial
white-color hint survives but brightness resembles reference wood. Only1
horizontal and2 vertical ink samples are reliable; frame16 loses1 on each axis.
The old coverage gate needs2 samples per axis, so brightness-only empty prevents
strong shaded-white outline fitting. Independent disk fit quality0.995–0.998
in failing frames, with no exposed-wood evidence or surviving ink samples.

Candidate allows an outer-edge brightness-only empty to attempt the existing
>=0.94 white disk fit only when both axes have positive missing reference ink,
no surviving samples, a white-color hint, no wood evidence and no ownership or
geometry block. Interior conditions unchanged; failed fit preserves empty.
No saved position or expected stone count is used to label the image.
Added both failing photos to FaintBoardO2 fixture and edge exposure controls.
Verification in progress; installed app remains0.177, paused12moves.

P1 candidate verification progress: four-photo check1461 passed. Full recorded
68-frame replay now recognizes all12stones in every frame, with0 missing,
0 extra (P1 formerly13empty). Candidate BoardDetector compiled against unchanged
0.177 companion runtime; final production-runtime suites/build still running.
Added small positive/negative exposure tests plus edge shadows retaining rails.

Final0.178 runtime: all68 recorded frames show exact12stones,0 missing/extra;
worst measured detector time0.146s while build/tests were active. All10 selected
suites pass: faint-board1473, review-flicker21, shaded-white727, known-empty90+
residual-glare171, capture-clock113+103+75+429, covered-grid108 variants,
visible-grid27 variants, touching-edge1011, geometry27 cases, vision373.
Build registry7 and whitespace checks pass. Signed0.178/build179 installed,
hash8157230949585f70ed96ebe1b8b9814aa46b3b131eb7f18e732f8db54b977d2d.
Backup Install-0.178-20261113-192911; exact SGF and semantic clock/pending/review
sidecars preserved before relaunch. Live verification in progress.
User says the choice of clock balances does not matter because this is a test;
keep held balances and clear timing review while paused after verification.

Post-install verification:100 consecutive fresh observations over26.22s, exact
12stones in every frame,0 uncertainty/extra detections. Exact SGF and semantic
clock/pending/review sidecars unchanged across relaunch. Evidence at
new-board-setup-grid-0176/live-0178.json. Then, with user authorization, used
Clock options > Adjust clocks > Save clock correction to acknowledge held test
times. Black126.540327 (numeric field rounded by <1microsecond), White exact
117.28732356149703. Verified needsCorrection false,clock anchor absent,12moves,
Black next,all reviews committed,exact SGF unchanged. No missing timing inferred.

Next physical check instructed (also Kokoro): leave paused, remove only WhiteP1,
clear hand for3seconds, replace it, clear hand. Expect missing-stone warning then
clearance,12saved,Black next,both clocks stopped. Await user report; do not count
physical regression as passed yet. Then resume capture setup at BlackK16.

User reports P1 removal/replacement worked. Journal confirms11 observations of
P1 empty followed by White restored; final12saved,Black next,paused,0unclear,
0extra,needsCorrection false. Evidence p1-physical-0178.json. Physical regression
PASSED, no acceptance-matrix increment. To reduce unnecessary setup pauses,
next instruction combines B K16 (wait13saved/White clock) with W Q3 placement.
Leave captured BlackP2/P3 on board, clear hands, expect both clocks held and
removal prompt. Removal remains a separate timing checkpoint; not yet performed.

### 2026-11-13 — Q3 capture placement and grid support regression

BlackK16 saved correctly as13; WhiteQ3 did not establish a capture hold. User
paused: Black148.2037982498635,White85.94939968571998,White next,no clock review
required,no capturePosition. Preserve Q3 and both BlackP2/P3 prisoners physically.
Saved recording sidecars/journal under new-board-q3-0178; captured and stopped
Diagnostic19-34-21 2B8E1D48,126images,94operations,83delivered/11grid rejected.
Delivered Q3 rawWhite59/empty24. No move was manually added or timing invented.

Q3 brightness resembles wood; white hint and strong disk survive, but only1
horizontal reference ink sample is reliable, versus4vertical. Typically3vertical
samples disappear,none survive. The0.178 edge-only recovery was too narrow.
Candidate0.179 uses >=2 disappeared samples with evidence on both reference axes
and zero surviving samples to permit the existing>=0.94 white disk fit, anywhere
on the board. Wood and ownership guards remain. Failed fits retain previous
labels. Initial all126 replay:Q3 White123/empty3,no extras; frame78 also has an
uncertain Q2. These isolated residuals are explicitly retained as limitations,
not claimed as perfect detection. Full recorder replay is needed to assess holds.

Outer-rail midpoint profiles reject11frames despite low profile error. Candidate
samples up to5 positions per outer segment, counting each segment ONCE; requires
same3distinct segments on EACH border, distributed support, real contrast and
normalized shape match. All11previously rejected images now supported in
prototype. Added FaintCaptureQ3 frames2/3/5/64, exact anchor and13-move SGF for
photo-to-recorder capture-hold regression; full build/test pending.

Full126-image prototype replay passes: all grids accepted;Q3 White123/126,
remaining3 isolated empty readings plus1 Q2 uncertainty retained as limitations.
Using original frame timestamps, GameRecorder enters threshold2 capture hold
at0.594s. Through the rest of the25s clip, both clock balances stay fixed,
remaining prisoners stay exactlyP2/P3,13moves stay saved. No capture completion
invented. Full replay45984checks; committed4-photo regression1454checks.
The first fixture attempt omitted handObstructed=false; the recorded hand-pose
and outline decisions were clear. Supplying that pipeline result fixes the test
setup; no hand-clear or clock policy was relaxed. Final14-suite runtime and
signed0.179/build180 compiling; not installed yet.

Final0.179 runtime reproduces the full126-frame result:45984checks, capture hold
at0.594s,all126grids supported,stable clocks and prisoner count thereafter.
All14 selected suites pass: faint-capture1454,faint-board1473,review-flicker21,
shaded-white727,glare-grid64,known-empty90/residual171,resume-alignment18,
capture-clock113+103+75+429,covered-grid108variants,visible-grid27variants,
touching-edge1011,geometry27cases,automatic-grid71,vision373. Python registry7
and whitespace checks pass. No clock/recorder policy changed in0.179.

Installed signed0.179/build180,source hash
1f826d7f4de82beb194c2c1b14ce5e843cde4d8b0ddb5bd04387565bbf47baa9.
Backup Install-0.179-20261113-194609; exact SGF and semantic clock/pending/review
sidecars preserved across normal quit/install/relaunch. Recorded move count13;
clock baseMove remains12 (correction boundary), with timed move13 stored in clock
history. White next,paused. Post-install live check underway.

Post-install live check100observations:Q3 White87/empty13, Q2 uncertain3; all
other points correct. First3 coherent views at0.649s,longest coherent run14.
No grid-alignment warning events in this verification interval; camera Live.
Exact SGF and semantic clock/pending/review sidecars preserved;13saved,White
next,paused,balances148.2037982498635/85.94939968571998. Evidence live-0179.json.
This is improvement with residual single-frame misses, not a full-board perfect
recognition pass. Physical capture remains UNVERIFIED. Instructed clean retry:
remove only unsaved WhiteQ3 whilepaused,clear3seconds,Resume,replaceQ3,clear.
Leave BlackP2/P3 in place and report hold/removal prompt before removing them.

Retry clarification: after Resume, wait for White clock to start BEFORE replacing
Q3, so base-board verification finishes first. Final user instructions include
this requirement; initial Kokoro sentence did not explicitly include that wait.

User confirms0.179 physical retry: both clocks stopped and two-Black-stone
removal prompt; P2/P3 still present. Journal confirms automatic capture hold
at1794628111.339947,firstFrame1088387.1456336663,decision1088388.0593909167:
0.914s from first candidate image to hold.13saved,Black148.2037982498635,
White76.37752256123349,both stopped. Capture-hold checkpoint PASSED; completion
not yet tested. Latest generic recordingProblem says next move could not be
verified while active capture status correctly requests two stones; retain as
possible messaging issue, not evidence the hold failed.
Next: leave automatic hold active,remove both BlackP2/P3 together,clear hands;
expect14saved and Black clock automatically resumes,then user Pause. Removal
speed and final clock switch remain pending; no physical-matrix increment yet.

User confirms successful prompt two-prisoner removal. Journal: first clear
1088421.5376668759,completion1088422.9956734583,delay1.458006582s. Move14WhiteQ3
saved,Black automatically runs,White receives exactly30s (76.37752256123349 to
106.37752256123349). User paused atBlack137.91692825060937/White106.37752256123349,
no uncertainty/extra detections. Newboard capture regression PASSED; original
threshold2 case was already passed, so matrix remains15/27.

Diagnostic19-49-50 DC97EE78 stopped and archived under new-board-q3-0178 with
KEEP,390frames. Its initial state is ALREADY14saved: collection began after
completion. It does NOT capture the removal transition; reported1.458s is from
the journal's verified-clear boundary, not an independent image hand-clear time.

Next active-capture camera stop/start retry: using current14move game, simulated
B B1,W A1,B B2,W A2 (alllegal,nocapture),thenBlackA3 capturesWhiteA1/A2 exactly.
User can batch four setup moves in one Resume cycle,waiting for each saved move
and next clock,thenPause at18,Blacknext,A3empty. Capturing move and camera outage
remain separate checkpoints. No new setup moves reported yet.

### 2026-11-13 — A1 corner setup stalls confirmation of B2/A2

User reports four-move setup done. Saved15BlackB1/16WhiteA1,with high-confidence
ordered BlackB2/WhiteA2 retained; journal status2tentativemoves. A1 readsempty,
blockingstableconfirmation. Paused,Blacknext,no timingreview,balances
183.51502995871607/156.02402268652804. Do notplayA3 until18savedverified.
Snapshot under new-board-a1-0179. Diagnostic20-00-16 228A58E1 stopped/archived
withKEEP:159frames,117processed,A1empty114/White3. Actualphoto showsWhiteA1
present,slightlytowardouterboardedge. Initialwhitehint,referenceink[1,2],
missing[0,2],nosurvivingink,nowoodcontradiction. Strongshaded-white diskfitfails;
thisisnotlackofentrytothe0.179ink-lossrecoverypath. No sourcechangesyet.
AskeduserwhilepausedtocenterWhiteA1preciselyonthecornerintersection,smallnudge
inward,leaveeverythingelseunchanged;helpsisolateedge-background/outlineeffect.

Offline fit diagnostic: A1 body has~97%white votes,fitcenter(0.04,-0.16),
radius0.48,quality0.859–0.867 (required0.94). Exterior ring~16%white drives the
penalty. Adjacent A2 footprint quality0.877 is below0.90 masking admission;
neighbor/edge contamination is a likely contributor,not yet validated. Initial
physical offset~0.16cell is within normal0.28fit limit,so do not describe the
stone as illegally or grossly misplaced. Centering request is a diagnostic;
software should handle reasonable placement and still needs evaluation if it
only succeeds after adjustment. No production code/build changes this turn.

User clarification: swapped A1 for a better-looking/lightly colored White stone;
this is a jade set and the original is darker than most White stones. This was
NOT a controlled centering-only change. Latest100observations nowWhiteA1,
confidence1,offset0.08,no warning.16saved+2retained remain whilepaused,clock
balancesunchanged. Lighterreplacement is a WORKAROUND; darkerjade issue OPEN.
Preserved original photos allow regression work without claiming color alone
caused the difference (placement also changed). NextResume,wait18saved/Blackclock,
thenBlackA3,clear,leaveWhiteA1/A2 for capturehold and subsequentcamera-outage test.

Lighterjade comparison captured/stopped/archived withKEEP: Diagnostic 2026-11-13 20-05-30 21C7B7C9.
No source/build changes;0.179 remainsinstalled.

Userconfirms18savedthenBlackA3capturehold. Journalholdfirstframe1089693.5406334999,
decision1089694.3298183752 (~0.789s). HeldBlack175.11424262568954,
White156.02402268652804. Snapshot a3-camera-outage-0179. AgentusedStopcamera,
waitedatleast5seconds,verifiedoffhold,Startcamera; neverpressedPause/Resume.
FreshviewsafterrestartshowA1/A2White,A3Black,0unclear,18saved,automaticcapture
stillactive. ExactSGFandbalancespreserved. Camera-restart checkpointPASSED.

StartedcontinuousdiagnosticBEFOREremovalinstructions;pointer
/tmp/physical-go-a3-removal-capture-path. Muststop/archiveatnextreply.
NextremovebothWhiteA1/A2,clearhand;expect19saved/Whiteclock. ThenWhiteD10,
clearhand;expect20saved/Blackclock,Pause. SimulatedcaptureandD10withrepository
SGFPlayer: legal,exact2prisoners,noadditionalcapture. Wholeoutagescenarioawaits
removal/continuation;do notincrementacceptancecountyet.

### 2026-11-13 — Active-capture camera restart passed

The user's successful result is confirmed by the journal. Capture move 19
completed at uptime 1089891.82376675, after the first verified-clear frame at
1089890.523666917: 1.3001 seconds. Black received exactly one 30-second increment,
from 175.11424262568954 to 205.11424262568954. White D10 saved as move 20 and
started Black's clock. The user then paused: Black 198.08966539687145, White
173.61548924911767. No pending capture, timing review, unclear points, or unsaved
points remain. The original 18-move SGF prefix is byte-for-byte unchanged; only
moves 19 and 20 were appended.

The active-capture camera-outage scenario has passed end to end. Physical
acceptance is now **16/27 (about 59%)**, with 11 remaining; four outage/restart
variants remain. This is a new scenario pass, unlike the preceding Q3 retest.

The diagnostic clip is stopped and archived with KEEP under
`.build/GuidedTests/a3-camera-outage-0179`: 678 images, beginning at 18 saved moves.
It includes the removal transition and White D10. The first processed clear
image is 296; its processing event is at uptime 1089890.8153775418. The reported
1.3001-second delay uses the journal's capture-time boundary, not processing time.

Next, retry the manually paused capture/camera-outage case. Simulation from the
actual 20-move game confirms that Black B18, White A19, Black B19, White A18 are
legal and make no captures. A later Black A17 captures White A18/A19 exactly.
The user is instructed to batch those four setup moves, then pause at 24 saved
moves, Black next, with A17 empty. Manual pause, camera restart, and removal will
remain separate checkpoints. Use the lighter White stones for this clock-policy
test; the darker jade recognition defect remains open. Setup is not yet reported.

### 2026-11-13 — A19 corner recognition blocks the next setup

Black B18 saved as move21. White A19 is visible at the corner but not recorded;
no later setup moves were observed. User paused at Black223.4993453540713 /
White118.87759770848788, White next, no timing review. Keep A17 empty.
Saved recording sidecars under new-board-a19-0179. Stopped and archived diagnostic
20-23-25 2D6C1002 with KEEP:76images,56processed,all56 A19 readings empty.
The candidate reports empty confidence1 and no white-color hint; local wood-color
adjustment is large. Reference ink support is[0,2],with both available samples
missing. The default strong shaded-white fit (zero color-shift probe) is near
0.91–0.92 quality,below0.94. Investigating actual global-versus-local color
adjustment before changing thresholds. No source/build edits yet.


A19 diagnosis: after correcting lighting from exposed wood, the stone retains a
cool jade tint. Saturation reduction alone rejects most body pixels. A general
color check now also accepts a low-saturation cool surface with both substantial
red loss and blue gain relative to corrected wood. Brightness, exposed wood,
surviving ink, shape and ownership checks still apply; no coordinate or saved
move count is used to invent an observed stone.

The other contributing factor is the corner reference rail: only one axis has
reliable ink. Two positively lost ink samples with none surviving can now
challenge brightness-only empty even on one axis, but the same strong white disk
fit (quality >=0.94) is still required. This is weaker ink-loss evidence, not a
claim that both rails are covered. Color-only changes recognized 13/56 frames;
combined changes recognized 55/56, with no other point/color errors. Frame 62
remains a miss. The original app reported A19 empty in all 56 frames.

Added JadeWhiteA19 photo fixtures with five recognized frames and the residual
miss, absence controls from earlier board photos, and cool-colored circular
lighting patches that retain rails. Broad vision, glare, shadow, grid, and
capture regression checks and a signed 0.180/build 181 are in progress.


### 2026-11-13 — A19 validation and departure from the jade-board location

The production runtime replays the original A19 incident at 55/56 White, with
one residual empty result (frame 62) and no other stone errors. All **18/18**
selected regression suites passed: jade-white, faint-capture, faint-board,
shaded-white, glare-grid-recovery, known-empty-lighting, resume-alignment,
capture-clock, recovery-glare, lighting, covered-grid-stone, visible-grid-stone,
touching-shadow, shaded-cross, touching-edge, geometry, grid, and base vision.
Seven Python build checks also passed. The signed 0.180/build 181 was installed
by normal quit/relaunch, preserving the exact SGF and semantic clock, pending,
and review sidecars. Source hash:
`ad32ecb51c3bd233d86bd930009f9ba4571c579aac0c9a19d477862f1c2cf2fd` (135 sources).

Before packing, a fresh paused live clip captured 77 images / 64 processed
observations. **A19 was White in all 64**, both before and after lighting
adaptation. White O2 was briefly empty in 2/64; all other points matched and no
extra stones were invented. This is a short live stability check, not a completed
placement/removal test or proof of perfect recognition. The old darker A1 photos
still fail in the separate replay; that limitation remains open.

The user is moving to traditional boards in another location. Camera and
continuous diagnostics are now stopped, and both clocks remain paused. The
recording still has 21 saved moves, White next, Black 223.4993453540713 seconds /
White 118.87759770848788 seconds. A19 was observed but never saved; no move or
time was fabricated for it. The manual-pause capture setup remains incomplete,
with A17 empty. Acceptance remains **16/27**, with 11 scenarios remaining.

An independent APFS copy-on-write backup outside `.build` preserves the current
recording and all sidecars, empty reference, app preferences, session progress,
and six incident folders covering O3, grid/O2/P1, Q3, A1, A19, and the successful
A3 camera-outage capture. A seventh folder contains the final A19 live clip.
Original evidence file inventories and sizes match; event logs match byte for
byte. SGF and full clock JSON also match the pre-install snapshot after the live
check and camera stop. Backup location:
`~/Library/Application Support/Physical Go/Backups/Jade-board-location-20261113-203757`.

Next session should establish a new empty-board calibration/reference and a
separate test recording for the new board and lighting. Keep this saved game
and evidence intact; do not reuse its lighting baseline as evidence about a
physically different board. Resume outstanding capture-policy/outage scenarios
from a convenient fresh setup, batching routine placements where appropriate.

### 2026-11-15 — stale alignment failure after manual corners

The setup banner retained `alignmentCheck.failed` from an earlier automatic
grid search even after manual corner selection and fresh live validation. The
green new-game readiness message independently requires fresh aligned frames
and a verified empty board, so the two messages could contradict each other.

Canceling a search or changing manual corners now clears its obsolete result.
A fresh accepted live observation supersedes a failed search only after the
existing obstruction, alignment, lighting and possible-board-movement gates.
No recognition thresholds, move timestamps, capture rules or clock logic changed.

Verification: optimized camera-preview and workflow-ui suites both passed
(`/tmp/physical-go-alignment-tests.log`), including six added status assertions
for accepted live frames, hand obstruction, freeze/stale frames, recovery, corner
edits and grid reset. Existing clock/capture/game-preservation checks passed;
`git diff --check` passed. Source fix only: installed/running 0.186 was left
untouched to preserve the user's current calibration and live testing session.

### 2026-11-15 — 0.187: in-game rotation and B19 false-pause timer

Added Rotate view to local Play controls and renamed Set up next game navigation
to Camera & setup. Existing Setup rotation remains usable during a game; manual
rotation changes display orientation without rewriting recorded coordinates.

User confirmed displayed B19 (raw point 323 at quarter-turn 1) was empty. Its
flickering black readings nonetheless triggered a clock review after move 4.
The candidate vanished in a clear frame, but resetObservationHistory did not
clear provisionalTimingBlockedSince, allowing the next flicker to inherit the
previous two-second deadline. Clearing that timer with its history fixes the
reproduced false pause. Continuous unresolved timing keeps the existing guard.

Saved readings plus a reconstructed initial logged adjustment marker reproduce
the old pause at the exact recorded observation. The new fixture verifies no
false pause/press, the actual F4 fifth move, its own timestamp, and correct elapsed
time. Images were unavailable: diagnostics had hit the configured storage cap.
The visual cause of the false reading remains undetermined.

Verification: 122 transient-pause checks; seven additional suites (shadow
recognition, adaptive timing, placement timing, provisional play/captures, camera
preview/alignment, workflow, orientation); seven build-registry checks; whitespace
and strict signed-bundle checks all passed. Installed/relaunched 0.187/build188.
Five-move SGF and exact held clock engine verified unchanged after normal shutdown
and relaunch. Existing clock review remains for user confirmation, White next.
Backup, original journal/sidecars, before-fix probe, regression logs and verification:
`/Users/dave/Documents/SGF PLayer/work/clock-pause-2026-11-15`.

### 2026-11-22 — OPEN: AI R13 false hand-obstruction latch

Major reliability issue; camera restart was recovery only, not a fix. At move265
White R13 (raw44) was visible but continuous `camera_hand_obstruction` prevented
move inference. Saved photo has no hands; independent Vision replay returns a
reliable empty hand list. White R13 is detected at confidence .8333 with circular
fit quality .8333. The active outline tracker was the blocking layer. Its frozen
background/checkpoint was not retained, so the exact foreground component and
reason for failure to clear remain unproven. Do not relax hand interlocks or
clear based solely on elapsed time or missing poses.

Paused, restarted camera through existing controls, resumed: fresh frames were
hand-clear/aligned, R13 accepted as move266, Black S8 replied as move267 with
confirmed laser tracking. All preceding moves/timestamps were preserved. At
user bedtime, paused game and disconnected laser; position saved for offline
work. Evidence: /Users/dave/Documents/SGF PLayer/work/ai-laser-integration/r13-hand.

Next: persist bounded diagnostic tracker checkpoint/reason/component evidence
without continuous image recording; reproduce the latch with actual before/after
frames; fix clearance with positive visual evidence and regression tests that
retain genuine stationary hands/fingertips. Test dense-board shadows and new
stones together. Keep this issue open until that fix is demonstrated.

AI end-game UI currently offers Resign (human resigns) or End without a result;
there is no AI scoring UI. Two passes also save without an agreed score. Needed
follow-up: optional KataGo position estimate, clearly distinct from an agreed
final score, plus AI resignation support.

#### R13 replay and delayed-clearance detection (0.248 candidate)

Fresh 1920×1080 sample and a short placement recording were collected with game267
paused and laser disabled. Only S8 and R13 were temporarily removed; the remembered
S5/S4/S6 exchange was moves189–191 and remained in place. R13 was replaced. Saved
game and clock JSON stayed identical. App/camera then closed; Dave is free to
move equipment. Recalibration is required before further physical/laser tests.

Replay archive (marked KEEP): `PhysicalGo/Captures/Diagnostics/Diagnostic 2026-11-22 03-21-22 4A607332`.
It includes the starting frozen-reference checkpoint. Live replay cleared, but
alignment disruption reset the tracker before withdrawal. Offline replay with
retained state also cleared (frame143 first clear, frame144 confirmation).
Replacing its final view with the original failure photograph also cleared.
Thus the exact original incident has NOT been reproduced.

A reconstructed-state sweep using the same clear failure photo and recorded
background produced12 persistent false holds in56 combinations of remembered
edge/lateral position and learned/unlearned hand appearance; all12 lacked a
learned hand-color direction. This demonstrates a plausible failure mechanism
in the conservative image-difference fallback, not proof of the original state.
Do not describe this as an established root cause or permanent clearance fix.

Added a suspected-stall detector: at least5seconds and10 fresh observations with
a reliable clear hand pose while the active outline still obstructs. It changes
only the warning and saves two bounded numeric replay snapshots (current/previous)
on a background queue, independent of continuous image recording. Snapshots include
frozen background, current samples, pose, outline state, calibration, game ID and
move number. No automatic reset, move acceptance, clock change or laser enable is
authorized by the timer. Genuine missed fingertips produce the same discrepancy;
blind timeout/restart cannot be treated as proof of clearance. Current manual
recovery is Camera & setup / camera controls / Restart camera after checking the
board is clear. A positive visual recovery rule remains to be developed and tested.

Validation/update: installed signed0.248/build249 without launching the app.
269 outline checks,67 recorded-hand checks,28 photographed pipeline checks,
bounded snapshot storage/rotation,148 AI checks including real KataGo/HumanSL,
and7 build-registry checks passed. No game/clock JSON changes; laser confirmedOFF.
Source backups, build/test logs and signature/source-hash verification are in
`/Users/dave/Documents/SGF PLayer/work/ai-laser-integration/r13-hand/watchdog`.
Clearance bug remains OPEN; this release detects/records the condition and provides
manual restart guidance. It does not automatically clear an obstruction.

### 2026-11-22 overnight R13 investigation: demonstrated boundary defect

Further offline work found a concrete defect in the outline segmentation. A
connected changed region needed nine solid-core pixels anywhere in that region.
Those pixels could all belong to a bowl outside the board. Closing one-pixel gaps
then joined that outside region to thin noise inside the guard, or to an isolated
new stone. The region's deepest changed pixel kept an active hand track latched
even when its solid evidence was entirely outside the playing area. A frozen
background persists throughout an active track, so the same error repeats until
something changes or restarting the camera discards the track/reference.

A laser dark photograph saved roughly 14 seconds before the R13 placement gives
a useful near-time comparison. With the original blocked photo and reconstructed
unlearned appearance/right-edge states, the old code falsely holds two cases.
Its false component has 11 solid pixels, all outside the board, with only a
0.05-grid-unit incursion from thin boundary pixels. This demonstrates the defect
on actual incident photographs. The exact original active tracker checkpoint was
not retained, so this is evidence for the failure mechanism, not an exact forensic
reproduction of that runtime state. The pre-H11 image also lacks H11 and is sampled
using the failure image's calibration. The fixture records these limitations.

The correction requires a continuous solid component crossing the relevant
boundary, with its own support inside all four board bounds. A full core pixel
inside the guard retains a narrow fingertip; a broad shallow intrusion can instead
supply nine inside-core pixels. A few marginal pixels cannot borrow a bowl's
outside solid area, and thin links cannot borrow an isolated stone's core.
Two visual clear observations remain required. No elapsed-time reset or automatic
camera restart proves clearance. The diagnostic watchdog remains in place.

Safety checks exposed two additional weaknesses while testing that correction:

- A verified white stone's expanded mask could hide a fingertip next to it. The
  exclusion now stays within the actual fitted ellipse and requires each excluded
  pixel to be bright and neutral; a visible white center alone does not exclude
  adjacent hand-colored pixels. Pale/neutral fingertip variants are covered too.
- Replay frame143 visibly contains a motion-blurred withdrawing hand although
  its pose is empty. Contrary to the earlier replay interpretation above, this
  frame is **not clear**. A lost color/location track now checks independent solid
  paths from any boundary into the grid. This fallback requires support beyond a
  single edge stone's footprint, preserving the older captured-corner-stone
  removal test. Reacquisition drops the stale velocity fit and retains an observed
  interval for clock timing. Near-black pixels still provide luminance evidence
  when their chroma is unusable, retaining hands over black stones/dark sleeves.

Permanent regression data are in `PhysicalGo/Tests/Fixtures/R13Clearance` with
provenance and hashes. They cover the nearby pre-H11 reference, the much later
replay reference as a stale-background stress case, the clear blocked photograph,
five visible-hand/blurred-hand photographs, and actual clear withdrawal. Checkpoint
edges/centers and timestamps in the sensitivity tests are deliberately synthetic.
The old code fails 13 of the initial 137 photo checks; corrected code passes all
144, including seven further retained-appearance/clock-bracket checks. All 328
synthetic outline checks, 67 existing recorded-hand checks, and 28 complete
photographed hand/stone pipeline checks also pass. Genuine fingertips, captured
stone removal, camera gaps, duplicate frames, unreliable poses, and original clock
uncertainty checks remain covered. No recording tail was trimmed: the short R13
replay and its final withdrawal/clear-board evidence are retained under KEEP.

The full retained-state replay now blocks visibly blurred frame143, records
frame144 as the first clear view and confirms at frame145. Its clock estimate is
the observed143-to144 bracket, not a stale extrapolation. Tracker processing alone
took at most3.4ms across these36 replay observations (not a whole-camera-pipeline
benchmark). The replay used saved images only and did not reopen the camera.

Installed signed0.249/build250 without launch; source hash
`294859bf7497df9b66dc15c7a997c4a0a7442cf31024f44642f26a6d2c125a76`.
The demonstrated segmentation defect is fixed. Physical validation after
recalibration remains required; do not describe this as proof
that every possible clearance stall is eliminated. Game267, its timestamps and
paused clocks must remain untouched. Dave is away and may rearrange equipment:
leave the app/camera closed and laser disabled; install without launching.

Final verification: 275 AI/laser protocol checks, 148 AI checks including real
KataGo/HumanSL, bounded snapshot storage and seven build-registry checks passed.
Installed signature/source hash verified; unrelated source files and saved game/
clock JSON unchanged. App is not running, bridge reports laserOn=false/state=off,
request=off/reason=disabled. No controller/firmware change. Evidence and installation
verification are under `work/ai-laser-integration/r13-hand/clearance-cause` and
`work/ai-laser-integration/installation-verification-0249.json`. Shared laser
handoff updated; its response file has no new reply after Nov21 12:48:56.


### 2026-11-22 fresh-board session: calibration and broker preparation backlog

Dave cleared the board and moved equipment. Preserved the previous267-move game,
clock snapshot and recognition trace in `work/ai-laser-integration/fresh-board-20261122-133741/saved-ai-game` before ending it without a result. New test game
`3D20B55B-DBE7-42E1-847E-3B82E60FF65A` is paused at move0. Grid recovery initially
continued to use the old AI stones even after ending the game; resetting the grid
and starting the separate empty game allowed fresh automatic detection. This is
not a hand-clearance failure. Independent printed-crossing refinement matched315
points (median0.608px,p951.198px), visually checked against the empty board.

Old bridge97644 had a stale USB handle after equipment reconnection. Stopped it,
opened a fresh exclusively locked connection and confirmed v39OFF. First stationary
PEEK was invisible because Dave's physical switch was OFF; after switching ON,
a second4sPEEK was visibly around G13. Both ended in fresh OFF/STATUS confirmation;
no motion was commanded. This is visibility only, not pointing calibration.

Fresh broker-based commissioning then stopped before light when frame age exceeded
600ms. Native0.249 displayed1.2–1.5s publication gaps; a2s profile sampled the
laserFrames queue713/715times in prepare/PNG encoding. prepare() queued every
analyzed frame independently, while the publication drain could encode those same
frames itself. Old preparation closures accumulated and recompressed already
published frames, delaying fresh manifests. Camera restart helped only briefly.

Candidate0.250 bounds preparation to one newest pending frame, shares one drain
with approved publications taking priority, and skips preparation already covered
by a published frame. Same-frame safety verdict pairing, immutable images, epochs,
hand/lighting gates,600ms age limit and hardware leases remain unchanged. A blocked
encoder regression submits30newer frames and requires bounded encoding work plus
the newest frame's own obstructed/invalid verdict. Full tests/build and live cadence
verification are pending at this entry. Laser is OFF; optical calibration and0.249
physical clearance validation remain pending. Session scripts/evidence are in
`work/ai-laser-integration/fresh-board-20261122-133741` outside the repository.

0.250/build251 installed with signed sourcehash
`385057542a69db0a05d64072e635ba4a69f81dfcc913431f894e521aa08f44d2`.
Deterministic30frame congestion reproduction: old32encodes,new2; newest frame and
its own safety verdict retained.278laser lifecycle/protocol,328hand-outline,
13Python bridge and7build-registry checks pass. Swift6.2.4 also required splitting
the existing Checkpoint grouped property declaration; serialized fields and hand
behavior unchanged. Saved new-game snapshot byte-identical through installation.
Live0.250:147distinct frames in15seconds, max observed age0.256s, no stale/hand/
alignment rejects (previous max1.516s). Physical laser calibration resumed with
fresh broker frames; broader gameplay/clearance validation still pending.

Nov22 optical commissioning update: center03 slow-mode K10 passed(2.015px).
board01 passed D16/Q16/Q4 then stopped DARK with base_during_move; final v39OFF
confirmed. Full new physical calibration/binding not yet admitted. Fast center02
had tilt_moving2.545s after SETTLED; helper omitted the production bridge's measured
hold recenter before PREPARE gain change. This is a plausible script-specific
cause, not proof of hardware defect or general fast-mode unreliability. No motion
guards changed. Dave prioritizes AI/online decision-to-first-light latency with
fast approach then fine correction. Existing gameplay already uses this sequence;
measure first-light and verified accuracy separately before optimizing.

Nov22 timing preferences: Dave requests fast coarse gameplay movement followed by
bounded fine correction, cue simultaneous with laser activation (no pre-cue wait),
and accepts engaged motors during active play. Laser host candidate now dispatches
preloaded audio with TRACK/SWEEP after all dark checks; no firmware/native changes
for cue.61offline audio/adapter/measurement/runtime checks passed; acoustic/optical
synchrony not yet physically verified. Production service remains stopped.
Persistent dark holding needs a distinct app/bridge/firmware contract; existing
OFF must remain a full shutdown.2hour thermal/current/noise validation pending.
Historical86AI move timing audit median receipt-to-ON-ack~5.17s, only~.73s coarse
travel,~1.80s ARM+HOLD. These are Nov21 historical data, not currentsetup latency.

### November 22: maintained checklist and faster AI testing

Dave requested a current document for the integration work list. Canonical status
is now `IntegrationChecklist.md`, linked from README and AGENTS.md. No laser-agent
acknowledgment is pending as a prerequisite: shared requests are advisory until
ownership is acknowledged. Added centering-hint physical tests, capture-indicator
implementation/tests (no capture target type exists yet), and a proposed45C warning/
50C full-OFF thermal-test gate that must be implemented/verified before endurance.

Fast AI test-mode candidate preserves selected opponent settings while using the
existing Quick8visit realKataGo search without HumanSL and retaining its worker
between replies. One-visit prototype returned no move in the actualengine test;
changed to8visits before installation. Pause/fault/end release the worker; game
history and physical confirmation/clock gates are unchanged. Mode is saved with
the game and changed only while inactive/paused.0.251build252 verification pending.

0.251/build252 installed and signature verified; sourcehash
20f9afb79af5290a32457e01528784f01a58011ec234a60dc9cbd212f216b431.
162AI checks including real8visit cold/warm moves and four HumanSL ranks passed;
7build-registry tests and full signed build passed. Test19x19 replies: cold9.090s,
warm0.170s; normal5kyu18.206s in same run. Testmode enabled through appUI on saved
empty game; gameUUID, moves and clock JSON values unchanged. No gameplay resumed;
bridge disabled and hardware off. Prior0.250bundle retained in session artifacts.
Three offline agents now investigate motor faults, standby/thermal design and
capture/centering guidance. Root remains sole hardware operator.

Root dark-transition-zero-01 failed duringFASTARM beforeHOLD/anymovement:
base_moving, gpio_high_ms0; freshOFFconfirmed. DIAG captured lastfirmwaresample
base2422 tilt2143 v1=2 v2=0. Dave confirms untouchedequipment. Investigate startup/
released-axis velocity before anothermovement test; no fast-mode-only conclusion.
All3parallel offline reports complete; motoragent reviewingnewstartup evidence.
Checklist adds online laserwiring gap discovered bycaptureaudit; no onlinephysical
support claim merely from protocolaccepting sourceonline.

Nov22 basic empty-board hand check: first45swindow notperformed (Daveconfirmed
notyet). Secondguidedtest saw handObstructedtrue atframe6291, age.188s; later
withdrawalcheck saw aligned/handfalse stable2s, clearimage visuallyverified.
Gamepaused, beamOFF throughout. Evidence hand-entry-02.json,hand-withdrawal-02.json,
hand-clear-02.{png,json} in sessionroot. No latencyclaim because observations were
not continuous across operatorinstruction/polling gap. Still need stone-placement
clearance and actual laser hand-shutoff test aftercalibration.

Nov22 bounded read-only startup sampling completed (startup-readonly-01): temporary
v40 returned30 complete axis samples, no drops, torque/startup/error/current all0,
laser gpio_high_ms0. Acquisition windows0.574–2.541s after power-on. Base reported
position2421–2422 and velocity0–2; tilt position2143/velocity0 throughout. This
supports investigating low-speed measurement noise or tiny released-axis motion,
but does not independently prove physical stillness or justify relaxing guards.
Exact saved v39 binary restored with successful upload verification; fresh
AimControl v39 OFF receipt saved in motor-startup-instrumentation/restore-v39.json.
Production bridge remains stopped; game unchanged/paused; no further hardware
run started. Dave requests plain-language explanations of diagnostic work.

Nov22 stone-clearance-01 physical check: Dave placed a black center stone, held
hand over board, withdrew, then removed it and withdrew again. Continuous broker
observation saw handtrue at24.06s, clear31.71s with stone visible; handtrue41.36s,
clear43.00s with board empty. Clear persisted afterward. This paused-game/beamOFF
check passes the single-stone false-hand scenario; no live move/clock/beam-shutoff
or exact physical withdrawal latency claim. Evidence stone-clearance-01 folder.
Dave authorizes unattended heat work after software/short monitored hold gates;
no further human-presence approval gate. Four-hour temporary caffeinate assertion
started on AC; normal lock/screensaver settings unchanged. Hardware remainsOFF.

Nov22 correction to startup-readonly-01 timing: actual cached D2A0.8.2/OpenRB
SerialPortHandler::begin sets pin31HIGH and delays500ms. v40 then waited450ms
before its explicitHIGH/timestamp. Thus recorded0.574–2.541s sample windows are
relative to that later software timestamp, not first motor-power edge. Source
path implies about3.54s powered for this completed run; no physical power-edge
instrumentation exists. Prior3s bound claim was inaccurate. Raw evidence retained.
No torque/goal/light commands were sent and v39 restoration/OFF remain verified.
v41 heat candidate models actual libraryHIGH and starts absolute deadline before
first powerHIGH. Source-ID correlation hardening also underway before admission.

Nov22 thermal commissioning-01: independently reviewed privatev41 image
7b53c37d.../binarydc169587... installed with upload verification.225native checks,
25actual-library sanitized cases,17host tests and137pair simulated transcript
passed before attempt. Actualhost stopped after~2.22s: thermal reports stopped
advancing. Seq1complete at~1.452s (12/13C,0current/torque); seq3header~1.787s,
axis1~2.051s, axis2notreceived before750ms complete-report deadline. No firmware
fault reported; finalv41OFF clean. NoHOLD declaration or meaningful heat result.
Exactv39rollback restored/verified and freshOFF saved thermal-host/
restore-after-commissioning-01.json. Suspected delivery scheduling across slow
real monitor/enable operations; offline reproduction with6ms bus transactions
and70ms USB bounds underway. Do not increase freshness limits to force a run.

Nov22 commissioning-02 privatev42 passed60.014s;184 validated pairs, heldphase
54.85s; positions2422/2143 fixed throughoutheldsamples, max14C both axes,
reportedcurrent max0/5mA; normalP2000/I0/D600 profile, cleanv42OFFreceipt.
Source8397c408... binary3928df192...;225native+10timing+27reviewburst+17host checks,
132pair realistic6msbus/70msUSB replay maxgap/sampleage510ms under750ms limit.
Thermal-endurance-01 started16:16:08Pacific, finite7200s, expectedend18:16:08.
RootrunnerPID21217, laserintrinsicallydisabled, productionbridgeSTOPPED,
game0paused/preserved. Two-hour result pending; root monitors and restoresv39after.

Nov22 endurance-01 finalizedstopped278.361s,864acceptedpairs, Hphase273.68s,
maxreported16Cbothaxes,currentmax3/1mA,positions2422/2143fixed. No firmwarefault.
Hosterror Thermal sample age invalid:-0.014s; fixed conversion from independent
MCUelapsed to Macmonotonic drifted. Finalv42OFFconfirmed; exactv39rollback
restored/verified and freshOFFreceipt thermal-host/restore-after-endurance-01.json.
No2hresult, no coolingtransition. Do not widenfutureage tolerance; causalACK
acquisition provenance design/review underway. Actualv42host/firmware artifacts
archived separately before changes. Camera game/history/clocks unchanged.

Nov22 v43 source01ac8652... binary9512cbab... reviewed independently;225native,
37host andeight2h causal-clock simulations pass (worst670msunder750ms).
Commissioning-03 passed60.022s/533pairs/504heldpairs,max14Cbothaxes,current0/1mA,
heldpositions2422/2143fixed,maxhostcausalbound257.8ms,cleanv43OFF.
Endurance-02 startedabout16:42Pacific,finite7200s,rootPID26775,execsession42915.
Beam intrinsically disabled, productionbridgeSTOPPED,appgamepaused/preserved.
Physical2hresult pending; restoreexactv39andfreshOFF afterward. No sourceedits
or additional serialclients while active. Capturecandidate separatelyprepared,
78Swift/29hostcheckspass; unapplied/uninstalled/unvalidatedphysically.

Nov22 endurance-02 ended917.235s/8458pairs; observedheldphase911.834s,
maximum16/17C,measuredcurrent3/11mAmax. Baseencoder2422fixed,tilt2143–2144;
heldrawvelocities0/1only. Maxcausalage269.293ms/maxpairgap268.686ms, so clock
correctionworkedthroughthisrun. Stop: genericcamera agegate (any4timestampages
outside0–600ms); failedmanifest/whichage notretained, so producerdelay versus
readerpreemption or inconsistenttime notyetestablished. No firmwarefault or
coolingphase; no2hpass. Freshv43OFFthenexactv39rollback/uploadverified/freshOFF
saved thermal-host/restore-after-endurance-02.json. HardwareOFF, gamepreserved.
Rootnowpassivelylogsbrokeragefields, nohardwaretestorretry. Exacttestedhost
archived thermal-host-tested-v43-endurance-02 beforeaddingdetailedgatefailurelogs.
Capture/endedgamecandidatepatchesnowappliedtosource; fullappsuitesrunning,
installedappremains0.251. No beamactivation.

Nov22 passivecameraaudit afterendurance-02:600.06s/6000recordedobservations,
zero failedpolls underunchanged0–600msagechecks. Maximumrecordedcaptureage
514.3ms; samplingkeptnewframe/errorobservations, so thisis notmaxofallpolls.
No hardwareinthisaudit. Heatstopnotreproducedandcauseunresolved; noidenticalretry.
Separatelydeterministicbrokerresetcachebugreproducedandfixedinsource: cachekey
nowstreamEpoch+frameID, so newepochmetadata cannotreuseoldepochpixels. Thisis
notclaimedascauseofsame-epochheatstop. Fullappregressionrunsunderwayfor0.252.

Nov22 PhysicalGo0.252/build253 signed/installed,sourcehash
3c48d83c3f5bff55bc412be84e90aa05574c232d612b2ca906098b2430df55c7.
Sevenfullappsuites/590checks passed:162AIincludingrealengine,278laser,16recovery,
42capturestate,47capturecontract,37capturecontroller,8brokerepoch. Eightregistry
and29hostchecks pass. Capturedstonepurpose/capability nowimplemented, silent,
placementfirst, stablepositiveevidence andclocks preserved. Fullsuite caught
blanketcapturepending blockingvalidcombinedcleanup+reply; fixedwithcurrent
positiveprisoneremptyproof/priorremovalforreplyonprisonerpoint. Physicaltestspending.
EndedAIgridrecoveryguard andepoch+frameIDpixelcachefix installed; no claimthat
cachebugcausedsame-epochthermalstop. Postinstall151frames/15.07s,maxage.2446s,
correct0x11000000bda0567camera,newstream5ED3968B-9FBA-4143-9DF3-3A026A3F0FBB,
aligned/handclear/emptyboardvisuallyverified. CurrentgameJSONexactlyunchanged.
Finalstate:gamepaused,fastmodeON,bridgecheckboxOFF/consumerSTOPPED,
recording/warningsOFF,exactv39firmwarefreshOFF(final-v39-off.json).
TemporarycaffeinatePID9545released. 0.251rollbackbundle retained insessionroot.
Maintained IntegrationChecklist.md rewritteninreadablecurrentform; thermal2h,
fullmovedsetuplasercalibration/liveclearance/capture/centering/online stillpending.

Nov22 follow-up: Dave asks whether camera timestamp shutdown can be overridden.
Verified endurance-02 elapsed917.235s (15m17s), holding~912s; no override occurred.
Prepared explicit --stationary-dark-no-camera host option for private v43 only.
Default still checks camera; opt-in omits camera loading/identity/alignment/hand/age
checks, retaining current app OFF/no-target lease, cancellation/deadline, exactv43
identity, fresh paired motor telemetry/ACKs and all intrinsic firmware protections.
No production bridge or firmware changes. 20host +20independent protocol/transport
tests pass. No hardware run started with this option; current v39 remainsOFF.
Camera-gated optical gameplay still requires fresh camera evidence. The generic
old camera error cannot establish which age check failed; ten-minute passiveaudit
had zero failures, so this is neither a known periodic timeout nor proven resolved.

November 22 — testing direction updated at Dave's request
Dave prefers monitored gameplay with continuous holding and automatic cooling
fallback; formal two-hour endurance is no longer a prerequisite. Track both
motor temperatures during actual use and assess the observed trend/plateau.
Immediate implementation gap remains gameplay standby + temperature supervision
across firmware/bridge/app; private v43 heat firmware cannot play/illuminate and
installed v39 has no equivalent runtime thermal monitoring. Do not claim hold
is enabled merely because fast AI/capture guidance are installed.
Next physical sequence: short hold/stop validation, fresh moved-setup calibration,
ordinary fast-AI hand/stone recognition, ambiguous/off-center wiggle, controlled
single/multiple capture markers with partial-removal and clock checks.
Retain 45C cooling, both below40C for30s before persistent-hold recovery, 50C hard
trip, failed/stale-reading shutdown, fullOFF for pause/fault/disconnect, and all
optical camera/hand gates. No hardware action or software installation this update.

November 22 — version-control baseline before gameplay holding
At Dave's request, committed and pushed the app checkpoint e8b2b14 (including
11 previously unpushed commits) to codex/physical-go-confidence-validation.
Created private GitHub repository https://github.com/davemarvit/DYNAMIXEL-Go-Pointer
at the existing laser project root; baseline 1060bef pushed to main. Firmware,
bridge, tests, CAD and project documentation are tracked. Camera checks recordings
(~9.6 GB) remain local and ignored, along with generated caches/builds. No files
were deleted. A separate verified firmware archive is retained under
pre-gameplay-hold-checkpoint in the integration session directory.
No hardware operation, software installation, or gameplay-holding code change
was part of these checkpoints. Laser remains in the previously confirmed OFF state.

November 22 — monitored gameplay candidate, root-owned commissioning
Physical Go0.253/build254 is installed and signature/sourcehash verified
(ce241953f14c58738578888ccd7ec9fb62b367f9644ed135ab999435510c0aba).
Game JSON remains byte-identical, move0/clocks0, fastmodeON/paused. Broker enabled
only to publish OFF/no-target evidence; production bridge remains STOPPED. Correct
camera0x11000000bda0567/newstream15BBD21C-000D-471D-A8E2-F57D4EDE74F7, fresh
aligned hand-clear empty-board image visually verified. No new optical binding.
Root uploaded exact reviewed v44 binary83b04d6653e7f8b2fde1a5e98a8eeab5c32bee050a5f19273a3c0a37b5c63dc7
withverify; freshv44OFF and exactCAPS confirmed. Originalv39 rollback verified.
Root now owns finite dark-commissioning-01 (max40s), GA/SB hold/RS(no travel)/SB/OFF.
No other serial clients or core-source edits permitted during this run. No beam
or travel commands authorized by its fixedallowlist. Result pending in session
gameplay-holding-validation/dark-commissioning-01; finalOFF proof required.
Offline:8app suites+4finaltargeted suites passed; actualnative/host JSON bothways
pass. v44 6686nativeassertions/24independentcases/567actualcoreCDCchecks and
normal/cooling/±1% actualhostreplay pass without750ms widening.
Faster broker-only v44 freshcalibration tool remains under independent review;
legacy camera0/raw-v39 calibration paths must not be reused.

November 22 — dark commissioning passed; attended calibration next
Installed Physical Go 0.253/build 254 and reviewed v44 firmware. Dark commissioning
completed in 19.3598 seconds: 143 paired reports, reported motor temperatures
11–12°C, maximum causal sample age 148.183ms, fixed positions 2422/2143.
Fresh final full OFF confirmed, no controller error; saved game byte-identical.
This validates the short dark hold/reuse/stop sequence, not optical gameplay.
The broker-only fresh calibration candidate passed 36 offline checks. Root owns
all hardware. Dave confirmed presence for visible calibration; production bridge
remains stopped and app paused. No fresh optical binding is active.
Dave reports room temperature 61°F (16.1°C) and just raised the heating setpoint
to 68°F (20°C). This is an environmental change, not a measured 68°F room reading;
recorded motor temperature rise cannot be attributed solely to motor heating.
Motor telemetry is not an independently calibrated ambient thermometer.
Dave requests an audible beep whenever asked to locate a laser spot, dispatched
with illumination without waiting for playback. Calibration cue support is being
added before the first visible check. Absolute thermal policy remains unchanged.

November 22 — initial optical check stopped before light
initial-spot-01 stopped with Registered prelight image expired after PREPARE,
before any SWEEP or travel command. Final fresh AimControl v44 OFF confirmed at
1795416782.7954059, with no controller or supervisor fault. No beep was dispatched
because no illumination was admitted. Source 3dedc18463bf515dcd344022b64875a173b1181bfa09048604e0e81a2c1af8cc.
Investigating board-registration processing cost; camera freshness guards remain
unchanged. A separate Ping sound check succeeded and Dave confirmed hearing it
clearly. Root remains hardware owner; production bridge stopped/app paused.
Implementation checkpoints pushed: app d5d84ef and laser ed8ba32, both on
codex/monitored-gameplay-holding. No full-board calibration is claimed.

November 22 — stationary visible check passed with attention beep
initial-spot-02 completed initial_spot_verified with no commanded travel, 74
thermal pairs and clean fresh v44 full OFF at 1795417137.0143986. Seven camera
samples agreed on spot reference (1165.53,725.11), board (11.796,14.813), safely
inside the two-intersection initial margin. This is current-pose observation,
not a fitted map or full-board qualification. Source hashes unchanged during run.
Prelight collection .228s, registration .119s, captured-image age .304s;
beep process dispatch followed SWEEP command by .00844s. Actual acoustic/optical
synchrony is unmeasured. Dave previously confirmed separate Ping audible.
Reference-side registration caching preserves all feature/ECC/movement gates and
0.6s image/0.15s admission limits. 48 calibration and 14 registration checks pass.
The first expired-image cause remains unproven; saved timings show improved margin.
Dave notes occupied boards may process differently. An offline agent is measuring
saved sparse/crowded/capture/hand recordings, separately from empty calibration.

November 22 — audible repeat passed; full calibration stopped at grid fit
Dave missed initial-spot-02 visually, requested repeat, then confirmed hearing
and seeing initial-spot-03. Repeat passed with spot board (11.803,14.826), no
travel, prelight image age .302s, registration .106s, audio dispatch .00747s after
light command. Final clean v44 full OFF at 1795417222.4390912.
Full-calibration-01 then stopped before session engagement/light/travel with
Printed grid and app grid disagree. Clean full OFF at 1795417247.9939082.
No fitted map or full-board qualification. Original failed grid image was not
retained; candidate fix now saves exact image/manifest before fitting and reports
numeric errors without changing limits.
Passive subsequent grid audit captured eight images under
gameplay-holding-validation/grid-after-full-calibration-01. One fit exceeded
4px bottom-left error (4.0277), five were near3.7–3.98px, two below1px there.
Native corners were unchanged; a separate earlier image-registration comparison
showed only.06–.10px displacement. Do not infer equipment movement or repeatedly
retry to select a lucky fit. Author and independent reviewer investigating fit
variation using saved pixels. Root hardware remains OFF; app/game paused unchanged.

November 22 — occupied-board timing and grid-fit diagnosis
Offline ten-pair host timing report is PhysicalGo/Documentation/OccupiedBoardTiming.md:
79 usable observations; one explicit process suspension excluded. Sparse two-stone
pair~1.3s, crowded matched-reference pair~.15s; no monotonic stone-count claim.
Reference caching preserves accepted transforms/rejections and saves~25–35ms on
fast paths but does not solve slow ECC cases. Native pipeline was inspected, not
timed. Existing gameplay obtains a newer clear frame after some alignment work;
these timings do not prove every gameplay request violates the new calibration's
same-image prelight lifetime. Freshness and safety thresholds remain unchanged.
Grid diagnosis: RANSAC excludes all left-edge points on several saved frames,
causing extrapolation variation. Deterministic all-point fit is steadier but has
only6–9/19 left-edge points within1.5px. Investigating direct printed-line centers,
edge-junction localization and fitting objective rather than lowering limits.
No full calibration, map activation or gameplay test completed. Root hardwareOFF.

November 22 — balanced grid passes; next stop is measured prelight timing
Frozen gameplay_calibration.py22064c37902bc1739a20f07f9c502e298ead6159215e94b3a75a41f805e2acff
uses deterministic fixed boundary/interior weighting, original251/<1.5px support
and<4px native-corner guards, plus all72 actual printed-boundary points<3px.
51tests and independent moved/misindexed/erased-edge cases pass. All8 recorded
frames pass actualfresh_grid; worst trueboundaryerror2.005px. Fresh livepassive
preflight334inliers,.166s,maxboundary1.915px; emptyboard visually confirmed.
full-calibration-02 passed that grid, initial visible spot, and first dark PTO2440
move (2422/2143 to measured2439/2143) with no motor fault. Next prelight check
stopped: collection.432943s, registration.277273s, capturedage.630870s vs.600limit.
Clean full OFF at1795418406.4329135; last paired temperatures14/14C, no supervisor
or controller fault. No model/binding/target qualification completed.
Root authorized bounded fullyNEW prelight image acquisition whilealreadydarkREADY:
max3attempts and2s total, no additionalPREPARE/travel/reenergization, everynewimage
fullyregistered with unchanged age/admissionlimits; only specificimageexpiry can
retry. Hand/context/geometry/telemetry/cancellation faults stopimmediately. Author
and independentreviewer implementing/testing; no hardware retry untilreviewclear.
Dave asked about4Kwebcam. Root recommends fixing softwarefirst: currentimage has
40–60px gridspacing and adequate printed-line evidence. 4K may improve detail
but increasespixelwork4x; lens/focus/exposure and distortion are separate issues.
No purchase or camera/configuration change was requested/performed.

November 22 — priorities and commissioning poll tolerance reviewed
Dave explicitly prioritizes dependable gameplay over short calibration: extra
setup time is acceptable; failures during a game are unacceptable. Test degraded
operation and recovery as well as normal moves, preserving game history/clocks.
full-calibration-03 reached eight spot measurements and seven movements near
center before the commissioning metadata permit expired. Its actual image and
app lease remained fresh. A153.794ms read/parse span exceeded the150ms cached
refresh budget; clean full OFF followed expiry by19.72ms, at1795418887.5419178.
398 paired thermal samples, max16/16C, maxcausalage170.70ms, no controllerfault.
Source hashes and saved game SHA6ca3728c88fa9fc7aeba9675715543a1b02f37dafd5b134daa9ebeec8a972f09 unchanged.
Root's30s passive probe:1103polls,no invalid evidence,max refreshgap75.99ms;
longest steps were opens with little threadCPU. Subsequent1080-per-method A/B
showed no useful tail benefit from directory-descriptor reads; no I/O rewrite.
After user's timing challenge and independent review, root authorized250ms for
the extra commissioning cache allowance, still capped by remaining600ms image
ages, actual app lease and total deadline.20ms polling, immediate bad-evidence
revocation and separate150ms fresh optical ticket remain. Explicit tradeoff:
a stalled polling worker could allow up to100ms more before shutdown; this is
not a certified end-to-end hand-response bound. Production gameplay already
uses its actual600ms data/cache ages and does not have this150ms test-only cap.
Implementation/tests for250ms pending final review; no further hardware run yet.
Continuity audit found installed0.253 stops guidance on a hard laser fault but
can leave local AI clocks running. App agent is implementing scoped automatic
pause for genuine current hard guidance faults with explicit recovery; normal
hand waits/arming/status acknowledgments must not pause play. Independent review
assigned. No app update installed yet, and no camera-outage timer invented.

November 23 — calibration meaning, stationary analysis and future learning
Dave clarified that initial calibration has no expected board activity: geometric
analysis may take longer than the live clearance freshness budget. Root accepted
that distinction. Proposed implementation: bounded dark analysis of frame A,
then a distinct fresh frame B proving unchanged measured boundaries/texture and
current hand/identity; geometric evidence is not relabeled fresh. Staged policy
under review; no new hardware run or full-board calibration completed.
Dave requested a table distinguishing camera-to-grid calibration, laser motor-map
calibration, ongoing scene checks, per-move aiming corrections and stone recognition.
He also requested a deferred continuous map-refinement task. Current gameplay
bridge uses saved model parameters/offsets for each new target; camera feedback
corrects the current pose but does not persist improved motor-map parameters.
Checklist item18 records later learning from high-confidence pose/spot observations,
separate bare-board/raised-stone geometry, bounded candidate updates, validation,
versioned activation and rollback. No adaptive-map implementation started.

November 23 — staged calibration reviewed; gameplay recovery edge cases
The staged calibration implementation passed independent review: 93 calibration
checks including both retained-image cases, plus 24 dark checks. Fresh B proof
took .117–.118s in independent replay; shifted/rotated/perspective-changed scenes
and interior occlusion were rejected. Runner94bdda22/helper0eb1bde7 are frozen.
No new physical run; last run04 ended with clean full OFF1795419902.9484515.
App candidate0.254 passed ten regression suites, alongside133 focused continuity
checks and302 native checks consuming56 actual host status fixtures. Independent
review then identified transient hand/camera recovery latches and a false hard
thermal diagnosis on unknown output during startup. Native author and reviewer
are repairing/testing actual fault-to-OFF-to-fresh-clear transitions before
installation. Current installed app remains0.253; game/clocks preserved/paused.
Deferred continuous map refinement remains checklist item18; no learning code
started. CalibrationAndTiming.md now explains both calibrations, ongoing checks
and distinct timing budgets in tables.

November 23 — offline overnight boundary and final software checks
Dave plans to go to bed and turn off room lights. Root advised switching off the
laser physical power; physical switch state is not independently confirmed.
No further light, travel, camera qualification or physical tests until Dave
returns. Last commanded state remains clean full OFF from run04. Saved game
SHA6ca3728c88fa9fc7aeba9675715543a1b02f37dafd5b134daa9ebeec8a972f09
remains unchanged. Restore lighting and verify setup before tomorrow's tests.
Final recovery suite passes492 checks with68 actual host statuses. It includes
full transient recovery, same-game AI retargeting, Pause/Resume and strict
scope/hard-fault rejection. Final root rerun passes225 standby,278 laser
lifecycle,47 capture-contract and26 progress checks (4/4 suites), plus8 registry
checks. No physical recovery claim yet; installed app remains0.253.
Progress UI and passive publisher independently reviewed:104 calibration/progress
and24 dark checks pass, including injected reporting failures that cannot skip
OFF. Reports5 fitting targets and9 independent check targets, stage and elapsed
time; successful candidate still requires setup review/binding activation.
Architecture review is complete in ArchitectureReview.md. Existing app/host/MCU
boundaries are appropriate; overlapping native recovery/admission logic is the
main structural hotspot. Incremental reducer/protocol/IO/build-snapshot work is
recommended after a supervised baseline, not an automatic rewrite. Source-hash
manifest coverage and camera-failure clock policy remain documented follow-ups.
Signed0.254 build is running; prepare the candidate offline without replacing
or relaunching the installed application tonight.

November 23 — signed candidate and pushed checkpoints ready for tomorrow
Full optimized Physical Go0.254/build255 build passed; signature verified before
and after copying to gameplay-holding-validation/app-0254-candidate/Physical Go.app.
Source hash c03914ec09b7de194b7ede5707ee266699a9c60dfff2bc1abe882346e5d03a9b;
binary hash 7cdf9b886835d9ddcb6f4e6a4fc371bff0351f9fccc1ea4212fb9387d44bc5f6.
source-manifest.json records160 exact app inputs,117 laser source/test files,
checks and source commits. Source snapshots and unchanged paused-game backup
are beside the candidate. Code checkpoints pushed: app64a1b77 and laser11d3855
on codex/monitored-gameplay-holding. Installed app remains0.253; no relaunch,
serial access, light or motor action performed during this offline closeout.
Tomorrow: restore lighting, install/visually verify candidate preserving game
and clocks, verify camera/grid/setup and finish full laser calibration with
beeps. Final reference/context/binding and production route validation still
precede gameplay; current-point success is not a full-board qualification.

November 23 — user authorizes isolated overnight improvements
After the signed0.254 checkpoint, Dave authorized using the remaining hours for
reversible software work. Separate worktrees/branches preserve appc39e7e0 and
laser6dec0c9 primary code. Workstreams: pure transient-recovery reducer; immutable
build inputs/ownership; mandatory paired contract acceptance; complete calibration
source inventory; optional bounded latency diagnostics; adaptive-map literature
and offline/shadow prototype. Root checklist records branches and validation gates.
Adaptive calibration is item18 (item19 is progress UI); it is now authorized for
advance development, but no live learning/map activation or physical tests.
Each implementation has independent review/targeted tests; full Swift builds are
serialized. Primary installed app, signedcandidate, saved game and hardware are
untouched. Successful experiments remain optional separate candidates until root
reviews evidence; uncertain work must not displace tomorrow's tested baseline.

November 23 — optional integrated0.255 software checkpoint
Paired experimental app939fe27 and host45ed952 on codex/overnight-reviewed-candidate
pass11app suites,344host tests(no skips),69tooling tests(no skips), and mandatory
fresh app→host→app acceptance with exact source/linked-runtime provenance.
A pre-existing fake-device float timestamp race was fixed ONLY in its testfixture;
real parser/firmware rules unchanged. Full0.255/build256 optimized build and
strict signature/source verification passed. Candidate, manifests and snapshots
are in overnight-software-20261123/candidate-0.255.
Sourcehash e63bdbb90964f08cc336e60fff7fdac3190af0412750ff2f0782462913151112;
binaryhash e8057cc4546b8ce3b7f37c58f953d8db0fcfd0912f69353e853ebf3cf391df56.
Not installed/physically tested. Originalsigned0.254 and primaryinstalled0.253
remain unchanged. No physical actions, camera use or firmware upload overnight.
Adaptive core is separate branchcodex/overnight-adaptive-calibration dc03dc9,
35tests and syntheticpositive/negativeaudits pass; currentarchivesquarantined
for missing time-paired settled-pose evidence. Dave's later spatial-distortion
suggestion is extending only thatofflineexperiment with25fit+24edge/interior
validation locations, optional361 and repeatedanchors. No hardwareexecutor or
adaptiveactivation. See OvernightSoftwareResults.md for pairedbranches/rollback.

November 23 — cleared-board distortion campaign reviewed and saved
Adaptive branch f47f36c adds an offline plan/analyzer: 49 locations (25 fit,
24 reserved including8 edges),130 episodes including approaches/anchors; optional
361 locations/832 episodes. First aim before correction and final settled evidence
are separate. Compare motor bias, translation, rotation, affine and local residual;
missing first aims remain failures. Independent review fixed heldout leakage from
misconverged final spots. Total56 author/reviewer tests pass; original adaptive
core/candidate hashes unchanged. Synthetic results do not establish physical gain
or mechanical cause; sparse local learning remains limited. No executor, map
activation, firmware change or hardware/camera use. Separate experimental branch
preserves signed0.254 and optional0.255. Checklist and OvernightSoftwareResults.md
record the final offline checkpoint and later attended comparison requirements.

November 23 — resumed physical setup after equipment movement
Dave restored lights and confirmed empty board, camera and pointer both moved,
and physical power on. Correct app camera restarted (0x11000000bda0567); app
remains0.253 with game paused and SHA unchanged. Fresh grid qualified. First
spot-only attempt stopped before light/motor engagement for insufficient printed
boundary evidence; full OFF confirmed. A fresh second attempt passed: measured
spot near H8/H9, pose1973/2213, seven-frame consensus, final full OFF without
controller fault. Dave confirmed seeing the spot and hearing the beep.
Dave explicitly requested automatic continuation after leaving. Root owns one
finite600-second full calibration using reviewed host45ed952 with existing
camera/motion/thermal guards, no automatic fault retries or binding activation.
This updates the earlier attended-only operating plan for this specific run;
physical prerequisites were checked with Dave. Artifacts: session directory
calibration-resume-20261123, including authorization.json and full-calibration-01.
Do not open a competing serial client. Full-run result will follow.

November 23 — automatic calibration stopped cleanly at target time limit
full-calibration-01 (reviewed host45ed952, installed app0.253) completed37 spot
measurements and37 staged A/B prelight admissions. K10 passed1.5625px and A19
2.7839px. T19 exhausted its120-second target correction budget after21 moves;
last spot reached the intermediate inset[15.9992,1.9603], before the final corner.
Confirmed full OFF1795463029.7635274, controller_error null, no supervisor fault,
source inventories unchanged, peak temperatures14/15°C. No model/binding created.
Game SHA remains6ca3728c88fa9fc7aeba9675715543a1b02f37dafd5b134daa9ebeec8a972f09.
Near-edge40px step caps led to repeated approximately one-intersection moves;
full correction cycles cost roughly5–6seconds. Each target's120seconds includes
both inset waypoints and its final corner. Later fine adjustments also added
cycles. This is a route/budget/convergence issue, not the previous stale-prelight
failure or a reported motor fault. A analysis median0.223s; B proof0.121s;
SWEEP command roundtrip0.119s (not optical latency). All raw evidence retained.
Next: offline interior-route and intermediate-waypoint accuracy review without
weakening final3px checks or motor/camera safeguards. No unattended automatic
retry. Saved summary: calibration-resume-20261123/run-summary.json. Full calibration
and independent nine-target validation still required before gameplay.

November 23 — explicit longer experimental allowance ready, not run
Dave asked to retry without the two-minute target timer, then authorized beyond
30minutes while away for a couplehours, explicitly excluding ordinary runs.
Separate branch codex/calibration-experiment-budget commitfaa2230 adds
--experimental-long-run --seconds7200 --target-seconds0. Normal defaults600/120
and whole-run maximum900 unchanged. The flag gates two-hour whole-run maximum
and disabled target timer.35corrections/stage, accuracy and all camera/hand/motor/
thermal/command/heartbeat limits and OFF cleanup remain unchanged. Exact options
are recorded in result.json. Independent review153tests pass (128calibration,
25dark), mocked fullrunner default/experimental reportforwarding verified; source
SHA8bf34fea10cef6bb45cebd32209d58f9f0cb111b1b7c6c6be64bd8dd5790fbdd.
No new hardware command or retry performed. Last spot[15.9992,1.9603] is outside
the unchanged initial[2,16] margin. Dave was asked to switch physical power off,
coarsely re-aim toward center, restore power and confirm ifstillpresent; reply
pending. If alreadygone, keep hardwareOFF and wait for physical setup correction.
Do not weaken initialmargin, use oldmap, or repeatedlyretryborderlineobservations.
Review evidence saved in calibration-resume-20261123/experiment-budget-review.json.

November 23 — longer experimental calibration started after re-aim
Dave said Try now. Correct camera/clear aligned fresh broker and paused OFF lease
verified; game SHA unchanged. initial-spot-03 measured[8.7775,8.9375] nearK10,
comfortably within initialmargin, and finished fullOFF1795463663.4061315 without
fault. Started full-calibration-02 on reviewedfaa2230 with explicit experimental
7200-second overall allowance,target timerdisabled,35corrections/stage and all
safety unchanged. Root solehardwareowner; no competingserialclient. Result follows.

November 23 — extended run stopped on image match; shadow hypothesis supported
full-calibration-02 used reviewedfaa2230 with7200whole-run,target0 explicitly
recorded. K10 passed2.9017px, A19 passed2.2654px,14spot measurements. Next
measurement raised LaserOpticalFault: Unreliable board registration texture match.
Full OFF1795463793.625718 confirmed without controller/supervisor fault; source
inventory unchanged, no candidate/binding activated. Saved game unchanged.
Dave reported moving near the board and suggested a shadow. The exact rejected
five-frame median and newestcontributingframe metadata were preserved. Root
replayed the actual registrar offline without changing its thresholds: firstECC
0.9197929, localized-mask retry0.9477494 below0.95. Rejectedfit estimated corner
motion0.102–0.203px; median brightness changes on0..255scale were topLeft-4,
topRight-2,bottomLeft-8,bottomRight-3. Reference/rejected comparison and report
are consistent with local lighting/shadow, not proof of cause or acceptedgeometry.
The app's newestmetadata indicated aligned/handclear; a person outsideboard need
not sethandflag. No threshold or hardware change. Proposed follow-up: bounded
beam-off waiting and fresh requalification before resuming after temporarylighting,
rather than aborting all calibrationprogress. Currentcode still aborts. Evidence:
full-calibration-02/shadow-diagnosis.json and ../full-calibration-02-summary.json.

November 23 — distinguish smooth illumination from localized changes
Dave proposed lower significance for gentle changes over a large area, versus
waiting for localized stone/hand-scale changes. Current registrar compensates a
global gain/offset and masks some localized residuals but still gates globalECC.
Root offline diagnostic fitted a robust quadratic log-gain field in rectified
board coordinates, with no spatialwarp fit: saved rejectedmedian correlation
0.9578→0.9762, gradientcorrelation0.9800. Syntheticgentleillumination normalized;
stone/ellipseocclusion/5pxgridshift retained changes. Smallstone retained a high
wholeboard score, so localshape/edge/gridvisibility evidence is necessary;
residualarea alone is insufficient. These diagnostic scores differ from liveECC.
No production code/threshold/activation changed, no hardware commands. Proposed
architecture separates geometry, smoothlighting and localizedforeground, followed
by bounded darkwait/requalification for ambiguous views. DiagnosticJSON retained
at full-calibration-02/lighting-separation-diagnostic.json. Not a validated classifier.

November 23 — delegated scene-change study; current-point recheck
Dave explicitly requested another agent to classify/detect relevant scene changes,
including historical data, while root continues calibration. scene_change_detection
is assigned offline historical recordings, source review, diagnostic prototype and
negative controls in an isolated worktree; no hardware/live source changes.
Root initial-spot-04 passed onboard observation at[1.95675,1.83198] but failed the
initial[2,16] interior-margin prerequisite. Full OFF1795464228.406652 confirmed
without controller fault. Re-aim towardcenter withphysicalpoweroff requested if
Dave stillpresent; no fullrun or repeatedborderline retry started. History study
continues independently. Correct camera/epoch/clearance/pausedOFFlease verified.

November 23 — measured-pose recenter implemented, reviewed and physically passed
Dave suggested small automaticinward movement and recalling measuredK10motorpose.
Separate branch codex/calibration-recenter commit8fd0630 adds explicit preparation:
fresh dual-reference/pose/spot qualification, K10direction, max8darksteps <=8pan/
5tiltcounts with5pxprintedboard clearance, remeasure each, stop inside[3,15].
Independent179tests pass withoutskips, including partialfailure/fullOFFcleanup.
Physical recenter-01 passed8steps/9observations fromnearcorner to[3.05686,3.09366],
pose1853/2364, freshanchor residual1.9439px and recent-spotresidual0.6520px.
Full OFF1795465128.0599422 confirmed nofault; inventoriesunchanged. No map/binding.
Root then started full-calibration-03 fromthe verifiedinterior with7200seconds,
targettimer0 and allotherguardsunchanged. Root solehardwareowner; result follows.
Sceneagent completed16historicalcomparison study andedgefollowup; separateoffline
branch, no classifier activation or live threshold change.

November 23 — full calibration stopped on camera evidence age; appearance study active
full-calibration-03 used reviewed host8fd0630 and the explicit7200-second overall,
target0 experiment. K10 passed2.44693px, A19 passed2.73264px;17 measurements.
The supervision thread raised External evidence permit expired, then set the
shared cancellation event. Thus the top-level Commissioning cancelled message
was a consequence, not evidence of a user cancellation. Last successful poll
saw frame26550 aged0.582566s, with only17.434ms of evidence lifetime remaining;
next poll saw0.615428s, beyond0.6s. The final poll gap was30.693ms, maximum
recorded gap86.186ms. Full OFF1795465259.8695755 confirmed, no controller fault,
source hashes unchanged, game SHA unchanged. No map/binding activated.
architecture_review owns an offline assessment of safe full-OFF pause/fresh
requalification with progress preservation. No live timing checks weakened.
At Dave's explicit request, intersection_appearance is reviewing per-intersection
empty/black/white evidence and historical coverage, first avoiding duplication of
BoardVision empty-reference and inspector-only StoneAppearanceModel features.
Hardware OFF notice sent before agent starts heavier historical replay.
Scene-change edge follow-up a7286f7 pushed, eight tests pass; complementary edge
and local texture evidence remains diagnostic only. Root remains hardware owner.

November 23 — explicit camera-age override and confidence requirement
Dave clarified the stationary experimental run should not use the0.6-second
camera age cutoff, then emphasized that repeated run-ending delays are unacceptable.
calibration_readiness owns a separate experimental age override; architecture_review
independently reviews all age paths. fast_calibration owns separate full-OFF recovery
with preserved progress and fresh actual pose/spot; interruptedcommands are not
replayed. These remain in progress, no hardware activated. Planned explicit10s
camera allowance is distinct from unchanged leases/heartbeat/thermal protections
and increases possible unseen-hand delay. Normal defaults remain unchanged.
Appearance report and reproducible144-sample audit integrated as8212400; root
independent replay agrees. Dave requests per-intersection confidence in addition
to black/white/empty/uncertain for downstream fusion. Agent is adding class scores,
confidence semantics/calibration status and correlated-source provenance.

November 23 — experimental camera-age policy physically exercised
Host98a2fb6 oncodex/calibration-experiment-camera-age explicitly propagates
--experimental-camera-max-age-seconds10 through metadata/permit and alloptical
readers/admission paths, gated by--experimental-long-run.219targeted checks pass,
independent failure-snapshot replay passes; normal0.6sdefaults unchanged.
Root initial-spot-05 used explicit10s and passed: pose1813/2406, spotboard
[1.16140,1.02257], fullOFF1795466083.6103785, nofaults, sourcehashesunchanged.
Largest observedcameraage0.3674s, so this short physicalrun didnot itself exercise
an over600ms frame; that case was covered by replay/tests. The actualpose matches
the last accepted sample, not the interrupted TTO2396 command. It remainswithin
5pan/3tiltcounts ofa cleanrun02anchor, allowing existing fresh requalification.
A boundedexperimental16-step recenter allowance is being reviewed because this
start isfartherfromcenter thanprevious8-step run; per-step movement andfresh
opticalchecks unchanged. HardwareOFF whilecode isprepared. No fullmap yet.
Confidence contract followup integrated as5b30e0d; design/example only,no liveAPI.

November 23 — recenter02 passed; full-calibration04 active
Reviewed424f3a5 adds explicit experimental16-step allowance (default8), independent
review+171calibrationtests pass. Physicalrecenter02 passed12steps, finalpose
1853/2364, board[3.05908,3.08168], cleanfullOFF1795466437.5372622; sourceinventory
unchanged. Maximumguardcameraage0.371s, noover600msobservations. Rootthenstarted
full-calibration04 fromverifiedinterior, explicitcameraage10s/run7200s/target0.
Rootsolehardwareowner; otheragentsheavytests paused. Resultwillfollow.

November 23 — all fit targets passed; independent cache watchdog stopped validation
Full-calibration04 host424f3a5 usedcamera10s/run7200s/target0 for702.277seconds.
106samples; all5fit targets passed K10=2.21,A19=1.76,T19=2.31,T1=2.58,A1=2.86px.
Firstvalidationlegstopped on250ms polling-cache expiry, notcameraage. Pre-gap
poll finished1905175.957824, cachedeadline1905176.207824; nextpoll started
1905176.279739, firstOFF.279812. Appleasewasvalidto1905176.528499; oldcamera
snapshotstill~0.516sold atOFF. Newpollreturnedfreshframe45622,age0.223s.
Supervisorlatchedcancelbeforethatfreshpollcompleted. FullOFF1795467167.9429295,
no controllerfault, sourcehashesunchanged. Cameraage max0.5376, temperaturesmax
15/17C. Concurrentserial/HB/thermalgap suggests sharedprocessscheduling, not
proof oftheblockingfunction. Offlineinvestigation andprogressrecovery assigned.
Root fitted95fit-stagesamples offline: median2.493/p955.188motorcounts, saved
fit-only-candidate.json SHA1b083a14534d79d45ad23c5dd35109bb667e5cb2fb2d5641789e9e47cbfaa7e9.
Unvalidated: no held-outtargetscomplete, no activebinding. Recoverymust freshly
measure actualPOSE/spot; lastsample1679/2243 preceded settleddarkmove1726/2272.
Do notreplayorassume commandedpose. Allninevalidationchecks remain. HardwareOFF.
Speedproposal andtimingreport preserved; exactstagecosts do notestablishspeedup.

November 23 — reviewed validation-only recovery started; fresh admission passed
Host983ef924 reviewedandpushed;194calibrationchecks(1optionalfixturegroupskipped),
25darkchecks;independent31focusedactual03/04tests passwithoutskips. Rootstarted
validation-resume01 with2boundedprocessrestarts,10scameraage,7200soverall,target0.
Fresh originalreferencegeometrypassed. Actualpose1726/2272,spot[2.00797,9.15147].
LocalJresidual6.608pxfailed3pxbranch; explicitfixedmodelconsistency passed3.386
motorcounts(<8). CandidateSHAunchanged; firstfreshcheckpoint/travelstarted.
All5fit targetsretained; all9validationtargetsnewlyrequired. Rootsolehardwareowner.
Schedulingprobesfinishedoffline: normalimageoperationsgaps<40ms,forcedGC<47ms;
largeFINALreportencoding350msgap excludedaslivecause becauseafterOFF. Exactcause
unproven; phase/CPU/loopgap/GCdiagnosticrecommendations archived. GameSHAunchanged.

November 23 — validation continuation stopped on spot detection; steering gap identified
validation-resume01 attempt000 passedfreshgeometry/model-positionadmission, then
observed1728/2275 at[1.99883,9.00813]. NextA10movecommand1626/2323 settled1625/2321;
fiveandsevenframes returnedSpotUnreliable Ambiguousspot. Detectorwordingincludes
zerocandidates; itdoesnotnecessarilymeanmultiplebrightspots. FullOFF1795468415.5879025,
no supervisor/controllerfault; inventoriesunchanged. Rawfailedimageswerenotsaved;
brokercontributors58056/58084expiredbeforeinspection. Original5fit targets preserved.
Offlinefixedmodelinversepredictsactualfailedposeat[-1.1257,8.1610], outsideboardmask;
64.49pxfromlocalprediction. Thisishypothesis,notphysicalobservation. KeepbeamOFF.
ReviewfoundglobalpositionadmissionretainedoldlocalJacobianforsteering; onetiny
combinedaxisupdatecannotindependentlyvalidatebothaxes. Earlierreviewmissedthisgap.
Separateauthorspreparerevieweddark-onlyreturnto1728/2275, independentaxisprobe+
finiteendpointagreementchecks, andfailedimagebufferflushedonlyafterconfirmedOFF.
Daveadditionallyrequestslarge-movelandingexperiments; adaptiveagentownsdata-only
bidirectional/distance/diagonal/repeat/heldouttransitionplan, firstlandingbeforecorrection.

November 23 — dark return passed; combined steering review and large-move plan
The reviewed dark-only return (host65e5fd4) moved actual1625/2321 toward the last
observed1728/2275 and settled1728/2277. Exactly one GOTO, no illumination, clean
full OFF1795469498.7246559. Return report SHA256:
30c491901017fcb67243f52f9c00aaf9a25aa4c56bc03aa4c8b0a9442cba2fbf.
Fresh optical/two-axis qualification remains mandatory before further travel.
Combined steering and failed-image retention atbc713f8 passed independent code
review. Focused93-test integration run has3 errors from outdated MagicMock
collector returns; tests are being corrected to the real collector contract.
Runtime guards are not being weakened. Failed images will be buffered in memory
and flushed only after full OFF and worker shutdown. No new physical run yet.
Large-move first-landing protocol86bf0b9 is pushed: fixed camera, six-move pilot,
then optional distance/direction/diagonal/repeat/held-out transition campaign.
It is a proposal, not an executor or physical validation. Root owns hardware.

November 23 — steering probes passed physically; small-step profile mismatch found
Combined source6cf3c99 is pushed;93 focused tests pass without skips after test-only
mock repairs. validation-resume02 freshly admitted actual1728/2277 and qualified
both axes: candidate displacement errors1.207/2.154px. Guarded A10 approach then
shrunk to4pan/2tiltcounts while still selecting fast GOTO from the originalpixel
error. Repeated actual1720/2274 observations demonstrated no useful progress;
profile selection needs to use final guarded movement size and recheck fine-axis
intermediates. Separate supervisor LaserTransportFault serial write completion
exceeded deadline stopped the run. FullOFF1795470112.9394574, no controllerfault,
source inventory unchanged; parent reapedexit1.123 totalsamples, no validation
target completed. Automatic retry correctly refused the transport failure.
ReportSHA4f5c7dc44dad52a9f42fd390e879e9b6b9f8f2aae42a860c6a6dc2918d1b5589.
Fast-calibration agent owns isolated profile fix; transport reviewer investigates
actualdeadline evidence offline. No new hardware attempt pending those findings.

November 23 — reviewed fine dispatch repair and existing move coverage
Reviewed small-step source91df4a7 integrated and pushed as0e7434a. Four targeted
and51 existing checks passed; independent four-case review passed. Final guarded
steps within the existing18/10count fine envelope usePTO/TTO, with fine-axis
intermediate path checks repeated. No accuracy/deadline/step-limit relaxation.
Not physically retested. Offline move audit found largest measured opticalinterval
2.965intersections in full04 fitting,2.548 in validation; intervals can contain
multiple commands. Thus no long-jump validation exists. Smallest nextpilot is one
qualified interior2–3intersection span in both directions, firstlanding preserved.
Transport review infers lateTA769 reachedfirmware becauseGT770 acknowledges769;
failedwriteitself wasnotrecorded. Overlapping137.9ms permitread window supports
hostdelay aspossible, notprovenUSBblocking. Bounded diagnostic patch underreview.
Hardware fullyOFF, serialportunowned, savedgameSHAunchanged. Caffeinate stopped.

November 23 — follow-up software checkpoint complete; hardware remains OFF
Bounded serial-write diagnostics6dd292b integrated asbbc7f72 alongside small-step
fix0e7434a. Final combined112 tests pass with no skips after the optical shutdown
mock gained the real snapshot return contract. Diagnostics preserve the100ms
write deadline and transport behavior, retain64 in-memory records including
failedcommand/bytecounts/observed timing windows, and serialize afterOFF/close.
Independent review passed; optionalCPU instrumentation was removed. No further
physical retry: small-step repair and diagnostics remain offline-tested only.
Serial-delay cause unresolved; no automatic transport retry enabled. Remaining
physical work is fresh qualification and allnine validation targets, then the
short bidirectional first-landing pilot before expanding distance. Root owns
hardware; laser and motor power fullyOFF, port closed, game/clocks preserved.

November 23 — requested large-move restart and timeout investigation
Dave explicitly requested resuming the larger-move experiment and diagnosing the
previous timeout. Correct broker camera is fresh, empty board visually inspected,
no hand and aligned; original stream epoch persists, saved game SHA unchanged.
Root OFF-only serial probe01 passed96 STATUS replies in15seconds; worst reply
2.356ms. Only STATUS/HB/OFF permitted, no torque/light requested. Final fullOFF
1795471865.586275, no controller/cleanup fault. No large movement yet.
Offline exact steering replay:1000 calls max4.53ms;50 reconstructed checkpoints
max42.70ms; no100ms simulated write failure. Original failure remains a host-side
100ms completion check, likely thermal ACK769 which firmware received. Evidence
does not identify USB blocking versus scheduling. Bounded diagnostics are ready.
Pilot author and independent reviewer are preparing explicit SHA-bound manual
restart, fresh pose/spot/two-axis checks and conservative interior out/back moves.
Ordinary3px linear-response agreement inherently shrinks curved-map large moves;
separate named diagnostic proposal uses[3,15] interior predictions/path,25px
maximum model disagreement and unchanged108/58 motor envelope. No automatic
transport retry, model training or calibration/binding approval is implied.

November 23 — interior pilot01 physical result: separate poll-cache expiry
Host5b3880d passed9 independent actual-artifact tests and51 existing tests, then
root ran interior-pilot01. Fresh camera/geometry/pose/spot admission passed;
position residual0.09527px, model residual2.241motorcounts. PTO1728 began but no
SETTLED was received. Poll-cache expiry caused fullOFF1795472563.6018767 with
no controllerfault and unchanged source inventory. Last telemetry1720/2274;
actual next pose must be queried before any illumination. One new opticalsample,
no completed steering probes or diagnostic legs. Parent exit1 reaped.
Last successfulpoll finished1910571.718266666, cachedeadline.968266666. Nextread
started.745209166 andfinished.973832541:228.623ms read/UTF8/JSON interval, BEFORE
validatorwork; totalrefreshgap255.566ms. Cameraage.411s andleasevaliduntil
1910572.297; firstOFF.97301625. SerialHB/TA continued and diagnosticsrecorded no
failedwrites. This differs from prior100ms serialcompletionfailure.
Root is preparing an explicit0.5s stationary cache allowance, preservingminof
camera/lease/run deadlines and immediate invalid-evidence revocation; normal
0.25s default unchanged. Passive per-read-stage profiling runs withhardwareOFF.
Earlier timeout replay and safe checkpoint copy removalce1b36b are pushed;
optimization not merged into pilot and not claimed to fix the original timeout.
Systemlog shows the same OpenRB request-abort message near both failed-run and
successful-OFF-probe shutdown, so that message alone is not evidence of a USB cause.

November 23 — workflow timing model delegated; pilot02 stopped before light
Dave requested a separate agent to model the whole workflow and relevant timing
options, then generate a timestamp/event data structure. workflow_timing_model
owns an isolated offline model/generator/schema/coverage inventory. Root continues
physical work; no runtime changes or hardware access delegated to that agent.
Pilot02 on9841f0 with explicit0.5s cache ended before illumination: measuredPOSE
1725/2274 exceeded the saved1720/2274 anchor's3-count start envelope. This confirms
partial movement from the interrupted first probe. No PREPARE/SWEEP writes, clean
fullOFF1795472997.1711957, no controller/supervisor fault, sources unchanged.
A narrow explicit dark-return-to-anchor option is being prepared/reviewed for
this5-count difference, within8/5counts, using provisional candidate bounds and
ordinarypath/settlement checks. No light until returned within3counts, followed
by fresh optical admission and two independent probes. Default rejection remains.

November 23 — workflow timing contract complete; interior pilot resumed
Pushed/reviewed7737129 provides64 workflow stages across eight parallel lanes,
37 timing options, generated event schema/selected-path plans, legacy inventory
and20 passing tests. No runtime instrumentation enabled or timing policy changed.
Distinct clocks, requested/settled/measured positions, image acquisition, sound
dispatch/onset, fault origin and OFF/close/persistence boundaries are explicit.
Pilot03 on3202fe3 reached interior without timing/serial faults; stopped before
second interior probe because the actual first-probe pose drifted one count,
requiring nine counts to return to baseline against the eight-count cap. Latest
observed1828/2257 at board[4.12182,8.94954];134 samples preserved, fullOFF
1795473507.3676848, no controllerfault and unchanged sources.
Reviewed/pushed094ddfd clips that return to the unchanged eight-count cap and
preserves the latest clean observed anchor separately from the inherited123
checkpoint. Six independent actual-recording tests and relevant existing checks
passed. Root launched pilot04 from that interior anchor, with explicit10s camera
age/0.5s cache,7200s finite limit and attention beep. No automatic retry; fixed
95-fit model and all nine pending validation targets remain unchanged.

November 23 — pilot04 stopped on measured probe independence, not timing
094ddfd passed fresh geometry/position admission (0.830px). Actual observed
probe poses1828/2257→1836/2257→1829/2254; second target1828/2252 settled
1829/2254. The measured two-axis basis failed its unchanged minimum travel
criterion. No outbound diagnostic leg.137 samples retained, latest board
[4.198813,9.031403]. FullOFF1795474158.026998, no controller/supervisor fault,
no cancellation, source hashes/inventory and savedgameSHAunchanged; exit1 reaped.
ReportSHA416473721b04c8f588125686b2cd8505ed9bcaa120cbf7491296c3b8d5daab10.
Root requested offline design review for bounded additional probing without
weakening measured qualification. Hardware/serial port released, no auto retry.

November 23 — interior pilot05 completed; timing outcomes model reviewed
Pushed44aeb5e passed fresh position/two-axis qualification and exercised one
bounded extra tilt probe. Outbound requested2.5intersections, measured2.322;
return measured2.148. First target misses0.190/0.188intersections, model-at-actual
residual3.700/2.115px, actual motor goal residual(+1,+2)/(−1,−2)counts. Return
optical error7.276px: useful diagnostic, not accuracy approval. No camera-directed
correction/model update;144samples retained. Coarse legs each include normal
secondGOTOactualsettled beforePREPARE, so single_goal is not one wire command.
Host travel-to-light dispatch3.410/3.324s: travel receipt1.241/1.228s, goal-prime
receipt0.625/0.550s, PREPAREreceipt0.568/0.471s, READY-to-light0.965/1.070s.
Lightack0.107/0.137s; these are not physical onset measurements.
Arming captured279.048ms polling gap:159ms request readwindow +94ms manifest
readwindow, JSONonly0.029/0.021ms. Original camera/lease valid; explicit0.5cache
run continued. Exact filesystem/schedulingcause remains unresolved.
FullOFF1795474672.1551886, no controller/supervisorfault/cancellation, source
inventories and game/clocks unchanged; exit0 reaped. Latest actual1820/2248 at
board[4.169881,9.453444], maxreportedtemps14/14C. Caffeinate stopped/reaped.
ReportSHA034883c595c2f4a6fc4cc66f974b233e2535de3e8e290799a54428a66ea2356c.
Allnine fullboard validation targets remain; no bindingactive.
Workflow followupa4867ea pushed: seven outcome definitions added,23 tests and
independent review pass. Missing acceptance/exposure/onset/correlation/clock
evidence remains explicit. No runtime adapter or timeout changes enabled.

November 23 — pending software work and workflow efficiency review started
Dave authorized beginning the pending work and reviewing whether the workflow
is efficient. Five offline owners: latency_logging adds schema-aligned bounded
host events; workflow_timing_model imports/audits existing reports; transport_review
measures the file-reading path; fast_calibration prepares explicit fresh manual
validation from completed-pilot evidence; architecture_review independently
examines dependencies, repeated work and speed/reliability tradeoffs.
Root created codex/workflow-review-integration at44aeb5e plus reviewed model
commits7737129/a4867ea (integration equivalents ea205f9/277a59d). No hardware
operations, installed app/firmware changes or game/clock/binding mutations.
All software changes require focused tests and independent review before merge
into the isolated candidate. Physical validation is a later separate step.

November 23 — attended manual validation started
Dave is at the board and confirmed nothing moved and beam area clear. Root alone
started manual-validation-01 on independently reviewed standalone bed3c52 from
pilot05 SHA034883c595c2f4a6fc4cc66f974b233e2535de3e8e290799a54428a66ea2356c.
Explicit10s camera age/0.5s poll cache, finite7200s ceiling/no target elapsed cap,
attention beep; user-facing budget one10–20min attempt then stone-placement test.
Fresh optical correspondence0.673px and fresh steering qualified; validation in
progress, no binding activation. Merged f9101f2 not used because aggregate tests
reported errors requiring diagnosis. Installed0.253/v44 and saved game unchanged.

November 23 — manual-validation-01 stopped on post-settlement prediction guard
Reviewedbed3c52 passed fresh position0.673px and independent steering. Approximately
102s into run, beforeA10, last observed1704/2284 planned1681/2289 with local/fixed
model predicted endpoint disagreement2.143px. Actual coarse settlement1681/2287
remained within firmware tolerance but recheck disagreement3.172089px exceeded3px;
predicted polygon margins50–54px. No optical observation at settled endpoint.
This is not camera age/serial timeout or measured A10 target error.159samples,
allnine validationtargets pending. FullOFF1795478146.9190755, no controller or
supervisorfault, cancellationfalse, sourceinventories/gameSHAunchanged; exit1
reaped and serial released. ReportSHA82b063a6c6e246c24d9b724b1201a79ee441aa2c88a36b9f88eb8a36cdc52b84.
Root switches to attended stone tests. fast_calibration acknowledged offline
settlement-aware planning diagnosis; no hardware ownership transferred.

November 23 — attended stone session: basic recognition passed; ambiguity failed
PhysicalGo0.253/build254, fasttestmode, laser fullyOFF/bridge disabled. Recording
16-32-43/81F57368 captured two explicit hand-overboard/slowwithdrawal cycles;
handtrue→false twice, alignmentvalid, no game moves whilepaused. Resumed humanWhite
game: AI Blackpoint72 accepted exactlyonce. Recording reached per-session5GB
(1552frames), not diskfull (~59GB free). Diagnosticpause script verified images/
warnings off. No tailtrim: recording ended18s after meaningfulplacement.
Paused atmove1, clocks101.293sWhite/11.380sBlack, restarted recording16-37-13/81D4E9F0
with10GB requested (archive allocated5.976GB). Resume verified existingposition
withoutduplicate. White180 and AI Black300 acceptedonce; placement cleared about
0.5–0.7s after handflagclear. Bothrecordings markedKEEP.
Ambiguitytest FAILED: user placedWhite midway between emptyintersections, withdrew,
thenremovedit. Nativeacceptedpoint275 at1795480763.698962 andAIpoint288 at
1795480764.873220. Frame697/time1795480763.128513 retainsclear image; footprint
center[9,14.28], quality0.915, readingWhiteconfidence1, placementFits/tracks empty.
Cause notyetproven; marker_scenarios owns isolated offlineinvestigation.
Firstactiondiagnosticpause script succeeded; thenAIpaused atmove5/pendingBlack.
History/clocks preserved, pre-failure3move snapshot saved; do notresumeagainst
physical3stoneboard without deliberate recovery. Secondrecording stopped795frames/
2.571GB; no redundant30s tail. No physicalcapture/laserwigglepass claimed.
FastAI review: bothsearches8visits. AfterPause/Resume boardrecheck0.793s+engine/
presentation8.253s=9.047s; nextuninterruptedmove0.796+0.378=1.174s. Workerstop
onpause explains likelycoldrestart; exactload/searchsplit notlogged. No AIchange.
Evidence: work/ai-laser-integration/stone-session-20261123/session-result.json and
ambiguity-failure/ beneath /Users/dave/Documents/SGF PLayer.

November 23 — clarify ambiguity failure and preliminary cause
Dave clarified: WHITE color classification was correct; assigning the stone to
an intersection was incorrect. Expected behavior is spatial abstention until
centered, regardless of laserhint toggle. Agent preliminaryread: measuredoffset
0.28 is below hardambiguity0.30; neighboring294wasuncertain but borrowed prior
verifiedEMPTY, permittingstable singleWhite275acceptance. LegitimateWhite180also
measured0.28offset, so simplyloweringthreshold is not a justified fix.
marker_scenarios owns targeted neighbor-evidence investigation; contract_review
is assigned independent review. No production/installed change yet.

November 23 — ambiguity candidate and stone-set samples
Reviewednarrowfixappliedtoinstalledbaselined5d84ef with exactoriginalsourceSHAce241953.
Candidate347eb84/0.256build257 passes52newambiguitychecks andfive selectedsuites
(80markers,146lifecycle+realengines,278AI-laser,37capture-controller). Signedbuilt
sourceSHAd9c8b08cb2418b1e726ddf3a75d5f122b8dbb35f763b7506cd64d119498fd0b2;
binarySHA7da38ad7520813714ea9192a1844f65f3a232680833fce8b0dfa1c23961aa488.
Capture directorypreserved. Notinstalledyet; cameraidentityretainedforstone-set
sampling. No parallax/markerthresholdchange inthisguardfix.
Userofferedcenteredstones andnamedreusablestone-setprofiles withoptionalmanual
thickness. Collectedwhite-01 andblack-01:8outerstarstones,8rawbrokerPNG/manifests
each, freshclearaligned,pausedOFFrequests,nohardwarecommands,gameSHAunchanged.
An earliermistakenBlackreadinesswasWhite; visuallycaught,userconfirmed,renamed
white-repeat-01 withexplicitcorrectionaudit. Unknownphysicalscale/effectiveoptical
height remain distinctfrommeasuredphysicalthickness. Sameboardcalibrationunchanged.
November16parallaxexperimentwasneverinstalled; priorfreefitexcusedrealmisplacement.
Currentanalysisdistinguishesbody/contactparallax fromadditionalfitter-to-bodybias
(~.11cell,4–5px inframe697). intersection_appearance handlesofflinefit/heldouts;
calibration_progress_ui preparesisolatedprofilemodel/UI withoutfakeapplication.

November 23 — offline work completed while awaiting final physical negative

Dave is away approximately 20 minutes. Current app remains 0.253/build254, paused
at five moves/pending AI Black; physical board holds eight Black outer-star
calibration stones. No Resume against that mismatch. Original three-move and
failed five-move states/clocks are preserved. Hardware remains fully OFF since
1795478146.9190755; no later commands. App bridge setting is now ON solely for
passive camera broker sampling and OFF requests; production bridge remains
stopped. This supersedes the earlier bridge-disabled/three-stone physical state.
Diagnostic recordings/warnings remain OFF. Narrow signed 0.256 is deliberately
not installed until the final same-camera negative photo is captured.

Combined laser candidate codex/workflow-review-integration is pushed at42e5022
(runtime3498fb2). All183 host/calibration/workflow and38 model/importer tests pass.
Earlier aggregate failures were missing diagnostic-snapshot methods in test
permits; test-only fixes796dd49/3498fb2 restore the actual permit interface.
Includes reviewed immutable-source registration reuse, fresh manual validation,
DARK-before-image-persistence, read diagnostics and optional bounded native
workflow tracing. OFF/cleanup precedes deferred persistence. Tracing defaults
OFF. No hardware execution or claim that this fixes the steering disagreement.

Settlement study codex/calibration-settlement-admission is pushed927b63b. Existing
samples poorly constrain the second motor direction. Better rolling fits reduce
the observed endpoint disagreement but still fail the full settlement-region
checks. Reviewed offline protocol proposes17 fitting observations plus4 independent
checks with unchanged movement/agreement limits and separately qualified probe
corridors. Eight deterministic tests pass; synthetic feasibility is not physical
reliability. No executor or production change; allnine accuracy targets remain.

Stone study codex/stone-set-profile-study pushed8f692b3, independent reviewc7286b1:
six-fit/two-held-out anchors per color, three geometry hypotheses retained, six
analytic controls and34 producer-to-native profile checks pass. Estimated optical
height is setup/estimator-specific, not physical thickness. Constant contour bias
and grid scale can imitate height; the existing White midpoint informed development
and is not an independent negative. Fresh Black midpoint and another setup remain
pending. Named set UI/store codex/stone-set-profiles pushedbf241bc,34 author/15
independent checks and SwiftUI typecheck pass; no hosted UI or runtime activation.
Optional measured Black/White thickness is separate from optical candidates.

White-vote diagnosis independently reviewed/pushede6a6e85 on
codex/white-vote-mask-diagnostic. All8 source hashes,4 archived footprints,8,450
pixel votes and full discrete optimizer searches reproduce. In the centered180
and misplaced275 White stones, relative-color core support is zero; the brightness
fallback favors the upper body and disk/ring objective selects that region.
Native minus visible-body row discrepancies are -0.10809/-0.10988. This verifies
estimator disagreement on two examples, not the physical cause of brightness,
contact-point ground truth, physical thickness or a universal correction.
Next bounded geometry work should expose full-boundary evidence, coverage,
neighbor ownership, disagreement and abstention separately from classification;
frozen centered/midpoint/shadow/crowd/empty/hand examples and another setup precede
any runtime consumer. No global threshold reduction or constant offset justified.

Optional fast-test idle reuse codex/fast-test-idle-reuse pushed8c142a2, based on
narrow347eb84. It retains only a completed idle fast-test engine through ordinary
Pause/Resume/Freeze, revalidates launch assets, cancels active search and fences
late results from replacement work. End/settings/fault/shutdown release it. Tradeoff:
model memory remains resident during pause.42 targeted checks (23 independent),
8 build-registry checks and requested debug regressions all pass: AI-play162
including real engines/HumanSL, AI-laser278, ambiguity52. No installed change,
physical speed claim or mutation of the signed0.256 candidate.

Next attended action: front-middle Black from raw(9,15) halfway toward center to
(9,14.5), otherseven unchanged, capture against frozen six-anchor model. Optional
fresh White at the same halfway location would provide a development-independent
White negative. Then install narrow0.256 and deliberately recover the three-move
checkpoint/physical position for ambiguity and capture tests. Laser work remains
separate and requires empty board/setup verification before requalification.

November 23 — fresh Black and White misplaced examples captured

Dave returned briefly and moved the nearest-side middle Black toward board center,
then replaced it with White at the same intended position. Root saved eight fresh
broker images per episode under stone-session-20261123/stone-set-calibration/
black-midpoint-01 and white-midpoint-01. Maximum capture ages0.233/0.246seconds;
same camera ID, epoch and context as centered samples; all clear/aligned, app OFF
requests, AI game-file inventories byte-identical before/after. No hardware commands.
Visual confirmation: seven centered Black stones, one moved stone, then White.

The user sits at camera-image right. Root's nearest-you instruction therefore
moved raw(15,9) toward(14.5,9), not image-bottom raw(9,15). Independent body analysis
confirmed Black center14.9991,8.9025→14.5727,8.9111 (~0.426columns left); intended
held-out bottom-middle remained essentially unchanged. Corrected samples.json
preserves original instruction and explicitly identifies actual location. Images
and frame metadata remain unchanged. These are fresh negative episodes at a
previously fitted anchor, not a preselected held-out-location test. Neither is
included in training. Frozen Black/White model evaluation delegated offline.

Physical board now seven centered Black plus displaced White near(14.5,9); app
still paused at failed five-move game/pending AI Black. Do not Resume that mismatch.
Both requested photos are complete, allowing later narrow0.256 installation;
not installed during collection. Dave can step away; laser remains fully OFF.

Frozen-model follow-up: exact current-grid equality check detected a small
automatic grid update despite identical epoch/context. Seven unchanged exposed
crossings measured maximum0.462px Black/0.535px White displacement; residuals
after estimating common shift were0.187/0.176px. No common shift is applied to
stone pixels: bodies are explicitly mapped through raw image coordinates into
the frozen grids. Original metadata, estimator thresholds and model coefficients
are preserved; <=0.54px view uncertainty remains explicit.
Across eight frames per episode, conditional nearest-crossing median distances
are Black0.434cells(native grid)/0.461(refined grid), White0.484/0.488. Both retain
substantial displacement after correction. This supports these two fresh negative
episodes only, not physical thickness, independent-setup portability, calibrated
confidence, or installed-app acceptance. No model training or live activation.
Results: stone-set-calibration/offline-body-study-02/fresh-midpoint-results.json.

November 23 — further offline work completed during Dave's absence

User requested useful work while away and explicitly said proceed. Hardware and
live state were left untouched. Final preservation audit: installed0.253/build254,
all AI game-file hashes equal the saved White-negative inventory, app bridge
requestOFF. Physical board remains seven centered Black plus displaced White;
no Resume against five-move logical game. No laser/controller commands issued.

Recommended next test candidate0.257/build258 combines ambiguity347eb84 and
fast-test idle reuse8c142a2. Source/version47dc15b, pushed documentation7edf1b0 on
codex/recognition-fast-test-candidate. Optimized full build and8 registry checks
pass. Prior unchanged feature checks42idle/162AIplay/278AI-laser/52ambiguity pass.
Independent copied-package review verifies strict Developer ID signature, version,
158ordered Swift inputs,4build inputs and173bundle files. Capture directory stays
/Users/Dave/SGFPlayerClean/PhysicalGo/Captures. Frozen read-only artifact:
stone-session-20261123/app-0257-candidate/Physical Go.app. SourceSHA
142bb2374398dbac1df8b445047d703370436ed97aa768c366740d0c4dae4394;
signed binarySHA4b4d8076dd60772f504d771ac9d84d43604178fce480ed189430086e376cf5af.
Not installed/launched. Installed0.253 and retained signed0.256 remain unchanged.
No optical profile, boundary experiment or broader0.254/0.255 changes included.

Fresh negative optical study7c9f57c independently reviewed/pushed201a258 on
codex/fresh-midpoint-review. Full replay exactly matches;16 frame source/metadata/
model checks, coordinate inverses and rejected hash/epoch controls pass. These
are new negative episodes at previously fitted(15,9), not heldout/new setup.

Boundary diagnosticb4184d5, review4c958ce, both pushed on separate branches.
29cases and numeric policy frozen at738f2d7 before replay; later setup grouping/
auxiliary-hash metadata corrections preserve original selections and all numeric
outputs.7 mechanism controls and exact29-case independent replay pass. Evidence
schema separates outline, coverage, neighboring-owner exclusions, compact-fit
discrepancy, angular-deletion sensitivity and abstention. Every output says
runtimeDisposition=diagnosticOnly,boundaryIdentity=stoneVersusShadowUnverified.
Reason to withhold production: shadows can pass geometric support. Independent
stone+shadow control has100percent coverage but0.118cell center error with<0.015
quadrant spread; round dark nonstone also passes.5of9 current Black cases abstain
under fixed radius bound. Supported outline is not identified body/contact truth.
No threshold tuning on fresh negatives, classifier/model change or live consumer.

Root native replay46b9cdd pushed on codex/fresh-negative-native-replay. Unchanged
BoardDetector closure from347eb84 reproduces actual archived697 fourfootprints
and zeroplacementFits exactly, then replays32 centered/freshnegative images.
Eight independent input/parity integrity controls pass; all source/input hashes
unchanged. ReferencePNG exactly equals both current persisted snapshot and prior
backup (SHAcdc8d10f006fe81fec510f06ab212a75e6b39e412e7d14cdddcf9f0b70a4c268).
Threshold explicitly archived0.13; freshbrokerlacks threshold/referenceimagehash,
so no per-frame in-memory-reference claim. Currentgrid is passed perframe.
At rawside-middle: centeredBlack fit(15,8.96), centeredWhite(15,8.76). FreshBlack
fit(14.56,8.96), Blackat(15,9)score1, neighbor(14,9)uncertain.6875. FreshWhite
both14/15uncertain(.625–.71875/.5625–.59375), no localfootprint/placementfit inall8.
This is stateless detector evidence, not temporaltracking, moveacceptance, clocks
or hintdispatch. Missing footprint explains why abstention does not guarantee a
usable centering-hint target. Full artifacts in stone-set-calibration/native-fresh-replay-01.

Capture kitf0009e9 pushedcodex/attended-capture-kit. Two artifact-only synthetic
four-move humanBlack19x19 fixtures: single A18,A19,T1,C19 then B19 captures A19;
double B19,A19,B18,A18 then A17 captures A19/A18. Fasttestmode true, no fabricated
observed timestamps or verifiedcamera evidence.34 actualSGFrules checks plus20
actualPhysicalAI snapshot/acceptance/capture/clock checks pass. Singleelapsedclock
continues, double/partial holds, out-of-order removal and fullcleanup verified
with synthetic observations. Existing-output/Library destination refusal checks
pass. Short run card and validated-fixtures at work/ai-laser-integration/
attended-capture-kit-20261123. App has no AI SGFimport/fixturepicker; activation
requires separate preserved-state loading transaction. No productiontesthook,
livegamemutation or physicalpass. AIcapture-first guidance and Blackprisoner
surface tests remain outside this kit. Laser tests still require qualification.


## November 23 — consolidated physical-test candidate preparation

At Dave's request, root is assembling 0.258/build 259 from reviewed 0.255
recovery/progress/tracing/build tooling and 0.257 ambiguity/fast-test idle reuse.
Integration source frozen at 9b51d45 also hosts named stone sets and bounded
screen-only illegal feedback. Four practice positions are merged and independently source-reviewed: empty Human Black, empty Human White, single capture and
two-stone capture. Combined acceptance, build/signature/package verification,
installation and physical validation are pending. Earlier receipts remain
source-specific; they do not establish success for this combination.

Installed app remains 0.253/build 254, firmware v44, original game paused at five
moves. Latest user statement reports eight Black stones; earlier photo showed
seven Black plus displaced White. Current colors/positions are not freshly
verified. Do not Resume against the mismatch. Preserve the five-move failure,
three-move checkpoint and clocks before installation; intended first session is
a separate paused empty Human Black practice position with intentionally cleared
board. Turn Connect laser bridge OFF for camera-only tests (currently ON for
passive broker publication). No app, camera, hardware or saved-state action was
performed for this documentation reconciliation.

All nine laser accuracy checks remain pending after the settled-pose steering
mismatch. Future laser work requires an empty board, reviewed remedy and fresh
qualification. The candidate enables no parallax/body-edge correction, adaptive
map learning or illegal laser marker. See NextPhysicalTestPlan.md for the ordered
camera/AI and later laser tests, and LaserMovementCheckpoint.md for evidence.


November 23 — integrated0.258 installed and empty practice prepared

Compiled87fc4a9,0.258/build259 signed and independently package-reviewed.23
selected suites are accounted for in source-specific receipts:20 initiallypass,
then5 final focused reruns after two test fixes and an ExperimentModel dependency
injection seam. Initial illegal test accessed private state; idle recovery fixture
omitted post-commit board verification. Mode test read the real saved AI game;
current.json SHAfe2ee0b70e4936ba567533510da291f3cdba3700927c1fb36c48086cb3ee1b89
remained unchanged. Isolation now supplies temporary AI/laser/online stores.
Final idle67, illegal69, standby225, continuity133 and mode/UI checks pass. Fresh
app-host-app acceptance exacthost42e5022 passes229/241/495 plus225/133 controls.

Fresh stopped-app backup preserves0.253, AI Games, reference, preferences and
three-/five-move checkpoints. Stage rename initially failed on sealed directory
permissions and automatically restoredoldapp; owner-write on stagedbundle directory
allowed replacement, signed bytes unchanged and signature reverified.0.258 launched.
Practice EA70E983-9FAF-40ED-8939-312ED10A1A68 loaded empty HumanBlackfastmode,
0moves/0clocks, paused. Original backup bytes exact; restart retains practice bytes.
Profile Newset/Cancel opens and closes without saving invented values. UI checked
through accessibility controls; screen captures were unsuitable and stopped after
Dave flaggedthem. They are not webcam evidence. Nativewebcam emptyboard preflight
visually confirmedclear; postinstalldirectframe0.184s, correctcamera, aligned,
handfalse. Bridgebrieflyenabledonlyforpassivepublisher withnodriver/serialowner,
OFFrequests; thenOFF. FinalrestartshowsLaserbridge disabled. No hardwarecommands.
Reference PNG/grid/camerafields unchanged; savedAt refreshes normally. Boundednative
latencyloggingenabled; diagnosticimages/warningsremainOFF untilphysicaltest.

Laserrecovery f15531c adds strict offline historical-stop/source/model preflight;
10tests+5 independentprovenancemutationspass, noexecutor/light/motionauthority.
Stationary optical observation may use existingv44 only after separately reviewed
activation/hold admission; earlyGT cannot establishpret-orque anchor relation.
Allnineaccuracychecks pending. No parallax/adaptivemap/illegal-laserpattern activated.
Artifacts: stone-session-20261123/app-0258-candidate, before-0258-install,
install-0258.json, practice-0258.json and empty-board-preflight-0258.


## November 23 — stationary laser position recovered optically

Reviewed host42e5022 initial-spot-only run completed successfully against installed
0.258/build259 and firmwarev44. User confirmed equipment unmoved and could watch.
Direct app webcam, camera0x11000000bda0567, verified the empty board; no desktop
image was used. Current stream differs after app restart, so subsequent reuse
requires explicit reference registration, not weakening ordinary epoch checks.

Evidence: laser-position-recovery-20261123/initial-spot-01/result.json, SHA256
2b828043e0cc2f35620d4583179c6f24a09a5e939fa8efec732d313288120e7a.
Status initial_spot_verified; actual held pose1681/2287; spot592.132/487.443px,
board0.8644/9.0227 in this run's unrotated frame. No GOTO/PTO/TTO commands.
GA holding can settle slightly; this is not a guarantee of zero shaft movement.
SWEEP-to-DARK dispatch interval2.1607s; audio dispatch11.6ms after light command,
not a measured acoustic/optical onset difference.76 thermal pairs, first11/12C,
last12/12C; no endurance or absolute ambient-accuracy claim. Exact v44 OFF confirmed
at Unix1795492387.674151. Saved AI files before/after identical.

Dave heard the beep and accepts the clearly recorded camera spot despite not
watching it himself. No repeat needed solely for visual confirmation. Fresh live
pose/spot requalification is still required before a later movement session.
Connect laser bridge ON only for passive webcam publication and OFF/no-target
requests; production driver stopped, root sole hardware owner.

Existing 3.172px stop was a prediction-consistency failure, not a timeout or proof
of a large miss. All nine held-out accuracy checks remain pending. fast_calibration
owns generic source-bound initial-spot registration/requalification,
adaptive_calibration owns conservative inward/probe planning, and
dark_commissioning independently reviews command envelopes. Frozen95-sample map
remains unchanged; no gameplay binding or adaptive correction activated.


## November 23 — observed-anchor recovery passed, repeated settlement planning defect

Hosta84faa599f64fcf33942071abeecdb96830e6e0c committed/pushed with independent
34-test pass using retained fixtures (no skips). Generic clean initial-spot
registration preserves original reference/model and new epoch provenance. Root
ran explicit --observed-validate-full with7200s experiment allowance, targettimer0,
10s camera/.5s cache; ordinary gameplay policies unchanged. Direct webcam empty
preflight age.166s; currentepoch59B7F169-A2A9-4B8C-954D-B8910738AA23, handfalse,
aligned, OFF/no-target request. No competing serialowner. No desktopimage used.

observed-validation-01 re-observed1681/2287 and qualified measured two-axis
steering. One typed additional5count tilt probe completed an initially weak
independent basis; optical checks passed without threshold change. Explicit
reported transition then entered existing baseline monitored-pose validation;
no claim that every firmware-permitted hold position remains insideboard.
A10 measured1.111477px and passed. Next route towardK19 stopped: lastoptical
1832/2290 atboard3.73128/7.31161. PlannedGOTO1860/2294 had2.919063px agreement;
actualSETTLED1860/2292 failed3.450899px, allendpointmargins195–200px. This number
is disagreement between two predictions, not measured aimingerror. No optical
measurement exists atfinalsettlement. Stop was not a timeout/controllerfault.

Exactv44OFF1795493870.3991501, processreaped/noowner.1155thermalpairs, maxima
14/15C. Sourceinventory unchanged; sixAIgamefiles byte-identical. No binding.
Oneofnine targets passed thisrun; complete futurequalification stillneedsallnine.
RawreportSHA071dc8ad5fe5f39f8b537ca97cdae9494ded5b88d8242172c8c424aed1d999b0;
artifacts laser-position-recovery-20261123/observed-validation-01 and derived
observed-validation-01-summary.json. Existingrawreports/reference/model untouched.

Next: adaptive_calibration owns proactive settlement-consistency goal shrinking,
fast_calibration owns isolatedrunnerintegration, dark_commissioning reviews
actualfirmware finalregions/primewrites. Keep actual3px/5px checks and distinguish
darktravel from illumination; do not add impossible wholehold containment as an
unstated prerequisite. Architecture review separately considers bounded static
optical requalification after a healthy predictive-disagreement stop, so camera
feedback may recover without treating an inaccurate prediction as a physical
miss. This is a proposal, not an enabled controllerfaultretry or guard waiver.


## November 23 — final settlement observed; local prediction was less accurate

Root added optional --initial-spot-expected-pose PAN TILT on isolated hostbranch
codex/initial-spot-pose-gate, commitece72fa, pushed.54 calibrationtests pass
independently; one oldMock diagnostic fixture was corrected to return a list.
FreshheldPOSE must be within3counts/axis beforePREPARE; wrongmode/domain rejects
beforehardware. No travel allowed. Independent optical-only containment of
expected1860/2292±16 hadminimum169.502px predictedmargin acrossall3hypotheses.
This is not steering consistency or a bound on allphysicalmodelerror.

initial-spot-02 passed: actual1860/2292 exactly, newreferencepixel758.07776/398.88571,
board4.338206/7.025124. Root viewed directwebcam spot. FullOFF1795494545.537726,
85thermalpairs,maxima12/12C, noerrors; sources and6savedgamefiles unchanged.
No GOTO/PTO/TTO travel; no new binding. RawreportSHA
bb938bc23833cd6cedb3942d4132b3609953d48b7583d31a9267cdcc3110d4b8.

Genericregisteredanchor loader accepts this report unchanged. Originalframe
pixel757.97327/398.66919; registrationECC.990852,335inliers,72boundarychecks,
maxcorner1.390px. At this actualpose oldlocal predictionerror5.10239px,
anchor-relative frozenpredictionerror2.34640px, absolute frozenmodelerror1.46193px.
Frozenmodel motorresidual.75718counts. Includesregistrationuncertainty; no fit
or claim of targeting an intersection (this was an intermediate waypoint).

Dave asked whycamera feedback could not slowlydialin. Motors alreadyhaveposition
feedback andcamera alreadyhasfinecorrection; the separate3px prediction-agreement
gate interrupted beforeseeingtheactualspot. Newstrict settlementregionplanner
alone cannotfixthis: it canrejectevenfresh2axisJ. Root/dark/architecture selected
optional anticipatorygoalshrink, withtypedunavailabilityfallingbackto unchanged
baselineguardedproposal. Ordinarynominal/actual3px/5px guards remain. Only a
cleanfirstcoarseSETTLED prediction-disagreement may enter newboundedstationary
opticalrecovery: suspendsteering, separatelyadmitoneactualgoalprime, proveheld
geometrycontainment, normalcamera measurement/DARK, thenfresh2axisqualification.
Oncepertarget/twiceperrun, originaldeadline/model preserved; allfirmware/camera/
hand/lease/transportfaultsterminal. Fastauthor implementing; architecture/dark
reviewers. Notyet physicallyvalidated or enabled. Strictplanner purehelper
d72f034 has15reviewedtests; source remainsisolated, nohardwareauthority.


## November 23 — recovery fix reviewed; physical test blocked by changed geometry

Laser host `7bee8a416ee6f353bea8d6d5b8af192ff6a5a843` is committed and pushed on
`codex/settlement-aware-validation`. Both independent reviews cleared it; all
66 targeted tests passed with retained fixtures and no skips. It keeps optional
settlement-aware goal selection separate from baseline movement checks. Only a
clean first-coarse prediction disagreement can admit bounded stationary
remeasurement and fresh two-axis qualification. Original deadlines, frozen fit,
physical guards and one-per-target/two-per-run recovery limits remain.

Root's observed-validation-02 stopped before GA, torque, PREPARE or SWEEP. The
initial reference check reported printed/native corner residuals
[1.1122, 1.3686, 0.6162, 4.010906]px against the 4px limit. Only status, heartbeat
and OFF commands were sent; no thermal session or optical sample started.
Exact v44 OFF confirmed at Unix1795496145.193214; process reaped, saved game
files and source inventory unchanged. Raw report SHA256:
1c35e1e38bbd69c18e0131b8d21ba87fffd054ccd7986276dfdf73d88a11cb34.
The new recovery behavior was not physically exercised.

Twelve subsequent direct-broker dark frames span1.506s. Native current corners
are identical across them, but differ from initial-spot-02 by up to10.589px.
Independent printed-grid fits and board-masked image registration confirm a
structural image change: about9.5px versus initial-spot-02 and10.2px versus the
original frozen reference. Current fitted corners vary only.057–.133px. Eleven
frames pass fresh_grid and then fail movement; one fails printed-boundary fit.
Zero pass full existing reference verification. Lighting variation alone does
not explain this; the cause (camera, board, support or other) is unidentified.
Do not cherry-pick a frame that passes the first4px gate or retry old geometry.

Evidence and reproducible analysis are under
laser-position-recovery-20261123/dark-grid-diagnostic-01/analysis. Original images
were hash-verified unchanged. The exact initially rejected frame was not saved;
these later frames do not recreate that particular4.010906px calculation. Fast
author is fixing that diagnostic omission separately, preserving rejected PNG,
metadata and reason only after full OFF and quiescence. No threshold or retry
policy change. Dave was asked whether anything was touched/nudged; answer pending.
No further hardware run until the setup is reverified.


November 23 follow-up: rejected-startup evidence preservation is now committed
and pushed as laser `4e1a61b98401a3cae496d2ca904a8f9ff81753a9` on
`codex/rejected-startup-evidence`, extending reviewed recovery `7bee8a4`. The
32-test aggregate passed; independent review reran four focused cases. Exact
rejected PNG/metadata/reason are saved only after confirmed OFF and quiescence;
capture/disk failures remain secondary. No thresholds, retries or hardware
behavior changed. The earlier missing frame cannot be recovered retrospectively.
Hardware remains OFF and the equipment-movement question remains pending.


## November 23 — new setup observed; fresh calibration running

Dave could not rule out movement, then confirmed the housing aimed at the board
and that he could watch. Native Check alignment passed. Root preserved the
prior empty reference and direct webcam metadata/image before checking. No old
geometry was reused or threshold relaxed.

Fresh initial-only run moved-setup-initial-spot-01 using reviewed host4e1a61b
passed: pose1860/2292, new-grid coordinates4.399779/7.052266, interior margin
satisfied. All seven images found the spot; root inspected its direct webcam
image, and Dave confirmed both beep and spot. Setup3ef3a3070bb19b28. Full v44 OFF
1795497259.6732147; no commanded travel, no controller error. All six saved game
files remain byte-identical. Raw report SHA256
2d4df1d468ca222b383bc20b2d1a8c1a54d54bfe982af4c917e374582f86845d.

Root started moved-setup-full-calibration-01 using the same reviewed source,
fresh reference/model path, experimental7200s total and no per-target time cap,
10s camera-age/.5s permit-cache settings. Five fitting targets then nine separate
validation targets; original physical/camera/thermal guards remain. No old fit
or observed-continuation flags supplied. The recent bounded remeasurement path
is observed-full-only; fresh calibration does not use the old global/local
prediction disagreement gate because its model is fitted after measurements.
Root is sole serial owner; production driver remains stopped and the app paused.
This run is in progress, not a calibration pass or active gameplay binding.
Dave asked about a new conversation afterward: prepare a durable completion
checkpoint and test handoff after the active run shuts down.


## November 23 — fresh setup reached three fit targets; weak boundary image stopped run

Fresh run moved-setup-full-calibration-01 on4e1a61b reached K10(.2315px),
A19(1.1657px), T19(1.2777px), then stopped while heading toward T1. Exact error:
`Printed boundary lacks line evidence: axis=1, fixed=12, target=18, samples=2`.
This is insufficient local printed-line evidence near N1, not a timeout or
controller fault. Last actual pose2297/2401 was not illuminated; last observed
pose2303/2408 was grid16.491354/1.547468. No SWEEP followed the rejected proof.
Full v44 OFF1795497537.2905838; process reaped, serial/driver locks free.
38 optical samples and1860 thermal pairs retained, maxima14/15C. Source inventory
and all six saved game files unchanged. No model/binding qualified or activated.
Report SHA2565a4ae8689bde95e80da9a8ab2330855bfda5bb892b19a680d89ca16f30d34ac0.

Immediately preceding geometry A(frame55768) passed338inliers/72boundarypoints,
max movement.1887px, ECC.99720. Fresh B then lacked three usable local profiles
(two found). The exact rejected B was not retained: verification raised before
its event/evidence capture. Startup-frame preservation does not cover this later
phase. Root saved a separate later dark image56215 in moved-setup-post-stop-dark-01;
it passes B against the original reference with72points,max displacement.4482px,
ECC.99714 and clear foreground. Its N1 line has only three usable profiles,
weakestcontrast8.211 against threshold8 (reference had four,weakest14.42).
Supports fragile local contrast, not persistent geometry change; exact transient
cause remains unknown. Later image is not the missing failed image.

Fast author now owns an isolated typed insufficient-line-evidence B retry and
bounded exact A/B rejection retention. Proposal preserves the existing three
attempt/two-second B budget, original A/run expiry and complete positive proof
before light; no movement, extra PREPARE, or old evidence re-dating. Generic
movement/identity/foreground/controller failures remain terminal. Independent
architecture/dark review and tests required before a new physical run. Hardware
stays fully OFF while this software work proceeds. New-chat handoff is prepared
but setup is not complete; finalize outcome and ownership before transfer.


November 23 follow-up — root's stationary post-boundary-stop-initial-spot-01
stopped during GA startup, before PREPARE/SWEEP and without a new optical pose.
Exact cause CachedEvidenceExpired; full v44 OFF1795497780.4154284, process exited,
source unchanged. SHA256f4899e6215586c1b904d78b6310a9d34663bab92857a013945e75c909bd7c3ee.
Timing replay identifies the cached app lease as the earliest deadline:
last poll80 lease1935788.612318039 versus cache.909424916 and camera1935797.704467042.
Poll81 request-open observed duration190.224ms crossed lease expiry; manifest-open
added92.826ms. Refresh prevalidation finished1935788.713669791, after first
OFF.629406333. Heartbeats/thermal acknowledgments continued; no retained serial
write failure. These observed intervals include possible scheduling delay; the
underlying file-open delay cause is unproven. This is separate from weak-line
reobservation and not the experimental10s camera-age limit. No automatic retry
or expanded lease allowance authorized by this diagnosis. Hardware stays OFF.

Partial fresh-fit continuation review: no supported committed checkpoint or
fixed validation model exists, so the three targets cannot be resumed through
current APIs. Current actual position must be optically observed; if outside
fresh-start[2,16], attended coarse re-aim (physical power off before moving joints)
is the existing route. Do not manufacture archived-source compatibility.


## November 23 — bounded image reobservation physically passed

Host54589c335e5d5502402a6d7994244eec9ac6a3ac is committed/pushed on
`codex/calibration-prelight-reobservation` in its same-named laser worktree.
101 author tests passed with no skips; architecture and dark reviewers each
independently passed10 focused tests against exact frozen sources. Only typed
weak-line insufficiency can reobserve B, after independent texture/foreground
checks. Original3attempt/2s B/A5s/run deadlines remain; no additional movement or
PREPARE and no light until a complete positive fresh proof. Exact rejected A/B
bytes are retained within8records/64MiB, then flushed after full OFF/quiescence.
Escaped line geometry, movement, foreground/identity/controller failures remain
terminal. No app-lease change or partial-fit continuation was added.

Root's post-boundary-stop-initial-spot-02 physically exercised this path:
B frames62465 and62469 both failed weak N1 line evidence; frame62473 passed
at1936223.784656583 before originaldeadline1936224.534742333. No light occurred
on failed frames. Both exact rejected/analysis images and reasons were saved
after shutdown. Current pose2297/2401 observed at board16.135067/1.863926.
Root inspected directwebcam spot. Full v44 OFF1795498218.83076, process exited,
source/sixgamefiles unchanged, max temperatures12/13C. Raw report SHA256
aa173a6867f5136e9fe50b42e6d8946e56573d19f67ad37e1ec3526ef19852a5.
This validates one actual bounded reobservation, not a complete calibration.

The observed point is just outside the fresh-start[2,16] box. Dave clarified he
wants motor-driven pointer movement, and NOTHING has been touched since this
check. Do not ask for a power-cycle/housing move: it could disturb the webcam.
Root has promised small camera-checked inward motor movements, not a blind
30degree/20degree swing. Fast/architecture are assessing the minimal measured
inward requalification route. Historical nearby sample31(2294/2400) satisfies
existing8/5 proximity; no proximity relaxation needed. Its extrapolation misses
the current optical point by3.7–4.2px depending on historicalJ, so simply admitting
the old report would still fail3px correspondence. HistoricalJ must remain
provisional until freshly measured response qualifies it. No new motion yet.

A20s passive metadata poll after offline tests had322samples,zeroexpiredapp
leases,minremaining357ms,maxfileread149ms,maxcameraage670ms. All requestsOFF,
handclear/aligned. This does not resolve the earlier app-lease expiry or establish
production600ms-camera reliability; it supplied current startup evidence only.


## November 23 — motor-only inward recovery passed; exact local-line failure captured

Host48894b01b4198122de62b37a1e4a97689185aa59 is committed/pushed on
codex/observed-inward-recenter.48 author tests and both independent12-test reviews
passed with retained archives and no skips. Separate explicit mode establishes
fresh-start[2,16] position only; old[3,15] recenter unchanged. Fresh references,
actualPOSE±3/latestspot3px, single-axis8/5 caps, actualsettlement/5px clearance,
opticalresponse/inwardprogress, eight-dispatch maximum and full OFF remain.
No fitted model or steering authority carries into the next fresh calibration.

observed-fresh-start-01 passed in two actualaxis commands: tiltgoal2396 settled
2398, optical2397; pangoal2289 settled/optical2290. Final2290/2397 at
15.861271/2.006822. Full OFF1795499382.978848, source/sixgames unchanged, max12/12C.
SHA7521ab65a191ddd86ab079cdffda06a934f054ce74b3082fdf564d465e7be7bf.

Root then ran fresh moved-setup-full-calibration-02 on the same frozen source.
Initialspot2290/2397 at15.860489/2.003225 passed freshstart. Firstdarkpan probe
PTO2308 settled2307/2397. AfterPREPARE, geometryA rejected printed-boundary line
samples disagree, before that probe was illuminated. Full OFF1795499436.7751687,
process reaped, sources/sixgames unchanged; no targets or model. Last optical
2290/2397; latest settlement2307/2397 is not an optical observation.
SHA892931c427e4735c9c4daff025451c8345473df92b4784b2e2929979b538fdf9.

Exact failing A frame74674 now retained underprelight-rejections/02-rejected.png
and metadata/reason, SHAa6584b5eb42512cbca4e47ff76b6fd40c2e2871c936cab49b9af301ef479b532.
Offline reproduction localizes both failures to N1,col12,row18,vertical line.
A had three profiles at17.75/17.25/16.75 withcontrasts32.325/23.106/14.939 and
offsets−1.362/−1.127/+3.434px; maxfitresidual1.500854px exceeds1.5. Two others
wereweak<8. Reference/earlierA hadsamebadthirdprofile and marginal1.370/1.375px
residual, not a new physical shift. All four savedimages register against
reference withmaxcorner≤.061px,ECC≥.997817,649–691inliers. Reflection is visible
butnotpixel-saturated. Exact transient/lightingcause notproved; current evidence
shows localized noisyline measurement, not board movement.

No retry widening or thresholdchange authorized by this result. Occupied-board
diagnostic agent and architecture reviewer are evaluating additional non-grid-
intersection midpoint profiles within the existingwindow, with samecontrast/
residual/point-error limits and negativegeometrycontrols. CurrenthardwareOFF.
The saved failure and reproducible report are in full02/failed-line-analysis.


## November 23 — midpoint sampling reviewed; physical start recovered; full03 running

Hostacea4b341fcc78777556c3f56b14344aa1834de8 committed/pushed on
codex/midpoint-line-profiles (same-named worktree).120 relatedtests passed;
both independent reviewers each reran7 focused tests on four hash-pinned images,
zero skips. Only fixed nonjunction profileticks changed from.25/.75 to.25/.5/.75;
original windows/contrast/residual/3px/outlier/retry/lease limits unchanged. Whole
reviewed provenance profile explicitly added; original accepted-coordinate fit
arrays and actualpose response replay remain identical. Both exact failedimages
pass; seven unique synthetic negatives plus a recordedocclusion reject. New
supports can shorten span and increase endpoint sensitivity(~27% in rescuedB);
no calibratedconfidence/generalreliability claim.

midpoint-initial-spot-01 passed, no prelightrejections: actual2307/2397 at
16.320196/2.257017, fullOFF1795500588.8804305. Then observed-fresh-start-02
passed withfour actualaxis commands, freshresponsequalified when furthertravel
wasneeded; final2293/2391 at15.818993/2.420984, fullOFF1795500685.1973846.
No map/steeringauthority carried into nextsession. Source unchanged; these are
position/start checks, not fullcalibration. See derived result summaries.

ROOT CURRENTLY RUNNING moved-setup-full-calibration-03 on frozenacea4b3, sole
hardwareowner. Newfreshreference/fit, fivefit/ninevalidationroute;7200s overall,
targettimer0, experimental10s camera/.5s cache. Productiondriver remainsstopped;
apppracticepaused, boardempty, no otherhardware/CPUtestjobs permitted. Do not
treat priorOFF receipt ascurrentOFF whilethisrunactive. Finish/record actual
shutdownbeforehandoff oranotherprocess.


## November 23 — full03 stopped; local measurement instability under review

Fresh moved-setup-full-calibration-03 on host acea4b3 stopped after its first
dark pan probe: fresh boundary disagreement was 3.989569 px against A and
4.049711 px against the original reference. Full OFF (beam and motor power)
confirmed at Unix 1795500739.5855656; process exited. Last optical observation
was 2293/2391 at board [15.816780, 2.415560]; subsequent settlement 2312/2391
was not illuminated or optically verified. No fit targets/model or live binding.
Result SHA256: 25a7e7d32ec314f8d6188509840d0e9465db1de235fb071680f6fc0fdb4dd48b.
All six preserved game files still match the pre-run hashes.

Exact saved A/B analysis isolates N1 and O1; other 70 boundary points differ by
at most 0.159 px. Independent board registration estimates at most 0.053 px
whole-board movement. A local profile switches between competing dark features;
reference/A and B also use inconsistent native-versus-fitted sampling guides,
which amplifies disagreement. This supports measurement instability rather than
four-pixel whole-board movement. It does not prove local geometry is correct.
Reproducible evidence: laser-position-recovery-20261123/
moved-setup-full-calibration-03/boundary-jump-analysis/README.md in work artifacts.

Dave asks whether acceptance rules are unnecessarily strict and how to test that.
Root has assigned offline counterfactual evaluation against retained positives,
actual failures and movement/obstruction controls; compare unnecessary stops with
missed errors and relate thresholds to grid spacing and final pointing accuracy.
Fast-calibration and architecture agents are assessing consistent sampling and
uncertainty/redundancy rules. No new implementation, threshold relaxation or live
retry is authorized by the diagnostic result alone. Root remains sole hardware
owner; hardware stays fully OFF during this work. User requests motor-only
movement and reports nothing touched; do not request a housing move/power-cycle.


## November 23 — user clarifies accuracy policy

Dave clarifies that the original three-pixel value was an arbitrary preferred
laser-spot distance from the intended intersection. A coarse landing well beyond
three pixels followed by correction is acceptable. A final offset above three
pixels is also potentially useful and should not by itself terminate the system.

This supersedes treating every three-pixel accuracy gate as an immutable
requirement. Root has redirected the architecture and calibration agents to
separate aiming quality/convergence, prediction uncertainty, board geometry and
actual physical/control hazards; evaluate in local grid units as well as pixels.
The current loop already permits initial errors above three pixels and corrects
them; final validation still rejects such offsets, and separate prediction and
boundary checks can stop before observation. Motor-count limits with the numeric
value three have different units and are not covered by this accuracy preference.
No implementation has changed yet; hardware remains fully OFF. Offline study is
evaluating unnecessary stops and missed errors before selecting a coherent policy.
