# Live position issues, reviews, and clocks

Date: 2026-11-11 (America/Los_Angeles)

Status: all four batches completed in 0.157 / build 158. Full regression and
signed-build verification passed. Capture timing retains its configurable policy. See the
implementation and validation record below for coverage and limitations.

Latest follow-up: 0.168 / build169 installed with interruption-tolerant lighting
baselines and the 0.167 grid-alignment fix. Eight targeted suites passed for
0.168; live glare recovery confirmed after unlock.
Guided physical testing resumes at14/27, with14 moves preserved and
both clocks paused before Black A5 tests the two-prisoner automatic hold. See the investigation/install record at the end.

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
