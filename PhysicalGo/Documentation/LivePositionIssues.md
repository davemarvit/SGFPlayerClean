# Live position issues, reviews, and clocks

Date: 2026-11-11 (America/Los_Angeles)

Status: all four batches completed in 0.157 / build 158. Full regression and
signed-build verification passed. Capture timing retains its configurable policy. See the
implementation and validation record below for coverage and limitations.

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
resume speech; it is not a speech failure. A longer interruption with an audible
warning and paired recovery announcement still needs a physical test.

Next guided test: **Stop camera** while Black’s clock is running, leaving both
stones untouched and without manually pausing. Wait for audible pause guidance
(up to 15 seconds), then **Start camera**. Expect both clocks held during the
interruption, automatic Black restart after fresh verification, and “Clocks
resumed. Black to play” if pause guidance was audible. Manually pause after five
seconds of resumed play. If still stopped ten seconds after Live returns, leave
it stopped and report the status. Two-move/clock/review baseline saved; awaiting
user result. This tests an explicit camera stop/start, not a physical disconnect.
