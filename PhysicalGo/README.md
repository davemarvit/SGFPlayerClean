# Physical Go — camera game recorder

Physical Go is an independent macOS application inside the SGFPlayerClean repository.
It records stable physical Go moves from an empty board, supports move-by-move review,
and saves SGF. It supports two-player local games and online games through SGF Player’s
OGS connection, with visual guidance for opponent moves. Camera detection remains experimental.
Do not rely on it as your only tournament game record yet.

## Structure and maintenance

The agreed next behavior for automatic reconciliation, actionable board markers,
issue-specific review, and clock/capture holds is documented in
[Live position issues, reviews, and clocks](Documentation/LivePositionIssues.md).
It includes the numbered cases, current implementation gaps, acceptance criteria,
and a handoff prompt for continuing development in a new conversation.

The pre-maintenance snapshot is Git tag `baseline/physical-go-0.120` (commit
`22f3c7d`). It includes the shared application sources, assets and regression
fixtures. Raw camera captures, build products and scratch investigations are
excluded from Git.

| Component | Responsibility |
| --- | --- |
| `CameraCapture` | Device lifecycle and fresh camera-frame delivery |
| `CameraAnalysisPipeline` | Immutable frame processing on its serial worker; classification, tracking and rectification |
| `ExperimentModel` | Session coordination and presentation; rejects stale pipeline results using its revision |
| `GameRecorder` | Accepted game transitions and confirmation policy |
| `MoveObservationHistory`, `LocalMoveEvidence` | Bounded tentative chronology and fresh confirmation evidence |
| `ReviewHistoryCoordinator` | Review restoration, interrupted-commit reconciliation and known-pass policy |
| `RecordingStore`, `RecordingIdentity` | File formats, atomic file writes, stable signatures and failed-load protection |
| `LocalClockEngine`, `LocalGameClock` | Deterministic clock arithmetic and clock lifecycle/audio |

Keep domain decisions independent of diagnostic event text. Pending chronology
is checkpointed by recording transitions and fresh observations, including camera
stop. Shutdown flushes the session and cancels termination if a write fails;
starting or opening another game also requires saving the current session. The
recording panel provides a save retry. A pending or review sidecar that fails to load makes that
recording read-only until repaired and successfully reloaded. Closing a read-only
session preserves the original files. Pending checkpoints never move ahead of the
successfully saved SGF identity. Each file write is atomic; recovery reconciles
the known SGF/review interrupted-commit case across files.

Unknown review chronology is distinct from a pass. An explicit pass only ends a
game when the preceding known move was also a pass. Empty resolved false detections
are skipped when determining the preceding move.

### Running tests

Run these commands from the repository root:

```sh
python3 PhysicalGo/Tests/test_build.py
python3 PhysicalGo/build.py --list-tests
python3 PhysicalGo/build.py --persistence-test --recorder-test --review-queue-test
python3 PhysicalGo/build.py --workflow-ui-test --score-overlay-test --online-test
python3 PhysicalGo/build.py --all-tests
```

`scripts/test_suites.py` is the registry for all Swift regression suites;
`scripts/build_sources.py` resolves their production dependencies. Multiple test
flags run every selected suite and return failure if any fail. `--all-tests` also
runs the build-registry checks, continues through failures, and prints a summary.
`--test` retains its original meaning: the basic vision/placement/rectification
suite. `--debug-tests` disables optimization for faster iteration. UI suites need
a macOS GUI session; scoring integration suites use the configured local KataGo.

Native screenshots go to `PhysicalGo/.build/TestArtifacts`. Set
`PHYSICAL_GO_TEST_OUTPUT` to choose another output root. Add new suites to the
registry; its checks verify source existence, unique executables and coverage of
every regression entry point. Keep recorded fixtures separate from generated
test outputs.

## Advanced diagnostics (0.141)

Info & settings → Advanced provides an explicit Diagnostics mode switch. Panel
visibility is independent of collection. New installations leave camera diagnostics
off; an explicitly enabled older unusual-move preference is preserved. Disabling
the mode stops image collection and clears the transient camera buffer. Ordinary
SGF and compact clock history continue. Outside diagnostics mode, the detailed
observation journal is deleted only after a finished game with all reviews resolved
is successfully exported as SGF. Autosave and mid-game export retain recovery evidence.

In diagnostics mode, a lost byoyomi period—including the last period expiring—
triggers a camera clip independently of speech. The default is four seconds before
and five seconds after the event, at up to five full-resolution images per second.
Advanced settings offer 2/4/6 seconds before, 3/5/8 seconds after, and 2/5/10 fps.
Actual coverage depends on camera delivery, a 256 MB ring buffer and writer limits;
the archive records requested and available coverage. Pausing play preserves an
active clip's post-roll. Camera stop or disabling diagnostics stops collection.

Clips retain both clock states, period counts, available boundary timestamps,
hand-clear estimates and later recognition decisions. A period restored by delayed
recognition remains documented rather than deleting its evidence. Continuous
capture is optional and must be started manually after launch. While it is active,
period losses bookmark that recording instead of duplicating its images. All camera archives
share the existing 10 GB rotation allowance; kept captures remain protected.

Run `--byoyomi-diagnostics-test` for loss/refund/timeout detection, mode gating,
settings persistence, actual move 62 timing replay and camera pre/post-roll checks.

## G18 recognition and rapid-play recovery (0.147)

A covered white stone could be rejected exactly at the allowed 0.28-cell outline
displacement: subtracting column 17 from 17.28 produced a value slightly greater
than 0.28. The comparison now allows floating-point rounding at the same bound;
outline quality, separation, grid coverage and color checks are unchanged.
`--g18-rapid-play-test` checks seven recorded photographs, including the empty
G18 control, then replays the rapid G18 / J19 capture / G17 sequence with only
G18's documented classification corrected. A single complete, legal suggested
review order is now shown as a draft for explicit confirmation.

## Provisional placements and clock presses

Local play separates a completed turn from its exact intersection. When the
camera repeatedly sees one new stone of the expected colour after the hand clears,
the clock switches using the first retained clear sighting. From 0.146, this
timing path is independent of legal placement candidates: unrelated ambiguous
intersections or a spurious candidate cannot keep charging the previous player.
The expected colour follows alternating clock presses. A short tone marks
a new ambiguity. The counters below each clock count placements, not candidate
intersections; clicking a counter opens the earliest historical position for
that player, with Previous/Next navigation.

Browsing, choosing Correct placement, and dragging a stone into a correction
preview keep recording and clocks active. Explicitly accepting a correction pauses
play after its source revision and legality have been checked. Multiple pending placements can be edited together;
confirmation saves the revised legal history, and Resume checks the physical
board. Later clear placements and legal captures can resolve earlier alternatives.
Hand-covered points alone never establish a capture. Unresolved placements block
final scoring and complete SGF export.

Each provisional press is stored separately in the clock sidecar, with its
original estimate, error information, and observed location alternatives. These
alternatives identify the physical stone without committing an SGF intersection.
Promoting moves into SGF transfers those
presses without charging time or awarding increments again. Restart restores them
paused. Contradictory turn evidence, capture-pause ambiguity, and timing intervals
that overlap expiry require clock review. Candidate search is bounded; reaching
its limit preserves prior hypotheses for correction rather than choosing a path.

A pending on-time sighting prevents the timer from declaring a loss while visual
confirmation is still outstanding. If several new turns first appear in the
same clear view, alternation can identify their colours but cannot reconstruct
their individual clock times. Both clocks stop for timing review without
inventing increments or silently charging one player for the missing turns.
`--placement-timing-test` replays the recorded White72 incident, including the
spurious Black166 candidate, and checks the near-expiry confirmation race.

From 0.150, entering clock review also protects a pending on-time sighting before
advancing the clock. Black87 exposed a second route to false expiry: placement
review ran after the deadline, ahead of the timer callback, and charged the
original player through recognition delay. The regression uses the incident's
timestamps, preserves the 2.04-second balance before the unresolved press, keeps
review required, and verifies that definitely late placements still expire.

From 0.153, live game, pending-history, review and clock snapshots use one ordered
background writer. JSON encoding and disk writes no longer run in camera or clock
callbacks. The first storage failure stops dependent writes and pauses play with a
Retry saving action. The critical queue is bounded; overload is a visible storage
failure, not silently discarded game data. Consecutive snapshots of the same file
coalesce to the newest complete state, without crossing dependent-write boundaries.
Retrying writes the current in-memory
session again before allowing Resume. Explicit shutdown, session replacement and
paused edits still wait for durability; ordinary observations and timer ticks do not.
This preserves the existing file formats; it does not add a multi-file crash transaction.

Observation journals have a separate bounded background queue so optional diagnostics
cannot delay game persistence. Under sustained disk pressure, diagnostic rows can be
omitted. Game moves and clock snapshots are never handled as optional diagnostics.

Every recording Resume command now passes through GameRecorder: timing review is
checked first, manual pause is released once, and fresh board verification is required
before clocks start. The UI derives Playing, Checking, Paused, Clock review, Capture
removal and Storage blocked from one shared flow definition. Confirm times & resume
enters Checking directly, without a second Resume. Pause checking cancels automatic
resumption. An unresolved placement alone does not require clock review.

Clock confirmation is durably saved before the sheet closes. Storage failures remain
visible inside the sheet with Retry saving. A pre-correction board seen during fresh
verification cannot become a new timed move. Historical move-order reviews also no
longer block scoring a stable physical position; unsettled placements and provisional
clock moves still do, and territory scoring still requires prisoner confirmation.

Run `python3 build.py --storage-flow-test --persistence-test --clock-review-test`
for blocked-disk responsiveness, failure/retry, ordered durability, restore, manual
pause, camera recovery and clock-review regressions.

Validation checkpoint for 0.153: all 82 registered Swift suites compiled against
one optimized app module; 74 pass, including the new 31-check storage/flow suite.
The six Python build-registry checks pass. Tests that reopen or deliberately damage
files now wait at explicit durability boundaries. Diagnostic tests wait for writer
completion instead of assuming that a fixed 0.4-second delay is sufficient.

At that checkpoint eight suites failed, and each failure also reproduced at the pre-refactor
checkpoint `a310de3`: `visible-grid-stone-test`, `touching-shadow-test`,
`crowded-white-test`, `centered-stone-test`, `capture-continuation-test`,
`grid-ui-test`, `crowded-adjustment-test`, and `visibility-test`. These assertions
remained enabled. Further architecture work was held pending their repair. In the capture replay, all 13 later moves are retained
but the recorded observation calls an existing White stone at point 24 empty,
contradicting the legal final position. The touching-shadow failure calls a small
opaque cover empty; the visible-grid case withholds a labeled White stone. The
other failures concern historical classification or pending-placement expectations.

Regression repair follow-up (0.154): a retained off-center stone no longer
becomes a second move when outline quality falls below the alternative-location
threshold. Current raw placement selects the displayed candidate; all legal
alternatives still participate in confirmation and survive checkpoint restoration.
Two visible bodies remain separate. A small local disappearance of an unchanged
recorded stone now permits retaining later chronology, but blocks SGF acceptance
until the original board agrees again. Broad disappearances remain blocked.
Accepted stones do not get fresh centering requests from an offset alone.

The exposed-wood test now checks inner and outer samples at both the nominal grid
point and proposed body center, preventing a small dark cover from being declared
empty. Historical signature tests permit uncertain-to-empty improvements, with
separate photographed negative labels for known false whites. The outside-edge
White in the visible-grid fixture remains unassigned; on-grid Whites are checked
separately. The capture fixture's raw missing-stone contradiction must retain the
13 later moves, then verify the exact 64-move result from the final real photo.
Repeating that photo tests confirmation behavior, not independent image accuracy.

The grid-reset fixture now preserves its supported 15-move prefix and all review
evidence through recovery, and verifies the final 31-stone colored position from
12 real photos. It no longer requires silently reversing an observed out-of-turn
sequence. Original images, raw observations and historical provenance are retained.

Validation for 0.154: all 82 registered Swift suites pass against the same
optimized app module (81 in the full run, followed by the corrected visibility
fixture test). All six Python build checks pass. The visibility test separately
requires the neighboring alternative to become positively empty after simulated
centering; an unreadable alternative remains pending. Its restoration checks use
an immutable saved checkpoint instead of racing two stores against one file.

From 0.155, valid camera presentation timestamps keep their original age even
when delivery is delayed by more than 1.5 seconds. Previously that delay switched
to callback time, making an old frame appear fresh. Invalid/missing clock data
still uses the explicit callback fallback. Camera delivery rejects already-stale
buffers before grid changes or analysis; the post-analysis freshness check remains.
Native CoreMedia sample tests cover both sides of the old cutoff through a
one-hour delay, alongside existing timestamp journaling and missing-clock tests.

Diagnostic event, operation and automatic-clip annotation payloads are constructed
only after the relevant session/buffer guards pass. Disabled diagnostics, stale
callbacks and duplicate completions no longer serialize unused board snapshots.
Active diagnostics still capture their immutable values on the main actor and
write them on their existing worker. Regression counters verify zero evaluation
when skipped, exactly one when accepted, and archived payload preservation.
A focused 1,000-call disabled-operation probe went from 1,000 serialized 361-point
payloads (about 0.97 seconds on the development Mac) to zero payloads. This measures
removed diagnostic work, not an overall camera frame-rate improvement.
Validation for 0.155: all 82 registered Swift suites passed in one full run,
including the 60-check diagnostics suite, 31 storage/flow checks, native CoreMedia
sample journaling, real KataGo integration and native UI rendering. All six Python
build checks passed. The production app was built, signed and verified with a
source hash matching these sources. Live phone reconnection still needs hands-on
validation; recorded and synthetic camera tests do not establish that behavior.

From 0.156, marked Live position stones and **Review highlighted stones** use
the same issue-based routing: capture/restoration or deferred-history reviews,
pending-location confirmation, recorded-placement correction, or missed-move
recovery. Camera-only translucent stones can legitimately coexist with zero
placement ambiguities; their task is to establish history, not confirm a retained
location. The frozen photo annotation tool is explicitly labeled for recognition
testing; existing capture/restoration photo confirmations remain available.

Missed-move recovery preselects retained chronology when all candidates agree on
one sequence (including shorter prefixes). Approval cannot silently discard or
reorder that pending sequence. Existing provisional clock events are attached to
the accepted moves without charging again; missing timing still requires review.
Tests cover zero-ambiguity markers, per-issue routes, preservation of three pending
moves, rejected partial replacement, clock-event retention and reopening.

Validation for 0.156: all 82 registered Swift suites pass (81 in the full run,
then the mixed-warning fixture after replacing its obsolete wording assertion
with a specific move-46 click-routing check). All six Python build checks pass.
The signed native app's source hash matches the tested production sources.
The affected test recording was recovered separately as 89 legal moves, keeping
the first 86 unchanged and retaining clock balances paused for review; its
original recording and evidence remain intact.

From 0.164, known-empty lighting baselines can also learn from repeated current-
image evidence: nearby wood establishes local brightness and color, and both
printed grid axes must remain visible. This helps when changed glare makes the
old reference uncertain. Detected stones still take precedence.

From 0.163, repeated independent empty readings at saved-empty intersections
learn temporary local lighting baselines. An uncertain reading can remain empty
when brightness, color, and the center still match. Detected stones take
precedence; baselines expire and reset on conflicting known stones, camera gaps,
obstructions, position/context changes, and grid displacement. Original reference
images remain unchanged.

From 0.162, the flattened camera view retains its display geometry during
alignment checks and grid searches, with an in-place checking label. Unverified
frames still cannot supply stone observations or moves. The raw perspective
remains available through the explicit straighten-board setting.

From 0.161, resolved disagreement panels show a prominent **RESOLVED** heading
and remove the orange marker. Changed evidence is labeled separately. Heading
and explanation variants reserve the same space so the board and sheet stay
in place through acknowledgment and resolution.

From 0.160, a lone missing-stone review closes automatically after fresh, clear
views verify the complete saved position again, including while manually paused.
Its original camera evidence remains in the resolved review; moves and clocks
are unchanged. Reviews with later moves or proposed sequences still require review.

From 0.159, application-specific Kokoro pronunciations augment the pinned
lexicon through `Resources/KokoroPronunciations.json`. The recovery messages
pronounce “verified” as a word; synthesis tests check its phonemes and regenerate
the short cached clips so an older spelled-out recording cannot persist.

From 0.158, verified restoration stops obsolete recording-warning speech and
acknowledges an audible warning once with “Board position verified.” If clocks
are paused, it explicitly says they remain paused. This also works when an
existing stone is restored without recording another move. Fresh evidence,
remaining issues, mute, and session changes guard the acknowledgment; clock
accounting is unchanged. Both recovery messages are bundled in Kokoro.

From 0.157, one typed issue policy drives Live position markers and click routes.
A saved-stone disagreement opens evidence inspection with **Recorded position is
correct**; this acknowledgment changes neither SGF nor clock accounting. A
persistent disagreement after acknowledgment becomes a recognition task, scoped
to the current position and view. Unknown or repeated images cannot clear a real
absence. Accepted recovery clears its obsolete markers.

Inspection stays live, including saved-position browsing, pending placements,
chronology, and historical correction previews. Stale proposals require refresh
or reopening. Accepting a mutation explicitly holds play; cancellation does not
change clocks. Capture progress can be inspected without converting its automatic
hold into manual recovery. The separate manual-recovery action still requires
clock review. Removal guidance also remains available below the configured
threshold, without creating a hold. Off / 2 / 3 / 5 capture thresholds remain unchanged.

Static alternation without individual timestamps now requires timing review at a
supported boundary. Fully retained timed turns can be assigned to SGF without a
new clock review or duplicate increments. A known physical disappearance alone
keeps the established turn. Aggregate regression commands compile one testable
production runtime from the authoritative source registry and run native suites
serially; the old local scratch runner is no longer needed.

Validation for 0.157: all 83 registered Swift suites and seven Python build checks
pass. Native issue/review views were inspected; the Developer ID signed build's
source hash matches all 134 resolved production sources. Tests used isolated
synthetic/recorded fixtures, including real KataGo integration, not a live camera.
The existing installed app and its open recording were left untouched.

From 0.152, camera-backed clocks track the latest usable observation. If analysis
falls more than 1.5 seconds behind, the clock pauses at that observation instead
of charging the blind interval. Explicit camera interruptions use the same
protection immediately. The timer checks freshness before declaring expiry;
a fresh view beyond the deadline still permits a real timeout. Fresh board
verification remains required after a hold, and manual pauses and the explicit
continue-through-interruptions preference are preserved. `--processing-gap-test`
replays the 2.45-second resume stall, both callback orders, short delays, a real
timeout, camera failure near expiry and verification before resuming.

Diagnostic archive allocation, directory scanning and rotation now run on the
writer queue before its queued frames and events. Startup failures are reported
asynchronously without touching game/clock state. Pending writes remain bounded;
Stop and application exit drain initialization and accepted writes in order.
Only the diagnostic event journal batches disk synchronization (at most once per
second, plus completion); game and clock persistence are unchanged.
`--async-diagnostics-test` holds the archive allocator busy while proving the
main thread can continue, then checks queued frame/event ordering and failures.

The outline fitter skips candidates whose maximum possible score cannot exceed
the best fit. Search order, thresholds and current-frame evidence remain the
same. Seven G18RapidPlay photos (three runs each) measured median full detection
at 218 ms before and 137 ms after, with identical serialized readings, confidence
values, centers, radii and fit scores. Busy camera-frame counters publish at most
once per second; successful analyzed views still update immediately. Diagnostic
context is constructed only for samples that will actually enter the buffer.

From 0.151, confirming clock times also acknowledges the retained pending turns.
Those turns remain separate from accepted SGF placements and carry an explicit
review marker, not fabricated camera timestamps. Fresh views verify the pending
position before clocks resume. The same stones cannot reopen the timing review,
and accepting their locations later cannot award a second overtime reset.
`--clock-review-test` replays the actual 86-move/two-pending-turn resume loop and
checks preservation of agreed balances and the boundary across relaunch.

`--provisional-play-test` exercises alternative locations, later replies, capture
resolution, capture pauses, persistence, direct corrections, and press promotion
across all timed clock modes. The normal recorder, capture and clock regressions
remain required for changes to these paths.

## App icon

The app icon pairs a physical black Go stone with a pale wiremesh stone.
Master artwork and the built-in image-generation prompt are preserved in
`Resources/AppIcon/PhysicalGo.png` and `Resources/AppIcon/generation.json`.
`python3 PhysicalGo/scripts/build_icon.py` creates the complete macOS `.icns`
family using system image tools. Normal app builds regenerate it when needed,
copy it into the bundle, and set `CFBundleIconFile` before signing.

## One-step scoring approval (0.116)

Approve all scoring details covers prisoners (territory rules only), dead groups,
territory assignments and unmarked neutral points. Review components expands an
indented list with independent checkboxes, current counts and Edit controls. The
native parent checkbox shows a mixed state when only some components are approved;
clicking a mixed state approves all, while clicking a checked state clears all.

Editing a component invalidates that component's approval; no-op edits leave consent
intact. Fresh analysis and reopening reset approvals. The Save button states which
approval is missing, and the score report records the approved components. Approving
never saves a result automatically; Save agreed result remains a separate action.

## Reviewable AI territory count (0.115)

Physical scoring now builds a proposed count from the shared AI ownership map as well
as directly enclosed territory. Open boundaries no longer silently remove large areas
from the count. Living stones never count as Japanese territory; marked-dead points
and dead prisoners are counted separately. Search ownership is a proposal, not proof
of life or death, and the whole-group proposal threshold is documented in code.

The final review shows the proposed dead-stone totals and number of unassigned empty
points. Players can revive/kill whole groups or assign individual points to Black,
White or neutral. Every correction revokes agreement. Saving a result requires explicit
agreement on territory, dead groups and unmarked neutral points, in addition to prisoner
confirmation when history is incomplete. The score report stores the accepted territory
map and corrections. SGF Player Clean's ordinary enclosed-territory scoring is unchanged.

The actual 179-move retained position and cached KataGo response are regression fixtures:
74 Black / 107 White proposed territory, 38 Black / 2 White proposed dead stones,
45 unassigned empty points. This yields a proposed W+75.5 count; KataGo's separate
continued-play forecast is W+80.7. Neither is asserted as an agreed result automatically.

## Territory estimates after the game (0.114)

Score game now defaults to the shaded AI territory view for finished games too.
The AI territory / Final count selector separates the prediction from the editable
territory dots, dead groups and prisoner totals. The estimate always uses KataGo's
score lead, including positions with retained moves; it is no longer mislabeled
with the partial static count. Clearing the physical board does not clear the
saved scoring position. Final count remains an explicit review and confirmation.

## Scoring territory display (0.113)

The scoring screen now reuses SGF Player Clean's ownership estimates and feathered
black/white shading during play. Stronger estimates have stronger shading; unsettled
or neutral areas stay clear. Likely lost groups fade and receive proportionate crosses,
without declaring them dead or changing the recorded game. A short legend explains
these distinctions. Ownership and stones share the playing board's orientation.

Final review uses soft black/white dots for the editable territory count and red crosses
for proposed dead groups. Neutral-area and life/death corrections update those dots;
the AI shading is omitted here so it cannot contradict the reviewed count. Analysis
is still on demand on battery; this display does not start another engine.

`python3 PhysicalGo/build.py --score-overlay-test` checks both player perspectives,
all four orientations with native renders, uncertain/malformed ownership, final-score
corrections, fresh-position reset, and the existing real KataGo/power/handoff tests.

## Shared play status and capture timing (0.127)

Local play has one status area below the clock controls. It shows the current
clock/recording state, next action, review completion and export feedback.
The original automatic-pause reason and earlier timing notes are collapsed under
**Earlier clock details**, so an obsolete turn question cannot remain a current
instruction after review. Review editors are attached sheets; successful saves
close the editor and report completion in the main status area. Clock review,
when required, remains enforced by **Review & resume**.

Setup → Players, rules & clock includes **Automatically pause for captures**:
Off, two or more (default), three or more, or five or more stones. This is a local
clock policy, independent of scoring rules; it does not control an online server
clock. [AGA Tournament Regulations](https://www.usgo.org/docs.ashx?id=1166826)
(February 20, 2023), VII.11(c), permit stopping
both clocks for removal of more than one captured stone. Automatic pausing is
our configurable implementation of that permission, not an AGA requirement.
The regulations also require removal before move completion (VI.B.3).

A legal incomplete capture must be identified in repeated fresh views before an
automatic hold begins. The clock is reconstructed at the first supporting frame;
neither player is charged for removal. Five fresh matching views spanning at
least 0.8 seconds verify the finished capture. The move is saved once and the
opponent's clock is reconstructed from the first clear completion frame, including
recognition delay. Manual pauses are respected. Camera interruptions invalidate
confirmation evidence; cancellation of a presumed capture requires clock review.
Pending capture holds survive restart with both clocks paused until Resume.
**Review capture…** hands a stuck hold to the existing capture/photo workflow;
that explicit fallback asks players to check clock times before resuming.
A capture entirely hidden until removal finishes has no reliable removal-start
timestamp: this policy does not invent or refund an unobserved interval.

Local timed play uses Apple's on-device Vision hand-pose detector in the existing
camera analysis worker. Detected hands over the calibrated board postpone move
acceptance. Completed positions use retained clear-frame capture timestamps for
clock accounting, with existing legal-move and temporal confirmation gates.
The camera feeds analysis at most five times per second; 0.2 seconds is nominal
sampling resolution, not a guaranteed accuracy bound. Missed detections, processing
backlog and dropped frames can reduce precision. Old or interrupted evidence cannot
cross a pause/recalibration boundary. Recorded fixtures without hand metadata retain
the previous first-candidate timing behavior. Online clock times remain server-owned.

`--capture-clock-test` covers actual incomplete-capture data, thresholds/off,
manual pause/resume, camera interruptions, cancellation, clock balances, confirmation
delay, hand gating, clear-frame timestamps, restart, legacy settings, photographed
hand detection and native sheet attachment. `--review-queue-test` and
`--workflow-ui-test` cover resolved-turn guidance, completion messages, retained
review selections, photo handoff, and the unified native play layout.

## Recovery without persistent overrides (0.126)

Board-photo labels now apply only to the frozen photograph being checked. Saving
labels archives the original image and explicit labels, then discards the draft;
local and online move recognition always receive live camera readings. There is
no sticky Empty/Black/White mask, including after a game, turn, or camera change.
This does not train the recognizer automatically.

Capture and restoration reviews offer **Check camera photo…**. If the checked
photo matches the current legal correction, an explicit **Confirm … from this
photo** action can resolve that review. Saving labels alone does not resolve it.
The approval is tied to the review ID and target, expires after 60 seconds, and
is invalidated by a camera interruption, freeze or calibration revision. The
archive must succeed before resolution. Clocks remain paused, and the existing
capture-complete announcement is deferred until they actually resume. Photo
labels never authorize automatic online submissions.

The current-image White classifier now requires a surrounding edge, rather than
accepting a smooth bright patch solely because it is paler than nearby wood.
Unbounded glare remains uncertain; history is not relabeled as visual truth.

Camera retry allowances replenish after 30 seconds of uninterrupted healthy
frames. A system wake or reconnection of the selected camera can recover an
exhausted stream, while explicit Stop prevents automatic reopening. Each failed
outage remains bounded. Exhausted grid searches retry every 30 seconds while
fresh frames continue; lighting/visibility guidance asks players to check the
view without assuming that the camera needs moving. Recovery never bypasses
fresh-board verification or a manual clock pause.

`--recovery-lifecycle-test` replays the actual glare labels, confirms the legal
capture once, and then records real White and Black observations at formerly
labeled points. It checks expiry, changed review/target, replay, clock values and
restart. `--recovery-glare-test` checks the archived camera photo and six synthetic
transfers of photographed stones with their rims/shadows into the glare region.
Those composites are regression probes, not measured live-placement accuracy.
The user also supplied a real matched Empty → White → Empty sequence at L15
without moving the camera or changing the lighting; all three frames are required
and checked exactly, independently of the synthetic probes.
`--recovery-ui-test` covers the native pipeline, lights off/on and photo approval
invalidation on camera interruption. `--camera-test`, `--correction-test`,
`--online-test` and `--review-queue-test` cover retry limits, Stop, label isolation,
no submissions from labels and legal review persistence.

## Obstruction and recovery feedback (0.125)

Surviving distributed stone landmarks plus partial loss of outer rails suggest
a temporary obstruction. This is an obstruction hint, not semantic hand detection;
a measured large camera shift overrides it. Invalid frames remain excluded from
move confirmation. Likely obstructions get eight seconds before full-grid search
or a short spoken prompt; other alignment failures get five seconds. Lighting
advice also waits eight seconds, allowing ordinary hand movement to finish.

After an interruption lasting at least 0.8 seconds, five fresh clear frames over
at least one second produce “Board view clear.” If local clocks remain paused,
the message says so. An existing clock-resume announcement supplies the recovery
acknowledgement instead of adding a duplicate. Redraws, frozen frames, short
flicker and camera gaps cannot supply stable recovery evidence. A renewed
obstruction cancels pending all-clear speech. This feedback does not resume play.

When a capture or board restoration remains unresolved and clocks are stopped,
the main transport opens that correction instead of offering Resume or Pause
checking. Its guidance explains the outstanding action; the unknown-turn prompt
does not compete with a capture that already establishes the next player.
Clock and board controls share one attached review sheet (since 0.127).
An expired camera witness shows the capture diagram as the last known position,
rather than claiming the previously seen stone is still present. Confirmation
still requires fresh alignment and clear evidence at the corrected intersections.

`--obstruction-feedback-test` replays the reported hand-wave geometry evidence,
checks speech timing/lifecycle and runs the photographed covered-border cases.
`--recovery-ui-test`, `--lighting-test` and `--bump-test` cover the camera delivery
path, unchanged saved games/references, lighting adaptation and real movement.

## Undo a move

Local play exposes **Undo move…** beside the board heading. It pauses recording
and clocks, previews the previous position, and identifies both the last stone
to remove and captured stones to replace. **Confirm undo** becomes available
after fresh camera frames verify that restoration. A pass has no stone changes.
Pending detections or unresolved reviews must be handled first. Cancel leaves
the recording unchanged and paused; after confirmation, resuming remains explicit.

Undo backs up the original SGF and its clock, review and pending-history sidecars.
Known per-move clock history is restored; otherwise current clock readings are
preserved and require review. Reviews whose moves were later undone retain their
source snapshots and identify the undone move numbers. A failed save offers a
save retry without undoing another move.

Online play provides **Request undo…**, **Accept undo**, **Decline** and
**Cancel undo request** through SGF Player’s existing OGS takeback API. Both apps
must be updated to use these controls from Physical Go. Older SGF Player builds
show an **Undo in SGF Player…** shortcut instead. The opponent/server decides the
takeback, and the server clock continues. Leave stones in place until OGS updates
the board, then follow the physical restoration marks. New camera moves are held
while an undo is being negotiated; an approved undo requires synchronization so
the old stone cannot be sent again as a new move.

`--undo-move-test` covers local capture/pass restoration, fresh frame provenance,
stale previews, duplicate confirmation, save failures, clock checkpoints and
review audit/restart. It also checks online action validation, old peers,
disconnects and physical synchronization after a takeback. `--online-test`
checks the existing move bridge; the regular SGF Player release build verifies
the publishing/OGS side without connecting to a live game.

## Physical correction guidance (0.122)

Version 0.123 fixes confirmation being blocked by limited uncertainty away from
the correction. The actual affected intersections must remain clear, and any
positive contradiction still blocks confirmation. Broad unreadability uses the
same more-than-one-third boundary as camera continuity. Disabled confirmation
now explains missing/stale frames, affected unclear points, differing locations,
broad obstruction, or a matching view still accumulating evidence. The regression
fixture includes 20 consecutive live frames with 22–29 unchanged uncertain points.

Review distinguishes an incomplete legal capture, a possible neighboring-stone
bump, missing recorded stones, new additions, color disagreements and mixed
changes. A capture shows only the captured stones still needing removal and
keeps the capturing stone identified. A possible bump offers restoration to the
saved intersections; missing stones can be restored if removed accidentally.
Actual moves and captures retain the sequence-review path.

Capture confirmation uses full game history, including turn and ko legality,
and saves exactly one move. Restoration adds no moves. Both require at least five
fresh matching camera views over 0.8 seconds, with clear evidence at every affected
intersection and no positive contradictions elsewhere. Stale, interrupted or
unreadable views cannot confirm a correction. These shortcuts apply only to the
last unresolved section with a matching saved context. Original snapshots and
accrued clock readings are preserved, and resuming remains explicit.

After a confirmed capture or restoration, spoken feedback waits until the clocks
actually restart: “Capture complete. Clocks resumed. White to play,” for example.
The next player comes from the running clock. The announcement plays once,
survives closing and reopening the game before resuming, and respects the existing
recovery-speech setting. A blocked resume or camera verification alone stays quiet.

`--review-queue-test` includes the three-stone capture with one stone left behind,
camera freshness and obstruction, illegal ko recapture, unrelated changes,
bumped/missing stones, persistence and native guidance renders.

## One-board guided review (0.111)

Review starts with the problem and two distinct choices: undo accidental stones or
enter the real move order. One board shows only relevant rings or sequence numbers;
passes, camera overrides and comparison details are collapsed. Cleanup uses fresh
camera observations so already-removed stones are acknowledged rather than shown as
still present in an old snapshot.

An accidental addition and later removal can now be resolved together. A proposal
replays all later known moves with the full rules history, preserves independently
legal later moves, and rejects unrelated gaps, captures that change the result, or
new placements at an excluded point. Confirmation requires fresh repeated evidence
that the extras are gone and retained changed points match. Source snapshots remain
in the review record; clocks stay paused and their accrued times are preserved.

## History-first confirmation and stable adjustment markers (0.110)

Unchanged recorded stones retain their identities through classification uncertainty,
without the former six-stone or proximity cap. New moves and capture removals require
fresh evidence; definite contradictions, illegal moves, broad obstruction of unknown
space, camera alignment loss and ambiguous new placement still prevent confirmation.
Retained identities no longer count against the unresolved-intersection budget.

Ordinary play draws orange markers only after repeated evidence of the same conflict,
capture issue or assignment ambiguity (four frames spanning at least 0.65 seconds).
Markers clear after five agreeing frames spanning 0.8 seconds. Classification flicker
on unchanged recorded stones stays in diagnostics. No history is rewritten by the
marker monitor, and missing outlines alone do not request stone adjustment.

## Actionable board verification (0.109)

While a move or resumed position needs verification, prominent orange rings mark
camera readings that block confirmation, including uncertain previously recorded
stones. History-tolerated uncertainty is excluded. Click a ring or Check highlighted
intersections to open the frozen correction editor at that intersection; explicitly
label Black, White, or Empty. The frozen editor retains the rings until corrected.
The pause control says Pause checking while automatic verification is underway.
These display changes do not loosen recognition or accept a pending move.

## Explained automatic clock pauses (0.108)

Automatic stops retain their original cause next to the clock controls, even when
alignment recovers or the player chooses Keep paused. The message explains the
current next step, including an unconfirmed move or clock review. The cause survives
restart and clears when clocks actually resume or the game ends. A short bundled
spoken notice draws attention to the screen, respects recovery-voice settings, and
is limited to once per ten seconds. Manual pauses remain manual through subsequent
camera interruptions. The recording journal includes the pause cause and timestamp.

## Byoyomi period bars (0.144)

Both clock sizes show one bar for each remaining byoyomi period. The last visible
bar's fill shrinks inside a fixed outline with the current period; an on-time move
refills it, and exhausting a period removes both fill and outline. Fill is green
at 50% or more remaining, yellow below 50%, and red below 20%, based on the configured
period duration. Recognition-time corrections restore bars from the same clock
state used for the digits and voice. Fixed slots prevent the surviving bars from
growing or moving when one disappears. Main-time bars are full green reserves; pausing
freezes them. The final bar disappears at timeout. VoiceOver describes the remaining
period count and current allowance, and larger configured counts wrap into fixed rows.

## Spoken recognition-time corrections (0.106)

If recognition restores a byoyomi period after a lower count began playing, speech
announces **Corrected: Black, 3 periods left** (with the actual restored count). The correction
belongs to the player who just moved, applies to confirmed and deferred move histories,
and respects the period-announcement preference. Ordinary moves and unspoken lower
counts remain quiet. Opponent overtime entry waits until the correction finishes;
speech logs include the player, period count and correction flag. Counts 1–10 are bundled.

## Crowded-board restart and automatic clock holds (0.105)

Recovery first checks the retained grid against known stone colors and uncovered
grid segments. At least 80% of distributed stone landmarks, 65% of tested exposed
segments, all four outer rails and all four quadrants must support it. Small scale
or pose changes are refined from exposed outer lines, bounded to a quarter cell,
then independently checked again. This avoids a projection search through crowded
rows while preserving the separate empty-board reference geometry. Larger changes
still use the existing full-view recovery.

When recording is armed but vision has stopped the clocks, the play heading says
**Waiting for board · clocks stopped**. The transport offers **Keep paused** to
cancel automatic resumption, rather than presenting the state as ordinary play.

## Review completion and speech feedback (0.104)

The saved-review completion notice closes when recording or clocks resume from the
main screen, or when the game ends. An unfinished review editor remains open.

Byoyomi speech announces entry and subsequent period losses separately for each
player. Starting another turn with the same count, pausing/resuming and restoring
saved clocks do not repeat the count. Entry phrases for 1–10 periods are bundled.

Camera and lighting guidance share one speech queue. A warning already speaking
finishes when the view recovers; an obsolete warning that has not started is cancelled.
Mute, camera stop and camera freeze still stop speech immediately. Clock announcements
retain immediate cancellation when the turn changes, so an old countdown cannot
continue into the next player's turn.

The lightweight observations journal records speech requests, playback starts,
completion and interruption reasons. Entries include phrase, source, utterance ID,
elapsed playback time and bundled clip duration when available. This works independently
of diagnostic image collection and adds no image storage.

## Setup, explicit Start and out-of-turn review (0.103)

**Save game setup** creates a ready, paused recording. The play screen presents a
large **Start** button; the clocks wait for that action and verification of the empty
board or handicap setup. A single start cue respects the recording-sound mute setting.
Subsequent presses pause/resume normally. The ready state survives an app restart,
and passes, manual moves and scoring stay unavailable until play starts.

**Check alignment** reports Checking, Alignment passed, or a failed check with concrete
camera-position instructions. Completed checks offer **Check alignment again** in the
same fixed-height layout.

Reviews with decisive out-of-turn evidence explain the detected first stone, expected
player, why that order cannot enter the record, and the available corrections. Color
overrides are tucked under an explicit camera-color correction disclosure. For the
latest addition-only section, players may confirm that they removed accidental stones
and withdraw those moves. This preserves the original snapshot and correction reason,
adds no fabricated pass, retains prior moves and clock totals, and stays paused for
physical-board verification on resume. Captures and sections with later play cannot
use this shortcut.

## Scoring handoff and confirmation (0.102)

AC-powered analysis stays warm across short camera-confirmation gaps. Score game reuses
ownership and score from the matching position, including continuous-search snapshots;
a sufficient cached result opens immediately. A partial result remains visible while
the existing worker finishes the requested search. Battery operation remains on demand.
Analysis identity includes Go history, setup, rules, komi and handicap, but excludes
player names, clock metadata and resignation results. Opening scoring never changes a
recorded result.

Crowded positions may retain up to six uncertain established stones (at most 10% of
accepted stones). Beyond two, none may be adjacent to a changed point. Definite contradictions, new placements and capture removals still
need direct evidence. The three-view clear-move shortcut permits the same distant
historical uncertainty, while interruptions and ambiguous placement still block it.

## Setup and Play workspace (0.89)

The top **Setup / Play** switch changes presentation only; it never pauses recording
or the camera. Local/online mode changes remain separate and pause the local game.

- **Setup** proceeds through Game → Camera & board → Ready to play. Players, rules,
  handicap and clock settings expand under the first step. Camera source and advanced
  alignment/reference controls expand under the second. Starting a game opens Play.
- **Play** keeps the turn, recording state, clock, pass, scoring, end-game and SGF export
  controls visible, followed by one interpreted-board panel. **Live position** is the
  default; **Saved moves** and **Live feed** are explicit tab choices. Warnings do not
  insert another camera view or change the selected tab. Camera setup stays in Setup.
  The online board stays visible to show the opponent’s marked move.
- **Info & settings** opens a sheet for game metadata, clock configuration, feedback,
  recovery speech and analysis settings. **Clock options** contains large-clock and
  adjustment commands. Timed games use the clock’s pause/resume action, with a separate
  recording resume only when the clock was deliberately left running while recording paused.
- **Diagnostics** is a disclosure independent of collection. Continuous camera images
  and automatic unusual-move clips have separate controls. Live recognition, timing and
  tracking data have a second disclosure. Capture indicators remain outside the disclosure.
  Lightweight game decision/timing journals remain enabled. Unusual-move capture and
  storage-limit preferences persist; continuous image recording requires explicit start
  each launch. None of these controls changes or discards the recorded game.

`python3 PhysicalGo/build.py --workflow-ui-test` checks presentation transitions,
collection/display independence, persistent choices, game preservation and clock-review
states, and renders native dark/light and enlarged-text layouts. Layout rendering uses
saved test state without a physical camera or an online move submission.

### Independent live play, clocks and scoring (0.94)

The review queue no longer stops the clock or blocks scoring. Color counts can
identify the next player even when same-color moves are unordered. If the turn
cannot be established, recording continues and a Black/White turn confirmation
restarts the clock independently of historical review. Unknown earlier clock
presses are not fabricated: existing times are retained, a nonblocking timing
note offers adjustment, and subsequent observed moves use the usual increments,
overtime, and first-sighting recognition-delay accounting.

Clock presses have stable event identities in the clock checkpoint. Finishing
historical reviews associates those presses with SGF move numbers without
charging time again or resetting clocks. Restoring a game preserves live clocks
and review events, paused until explicitly resumed. Explicit Pause stops both
clock and recording; camera interruption behavior remains separately configurable.

End Game now ends live play even with outstanding reviews. Score Game analyzes
the latest stable board, including stones after a gap. Japanese/Korean scores
require players to confirm total prisoners before saving an agreed result;
area scoring does not. AI ownership is converted to a current-board count when
history is incomplete, avoiding a misleading territory estimate from missing
prisoner history. Dead groups and neutral areas remain reviewable. The agreed
result and live scoring board are saved separately from incomplete chronology;
if subsequent corrections change that board, the stale result is cleared.

Red review buttons remain available after End Game. All reviews must be resolved
before exporting the complete SGF. Background analysis follows the live board
only on external power; battery use remains on request. Tests:
`--live-play-test` (including an actual local KataGo request),
`--review-queue-test`, and `--clock-review-test`.

### Review queue and recording past gaps (0.93)

An unresolved multi-move change opens a numbered review section while camera
recording continues. Stable later single moves, their capture changes, and
first-seen/confirmation timestamps are stored independently of the ambiguous
section. Further ambiguous changes create additional sections. Brief flicker
never opens a section; an isolated unresolved candidate gets the existing
recognizer's opportunity to settle before a review is opened.

The Live position board has a right-hand review rail: red **Needs review**
buttons, green **Resolved** buttons, and preserved snapshots for every section.
Sections may be resolved in any order. Click the missing stones in sequence,
include passes or previously captured stones, then save the review. Explicit
camera overrides support correcting false detections, including a no-move
section. Full chronological replay checks turn order, captures, ko and final
positions; a newly discovered conflict reopens the affected section instead of
silently accepting it. Once all sections validate, the recovered suffix is
written to SGF once, and green review buttons remain available for inspection.

The `.reviews.json` sidecar is saved atomically after every stable transition
and resolution. Autosave SGF retains the accepted prefix until the queue is
resolved; export and scoring are gated while it is incomplete. Resume continues
camera recording after a gap, while clocks stay paused until the reviewed
sequence and clock times are confirmed. End game stops recording and preserves
the queue for later completion. Explicit passes can be recorded once the later
player-to-move is known. Recovering the suffix never invents missed clock times.

`--review-queue-test` exercises three gaps, later ordered moves and captures,
out-of-order resolution, restart, transient noise, full-history ko conflicts,
passes/end-game, corrupt sidecars and interrupted finalization. Tests operate on
temporary recordings; native render tests do not click the user's live dialogs.

### Ordering missed moves and live feed (0.92)

The Live position board offers **Order missed moves**. It pauses recording and
clocks, holds the camera interpretation steady, and lets players select the
missing moves in order. Numbered markers, undo, clear, passes and explicit camera
color overrides support review. The normal Go rules validate captures, ko and
suicide. Approval validates the complete sequence against the unchanged saved
game, saves it with manual provenance, and replaces tentative history only after
saving succeeds. Clocked games then require confirmation of both times; all
resumes wait for physical-board verification. Cancel leaves saved moves intact.

The board area now has Live position, Saved moves and Live feed tabs (plus the
optional detection inspector). Camera detections outside saved history have a
separate count, even when there is no retained pending sequence. Live feed uses
the same oriented camera renderer with calibration gestures disabled.

`python3 PhysicalGo/build.py --move-recovery-test` checks draft isolation,
turns, captures, ko, stale/double approval, failed-save rollback, clock review,
SGF restore and native numbered boards in all four rotations.

### Prominent clock transport (0.91)

A single large play/pause button beneath the two clocks controls both timing and
recording. Its text identifies Pause, Resume, or Review & resume; clock review
still opens the existing confirmation sheet before any restart. The same control
appears in the expanded clock view. Recognized moves continue to switch players
automatically.

### Clock-focused Play view (0.90)

Local clocks lead the Play view, with 160-point digits that scale down only to fit,
28-point two-line overtime descriptions, and compact routine recording status below.
The active player's clock uses a red border, digits and subtle background when time
remaining is at most 10 seconds. The ordinary active border returns once remaining
time exceeds 10 seconds, including a fresh longer byoyomi period, or the turn changes.

Issue guidance highlights the next useful control: red with an explanatory label/icon
for required camera/board review and clock review, amber for ongoing checks. It does
not promote End game, manual board overrides or ordinary Resume as error actions.
Hidden camera problems lead to the camera view, where start/resume/restart controls
are highlighted as applicable. Existing recovery banners still ask for physical
camera/lighting adjustments when a button alone cannot resolve the problem.

## Run

Open `/Users/Dave/Applications/Physical Go.app` after the first installation.
Normal launches reopen the last explicitly used local recording before starting
the camera, with clocks paused. Saved stones are available immediately for grid
recovery; Resume still requires live board verification. Online mode and sample
launches do not automatically restore a local game. The app remembers a recording
path rather than selecting whichever SGF or diagnostic log was modified last.
To rebuild and launch from source, double-click `Run Physical Go.command` in this folder,
or run `python3 PhysicalGo/build.py` from the repository root. The build uses Xcode's
Swift compiler, requires macOS 14 or later, and creates `.build/Physical Go.app`.
It uses its own bundle identifier and does not replace SGF Player or its settings.
Normal app builds use an installed Developer ID Application certificate, or an Apple
Development certificate when no Developer ID is available. Set `PHYSICAL_GO_SIGN_IDENTITY`
when more than one identity is available or to pin a particular certificate. Builds fail
rather than silently switching to ad-hoc signing. An explicit `-` override is available
for disposable test builds, with a warning that permissions may be requested again.

On launch, the app opens the last-used camera and requests macOS camera permission if needed. If denied, enable
Physical Go in System Settings → Privacy & Security → Camera. No microphone is requested.
This is separate from the USB/Thunderbolt Accessories setting. Before 0.7, ad-hoc signing
changed the app's designated requirement on every rebuild. Version 0.7 uses a stable
certificate-based requirement. The transition may require one more Camera approval;
subsequent updates should preserve it when the signing identity remains consistent.
No system privacy database or accessory policy is modified.
The app starts camera preview automatically, but recording begins only after you press Record.
Opening a saved sample with `--open-sample` leaves the camera off. No images are sent over the network.

## First test with Dave's board

1. Use one board and its usual black and white stones. Connect a USB webcam and fix it
   above the board so all four outer grid intersections and a margin are visible.
   Begin with even lighting; avoid moving the camera, zoom, or board during a test.
2. Wait for the last-used webcam to start automatically, and choose 9, 13, or 19 intersections.
   To change cameras, stop preview, select the webcam, and click **Start camera**.
3. Keep the full board visible while the app automatically finds the grid; stones may
   already be present. Check that the
   cyan lines overlay the printed grid across the entire board. A green **Grid detected**
   indicator appears when ready. While the live view is uncalibrated, failed searches
   retry on fresh frames at most once every two seconds. **Find grid now/again** is an
   optional override. If needed, choose **Manual corners** and click the
   **top-left, top-right, bottom-right, bottom-left playable intersections** in the
   camera image—not the corners of the wood. Automatic detection uses the selected size.
4. Detection starts immediately after calibration, without an empty-board reference.
   If the entire board is visibly empty for several fresh frames, the app captures a
   reference automatically. **Capture empty reference (optional)** is still available
   after you remove all stones and hands; **Use without reference** returns to local
   appearance detection.
5. Place black and white stones at several corners, edges, and the center. Compare
   the camera overlay and small detected board with the physical position. The detected
   board includes nine star points on 19 × 19 and five on 9 × 9 or 13 × 13 for reference.
6. Click **Freeze**. On the small board, click any wrong intersection to cycle its
   label through empty → black → white → uncertain. A blue ring marks a manual label.
   Labels apply to this frozen sample only; **Resume** clears them.
7. Give the sample a descriptive name such as `Kaya board / overhead lamp / black slate`.
   Click **Save sample…** and select a new folder name. Saving a live view freezes it.
8. Repeat with adjacent stones, a crowded group, glossy highlights, and a hand entering
   and leaving the image. Include failures; they are particularly useful for improving
   recognition. A stationary hand can look like stones in this early detector.

Start with one board under one light, then vary one factor at a time. Use a separate
empty-board reference for each board/lighting combination. Small camera bumps recover
automatically; recalibrate after larger moves or when recovery cannot verify the grid. Different boards and lighting are valuable test material;
we do not yet need an exhaustive collection.

Stone sets are an independent test variable, not a property of the board. Test different
sets on the same board under the same lighting before combining variations. Include matte
and reflective black/white stones, thin and thick stones, and adjacent crowded groups.
Record black and white materials/finishes separately when they differ. Reflections can
change apparent brightness, while stone height and camera angle affect apparent position
and occlusion. The current detector has not been validated across these variations;
future recognition should avoid assuming uniform stone brightness or one fixed profile.

Useful details to report: webcam model, mounting arrangement, board size/material,
stone material, finish (matte/polished/glossy), thickness (millimeters if known, otherwise
thin/medium/thick), lighting description, and which intersections were wrong. Share the
whole saved sample folder, especially one successful and one problematic example.
If no webcam is ready, **Open photo…** also works: load an empty-board photo, calibrate,
capture its reference, then open a photo with stones from the exact same camera position
and image dimensions. EXIF orientation is honored. A change in dimensions clears calibration.

## Saved samples

Each new sample folder contains:

- `frame.png`: the camera/photo frame actually analyzed, with no overlay baked in.
- `empty-reference.png`: the empty-board baseline, if captured.
- `sample.json`: schema version, source name, notes, image dimensions, board size,
  current and optional reference four-corner projective calibrations (schema 3), detection
  mode and automatic-reference provenance, alignment-recovery
  status, threshold, per-intersection candidates and optional
  manual labels, plus `displayQuarterTurns` for the display orientation. Images and
  coordinates remain in the original camera orientation. Row 0 is the top; column 0
  is the left. Manual-label keys are
  `row * boardSize + column`. Unlabeled detections are **not** ground truth.
- `position.sgf`: only when all intersections are classified (including overrides).
  Uses SGF setup properties `AB`/`AW`, not a fabricated move sequence. It opens in
  SGF Player. Verify its stones against the physical board.

Samples are only written when explicitly saved. This experiment does not continuously
record video, infer passes, or send moves online. The recorder preserves accepted history
through camera interruptions; passes are explicit controls.
A stalled or interrupted stream triggers up to two automatic reconnections. The app waits
for actual frames before saying Live, allows eight seconds for startup, and detects five
seconds without fresh frames during capture. After retries are exhausted, use **Restart
camera**. Image-content checks also detect severe whole-frame blur sustained for at least
0.8 seconds and repeated original-pixel fingerprints for at least 1.5 seconds.
The detector samples sensor noise, so an unmoving live board is not classified
as frozen just because its stones stay still. Blurred placeholders are withheld
from recognition. Reconnects use the selected camera and the same two-attempt
budget; unusable frames cannot replenish it. Automatic clock protection remains
in effect during recovery, followed by fresh-board verification. A brief outage
still cannot establish the timing of a move made out of view. `--camera-test`
includes the recorded blurred phone image and sharp board/reference controls.
Camera restarts preserve the paired empty reference and calibration and validate a fresh
frame before detection resumes. Frozen samples remain available for saving. A different
camera, image size or full-view recalibration invalidates active reference reuse. Stop
cancels pending recovery. Existing sample folders
are never overwritten. A save failure can leave a partial new folder; choose a new name
when retrying. Images remain on the Mac unless you choose to share them.

## Shared code and future mobile support

`build.py` compiles the authoritative `SGFPlayerClean/Models/OGSModels.swift` and
`OGSScoringState.swift` by reference. This shares `Stone`, `BoardPosition`,
`BoardSnapshot`, SGF coordinates, parser and writer without a fork or copies.
The scoring source satisfies the existing model file's dependency. The experiment does
not instantiate networking or analysis services. Recorder builds additionally share
`SGFPlayerEngine.swift`, with the playback-preference subscription excluded only for
the `PHYSICAL_GO` build.

`Sources/BoardVision.swift` contains the projective calibration, grayscale sampling,
classification, optional normalized color samples, stability check, and SGF position adapter. It imports only Foundation
and CoreGraphics and is kept separate from camera lifecycle and the desktop interface.
`Sources/AutoGridDetector.swift` adds Vision-based automatic calibration.
These recognition components can be reused on iOS/iPadOS. `CameraCapture.swift` is the
Mac AVFoundation adapter; `CameraHealth.swift` holds the bounded timeout/retry policy; `ExperimentModel.swift` owns the Mac lifecycle and file panels;
`ExperimentView.swift` is the first desktop interface. A mobile application will need its
own capture orientation, lifecycle, permission and export integration, plus device testing.
The current shared model file is larger than this experiment needs; extract a dedicated
shared Go module when there is a concrete reason, without duplicating the model today.

## Algorithm and limits

Automatic calibration uses Apple's on-device Vision rectangle detector to propose a
search area. If the original view produces no verified grid, it retries rectangle
proposals at three smoothing scales proportional to image resolution. This suppresses
fine grid/background texture during outline detection. The grid itself is always fitted
and validated on the original sharp frame. It rectifies each proposed area, finds two
families of regularly spaced dark lines,
refines the four outer grid lines, and checks the predicted rails against the original
image. The blank wood margin and the printed grid are distinct: a wood rectangle alone
is insufficient. The selected 9/13/19 size must match; extra lines reject plausible
subsets of a larger board. Processing runs in a background queue, and stale results are
ignored after manual edits, source changes, Stop, or camera interruption.

This first implementation expects a mostly clear board, the full grid and a visible
margin, reasonably sharp lines, and a near-overhead view. Heavy stone coverage, glare,
strong perspective, other grids in the scene, or a weak board outline may prevent or
mislead detection. Live setup retries automatically until calibrated; still photos
use one attempt, with **Find grid now** available to retry. Manual corner selection,
Freeze, and Stop cancel automatic work; Resume rearms an unfinished automatic setup.
It does not continuously track board movement. Always inspect the cyan overlay; use
manual corners when necessary. Detecting a new grid clears the old empty reference.
The app never assumes that an automatically calibrated image is an empty board.

The detector fits a projective transform from automatically found or manually selected
grid intersections.
For each intersection it compares a disk of small grayscale patches against the empty reference.
Each patch averages 3 × 3 image pixels to reduce pixel noise.
It skips the central grid-line cross and excludes reference samples substantially darker
than the local wood, reducing interference from grid ink when alignment is imperfect.
The white-stone contrast threshold adapts to the local board brightness with a noise floor;
most retained samples must still agree. Modest exposure drift is estimated from
wood at cell centers between intersections. A nearby neighborhood median handles smooth
spatial variation; a global estimate is used when local evidence is insufficient. Excessive
local changes remain uncertain; large uniform changes mark the whole observation
uncertain and request a fresh empty reference. Consistently darker/lighter samples suggest
black/white; small changes suggest empty; mixed evidence is uncertain. An uncertain
intersection with substantial single-color evidence can search nearby sample centers
within 0.3 grid spacing. Each retry still requires 80% agreement and enough reference
wood. Neighboring candidates with overlapping centers are checked for competing claims;
ambiguous ownership stays uncertain. The grid calibration itself stays fixed.

Color camera frames retain sRGB samples in addition to grayscale. Local normalized-color
shifts are estimated from bare-wood gaps. A loss of the wood's tint can corroborate a
white stone even when brightness contrast is small, but positive brightness evidence
is still required. Where printed ink can be located in the empty reference, color-based
white evidence also requires that ink to be covered in the live image. Coverage alone
cannot create a stone. Grayscale inputs retain brightness-based classification. The threshold is adjustable.
Five identical fully classified frames light the stability indicator. **Stability is not
proof of accuracy**, and the heuristic confidence value is not a calibrated probability.

This deliberately simple baseline needs real-board evaluation. It does not yet compensate
for lens distortion, abrupt or large exposure changes, board movement, strong shadows, glossy stones,
white stones close to the board's brightness, or a hand obscuring intersections. It has no
hand detector and does not perform legal-move validation. Camera processing is limited to
about five frames per second and runs off the main interface thread. Image/overlay pairs
are presented together; stale results are rejected after calibration and source changes.

Later milestones: benchmark real samples; improve recognition and uncertainty handling;
add rule-aware move reconciliation, correction and autosaved game history; test complete
local games before tournament reliance; then add online guidance. Mobile tournament capture
is an intended future consumer of the same recognition core.

## Verification

From the repository root:

```sh
python3 PhysicalGo/build.py --test
python3 PhysicalGo/build.py --camera-test
python3 PhysicalGo/build.py --grid-test
python3 PhysicalGo/build.py --preview
python3 PhysicalGo/build.py
```

The first command exercises projective geometry, corner validation, grayscale image
orientation, 9/13/19 classification, uncertain-state export protection, stability transitions,
and round-trip export through the existing SGF parser. It creates synthetic photo fixtures
and replays `Tests/Fixtures/EdgeStones`, a real saved example with white A4 and black F1.
The camera tests cover startup/stall deadlines, bounded retries and cancellation.
The grid tests check real empty/occupied images, downstream edge-stone recognition,
synthetic 9/13/19 boards with perspective and rotation, wrong sizes, plain borders,
stripes, and an incomplete board. The clear-board failure saved under
`Tests/Fixtures/GridOutlineFailure` covers a raw camera image with zero initial rectangle
proposals and a screenshot crop with an interior-only proposal. Seven grayscale-derived
brightness/resolution/translation/rotation variants check that calibration remains near
independently annotated corners. Wrong-size checks also run on the new raw failure frame.
The preview checks the model workflow, labeling, exported sample contents, overwrite
protection and reference invalidation after recovery, and renders welcome/detection screenshots under `.build`. It does not request
camera access. The single real regression sample does not establish general live accuracy.

### Camera recovery update (0.2)

The first hardware session encountered a freeze that resumed after opening the camera in
Zoom. Its exact cause was not established from the available logs. Version 0.2 adds the
frame watchdog and recovery above, rejects old callbacks after Stop or camera changes,
and eagerly renders camera frames before the UI retains them to avoid holding deferred
references into the capture buffer pool. Camera status transitions are logged locally
under subsystem `com.davemarvit.PhysicalGo`, category `Camera`; images are not logged.
Automated recovery/model checks pass, but recovery from the specific physical webcam/hub
freeze still needs a live retest with Zoom closed.

### Edge-stone detection update (0.3)

The saved `Edge Stones Physical Go Sample 2026-11-01 09-22-49` reproduced the previous
detector's output: one black stone, no white stones, 345 empty and 15 uncertain points.
Its visible ground truth is white A4 and black F1. The white stone had insufficient
agreement under the old fixed brightness threshold; grid-ink samples contributed to the
uncertainty at empty intersections. Reference-based ink filtering and adaptive white
contrast now produce one white, one black, 359 empty and zero uncertain points on that
same frame at the original threshold. No manual labels or coordinate-specific exceptions
are used. The unchanged original sample is preserved as a regression fixture, with
visually checked expected positions in `expected.json`.

Tests also cover white stones on bright wood, moderate local shadows, uniform exposure
drift and ink outliers. A live edge/corner retest with different stones is still needed;
one saved frame cannot establish that flicker is eliminated. Camera/board movement still
requires recalibration, and a material lighting change requires a new empty reference.

Replay another saved sample without opening a camera:

```sh
python3 PhysicalGo/build.py --inspect-sample "/path/to/sample folder"
```

This emits JSON classifications plus raw sample brightness statistics. The comparison
with stored classifications is expected to differ when an updated detector corrects a
previously misclassified sample. The tool does not modify the saved folder.

### Automatic grid calibration update (0.4)

Camera startup now attempts automatic grid detection, with **Detect grid** to retry and
**Manual corners** as a fallback. A full-size fit and a check for extra lines in the
supposed wood margin prevent a one-row shift seen during development on the saved
occupied image. Real-image checks find the four playable corners within 10 pixels of
hand-estimated landmarks in both saved frames; this is one board/view, not a general
accuracy measurement. Both calibrations preserve the two edge stones and clear empty
intersections. White-stone contrast tolerance was modestly widened to accommodate the
shading sampled by the more accurately aligned grid, while retaining the noise floor
and 80% sample-agreement requirement. Live testing across boards and lighting remains
necessary. The detector uses no network service or additional runtime dependency.

### Grid outline recovery update (0.5)

A clear live view failed even though 0.4 passed the earlier saved examples. The new raw
sample reproduced zero board proposals, preventing the grid fitter from running at all.
The preceding screenshot yielded only a small rectangle inside the grid. Version 0.5
adds resolution-scaled smoothing solely to propose candidate board outlines; existing
full-grid, corner-line, wrong-size and wood-margin checks still use the original image.
It stops after the first pass with a verified grid, keeping successful original-frame
calibrations unchanged. Both failure images are now regression fixtures, and the native
UI replay verifies calibration followed by an empty reference. The failure message also
avoids assuming that the user needs a clearer view. This update still needs live testing;
these examples do not establish accuracy across different boards or all lighting.

### Local brightness and stone placement update (0.6)

The saved `Physical Go Sample 2026-11-01 11-34-44` has four stones: white A5 and K11,
black A1 and D4. Version 0.5 recognized only three, with white A5 and 18 empty points
uncertain. The live/reference pair shows spatially varying brightness drift, and the
white edge stone is slightly off-center. Version 0.6 adds local exposure correction,
small patch averaging, and a tightly bounded stone-center search. It does not lower the
stone contrast threshold or sample-agreement requirement, and does not change automatic
grid detection. The exact saved calibration now yields two white and two black stones,
355 empty points, and two uncertain empty points. Those unresolved points still block
SGF export until manually verified. The original saved files remain unchanged.

Tests cover the new fixture, one-pixel calibration perturbations, offset stones at each
edge, smooth brightness drift, excessive local changes, small bright specks, and the
previous real samples. Live performance across stone sets and lighting still needs testing.
The camera currently requests 1920 × 1080 capture; a future 4K comparison needs an explicit
capture-format option as well as suitable hardware. More resolution alone does not fix
these illumination/classification failures.

### Permissions, placement and view controls (0.7)

The captured `CenterFlicker` fixture reproduces uncertain white H10 next to black J10.
The revised classifier recognizes all nine stones (4 white, 5 black), with all 352 empty
intersections clear. Tests include the preceding successful `AdjacentOffset` capture,
small image/calibration perturbations, low-contrast white stones on warm wood, visible
versus covered grid ink, white-balance shifts, real adjacent stones, and a deliberately
ambiguous stone between intersections. These are regression checks, not general accuracy
claims or validation of all live flicker cases.

Display rotation is shared by the camera overlay, detection board, star points, and tap
mapping. Saved raw images and SGF coordinates do not rotate; metadata records the view
orientation. Preview tests cover all four manual-corner orientations, Undo, reference
preservation, rotated export, automatic retry after a failed frame, and manual override.
The rotation button appears beside the frame count; the green grid indicator appears
under the board-size control. The empty-board reference still requires explicit capture.

The build now signs with a certificate-based identity. Two different test binaries were
verified to have different code hashes and identical designated requirements. Permission
retention across a later installed app update still needs an actual user confirmation.
The signing rationale follows Apple's TN3127: https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements

### Perspective-corrected preview (0.8)

**Straighten board** is on by default and takes effect after grid calibration, even
before an empty reference is captured. The live image, overlay and hit testing share
one perspective mapping. A 0.75-intersection border keeps outer stones visible. Rotation
works on the corrected view. Uncheck the control to inspect the original camera image.
Recognition, reference frames, sample PNGs and SGF coordinates remain in source space.

The displayed grid uses standard 22 × 23.6 mm spacing (about 7.3% longer in one direction):
https://www.britgo.org/learners/make.html . The app automatically fits both possible
long-side orientations using orthogonality and aspect constraints on the grid homography.
It assumes square camera pixels, no skew, a principal point near the image center, and
an unknown focal length in a broad range. Confidence requires a clear fit advantage
that survives small principal-point changes. This is an estimate, not lens calibration:
a single view, especially an axial tilt, can fit both orientations. The UI distinguishes
“Long side detected” from “Long side estimated” and offers an optional **Swap long side**.
No orientation question is required before viewing the corrected board. Aspect is chosen
once per calibration to avoid live flipping. Lens distortion, cropped/rescaled input and
nonstandard boards can affect that estimate; the warp does not correct lens curvature
or the height of stones above the board plane.

Tests exercise known camera projections with both physical long axes, deliberately
ambiguous views, inverse mapping through all four rotations, and raster landmarks at
corners and an asymmetric interior location. Model replay checks correction before
reference capture, toggling and swapping without changing recognition, raw exports,
rotation and clearing the corrected cache on calibration reset/undo.

### Small camera-bump recovery (0.9)

Each processed frame checks the printed grid near a fixed calibration anchor. Small
translations, rolls and perspective changes update the current homography; the original
empty reference and its calibration remain unchanged. Detection compares corresponding
board locations in those two images, including color, exposure and covered-line evidence.
The preview and overlays adopt the recovered geometry together with that frame's result.
No repeated image warping or incremental anchor updates accumulate drift. Small fit noise
is ignored, and a proposed movement must improve line-profile agreement with the anchor.

Recovery requires visible, validated grid rails and a move below 0.4 grid spaces from
the anchor. Blurred, obscured or larger movements pause recognition and show **Reacquiring
grid…**; uncertain alignment cannot export a position SGF or replace the empty reference.
A clear subsequent frame can resume automatically. For a larger move, use **Find grid
again** and capture a new empty reference. The small-bump path requires neither action.

The saved 12-36-03 fixture reproduces 221 uncertain intersections. Recovery leaves four
uncertain, recognizes eight black and seven white stones, and retains uncertainty at one
crowded white stone; alignment recovery does not claim to solve that recognition case.
Tests cover translations, rolls, repeated frames, whole-cell slips, blur/occlusion, earlier
successful stone samples, reference preservation, paused/recovered sample export, rotation
and cancellation of in-flight work. Run `python3 PhysicalGo/build.py --bump-test` for the
motion regression suite. Live testing with different camera motions is still needed.

Confirmed stone positions can become additional motion landmarks when game recording
maintains an accepted position. That future path must tolerate newly played/captured
stones, require agreement among multiple landmarks and verify the fitted grid; current
frame candidates alone must not redefine the coordinate system. This version uses the
printed grid, not a game history or stone landmark matcher.

### Optional reference and occupied-board tracking (0.10)

A calibrated frame is now classified even without an empty reference. Nearby cell centers
estimate wood brightness and color; a robust local brightness plane handles gradients
near the edges. Stone-sized patches and a bounded offset search identify black/white
candidates. An empty intersection needs both wood-like appearance and a visible printed
cross. The empty-board hypothesis is never accepted merely because no stones were found.

An automatic reference requires every intersection to be confidently empty on at least
five fresh live frames spanning at least one second. Uncertainty, stones, calibration
changes and interruptions break the sequence. Photos and display redraws do not count.
If the hypothesis fails, local appearance detection continues; it does not wait for an
empty board. The original explicit capture remains optional and requires the user to
clear the board. Choosing **Use without reference** suppresses automatic capture until
calibration is reset. All processing stays on this device.

Grid tracking first checks surviving line profiles across the established grid. It
requires broad spatial support and evidence on all four outer rails, rejecting blank or
blurred images and whole-row slips. This avoids repeatedly requiring a full fit when
stones cover some projection-profile peaks. Reacquisition is reserved for insufficient
alignment evidence. Stone-based game-history landmarks remain future work.

The occupied 13-05-51 sample is a regression fixture. Reference-free detection recognizes
all 21 stones (11 black, 10 white), with 33 empty intersections still uncertain at the
saved test settings. The earlier four-stone edge sample has no uncertain intersections;
other views remain less accurate. Do not mistake a successful stone count for complete
position certainty. SGF export still requires resolution of every uncertain intersection.
Some genuine empty frames stay uncertain and therefore do not become automatic references.

`--appearance-test` checks saved empty and occupied frames, a low-contrast wood-colored
occlusion, synthetic black/white stones, missing grid lines, and the fresh-frame gate.
The UI replay covers occupied startup with no baseline, reference-free sample export,
automatic capture on a verified empty live view, explicit opt-out, and occupied tracking.
The sample inspector supports both reference and local-appearance samples.

### Grained white stones and nearby wood samples (0.11)

The saved 13-22-35 sample caught white H3 as uncertain. In that exact frame the visible
line score was low enough already; the limiting factor was the white patch vote (10 of
12 samples), with an unreliable local wood fit. White detection now uses 32 spatial
samples at the same 85% agreement threshold. Black detection keeps its outer 12 samples,
so the additional inner samples cannot turn dark grid ink into a black stone.

Printed-line evidence is also kept separately for each direction: a single grain stripe
on a light stone must not count as a surviving grid cross. Synthetic checks reproduce
that distinct failure and cover both stripe directions at the center, an edge and a
corner. Cross-like marks in both directions remain ambiguous. Independently, one refinement
pass revisits uncertain intersections after excluding wood samples immediately adjacent
to confident stones; those samples can include stone edges and shadows. Newly promoted
candidates do not feed another refinement loop, and inadequate wood samples stay uncertain.

The saved frame now recognizes the correct 21 stones and reduces uncertain intersections
from 29 to 10. Tests perturb brightness and calibration and check every recognized stone
location, rather than just totals. Earlier occupied and empty samples retain their correct
stones without new false positives. Remaining empty-point uncertainty and live flicker
across boards, stones and lighting still require testing. Run `--grain-test` for this
regression, in addition to `--appearance-test` and the native UI replay.

### Automatic recovery after larger camera movements (0.12)

Three failed alignment checks on fresh live frames now trigger the same full-frame
search as **Find grid again**. Stones may remain on the board. The interface shows
local-check progress, full-view attempt counts, and paused recovery when frozen or
stopped. A failed search waits at least two seconds and requires another fresh frame
before retrying. After three unsuccessful full-view searches it shows **Grid needs
attention** with manual retry/corner instructions. Local tracking can still resume if
the original aligned view returns. Canceled searches do not consume the retry budget.

Recognition and perspective correction pause while alignment is unknown. A successful
full-view search establishes a new tracking anchor and resumes reference-free detection;
the previous optional empty reference is discarded only after the new grid is verified.
Small local corrections continue to preserve their original reference. In-flight results
are invalidated on reset, freeze, camera interruption, or a new search.

The `LargeCameraMove` fixture is the occupied 13-42-32 Desktop capture. Recovery recognizes
all 21 stones, with 10 empty intersections still uncertain. Native UI replay
checks automatic escalation, independently marked outer intersections, stable tracking
after recovery, bounded retries on an obscured frame, no retries from redraws, pause
status, resumption, and cancellation. It does not establish a maximum recoverable camera
angle or guarantee recovery on all boards and lighting conditions.


### Shadow beside a stone cluster (0.13)

The 13-52-09 `FalseBlack` fixture caught an extra black candidate at raw row 14,
column 15 (zero-based). The off-center search shifted toward two neighboring black
stones and their shadows. After excluding nearby stone-contaminated samples, the
local wood plane extrapolated brighter than the broader wood estimate; that made
11 of 12 outer patches appear dark enough to qualify.

Black patch votes now require darkness relative to both the local and broader wood
estimates. White classification retains its existing lighting and grain handling.
This removes the extra candidate while retaining all 21 real stones. The affected
empty point remains uncertain because the surviving line/wood evidence is insufficient;
this change does not force it to empty or hide it with temporal smoothing.

Run `--shadow-test` for the saved false detection and 27 small brightness/geometry
perturbations, checking every real stone and rejecting extra stones. Earlier edge,
off-center, grained-white, occupied and empty fixtures are covered by
`--appearance-test`, `--grain-test`, and the native UI replay.


### Off-center white stone with a reference (0.14)

The occupied `ReferenceOffset` sample from 14-06-35 contains 20 stones. The previous
reference classifier missed white at raw row 13, column 17 (zero-based), calling its
intersection empty. The stone is displaced and close to the reference wood in brightness.
A weak partial color signal did not initiate an offset search; centered ink-coverage
checks were also sensitive to small alignment changes.

Partial loss of the wood tint can now trigger the bounded offset search even when the
center appears unchanged. Near-equal brightness color evidence requires positive coverage
of the reference ink. Coverage checks follow the portions of the nearest printed rails
under the displaced candidate, rather than always sampling around the nominal cross.
The final 80% agreement, reference-wood support and duplicate-ownership checks remain.
Integer offset steps include both ends of the ±0.3-grid-space search symmetrically.

The saved frame now recognizes all 20 stones, including the deliberately aligned grain
examples. Five other intersections remain uncertain. `--reference-offset-test` checks
all real stones, rejects extras/duplicates, and varies brightness and current calibration
through 27 cases against the original reference. Existing placement tests cover colored
wood with surviving ink, white-balance drift, shifted printed lines, adjacent stones and
ambiguous placement. Native UI replay includes reference capture and the saved frame.

The earlier camera-bump fixture also improves: the previously unresolved white stone
at row 17, column 15 is now detected, giving all 16 stones with three empty points
still uncertain. Its regression now checks that real stone explicitly, rather than
expecting the known miss to persist.


### Shaded neighbors of displaced stones (0.15)

The `MultipleDisplaced` 14-21-55 sample already assigned all 21 stones correctly,
without duplicates. Twelve neighboring empty points were uncertain. Reference-backed
detection now revisits uncertain points for positive evidence of shaded wood: a modest
brightness change, retained wood color/texture in at least 75% of reference-wood patches,
and matching line contrast along at least 75% of the tested portions of each grid axis.
The line check tolerates small alignment differences; it requires reliable reference
ink and both directions. Disputed stone ownership and substantial lighting changes
cannot be resolved by this check.

Four of the twelve points are now confidently empty. Eight remain uncertain where
wood/line evidence is insufficient or obscured. Accepted stones are preserved. This
is a reference comparison, not yet a learned shadow-direction/shape model. Learning
local shadow patterns from confidently identified stones could later provide supporting
evidence, with independent wood/grid checks to avoid explaining away real stones.

`--displaced-neighbors-test` checks 27 lighting/alignment variations, exact stone
assignments, no duplicates, visible shaded wood, and an unresolved obscured grid point.
Synthetic comparisons require a shadow with surviving grid lines to be empty and an
opaque wood-colored object to remain uncertain. Native UI replay also covers this sample.

### Offline stone-outline experiment (Displaced round 2)

The saved 14-34-35 `DisplacedRound2` sample has 21 correctly assigned stones and 14
uncertain neighboring points. `Experiments/stone_footprints.py` uses the accepted
stones as seeds, rectifies frame/reference into grid coordinates, and fits elliptical
color-region boundaries over a bounded center/radius search. It is an offline analysis
using NumPy, OpenCV and Matplotlib, not an app dependency or a replacement classifier.
Scores measure mask fit, not calibrated confidence. The initial shape ratio uses the
sample's estimated board proportions; outlines are approximate and require visual review.

Run from the repository root:

```
python3 PhysicalGo/Experiments/stone_footprints.py PhysicalGo/Tests/Fixtures/DisplacedRound2 --output PhysicalGo/.build/round2-footprints
```

The outputs include fitted centers/radii, a full annotated image, detail panels, and
estimated body overlap with a radius-0.3-grid-space neighborhood of each uncertain
intersection. This neighborhood approximates the classifier's sampling area; it is not
an exact replay of its individual wood-filtered samples. In this capture five of the
14 uncertain neighborhoods overlap a fitted stone slightly (roughly 2–8% of area),
and nine do not overlap. The overlays follow the visible bodies, including the crowded
stones. This supports using outlines to distinguish stone-edge contamination from
surrounding shadow/lighting effects, but does not justify automatically labeling all
remaining areas empty. A future combined model should verify unexplained image evidence,
reject poor/overlapping fits, and preserve independently detected adjacent stones.
This offline experiment did not change version 0.15; native integration follows below.

### Native footprints and occupancy hypotheses (0.16)

`StoneGeometry.swift` ports the outline experiment into the portable Swift detection
path. Accepted stones seed elliptical body/ring fits using reference-relative color
and brightness evidence. Low-quality, search-limit and conflicting fits are excluded.
The fits refine uncertain points only; accepted stones, disputed ownership and excessive
lighting changes remain protected. This currently requires an empty-board reference.

For each uncertain neighbor, the detector considers a family of additional-stone
placements consistent with nearby fitted sizes and the assigned intersection. It excludes
placements that collide with established footprints. It confirms empty only if enough
feasible placements remain and every one is contradicted by exposed reference-matching
wood and surviving printed rails. At a board edge, three surviving samples on the continuing
outer rail substitute for the perpendicular line that terminates there. Corners remain
conservative. Unexplained stone-colored regions and newly covered reference ink veto
emptiness, including small or severely displaced opaque objects. Geometry alone, or failure
to find a new stone, never confirms empty.

The `DisplacedRound2` saved frame retains all 21 stones and reduces uncertainty from
14 to 8, including resolving raw row 14, column 18. `--geometry-test` resolves that point
in all 27 small lighting/alignment variations; all 21 stones remain recognized in 26
variations, with an existing stone uncertain in one. No real stone becomes empty or changes
color. Counterexamples deliberately mark added black, white and wood-colored objects as
uncertain before refinement and verify that they are not erased, including small and
far-offset objects. The test also checks blocked ownership. A full detection took roughly
0.07–0.11 seconds locally; this is a test observation, not a live-device performance guarantee.

**Show stone outlines** displays fitted cyan perimeters and center marks independently
of the grid overlay. Saved schema-3 samples add `stoneFootprints` for diagnostics. Native UI
replay checks the edge decision, rotated overlays, visibility toggling and sample export.
The classifier still has uncertain points and needs broader testing across boards,
stone sizes/materials, lighting and occlusion. It is not yet a learned shadow-shape model.

### Saved references and repeatable comparisons (0.17)

An empty-board reference and its original calibration are now saved together in one
atomic local archive at `~/Library/Application Support/Physical Go/EmptyBoardReference.plist`.
The current tracked calibration and camera identity are saved separately within the
same archive. Manual and automatically verified captures both persist. App launches
restore the reference; restarting or reconnecting the same camera preserves it and
checks alignment against a fresh frame before showing detection results. A different
camera or frame size clears the active reference. Full-view recalibration after a large
move still switches to reference-free detection. Lighting changes can still require a
new reference; alignment validation does not certify unchanged lighting.

**Open sample…** opens a sample folder containing `sample.json` and
`empty-reference.png`, restores the paired calibrations, and reevaluates `frame.png`
when present. This supports comparisons on identical raw images without clearing or
rearranging stones. **Start camera** returns to the live board while retaining the
restored reference for the matching camera. Legacy samples lacking camera IDs are
matched only when exactly one connected camera has the saved source name. Future
samples include the camera ID. The occupied frame is never substituted for its empty
reference. Samples without an empty reference can still be inspected with **Open photo…**.

Manual recalibration and **Use without reference** disable automatic archive reuse;
they do not delete the original saved sample. Reopening the sample restores it again.
Malformed imports leave the current session intact, and a corrupt archive does not
prevent starting the camera. `--preview` exercises lossless persistence, exact saved-frame
replay, fresh-frame validation, reconnection, relaunch, opt-out, mismatched cameras and
frame dimensions, and malformed data in addition to the existing native UI checks.

### First game recorder (0.18)

Start the camera and check alignment, clear the board for a new game, then choose
**Start recording**. The existing empty reference can remain in use. The recorder
requires five confidently empty frames over at least 0.8 seconds before arming;
Black moves first. Play one move at a time and wait for its recorded move number.
Remove captured stones before expecting that move to be accepted.

The recorded board is separate from the camera's detection board. First/previous/next/
latest controls browse accepted positions, including captures and passes. Browsing
pauses recording without deleting moves. **Resume recording** returns to the latest
position and checks it against fresh camera frames before accepting another move.
**Undo last move** removes the last accepted move, preserves a backup SGF, and pauses;
restore the physical board before resuming. While paused at the latest position, click
an empty intersection on the recorded board to confirm a missed move manually.
Manual entries undergo the same legality checks and are annotated in SGF. Passes are
explicit buttons; two passes finish recording. **Finish** can also end it manually.
No result, score or komi is inferred.

`GameRecorder.swift` uses the existing `SGFPlayer` rules engine directly for turn order,
capture simulation, no self-capture and simple ko (Japanese rule setting). It uses the
existing SGF parser/writer and board models. The `PHYSICAL_GO` build flag omits only the
main app's playback-preference subscription; the rules and replay implementation are
shared. The camera app does not import the main app's sound or rendering settings.

A candidate move needs five consistent fresh frames over at least 0.8 seconds and a
full legal resulting position. Newly uncertain points, missing established stones,
multiple additions, incomplete capture removal and wrong-color moves defer acceptance.
Uncertainty at previously empty intersections can persist if established in five resting
frames; it never adds/removes an accepted stone. Camera interruptions, grid changes,
freeze/resume and detector-setting changes invalidate pending evidence. In 0.18, after alignment
recovers, the accepted position must be seen again before automatic recording continues.
Version 0.19 also permits a strictly verified single-move continuation, as described below.
History checks alignment consistency; it does not yet fit camera geometry using stones.

Each game is atomically autosaved after every accepted move/correction to its own file
in `~/Library/Application Support/Physical Go/Recordings`. **Show autosaved game** reveals
it; **Save SGF…** writes an explicit copy. Export includes the entire game regardless of
the review cursor. The app does not yet reopen/resume these game sessions after relaunch;
the SGFs remain available to open in SGF Player. Starting a new game preserves the old file.
Save failures are shown without discarding the in-memory game.

`python3 PhysicalGo/build.py --recorder-test` covers stable transitions, flicker, duplicate
frames, legality, capture removal, ko, suicide, review isolation, correction, passes,
uncertain points, frame gaps, camera resynchronization, SGF round trips and autosave.
`--preview` additionally tests synthetic images through native recognition, recording,
review, freeze/resume and export, and renders the recording/review controls. Real-board
validation is still needed; a stable visual false positive can resemble a legal move.


### Recording readiness (0.19)

A banner above the camera now distinguishes **Not recording yet**, **Recording**,
**Checking board**, **Paused**, and **Finished**, with the accepted move count. The
recorded board says **No moves recorded yet** instead of an ambiguous 0-of-0 starting
position. Startup reports its clear-frame progress, visible stone count, or uncertain
intersection count. If an empty board remains uncertain, the message points to the
optional empty-reference capture rather than suggesting that game recording has begun.

Fresh empty-board evidence is collected before Start is clicked. Five confidently empty
frames over at least 0.8 seconds can arm recording immediately if the last frame is at
most one second old, has the same board size, and no camera interruption invalidated it.
Otherwise the existing empty-board verification remains mandatory. Once stones are on
an unverified starting board, the app does not invent their move order.

After an interruption, a fully observed, legal single-move continuation can now recover
recording without requiring the player to remove the stone just played. This requires
at least eight consistent fresh frames over 1.4 seconds, with no tolerated unknown
points after synchronization was invalidated. Multiple moves, missing established stones,
wrong turn, and illegal continuations remain blocked. This also fixes a separate deadlock
where a hand briefly hiding the grid during a move could leave the recorder permanently
waiting for the preceding position. Sample JSON adds recorder status and accepted move
count for future diagnosis. Unit and native UI tests cover pre-Start readiness, stale/
interrupted/uncertain empty evidence, occupied startup, and strict single-move recovery.

### Recording through uncertain empty points and grid corrections (0.20)

Move confirmation now follows the identity of a proposed legal move rather than requiring
an identical classification string across every board intersection. Up to 5% of the
board's intersections (minimum two) may remain uncertain if those intersections are empty
in both the accepted position and proposed resulting position. Their classifications are
not changed to empty. The union of uncertain points across the confirmation window is
also bounded, preventing a moving occlusion from evading the limit. Established stones,
the candidate itself and captured intersections still need confident matching evidence;
wrong colors, extra stones, illegal moves and large occlusions remain blocking.

A local grid correction already verified by the tracker no longer restarts recorder
confirmation. Actual alignment loss, full-grid searches, changed camera settings and
camera interruptions still invalidate pending evidence. Recovery uses the same bounded
empty-point uncertainty rule with the longer confirmation window. A saved real-board
fixture supplies stone pixels for a manufactured Black/White sequence with repeated
small translations; native model tests verify recording while corrections occur. This
is a regression test, not a reconstruction of the user's unrecorded move order.

Every accepted move produces an optional Pop sound. A persistent rejection for three
seconds raises a red **Recording blocked** indicator, an alert, and an optional warning
sound. **Recording sounds** controls both sounds. Acknowledging the alert suppresses
repeated warnings for the same blockage; successful recording clears the warning.
Each game's SGF now has a sibling `.observations.jsonl` with timestamped observed board
states, recorder state/status, pending-frame counts, interruptions and move acceptance.
The log contains classifications rather than video and exposes write errors separately
from SGF-save errors. It preserves evidence needed to diagnose missed transitions.

**A−**, the percentage reset button, and **A+** adjust interface text from 90% to 150%;
the preference persists across launches and defaults to 110%. The boundary between the
camera and the controls is a native draggable split-view divider. The controls pane can
be widened to accommodate larger text. Native UI tests check font limits and the presence
of the split view, and render the interface at 140% text size.

### Continuous-blockage warning timing (0.21)

Recording warnings now measure a continuous blockage. A valid resting-board or legal
candidate frame resets the warning timer immediately, even while five-frame move
confirmation is still in progress. A later one-frame detection glitch no longer inherits
an older hand-occlusion timer. Temporary uncertainty and capture cleanup receive ten
seconds before a modal warning; persistent conflicting moves retain the three-second
warning. This changes notification timing, not move acceptance or legality requirements.

The saved `RecordingSettling` classification log replays the user's actual Black/White
sequence with both moves preserved and no false warnings. Tests also retain alerts for
persistent multi-move conflicts and a board obscured continuously for ten seconds.

### Long-side estimation from stone silhouettes (0.22)

After grid acquisition, `StoneAspectEstimator` measures independently segmented stone
silhouettes in grid coordinates. It does not reuse `StoneGeometry`'s two preset ellipse
ratios. Local wood appearance separates dark/light stone bodies, thin printed rails are
removed, and enclosed highlights are filled before measuring shape moments. Cropped,
merged, skewed and implausible components are rejected. At least three spatially separated
measurements must agree; conflicting black/white estimates, nearly square grid-coordinate
shapes and excessive elongation leave the existing camera-based estimate unchanged.

The two hypotheses retain the standard grid-spacing ratio, 23.6:22. Horizontal/vertical
stone radius ratio above one supports long rows; a ratio below one supports long columns.
The display chooses the hypothesis making the ensemble rounder. It does not stretch
individual stones or modify recognition coordinates, game history, or SGF. This works
without an empty reference. Low stone counts, shadows, unusual stone shapes, lens effects,
and strongly oblique views of thick stones can make the evidence inconclusive.

Checks run at most once every two seconds. A reversal of an established stone-based
choice needs agreement on a second check, and absent evidence does not unset that choice.
Manual **Swap long side** wins over automatic inference and is preserved by grid refinement
on the same board. A successful stone check is indicated beside the long-side control.

The `LongSideBump` capture supplies ten independent stone measurements favoring long
columns; the previous camera-only estimate had chosen long rows. Tests cover both physical
orientations under projective distortion, offset stones, enclosed surface texture, outliers,
insufficient evidence, color disagreement, existing real-board captures, and the native
reference-free pipeline. `--stone-aspect-test` also renders before/after comparison images.
Native checks verify rotated rendering, unchanged classifications, and manual override
preservation through a new grid search.

For updates during an active session, `--review-recording <SGF path>` restores a Physical
Go record for review. Every move is replayed and legality checked before replacing history;
setup positions and variations are rejected by this limited restore path. An unfinished
game restores paused, and its existing diagnostic log is appended to rather than truncated.
Camera alignment is checked before recording resumes. Tests cover captures, passes, manual
entry annotations, continuation, and rejecting malformed/illegal records without damaging
the current game. This flag does not automatically choose a game on ordinary launches.


### Two-move catch-up (0.23)

If a stable frame shows exactly one new Black stone and one new White stone, the
recorded next player determines their order. Both moves must be legal under the shared
rules engine, and their complete final board must match the observation. Captured points
and previously recorded stones require direct evidence; the existing bounded tolerance
for uncertainty at otherwise empty intersections is retained. Empty points clearly seen
in at least two frames of the same candidate window are resolved, so transient empty-point
flicker does not accumulate into a false blockage. Eight fresh frames
spanning at least 1.4 seconds must agree on both placements, including after a camera
interruption. Changing either placement restarts confirmation.

The pair is saved together, with each intermediate position retained for back/forward
review. Recovery clears an earlier blockage alert. Two same-color additions, three or more
additions, illegal intermediate moves, incomplete captures, and unexplained disappearance
of an established stone still require review. No unobserved pass or vanished move is inferred.

Recorder tests cover both starting colors, stronger stability, changing candidates, camera
recovery, capture removal, illegal second moves, ambiguous three-stone additions, autosave,
and individual review positions. `TwoMoveCatchup` preserves the actual 18-move stall and
subsequent observation sequence: replay recovers Black at SGF `re`, White at `pe`, then the
later Black at `qd`, reaching 21 moves. The native preview also jumps directly from an
armed empty board to a two-stone camera image and verifies both recorded moves.

### Short observation history (0.24)

Recognition and SGF commitment are now separate. `MoveObservationHistory` keeps legal
candidate positions, their chronological sightings, and per-move confirmation evidence
for up to 12 seconds / 64 input frames. It can follow up to eight tentative moves, with
a bounded set of alternative sequences. Two sightings of an intermediate position,
spanning at least 0.15 seconds, establish its ordering before a later move extends it.
A single-frame flash cannot decide which of two same-color moves came first.

Normal moves still require five supporting observations spanning 0.8 seconds; recovery
and pairs first seen together require eight spanning 1.4 seconds. The observations need
not be consecutive: a hand or inconsistent detector frame contributes no evidence but
leaves the short history intact. Later legal positions contribute confirmation to earlier
stones that remain visible. The recorder saves the confirmed common prefix immediately,
retaining the later tentative moves in memory. Thus continued play does not require the
entire board to remain at one position for the full confirmation delay. The status reports
how many moves are being tracked; SGF, review, autosave and sounds refer only to committed
moves. Pass is disabled while a live tentative tail remains.

A newly placed stone captured before confirmation must have been directly visible in at
least two observations before capture; the capturing move must reach full confirmation.
Every intermediate move is checked by the shared rules engine, and every stored board
remains individually reviewable. Unseen stones, passes, and ambiguous orders are not
inferred. An earlier tentative stone becoming uncertain cannot be treated as empty or
replaced in the move order by a later stone of the same color. Expired ordering evidence
blocks automatic continuation until the discrepancy is reviewed or the accepted board is
clearly restored; it does not silently authorize a new order.

Brief local alignment loss preserves the queue and requires two fresh matching observations
before using it again. Camera restart/source changes, a frame gap over 1.5 seconds, full
grid searches, reference/threshold changes, freeze, pause/review, undo, finish, and new games
clear tentative evidence. Accepted history is always preserved. This is a bounded short
history, not video recording or arbitrary reconstruction after a long occlusion.

`--recorder-test` now includes `ObservationHistoryTests.swift`: six alternating placements
at 0.42-second intervals, incremental prefix saves, opponent moves during confirmation,
hand occlusion, local recovery, duplicate timestamps, expiry and lifecycle resets, ambiguous
orders, pending-stone occlusion, rapid captures, unseen captured-move rejection, and complete
SGF/review positions. The native preview feeds four alternating images with two observations
per move and checks that recording advances before play has stopped. The previous saved
camera-log regressions continue to run alongside these tests.

### Recording controls and turn display (0.25)

A red record/resume control and separate pause control sit above the recorded board.
The camera banner also offers Start/Resume or Pause and remains visible before recording
starts. Paused, waiting, finished, and preview-only states explicitly say that moves are
not being saved; camera activity no longer implies recording activity. Record/Resume is
disabled until the camera is live, unfrozen, and aligned. Pausing continues detection.

A black/white stone badge and “Black to play” / “White to play” appear beside the camera
and above the recorded board. The caption identifies the recorded move number (or the
reviewed move when stepping through history), so pending or unrecorded physical moves do
not silently change which position the turn indication describes.

For diagnostic recovery, `--replay-recording SGF JOURNAL OUTPUT` replays an explicitly
selected chronological observation journal into a new SGF. Existing output files are
refused; source SGF/journal files remain unchanged. Use a journal matching the supplied
starting game, such as observations after its restore event. The same recorder legality
and evidence rules apply, and unresolved later moves remain unrecorded. This tool does
not automatically convert deliberately paused camera activity into game moves.


### Automatic camera startup and recording readiness (0.26)

Normal launches open the last successfully used camera once, without starting a recording.
The selected device ID and name persist independently of the empty-board reference; older
installs migrate the camera choice from that archive even if reference reuse was disabled.
An exact device ID wins; a unique matching name handles a changed USB-port ID. If the
preferred device is missing or its name is ambiguous, the app shows an explanation and
leaves camera selection to the user. An install with no saved preference uses the first
available camera. Saved-sample launches remain frozen and do not activate the camera.

Both Record controls and their actions use a shared readiness check: a live, unfrozen
camera, completed grid detection, verified alignment, matching board size, and a successful
analysis of a live frame within the last second. A restored grid, photo analysis, stale
frame, or in-flight grid search cannot enable Record. A new game additionally requires the
existing five-frame / 0.8-second empty-board preflight, so clicking Record starts ready for
Black rather than silently waiting with zero moves. Resume requires the aligned live game
view instead of an empty board. Disabled Record controls are explicitly gray, with the
current prerequisite shown underneath; they turn red when ready.

Native checks cover one-shot startup, independent saved preferences, missing and ambiguous
cameras, changed device IDs, frozen samples, fresh/stale/absent frames, new-game empty-board
verification, occupied-game resume, and freeze/stop invalidation. Preview tests inject camera
activation and isolated preferences; they never open hardware or alter the user's camera
selection. The app's normal launch uses the actual capture adapter and existing macOS grant.

### Clear blocked-start feedback and shadow fallback (0.27)

The camera banner and transport controls now show an explicit **Ready to record** or
**Not ready to record** heading. When the grid is aligned but startup is blocked, the
explanation includes the current counts of uncertain intersections and possible stones.
Possible detections are not presented as confirmed stones on the physical board.

Automatic empty-reference capture requires positive empty evidence, so persistent shadows
can prevent both that capture and recording readiness. If the physical board is empty,
**Board is empty — capture reference** is offered beside the readiness message. Clear all
stones and hands before clicking. It captures the lighting/shadow baseline using the
existing reference mechanism, then requires fresh empty-board verification before Record
becomes available. It does not bypass the recorder's checks or start recording. The shortcut
is unavailable during an active or paused game, without a fresh verified grid, or while
ordinary all-empty frames are merely accumulating confirmation.

The native regression adds a stationary dark patch to an empty camera fixture, verifies
that readiness is blocked with an explanatory count, captures that explicitly confirmed
empty baseline, and checks that fresh observations reach Ready without creating a game.
It also verifies that the shortcut is unavailable after recording starts.

### Audible and persistent recording-failure feedback (0.28)

A detected stone remaining unsaved for 2.5 seconds now triggers a double low warning tone,
separate from the single confirmation pop. `RecordingWarningMonitor` observes candidate
stones even when global board uncertainty prevents the recorder from considering a move.
It requires three consecutive sightings, ignores duplicate timestamps, and coalesces
warnings within two seconds. Color/uncertainty flicker does not repeatedly announce the
same stone. A new stable unsaved candidate can trigger another warning; a continuing
blocked recording produces a reminder every eight seconds as fresh observations arrive.
These warnings are advisory and cannot add moves or relax the recorder's legality checks.

Recording-failure dialogs are replaced by a persistent red **STOP — moves are not being
saved** banner, last saved move number, unsaved candidate count, and a marker over the camera
image. Detection candidates are not claimed to be legal or confirmed physical moves. The
existing Recording sounds preference controls both tones, and the banner states when
sounds are off. The second warning pulse is canceled if recording is paused, the issue
clears, or sounds are disabled before it plays. Pause/finish/intentional stream resets stop
the warnings; accepted moves, including rapidly captured moves, remove their candidate
warnings. Partial catch-up retains warnings for candidates that are still unsaved.

Tests cover normal confirmation without warning, detector flicker, repeated candidate
moves, throttling, reminders, acknowledged alerts, partial/full recovery, pause/finish,
duplicate timestamps, captured candidates, and the real `RecordingWarnings` session. That
session still contains only one accepted move: the warning changes expose the sustained
uncertainty and later unknown order without guessing the missed game. Native preview checks
the nonmodal banner, last-saved count, image marker, and muted-sound indication.

### Local move evidence during widespread uncertainty (0.29)

`LocalMoveEvidence` retains timestamped readings independently at each intersection,
including frames that fail the recorder's whole-board uncertainty gate. Consecutive
identical readings share one run with first/last times, repetition count, and exact
support timestamps. A small change elsewhere therefore does not duplicate the whole
board. This is observation metadata in memory, not a video/image buffer; the existing
on-disk diagnostic journal remains available after temporary evidence is discarded.

Retention is bounded to 12 seconds and 64 runs per intersection. Evidence whose
ordering information expires is marked unusable for ordering, not silently treated
as a new first appearance. A clear return to the accepted board clears it. Pause,
review, a different grid/source, and other hard vision resets also clear it; local
alignment interruptions retain it subject to the same age limit. Once all visible
stones are accounted for, resolved evidence is discarded immediately. Uncertainty
at a previously observed new stone cannot be mistaken for an empty intersection.

The first fallback handles 3–8 surviving additions when no whole-position hypothesis
could be built. Repeated sightings of A followed by repeated empty readings at B can
establish A before B; unknown readings cannot. A definite contrary reading breaks a
stone's appearance episode, so an early false detection at B does not date its later
real appearance. The recorder enumerates alternating orders and proceeds only if
exactly one satisfies these temporal constraints. Every move must then be legal and
the resulting board must match the live observation, including accepted stones and
captures. Eight clear supporting frames over at least 1.4 seconds confirm the final
position before saving. The fallback does not infer unseen captures or passes, and
cannot resolve every obscured sequence. Existing whole-position history still
handles directly observed rapid captures and partial sequence confirmation.

Diagnostics now include `localEvidenceRuns`, `localEvidenceSamples`, and
`usedLocalEvidence`, in addition to the existing move/warning/uncertainty events.
`--recorder-test` includes `LocalMoveEvidenceTests.swift` and the latest stalled
session, `Tests/Fixtures/LocalEvidenceStall`. It recovers the three missed additions
at about 38.3 seconds, with no new commits in the noisy interval, and writes a separate
`.build/LocalEvidenceReplay.sgf` for review. Removing intermediate evidence must
leave the replay blocked; swapping the two Black locations must reverse their order.
Other checks cover compression, duplicate timestamps, bounded storage/expiry,
contradictions, simultaneous appearances, single-frame ghosts, hidden earlier stones,
legal moves, camera/pause resets, SGF review, and evidence cleanup. The original
user SGF and journal are never changed by these tests.

### Weak candidate blocking and shifted white false positives (0.30)

Raw per-intersection sightings are still retained for temporal comparison, but they
no longer all prevent recording when subsequently obscured. A protected local
candidate needs two separated sightings with at least 75% of its immediate valid
neighbors matching the accepted board. Broad changing regions therefore do not
turn every dark patch into a protected hidden stone. Definite contrary readings
remove protection. Existing whole-position hypotheses keep their stricter ordering
protection; pause/source/grid resets clear both forms. Protection markers are bounded
by the board's intersection count. This is an evidence qualification heuristic,
not a hand detector, and dense rapid play may still require a clear board view.

Offset-search white proposals can now be contradicted by the existing positive
empty-wood check: matching wood/color plus both surviving printed rails. This fixes
D4 in `RapidPlayStall`, where a local exposure correction and a shifted sampling
patch promoted bright wood beside D5 to a second white stone. It does not use absence
of a fitted stone outline as proof of emptiness.

Regression coverage includes the saved 16-stone frame at five alignment offsets,
existing color/placement/edge tests, two 27-case displaced-stone suites, and recorder
replays. The new rapid-play replay includes actual grid interruptions and recovers
11 moves rather than the original eight, without inventing an order for the final
five. `.build/RapidPlayReplay.sgf` is an isolated test output; the original user
recording is never rewritten. Widespread bad detections later in that journal remain
unexplained without camera frames from the interval. This release does not claim to
solve arbitrary rapid play or grid loss.

### Optional lossless diagnostic sessions (0.31)

Start **Diagnostic capture → Start diagnostics** before starting a test game. Clear
the board, wait for **Ready to record**, press the normal Record control, and play.
When a problem appears, pause the game if needed, then choose **Stop diagnostics**.
**Show folder** opens the resulting archive. Pausing/finishing a game does not stop
diagnostics; stopping diagnostics does not pause or change the game. Diagnostics
are off on ordinary app launches and never feed the move-reconstruction buffer.

Local data now lives under `PhysicalGo/Captures/`, excluded from Git:

- `Samples/`: manual saved frame/reference/calibration bundles. Save sample defaults
  here. The existing 16 Desktop sample folders were moved here, hash-verified, with
  a migration manifest preserving their old paths. The Desktop app shortcut stays.
- `Screenshots/`: the related Desktop edge-stone screenshot, also moved and hash-verified.
- `Diagnostics/Diagnostic <local date/time> <unique ID>/`: independent test sessions.
  `frames/` holds lossless full-resolution raw camera PNGs (no grid overlay or
  perspective transformation); `assets/` holds versioned reference PNGs and exact
  grayscale tracking-anchor bytes. `events.jsonl` correlates frames, grid searches,
  analyses, discarded/stale results, recorder events, SGF changes and timestamps.
  `session.json` identifies the schema, version/build/source hash, initial context,
  storage policy, counters and completion/failure state.

The camera currently delivers about five images per second to the app. Diagnostics
save every one of those deliveries, including frames skipped while analysis is busy,
while grid search is running, or while the display is frozen. Diagnostic capture is
not native-camera-rate video: frames between those deliveries are not retained.
Grid searches and redraw analyses also retain their exact input image/settings.
Analysis outcomes contain all intersection classifications, confidences and deltas,
stone footprints, final calibration, notice, recorder timestamp and recorder state.
Recorder events carry their originating frame ID when triggered by an analysis.
References are versioned when changed; tracking anchors include both calibrations
and unmodified grayscale pixels for reproducible alignment failures.

PNG compression and writing run on a separate utility queue. At most 12 image jobs
are pending; overload ends diagnostics visibly instead of silently dropping evidence
or slowing the detector deliberately. The selectable per-session limit is 1, 5 or
10 decimal GB (default 5 GB), with a 2 GB free-disk reserve. Limit/space/write errors
stop only diagnostics and preserve saved data. Metadata/termination bookkeeping adds
a small amount beyond the counted limit. A normal stop waits for started analyses
and pending file writes; application termination logs canceled operations and drains
the bounded writer queue. A crash/forced kill can leave an incomplete final event or
operation: a session still marked `recording` is not a clean completion. No saved
session is automatically deleted, including after moves catch up.

Replay a specific saved input without changing the archive:

```sh
python3 PhysicalGo/build.py --replay-diagnostic '/path/to/Diagnostic session' 42
```

The tool reconstructs the reference and tracking anchor, reruns alignment and stone
detection (or a full-view grid search), compares classifications with the recorded
outcome, and shows the contemporaneous recorder decision. Skipped frames report
why they were skipped. This is a single-input vision replay; the original event log
also preserves the sequence needed for later recorder investigations. Replaying
with changed source code intentionally tests that code against the archived input;
check the session's version/source hash when interpreting differences.

`--diagnostic-test` exercises lossless round trips, reference/anchor versions,
accepted/rejected/busy/stale frames, recorder-frame correlation, SGF checkpoints,
paused-game independence, storage/space/write/backpressure failures, stop/exit
completion, old-session isolation, actual failed grid searches and native controls.
Disk replays of both a saved accepted move and failed alignment/search inputs are
also verified during development.

### Diagnostic-session recovery fixes (0.32)

The November 2 rapid-play archive contains 457 delivered camera images over about
96 seconds. The original record stopped at 10 moves. Sequential pixel replay with
0.32 recovers all 18 observed moves by frame 389 (about 82 seconds), before the
user's pause. Originals remain in `Captures/Diagnostics`; the illustrated analysis,
comparison chart and separate recovered SGF are in
`Captures/Analysis/2026-11-02 Rapid play/` (local, excluded from Git).

Three issues combined in that session:

- Local lighting changes manufactured white stones on exposed wood and invalidated
  real stones. The detector now identifies exposed wood by retained color/texture
  and **both** printed rails, then uses those verified points to estimate nearby
  illumination. This evidence can veto centered as well as shifted white proposals.
  One stone-grain line is insufficient. Large unsupported exposure changes remain
  uncertain; matching an intensity alone never proves emptiness.
- Expiry of an old, already contradicted local color episode could poison a later
  real move at that coordinate. Expiry now protects unresolved appearances; clear
  contrary evidence ends the old episode. It does not turn unknown points into empty.
- Local chronology could only seed an empty hypothesis list. It can now extend an
  existing candidate if a unique alternating order preserves **every** retained
  prefix. Legal moves, matching final positions and eight fresh views over at least
  1.4 seconds still gate locally reconstructed continuations. No unseen captures,
  passes, or ambiguous ordering are inferred.

Replay an entire diagnostic session into a **new** folder:

```sh
python3 PhysicalGo/build.py --replay-session '/path/to/Diagnostic session' '/path/to/new replay folder'
# Compare recorder behavior using the original classifications instead of pixels:
python3 PhysicalGo/build.py --replay-session '/path/to/Diagnostic session' '/path/to/another new folder' --saved-observations
python3 PhysicalGo/build.py --session-regression-test
```

The sequential tool supports diagnostics starting idle (including the later Record
button event), verifying an empty board, or already recording an empty game without
pending moves. It reuses the saved calibration/alignment decisions,
analysis timestamps, and pause/interruption events; it does not simulate camera
scheduling or rerun the grid tracker across an entire session. Use the single-frame
`--replay-diagnostic` tool for tracking/search investigations. Mid-session game
replacement/manual edits are unsupported. Output includes a separate autosaved SGF,
per-frame classifications/status/timing, accepted decisions and a summary. Existing
output folders and destinations inside the source archive are rejected.

`DiagnosticSessionTests.swift` adds 107 checks: three original pixel fixtures under
nine brightness/alignment combinations each, old-classification reproduction of the
10-move stall, complete 18-move recovery with real interruptions, withheld chronology,
swapped later black-stone locations, review and SGF round-trip. The fixture's expected
moves were checked against sequential photographs; cached classifications are labeled
as detector output, not ground truth. Additional local-history tests cover disproved
ghost expiry and extension of an existing prefix. The full archive remains local;
only three regression frames, their reference, metadata and compact observations
belong in `Tests/Fixtures/DiagnosticRapidPlay`.

Dedicated hand detection remains deferred. Occluded observations can still contain
false candidates, but do not supply full-position confirmation. The successful replay
is evidence for this session, not a general tournament-accuracy guarantee.


### Retained move confidence and interpretation (0.33)

A partially obscured stone no longer prevents tracking later legal moves. Two clear
sightings establish a move's place in the sequence; compact ordering witnesses can
survive beyond the 12-second raw observation window. Up to 1024 pending moves and 16
candidate sequences are retained, with two old ordering witnesses per depth plus
the recent 64-frame window. Fresh, sufficiently clear observations must still verify
the complete position before its confirmed prefix is exported to SGF. Unseen moves,
passes and unsupported ordering are not invented. Confirmed SGF moves are not undone
because their stones later shift or become uncertain.

Per-move Low / Medium / High evidence levels describe repeated direct sightings and
agreement about order, not calibrated probability percentages. A clear later move
can have High evidence while SGF waits for an earlier unresolved move. Once a pending
assignment has strong agreed evidence, it remains settled despite later uncertainty;
fresh complete-position checks still gate SGF export. The inspection
board keeps the best supported stone assignment visible. A **red ring** flags pending
assignments with Low or Medium evidence; it does not draw alternate locations. A white
dot on black, or black dot on white, marks the latest interpreted move. The recorded
board uses the same dot for the selected review move and remains confirmed history.
Small orange points still represent uncertain image regions with no stone assignment.
Frozen diagnostic labels remain separate from game corrections.

The existing local `.observations.jsonl` beside each SGF now includes tentative
sequences, confidence evidence and uncertain observations. These records are diagnostic
and are not deleted when the live buffer catches up. Pause/Resume preserves supported
pending order and requires eight fresh matching views on Resume. Source/grid/settings
changes and manual game edits still invalidate tentative history. App restart restores
the confirmed SGF; automatic restoration of the pending journal is not implemented.

The November 2 10:14 diagnostic session also exposed duplicate black claims where an
offset search borrowed a neighboring stone's dark edge and shadow. Such secondary
claims now require an independent stone outline, otherwise they remain uncertain.
They are not assumed empty. `--morning-session-test` checks the captured positions
under small brightness and alignment perturbations; `--recorder-test` covers minute-long
uncertainty, later moves, bounded witnesses, pause/resume, SGF completion and review.

Finish checks for pending or visibly unsaved moves. If any remain, a one-time dialog
asks the user to inspect the interpretation board and adjust red-ringed assignments.
The game pauses with supported pending history retained. Resume to verify the adjusted
stones, then choose Finish again. An incomplete pending sequence is not silently
presented as a finished game.

The final 0.33 sequential replay recovers the exact 15-move morning sequence (previously
eight saved) and the earlier 18-move sequence. The morning analysis, original and
recovered SGFs, frame trace and screenshots are in
`Captures/Analysis/2026-11-02 Morning rapid play/`. Both original diagnostic archives
remain intact. Exact move coordinates and colors were checked, not only the counts.

### Physical placement confidence (0.34)

A repeatedly classified stone can still sit too close to the boundary between
intersection cells. Reliable fitted outlines now supply a separate displacement
measure in grid-spacing units. The current conservative warning threshold is 0.30
along either grid axis (the cell boundary is 0.50). After a concern is raised, fresh
outlines must place the center within 0.24 before sightings can settle the assignment.
This hysteresis prevents threshold flicker; missing outlines cannot clear a concern.
These are heuristic geometric margins, not calibrated probabilities. Weak/missing
outlines from the outset remain a limitation, particularly without a reference.

Spatial warnings appear as red rings on the inspection board even before recording.
During recording, the best-estimate move remains in the tentative sequence while
later legal moves accumulate. Placement uncertainty contributes to the per-move
confidence and prevents automatic SGF commitment. Once settled, later displacement
of a confirmed stone does not reopen its history. Diagnostic sample labels still do
not edit game history.

Supported order survives full grid reacquisition with fresh position verification,
and alignment checks while paused preserve the paused queue. Replays ignore the
internal interruption emitted by Resume because Resume itself restores that queue.
The sequential replay tool now also accepts sessions starting with an existing
recorded game and no pending moves, restoring a copy of the initial SGF into its new
output directory. Existing SGF files and diagnostic archives are never rewritten.

The two November 2 captures at 11:29 and 11:33 contain 844 and 589 frames. Analysis
identified moves 23, 51 and 53 as consistent displacement concerns; white move 52
provides a clearer control. The later pixel replay holds 51/53 and retains clear 52
between them. A combined observation replay retains the exact original 53-move
sequence across pause/resume and grid searches; simulated centering completes SGF.
A fleeting, unanchored extra stone may branch from the last supported prefix instead
of monopolizing the next turn. Locked assignments and witnessed ordering remain
protected. This does not infer unseen moves or strategic intent.

Run `python3 PhysicalGo/build.py --placement-confidence-test` for real pixel fixtures
and combined-session regressions, and `--recorder-test` for synthetic displacement,
missing geometry, hysteresis, later moves, tidying, pauses and lock-in checks.
`Tests/Fixtures/PlacementAmbiguity/sessions.json` contains compact image-derived
observations and control events; expected move sequences come from the original SGFs,
not from an independent annotation of every move. The raw archives remain local.
Marked photographs, comparisons and an interactive viewer for all 589 frames are in
`Captures/Analysis/2026-11-02 Ambiguous placements/`.

### Live interpretation beside saved history (0.35)

The main recording board now defaults to **Live position**. It shows the best retained
legal position, including moves waiting behind an uncertain stone. Red rings identify
pending moves below high confidence; the opposite-color center dot follows the latest
interpreted move. The saved/pending counts remain visible while paused. **Saved moves**
and the arrow buttons show only accepted SGF history; browsing preserves the pending
sequence. Manual move entry is available on the saved board when paused at its latest
position. Detailed confidence is collapsed below the board so it cannot push the
interpretation out of view. Pass is disabled while pending moves remain, so adding a
pass cannot discard their chronology.

The November 2 six-move report was a visibility failure: six moves were accepted and
seven were retained, but the old main board displayed only the accepted six. Move 7
(black C4 in source orientation) had a fitted offset of about 0.36 grid intervals and
was intentionally held for placement confirmation. The later six moves were still
tracked. Detection and the placement threshold have not been relaxed in this update.

Pause also writes a compact `.pending.json` beside the SGF, separate from diagnostic
images. `--review-recording /absolute/path/to/game.sgf` restores a matching checkpoint
into a paused game. A board-size/move-sequence signature prevents attaching it to a
different SGF; the rules engine reconstructs every pending path. Restored observations
cannot count as fresh confirmation, and Resume requires at least eight fresh views
spanning 1.4 seconds. Camera startup, automatic grid reacquisition, and Freeze preserve
retained chronology and require fresh checks. Manual grid/settings edits still reset
it. Accepted moves and manual edits replace stale checkpoints. This is a pause/review
checkpoint, not continuous crash recovery or automatic reopening of the last game.

Run `python3 PhysicalGo/build.py --visibility-test` for the captured six-move session.
It verifies the full 13-move interpretation, the single red ring at move 7, saved/live
native rendering, paused camera startup and history review, checkpoint validation,
and exact catch-up after **simulating** the measured center of move 7 being corrected.
It does not claim that a physical adjustment was performed. The compact observation
fixture comes from `Diagnostic 2026-11-02 12-19-54 2CCCB4B3`; original pixels, logs and
SGF remain untouched. Preview PNGs are written under `.build/SixMoveVisibility`.

### Obstruction-only candidates and confirmed identities (0.36)

The `Diagnostic 2026-11-02 13-00-35 260B14C1` session confirmed the previously
pending seven moves after the real adjustment and recorded through move 24. While
a hand covered much of the board, an empty point beside a black stone (source
point 77) was repeatedly classified black. Its immediate neighbors happened to
look unchanged, so local evidence promoted it to a blocking candidate. When the
hand left, the point returned to uncertain rather than definitely empty. The
recorder consequently refused the actual move 25 and eventually accumulated more
moves than its local ordering fallback could reconstruct.

Local evidence now distinguishes raw sightings from permission to establish a
blocking candidate. A view with more than eight apparent new/recolored stones
cannot promote such a candidate, even if that point's immediate neighbors look
unchanged. Raw readings remain available to establish chronology when the board
clears. This is an obstruction plausibility check, not a hand classifier; the
normal repeated-view confirmation still waits for settling. Small changes on an
otherwise partially obscured board remain eligible, preserving the protection
against replacing a real earlier stone with a later same-color move.

A second issue in the same clip was repeated uncertainty at accepted white move
16 after neighboring placements. Whole-position verification can now retain up
to two unchanged confirmed stones through uncertainty, capped at ten percent of
the accepted stone count. The allowance applies only if the legal resulting
position preserves the same color at that point. It never supplies evidence for
a new stone, a capture removal, or a definite missing/recolored old stone. Larger
occlusions still wait. Resting-board synchronization uses the same rule. Journals
now include `localCandidatePoints` so a future blocking local sighting is directly
identifiable.

`python3 PhysicalGo/build.py --stall-session-test` replays all 529 delivered
observations plus control events, including the restored six-saved/seven-pending
start. Expected moves were checked against the accepted prefix and successive
camera views of moves 25–35. It checks every accepted prefix, preserves all 35
moves in order, saves 30, and marks black move 31 (source point 48) as displaced.
A separate copy tests **simulated centering** of only that measured outline: all
35 moves then save after eight fresh views, while the actual uncertain reading
at old white move 16 is left unchanged. The recovery copy remains 30 saved plus
five pending; the simulation cannot silently confirm the user's physical stone.

`--recorder-test` adds obstruction-only phantom, raw rapid-play chronology,
bounded confirmed-identity, definite disappearance, wide occlusion, uncertain
new stone, and capture-removal regressions. The earlier 53-move placement sessions
and raw placement-image checks also remain passing. Original diagnostic archives
and the user's original 24-move SGF are preserved.

### Crowded-stone placement measurements (0.37)

In the November 2 13:28/13:29 diagnostic clips, black move 31 was physically
adjusted into the placement-clearance range, but its outline score dropped as it
approached two neighboring black stones. The fit's exterior ring counted those
neighbors as evidence against an isolated circular stone. Most fits disappeared;
the occasional remaining fit scored about 0.78, below the 0.86 placement-evidence
threshold. Missing geometry correctly did not clear the earlier displacement
warning, but this left a good adjustment permanently pending.

A separate placement-only fit now masks independently fitted same-color neighbor
interiors from that exterior ring. It requires two neighboring outlines, at least
92% interior coverage, at least half of the ring independently visible, geometric
nonoverlap with neighbors, and a score of at least 0.90. It is used only for a
strong black reading whose original outline cannot supply placement evidence.
The original footprints and occupancy/empty-point decisions are unchanged.
`BoardObservation.placementFits` carries these extra measurements; diagnostic
operation records include them and the saved-observation replay reads them.
Missing or inadequate fits still leave a placement concern unresolved. A tiny
numeric tolerance keeps an exactly 0.24-grid offset from failing due to binary
floating-point subtraction.

`python3 PhysicalGo/build.py --crowded-adjustment-test` checks raw captured images
before and after adjustment and 24 consecutive final images. It verifies unchanged
occupancy at all intersections, preserves the displaced control, and restores the
actual 30-saved/16-pending checkpoint. The real image-derived measurements then
confirm all 46 moves in the retained order and clear the ring after fresh evidence.
There are no simulated stone adjustments in this test. It exports a separate
recovered game, preserving the user's original SGF and checkpoint. The full vision,
recorder, and earlier placement-session/image regressions remain passing.

### Grid refinement, recovery and view coordinates (0.38)

The November 2 13:57 diagnostic sequence exposed a reset in the successful
`detectGrid` callback. Move 11 had a placement concern; the recorder kept tracking
later moves, reaching 10 saved and 20 pending. The first search interruption
preserved that chronology, but the successful callback called `resetCalibration`
without preservation. This discarded all pending paths (and hence their red rings)
and disabled the paired empty reference. The remaining captured frames contain
one further black move, for 31 moves altogether.

Successful same-size grid acquisition now preserves pending chronology and requires
fresh observations before confirmation. Compatible reference pixels retain their
original reference calibration; the newly detected calibration describes the
current camera image. Both are saved together for reuse. Changing board size
still invalidates incompatible pending paths. The original SGF and diagnostic
archive are retained; recovery writes a separate SGF with a pending checkpoint.

`python3 PhysicalGo/build.py --grid-ui-test` replays the actual pre-search
observations, exercises the real asynchronous grid-search callback on the final
photograph, checks the persisted reference pairing, and processes twelve distinct
final images. It checks the exact retained order, red warnings, camera-start
preservation and incompatible-board reset. It also checks coordinate mapping at
all four rotations on 9-, 13- and 19-line boards and renders native UI previews.
The displaced stones are not synthetically centered or silently confirmed.

Live-camera labels and interpretation labels use view-relative Go coordinates:
letters increase left to right, skipping I, and numbers increase bottom to top.
Label anchors follow perspective correction and rotation while text stays upright.
Canonical camera/SGF coordinates remain unchanged. Recording controls and game
interpretation have separate sections, and the interpretation board grows with
the resizable controls pane. Its red rings are thicker.

The former change-threshold slider is under Advanced detection, labeled Brightness
difference. Lower values are more sensitive to shadows; higher values can miss
low-contrast stones. Color and shape also affect detection. The default is 0.13;
it is not the confidence threshold for recording moves. Editing is disabled while
recording or while a pending sequence remains, because changing the detector
invalidates observation history.

### Capture continuation and one interpretation board (0.39)

The November 2 14:39 diagnostic session reached 51 saved moves and seven pending
moves, then stopped extending the pending path. A previously accepted white stone
was intermittently classified as empty, leaving only one usable whole-board view
of the latest pending move. Broad hand obstruction also produced false color and
empty readings that reset the local evidence for that move. The following reply
therefore could not extend the path, although the physical sequence was legal.

Frames with both excessive uncertainty and more than eight apparent stone
additions now contribute an uncertainty gap to local chronology. The original
images and classifications remain in diagnostics. Partially obscured views with
only a few changes remain useful for ordering. A pending tail seen only once as
a whole-board position can be extended when local evidence independently shows
its stone repeatedly present while the following point was repeatedly empty.
The resulting path still passes legal-move, full-position and fresh-confirmation
checks. This works across captures and later reuse of captured intersections;
it does not infer an unseen move from the final board alone.

`python3 PhysicalGo/build.py --capture-continuation-test` replays the real saved
classifications and geometry from the initial 48-move SGF through the pause. It
verifies the exact 64-move order, both captures at moves 53 and 57, subsequent play
on the vacated point at move 61, review positions and SGF/checkpoint reload.
A focused synthetic obstruction case and native before/after previews supplement
the recorded session. Original recordings are preserved; recovery uses a separate
copy. Recorder, earlier placement and grid-refinement regressions also pass.

There is one Board interpretation section. Live position includes recorded and
pending moves, plus distinct camera overlays: dashed red outlines for detected
stones outside the retained sequence, small orange dots for uncertain empty
areas, and dotted orange outlines for camera disagreement with an interpreted
stone. These marks never edit the game. Saved moves provides review arrows above
the board. Inspect detection switches the same area to camera classifications and
frozen-sample labeling; the former separate inspection section is removed.

Camera coordinates use small regular text directly on the wooden margin, with no
colored boxes. The 0.30-grid margin keeps them inside the visible wood; their
anchors still follow rotation and perspective correction while glyphs stay upright.

### Shaded white stones and accurate pending explanations (0.40)

In the November 2 15:13 session, new moves were well localized but an older white
stone at canonical point 24 (B6 in the displayed rotation) repeatedly classified
as empty. Its median brightness was slightly below the reference wood. The white
chroma test required a brightness difference above -0.02, so a stone around that
boundary could generate an empty result despite its loss of wood tint and covered
printed lines. This withheld whole-position confirmation and eventually stalled
continuation at 65 saved plus four pending moves.

The color-based white test now permits brightness differences down to -0.06.
It still requires strong desaturation relative to reference wood and positive
covered-ink evidence for a darker sample. The separate shaded-wood and neighboring
stone checks are unchanged. In the two raw failing frames, only point 24 changes
from empty to white; the successful control is unchanged. A full raw-pixel replay
of 445 delivered observations saves the exact 77-move sequence without centering
stones, relaxing recording confidence or inferring moves from the final photo.

`python3 PhysicalGo/build.py --centered-stone-test` checks those raw images,
view-relative explanation coordinates, genuine displacement versus pending
confirmation, recovered SGF/review state and native rendering. Vision, shadow,
grained-stone, displaced-neighbor and crowded-placement tests remain passing.
The diagnostic archive and original stalled recording are retained.

The live interpretation now explains whether pending moves have placement evidence
or are waiting for a consistent board view. A definite camera disagreement with
an unchanged, previously recorded stone identifies that intersection explicitly.
Restored-game and attention messages no longer imply that every red-ringed move
needs recentering. This explanation is informational and cannot alter saved or
pending history.


### Touching black stones at the edge (0.41)

The 15:46 diagnostic exposed a genuine black at view-coordinate A11 that the
brightness detector found, but the neighboring-stone safeguard downgraded to
uncertain. Touching black stones contaminated each other's exterior outline.
A strongly centered black neighbor can now supply a provisional exterior mask.
That mask never establishes occupancy: the questioned stone still needs at least
92% dark body support, a nonoverlapping interior, half its exterior ring visible,
and the normal 0.78 outline score. The weaker neighbor outline is not published
as a confirmed footprint. Exposure/ownership blocks still apply.

`python3 PhysicalGo/build.py --touching-edge-test` checks four original frames
and small brightness variations: pre-placement absence, a still-unclear earlier
view, and clear post-capture views. Only A11 gains occupancy; previously detected
stones are retained and the removed whites remain empty. The shadow, displaced
neighbor, crowded placement, and core vision regressions also pass.

The original 84-move recording is preserved. This detection fix does not rewrite
its sequence: A11 appears in the footage before E16, while the later B12 placement
is followed by removal of the two whites. Reconstructing that history requires
resolving the intervening move discrepancy; no pass is inferred from video alone.


### Diagnostic cleanup (November 2, 2026)

At the user's request, the nine older full diagnostic sequences were curated into
`Captures/DiagnosticEvidence/`. The three latest sequences (14:39, 15:13, 15:46)
remain intact under `Captures/Diagnostics/`. Each older session retains all event
logs, original session metadata, references and tracking anchors, plus selected
original frames around move/state changes, warnings, grid operations, known
regression cases, periodic context and the final settling sequence. The original
frame count in `session.json` is historical; consult `retention.json` for surviving
frames and the hashes of removed files. These are no longer full pixel-replay
archives. Historical provenance paths in the sections above and test metadata
refer to the original location; the session name is unchanged in DiagnosticEvidence.

All regression fixtures and the latest three sessions are verified unchanged by
SHA-256. Original saved games and journals remain in Application Support, with an
additional snapshot in `Captures/DiagnosticEvidence/Cleanup <timestamp>/` alongside
the cleanup inventory and verification report. No automatic deletion was added.


### Clearing placement warnings in touching white clusters (0.42)

The 16:11 diagnostic retained all 36 moves, with 29 saved and seven waiting for
white move 30 at view-coordinate C2. Early reliable outlines placed it about 0.4
of a grid interval from center. After the actual adjustment, its ordinary outlines
were missing or below the placement-quality threshold because adjacent white
stones contaminated the exterior ring. Missing outlines correctly failed to clear
the prior warning, but crowded placement refinement previously covered only black.

Placement refinement now supports white clusters. Strongly classified white
neighbors can supply provisional exterior masks when their own outlines are weak;
those masks are never published as placement evidence. The proposed C2 outline
still must satisfy 92% body coverage, a nonoverlapping interior, at least half of
its exterior ring visible and a 0.90 fit score. Occupancy and the recorder's
placement/confirmation thresholds are unchanged. The original displaced control
remains flagged; the adjusted stone measures about 0.16 grid intervals from center.

`python3 PhysicalGo/build.py --crowded-white-test` checks original before/after
images plus 16 consecutive final observations. Occasional missing fits remain
uncertain, while enough independently clear views confirm the exact retained
36-move sequence. It tests paused-checkpoint restoration, fresh confirmation,
unchanged occupancy, preserved earlier moves and the recovered SGF round trip.
The previous crowded-black, intentionally ambiguous placement, and core vision
checks pass. `--inspect-sample` also reports placement fits and offsets so this
failure is directly inspectable. Original recordings remain untouched.


### Withdrawing a contradicted tentative tail (0.43)

In the 16:24 diagnostic, a hand at G1 generated two compatible white sightings,
anchoring an unconfirmed tail behind four retained moves. When G1 later became
clearly empty and the real white move appeared elsewhere, the old tail could not
be shortened because it was already anchored. It was never saved to SGF.

Repeated positive empty evidence may now withdraw exactly one unlocked,
non-capturing tail and consider the preceding retained position. A replacement
must be the only new stone and have the same color. The normal legality and
whole-board matching checks still apply. Uncertainty, a single empty flash,
locked identities, opposite-color additions and earlier captures cannot trigger
this correction. Earlier placement concerns and move order remain intact.

`--recorder-test` includes synthetic protections plus all 1,108 saved observations
and control events from the real session. The replay replaces false G1 (point114)
with observed white214 while preserving the 63 saved moves and the four preceding
pending moves. A subsequent black232 capture is independently checked by the
shared rules engine: it removes points212,230,231,249 (M4, N3, N4, O3 in the current
view). The footage retains white249, so the replay correctly remains blocked
there. No physical removal or later game recovery is simulated or silently saved.
Diagnostic capture was on and stopped at its 5 GB limit after 1,419 images.
Near-duplicate image retention remains a proposed separate improvement.


### A false reply first seen alongside a real move (0.44)

The O3 capture omission was confirmed by the user. A separate offline recovery
copy treats only that captured point as empty after the independently verified
N5 capture; all original photographs, observations and SGFs remain unchanged.
This exposed a second tentative false white at B12. It first appeared alongside
a real Black move, so shortening that false reply removed the only ordering
witnesses for the real move before it.

Withdrawing a positively contradicted, unlocked tail now retains those paired
ordering witnesses at the shorter depth, marking them incomplete for the shorter
position. Fresh matching observations are still required. Capture, locked-move,
uncertainty and repeated-empty safeguards are unchanged. Rapid-pair checks cover the failure and later continuation. An additional
turn-order regression prevents a later White move being moved ahead of an
observed extra Black move, including after evidence expires; all 584 recorder
checks pass. Paired additions and local sequence search both respect positive
evidence that one point was occupied while the other was still empty.
The user-confirmed capture recovery remains separate from automatic recording;
no pass or missing move is inferred from a turn-order gap.

Camera delivery gaps and grid reacquisition that preserve the tentative path
also preserve its bounded local chronology, while invalidating whole-board
confirmation frames. Explicit resets and pauses still require fresh local evidence. Diagnostic replay now uses the same interruption policy
as the live recorder. This prevents a delivery gap between an out-of-turn Black
and the later White from making them appear simultaneous.

The full user-confirmed O3 recovery replay (1,108 diagnostic observations plus
170 later journal observations) retains the exact eight-move pending prefix
through Black G5. It stops before the observed extra Black B18; it neither moves
White D18 earlier nor invents a pass. The 63 already saved moves are unchanged.
The user confirmed that White did not intentionally pass. Original evidence and
saved games remain intact; this deliberately incomplete game is a regression case.

The [historical shadow regression set](Tests/Fixtures/ShadowRegression/README.md) retains original images, references and labels for repeatable offline comparisons, independent of diagnostic storage cleanup.


## Physical board with the existing OGS client (experimental)

The new connection reuses SGF Player's signed-in OGS client, game setup, socket,
clocks, and `sendMove` path. Physical Go never signs into OGS. Build both apps
from the current source; previously installed versions do not include the connection.

1. Start or join a game in SGF Player using the usual computer interface.
2. In its active game panel, enable **Use physical board**.
3. In Physical Go, enable **Online board**, select the same board size, and calibrate
   the camera. Recording a separate local game is optional.
4. Match the physical position to the displayed online board. The most recent stone
   has a red ring. An opponent move triggers a quiet sound, without coordinates.
5. When the status says **Your turn**, place one stone. Four clear observations over
   at least one second send the move automatically through SGF Player.
6. Captures work in either order: place your stone and remove the captured group
   immediately, gradually, or after the move sends. The recognizer computes the
   captured groups from the server board and accepts any subset still on the board.
   Match the updated server board, including removing remaining captures, before
   playing your next move.

Pass, resign, undo, scoring, and clocks remain in SGF Player. Keep both apps running
and the active game panel visible. Switching games disables the connection. An
uncertain view, wrong board size, stale connection, wrong turn, or mismatched board
blocks submission. A submitted move is never retried automatically; if the server
rejects it or confirmation is lost, inspect SGF Player and toggle the connection off
and on before resynchronizing. Camera recognition remains experimental. No real
online game was started during automated verification.

### Connection and iOS direction

The initial macOS transport exchanges atomic JSON files under Application Support /
Physical Go / Online Bridge. State includes a short-lived session token, game ID,
server version, timestamp, board size, occupancy, player color, turn, and last move.
Requests echo the token/game/version and include a timestamp and one intersection.
SGF Player validates the live session and suppresses duplicate submissions per
server version. State expires after two seconds; move requests after three seconds.
These files contain neither credentials nor camera frames.

This file transport is a macOS adapter, not an iOS inter-app communication contract.
For iOS, prefer hosting recognition and the existing OGS client in one app with an
in-memory connection; a phone controlling a Mac would need an authenticated network
adapter. Preserve the board-state/move-request boundary and existing OGS client,
replace file access and AppKit sound playback, and port camera capture/UI separately.
The current SwiftUI board rendering uses no macOS-specific drawing APIs.

Verification: `python3 PhysicalGo/build.py --online-test` exercises initial board
synchronization, stable submission, duplicate suppression, opponent turn, stale
state, natural capture removal, and comparisons against the shared Go engine
without contacting OGS or accessing the user's bridge directory.

Capture inference requires one new stone of your color and permits removals only
from opposing groups with no liberties after that placement. An unrelated removal,
extra stone, or suicidal placement blocks submission. Ko and superko still require
server history validation; a server rejection must be resolved in SGF Player.


### Automatic viewing orientation

**Auto-orient board** uses the long-axis estimate to put the board's longer direction
vertically before play. If the current view needs a quarter turn, it turns clockwise.
**Flip view** changes the player's end by 180 degrees and preserves automatic axis
selection. The existing clockwise rotation button takes manual control and turns
automatic orientation off. Turn Auto-orient board back on to resume automatic selection.

Camera placement is inferred from grid perspective and, when available, independent
stone-shape measurements; an empty symmetric board cannot identify the player's end.
The interface distinguishes an estimated long axis from a confident detection.
**Swap long side** remains available if the axis estimate is wrong. Neither the
canonical camera calibration nor saved move coordinates are rewritten by view rotation.

Automatic viewing rotation is held while a recording or online connection is active.
Before online play, align the view to SGF Player and the browser; the online diagram
uses the server's orientation. Manual view rotation during online play requires board
resynchronization before another move can send. A view flip by itself never sends a move.

`python3 PhysicalGo/build.py --view-orientation-test` verifies 90 checks covering axis
selection, side/end views, seat reversal, manual control, and online/recording locks.

### Printed-grid evidence for an empty board's long side

Version 0.54 adds an independent axis measurement for camera views where the grid
corners alone fit both rectangular orientations. It integrates normalized darkness
across horizontal and vertical printed rails, away from intersections, and compares
ink width in grid units across the board. Comparable physical line widths reveal the
unequal physical grid spacing even with perspective and moderate image blur.

The measurement rejects broad or displaced ink, faint lines, insufficient spatial
coverage, and conflicting regions. It is used when the corner-based camera fit is
ambiguous. Stone-shape evidence and the manual long-side override remain available.
This assumes comparable printed line widths in both directions; unusual linework,
low resolution, heavy occlusion, and lighting can leave the axis inconclusive.

The `SideCameraEmpty` regression fixture is the actual empty-board reference from
the November 3 supervised OGS session. The old corner-only fit selected long rows
without confidence; the new printed-grid measurement selects long columns, as
confirmed by the user's physical board. Tests also cover six earlier real views,
a deliberately misaligned view, independently projected physical grids in both
orientations, low-resolution conflicting evidence, and blank wood. Native startup
tests load this reference from each saved quarter-turn and verify a vertical long
axis. Run `--grid-aspect-test` and `--view-orientation-test` with build.py.

### Live position updates when OGS state_version stays unchanged

Physical Go 0.55 fixes the supervised 19×19 failure where outbound moves reached OGS but the online board stayed empty. The observed bridge file contained both stones while `version` remained zero. SGF Player now generates its own monotonically increasing bridge revision from the board, move number, turn, server version and readiness. Heartbeats do not advance it; passes and undo do. This leaves the existing OGS protocol sequencing unchanged. Incoming physical requests and duplicate suppression use the local revision.

Physical Go also detects position changes independently of the version field, refreshes the board and last-move marker before evaluating camera clarity, and announces an opponent update once. The online tests replay the first Black move, White reply, and next Black move with a constant OGS version, including legacy publisher snapshots, obscured camera observations, heartbeat deduplication, pass and undo. Run `python3 PhysicalGo/build.py --online-test`; capture, differential Go-engine and orientation tests run in the same suite.

### Quiet camera feedback during online play

Physical Go 0.56 keeps the online turn status separate from camera clarity. A brief uncertain frame no longer replaces “Your turn.” Persistent uncertainty displays a secondary warning after one second; it clears after 0.6 seconds of uninterrupted clear observations. The line is reserved to prevent the board shifting when the warning appears. This changes presentation only: every uncertain frame still cancels pending move settlement immediately, and a fresh clear, stable candidate is required to send. Connection errors remain immediate. The online test suite covers isolated and recurring uncertainty, delayed warning recovery, blocked premature moves, and a subsequent stable send.

### Online board star points

Physical Go 0.57 adds visible hoshi to the online board: nine on 19×19 and five on 9×9 and 13×13, matching the interpretation board. They draw below stones and the last-move marker. Native rendered previews were checked at all three sizes.

### Physical placement correction guidance

Physical Go 0.58 confirms a board mismatch across at least four clear frames and 0.7 seconds, then shows a prominent placement banner and graphical corrections on the online board. Red × marks identify extra/wrong stones; blue outlined intersections identify missing required stones. A misplaced opponent stone produces a “Reposition” instruction and one quiet correction sound per mismatch episode. Missing stones alone show a placement instruction without an error sound. Uncertain frames interrupt confirmation but retain already-confirmed guidance while the user moves a stone. Matching the board clears the warning. Legal own-move candidates, including partial capture removal, bypass correction feedback and retain the existing stable-send checks. Tests cover the intentional misplaced White scenario through all four rotations, camera interruption, single-alert behavior, clearing on correction and sending the next own move.

### Authoritative online turn display

Physical Go 0.59 replaces the offline recording banner with a prominent live turn indicator while Online board is enabled. The camera and online-board panels show the color to play, a matching stone icon and “Your turn”/“Opponent’s turn.” The indicator derives from the validated bridge state and account color before camera validation, so an obscured camera cannot substitute a local recorder turn. Disconnected, stale or disabled bridge state clears the heading. The offline recording controls and local recorded-game turn/review display are hidden in online mode; board interpretation remains available. Disabling online mode restores the local recording interface. Tests exercise both account colors, changing turns, camera uncertainty and loss of live state.

### Session synchronization across online moves

Physical Go 0.60 fixes a valid M17 placement being labeled “Remove” after an opponent move. A verified full-board match now anchors the same game/account/size/orientation session across position updates. The next own move can be accepted when a fresh observation matches the latest server board plus exactly one legal own move (including legal capture removals), even if the camera missed the intermediate exact-match position. Camera gaps and lighting/uncertainty interruptions reset settlement evidence while preserving the established session match. New connections, lost live server state, game/account/size/orientation changes still require a full match. Startup guidance explicitly says to lift a pending own stone and replace it after synchronization. Revision-only updates preserve the sent-move guard until the position/turn changes.

The M17Synchronization fixture contains 109 sparse camera observations from the supervised failure, with no account identifiers or tokens. Its replay sends M17 exactly once after clear stable evidence. Additional tests cover interrupted settlement, camera gaps, lighting blockage, reconnection, changed games and revision-only updates.

### Bounded confirmation through unrelated camera uncertainty

Physical Go 0.61 fixes long move delays caused by brief uncertainty at unrelated intersections repeatedly restarting confirmation. Clear candidate evidence can survive up to 0.65 seconds of uncertainty at at most three other points, within a 2.5-second total confirmation window. The new stone must stay clearly recognized, and every known reading must remain consistent with that same legal move and its captures. Candidate uncertainty, larger obstructions, known contradictions, long interruptions and changed live positions reset confirmation. Sending still requires a fully clear current board, at least four fully clear candidate readings and at least one second since confirmation began. Unknown readings are never used to dispatch a move.

The IntermittentClarity fixture preserves 203 camera observations from the supervised November 4 session, without account/game identifiers or tokens. It treats the already-played last stone as a new candidate against the preceding board. Replaying these readings reduced confirmation from 7.78 seconds with the old continuous-clarity rule to 1.45 seconds with the revised bridge, with exactly one request on a fully clear frame. Tests additionally cover brief one/three-point uncertainty, uncertainty on the new stone, hands, contradictions, prolonged obstruction and no fully clear recovery. Run `python3 PhysicalGo/build.py --online-test` for these checks alongside capture, synchronization, orientation and differential Go-engine tests.


### Rolling confirmation evidence and automatic delay history

Physical Go 0.62 replaces the 0.61 all-or-nothing confirmation timeout with a sliding 2.5-second window. Each fully clear reading expires individually. Small uncertainty elsewhere can pause evidence while the candidate itself stays clearly recognized and all known readings remain consistent. Sending still requires four fully clear candidate readings within that window, spanning at least one second, and a fully clear current frame. Unknown readings never count as confirmation; candidate uncertainty, more than three uncertain points, contradictions, camera gaps and position/session changes still reset evidence. A continuous obstruction expires all old evidence.

The RecurringClarity fixture records 192 observations of the stationary board from the follow-up investigation. It is explicitly not a recording of the user's delayed placement. A replay starting at the observed difficult interval compares the 0.61 rules with the rolling window against the same last-stone candidate. Both delay fixtures, capture/synchronization checks and negative cases run with `--online-test`.

Online mode now automatically writes compact local decision history to `~/Library/Application Support/Physical Go/Online Bridge/decisions.jsonl`, rotating into `decisions.previous.jsonl` at 2 MB per file. It records time, turn/position changes, uncertain intersections, known differences, retained clear evidence, camera waits and move-request dispatch. This allows a later report to distinguish camera, confirmation and server acknowledgment delays. It contains no images, credentials, account IDs or game IDs. Writes run on a background queue and do not affect move eligibility. Tests cover log contents, exclusion of credentials and bounded rotation.

### Neighbor-aware recognition of a shaded empty cross

Physical Go 0.63 fixes the supervised Q13 stall after the user correctly removed a pending Black stone and placed White's latest move. The physical stones matched OGS, but brightness gradients and low absolute ink contrast kept the empty intersection uncertain. The online gate correctly refused to synchronize; its previous placement warning incorrectly remained visible.

A second local check now runs only at uncertain intersections beside independently fitted Black stones (outline quality at least 0.85). Their observed bodies are excluded from the wood samples. At least 90% of the remaining samples must retain wood color within a bounded tolerance and plausible shaded brightness. Both original printed rails must still be independently visible, with contrast measured relative to their immediate surroundings and finer sampling within the same small alignment range. Neighboring stones never establish emptiness by themselves. Disputed geometry and lighting blocks retain their existing guards. The adjustment does not change online confirmation or dispatch rules.

The ShadedCross fixture stores three real frames and the empty reference from this failure. `--shaded-cross-test` covers 81 brightness/alignment variations, preserves all 37 real stones, and checks 12 opaque, wood-colored, single-line, displaced and small-object counterexamples. Online feedback tests also verify that corrected stones lose their stale placement warning when a different point remains uncertain; the app then says it is checking the remaining unclear intersections. No move is sent and no initial synchronization is assumed until the full board is read clearly.

### Authoritative physical-board corrections and labeled images (0.64)

Use **Check board photo…** in the header. Camera processing continues, but move dispatch and recording ingestion pause while the editor is open. The editor freezes a matched photo, calibration and raw observation; selecting an intersection reveals its original camera crop. The original persistent-correction behavior is superseded by 0.126: labels apply only to a reviewed photograph and never override subsequent camera readings. Saving labels archives the photograph without changing the game. A separate explicit confirmation can resolve an eligible local capture or restoration review, subject to the freshness and context checks described above. Labels never authorize an online move. Cancel discards the draft.

Each committed edit is archived atomically under `~/Library/Application Support/Physical Go/Corrections/<UUID>/`: lossless `camera.png`, optional empty `reference.png`, and `corrections.json`. Metadata contains original uncorrected readings/outlines, both calibrations, threshold, orientation, timestamps, app/source version, explicit actions and labels in raw camera coordinates. Only points explicitly labeled in that edit become training truth; prior manual values and the other 359 camera readings are not silently labeled. Returning a point to automatic detection is an action, not an occupancy label. An archive write failure leaves editing paused and preserves the draft for retry. Files remain across app updates; there is no automatic upload, retraining, or deletion. Ordinary diagnostic replay also records which user corrections were active without replacing its raw readings.

The supervised E3 capture/F3 removal and subsequent H2 stall exposed two detector failures. Touching-stone outline search now uses a wider bounded radius range only when neighbor masking is available, retaining body support, disjoint interiors, visible exterior and an oversized sentinel rejection. Empty-cross verification also permits darker wood to become warmer under mixed illumination, while requiring preserved wood hue/saturation and both reference grid rails. The recognition change makes 28/43 capture frames and 49/80 subsequent H2 frames fully clear, with no wrong classifications against the reviewed positions; adjacent frames are correlated, not independent accuracy trials. The frozen 449-visible-label corpus improves from 385 to 391 correct, with six pre-existing wrong results unchanged and no newly wrong or regressed labels.

Run `python3 PhysicalGo/build.py --correction-test` for photographic capture dispatch, authoritative-edit lifecycle, context isolation, stale/lighting guards, lossless image/explicit-label archiving and archive failure checks. `--online-test`, `--test`, `--shaded-cross-test`, `--touching-edge-test`, and `--geometry-test` cover the existing online and vision regressions. All automated move requests use disposable test bridge directories.

### Illegal-move and server feedback (0.65)

The SGF client publishes forbidden intersections using its existing rules and game history, and validates physical requests again before submission. Physical Go recognizes stable forbidden placements before its full-board synchronization check, explains the rule (including ko), sounds one quiet alert and marks the stones to remove or replace. Uncertainty elsewhere cannot hide a clearly observed illegal placement. Restore the online position before continuing.

Move requests carry unique IDs. Active-game server errors are relayed to the matching pending request; errors from another game are ignored. An unconfirmed request displays a warning after eight seconds and is never automatically retried. Tests cover ko with history, unrelated camera uncertainty, restoration, correlated/stale rejection feedback, timeout and a subsequent legal move. Network tests cover current-game error strings and objects, malformed errors and other-game isolation.

### Guided stone calibration and experimental appearance ranges (0.66)

**Calibrate stones…** starts a three-photo workflow while the camera is fresh/aligned, a reference is present, online mode is off, and no recording is active or paused. First confirm an empty board; then place three black and three white stones at the diagram's six positions; finally swap the colors. The touching center pair supplies empty samples beside one and two black stones, then beside one and two white stones. Small teal rings identify explicitly sampled empty points around the stones. The diagram follows the current view rotation and includes star points. Each photo is frozen for review before the user confirms its labels. Retake discards only an unconfirmed photo. The empty calibration image is separate from the detector's existing reference.

Every confirmed photo is saved atomically under `~/Library/Application Support/Physical Go/Stone Calibration/<session UUID>/<capture UUID>/`, with a lossless PNG, raw readings, calibration, timestamps, explicit sample labels, the confirmed placement diagram and source version. Cancellation retains confirmed photos. A save failure preserves the pending photo and stage for retry. A complete session also saves `profile.json`, linking its feature distributions and examples to all three captures. There is no upload or training from unconfirmed camera guesses. Profiles are available for comparison during the current app session; archives persist across restarts, but old lighting profiles are not automatically reactivated.

The portable appearance model compares brightness relative to nearby wood, within-patch variation, wood-color difference, grid contrast and body-to-edge contrast. Each class has a descriptive median and range with a noise floor. These ranges and fit scores are **not calibrated probabilities or statistical confidence intervals**. Black and white each retain one shared distribution. Only the **empty** distribution can have neighborhood-specific components: open, one/several black, one/several white, or mixed, with at least three labeled examples per component. Unlabeled neighbors remain unknown and use the pooled empty distribution. The inspector uses strong camera evidence or explicit user corrections for neighbors, rather than assuming the online board is physically correct. Large local lighting drift, stale frames and changed camera/reference/size prevent comparison.

**Inspect stone appearances…** selects a point on the board and displays the three expected brightness ranges and appearance fits. This model is experimental and **does not alter recognition, recording, manual overrides, or automatic OGS dispatch**. Calibration pauses ingestion and submission. Once calibration is complete, remove the six stones before starting a game.

Run `python3 PhysicalGo/build.py --stone-calibration-test` for photo/label archival, patterns, appearance separation and abstention, empty-only neighborhood conditioning, missing-neighbor handling, context/freshness guards and save-failure/cancel/retry behavior. `--online-test` covers existing online/capture/ko behavior.

The experiment is reproducible with `python3 PhysicalGo/build.py --stone-appearance-audit PhysicalGo/Tests/Fixtures/ShadowRegression/v1`, then `python3 PhysicalGo/Tools/stone_appearance_report.py NEW_OUTPUT --engine PhysicalGo/.build/StoneAppearanceAudit`. The report verifies frozen fixture hashes, excludes each entire test session from its training set, and uses one training sample per human-labeled point/episode. Across 449 visible historical labels, the production detector yields 391 correct / 52 uncertain / 6 wrong. An offline proposal that only resolves uncertainty when appearance agrees with independent strong outline or visible-grid evidence yields 417 / 26 / 6, with no newly wrong labels. The appearance-only classifier makes a new error and is not a replacement for the detector. Empty-neighborhood conditioning does not further improve this corpus: adjacent human labels are too sparse to fit the shaded components. These selected, correlated recordings share equipment and are not a general accuracy estimate or validation of a new six-stone calibration session. All 26 correctly resolved labels are empty intersections. The proposal also assigns empty to one occluded uncertain example; it needs an independent obstruction guard before live dispatch use. The proposal remains offline pending live calibration and obstruction evaluation.

### Calibration preview orientation and resuming confirmed photos (0.67)

The live calibration preview and frozen confirmation photo now apply the same `BoardOrientation` quarter-turn transform as the target diagram and game view. Non-square camera frames are fit after accounting for swapped dimensions; neither archived pixels nor raw-grid labels are rotated. Native rendered-image regression tests check marker placement for all four quarter turns.

**Resume calibration…** restores the latest unfinished set of confirmed photos. It validates stage order, labels, image size, board size, rotation, camera identity (when available), grid alignment and agreement of the saved empty photo with the current reference before rebinding the session. Legacy 0.66 captures lacking a camera ID must still pass image/grid/reference checks. Pending unconfirmed photos are never restored as labels. This permits an app update at the six-stone step without asking the user to clear the board and repeat the empty photo. Changed camera/orientation/grid and malformed archives are rejected. Resume restores the chosen game-view orientation; it does not choose a new orientation.

### 0.68 — Stable empty-reference controls

The empty-reference button stays visible in idle/finished recording modes, above the changing readiness text. Readiness messages reserve their line space in the recording panel and new-game sheet. A verified empty board no longer hides or disables reference capture; a fresh aligned live camera is still required, and recording, calibration, or correction editing prevents capture.

### 0.69 — Reference capture confirmation

Successful empty-reference capture replaces the startup button with a green “Reference captured” confirmation in the same reserved space. Camera uncertainty does not bring the capture prompt back. Replacing/removing the reference resets confirmation; a restored reference is confirmed only after a live empty-board check. Optional manual recapture remains in Board alignment.

Run `python3 PhysicalGo/build.py --reference-feedback-test` for capture completion, invalidation, and native layout checks.

### 0.70 — Shadows beside touching black stones

A confidently recognized black stone (pixel agreement ≥0.90) may now support the existing shadow test with an outline quality ≥0.80, instead of requiring ≥0.85 in all cases. This only enables a check: wood color and both surviving printed rails still have to demonstrate an empty intersection. It does not change online confirmation, legality, capture handling, or classify uncertain points from the server position.

The November 4 live sample had 37 uncertain readings across 53 frames; replay resolves all 37 without changing any stone readings. The frozen 449-label visible corpus is unchanged (391 correct, 52 uncertain, 6 existing wrong). `--touching-shadow-test` covers both affected empty crosses under 27 brightness/alignment variants and preserves all 11 real stones. Twelve synthetic object-cover results are unchanged; four wood-colored covers were already mistaken for empty by the primary detector and remain a known limitation. The existing shaded-cross suite retains its stricter opaque-object checks.

### 0.71: persistent move timing and correction photo orientation

Online play now writes compact per-game, per-run JSONL files under Application Support/Physical Go/Online Bridge/Move Timing, separate from the rotating frame log. Each observed online position and physical-board match is timestamped. Local attempts record first recognition, first clear candidate, request written, server position observed, interruption, and uncertain intersections/blocker counts. Attempts taking five seconds are flagged automatically. Durations use monotonic uptime; timestamps describe client observations, not the exact instant of physical placement or server receipt. Initial connections record a snapshot; disconnected or unobserved moves are not reconstructed. No credentials, full boards, or photos are included. Diagnostics offers Show move timings and reports write errors.

A clearly recognized added stone with other uncertain intersections now displays “Move recognized — checking the rest of the board.” Dispatch rules are unchanged. Correction close-ups and full photos use the same quarter-turn rotation as the playing board; archived source photos remain raw.

Verification: `python3 PhysicalGo/build.py --move-timing-test`, `--correction-photo-test`, and `--online-test`. The timing tests cover clock changes, slow flags, passes, split server updates, withdrawal and file preservation. Native photo tests check all four rotations, selection centering, neighboring landmarks and nonsquare aspect fit. Online tests verify actual timing integration and one request per move.

### 0.72: historical online move evidence

The online bridge now anchors once to the observed server position and then evaluates transitions. `HistoricalMoveEvidence` retains verified unchanged points, required opponent placements, captured remnants and empty-point witnesses. Uncertainty at unchanged points no longer gates a move. A candidate must be the unique newly observed stone of the expected color at a previously verified empty, locally legal intersection, with confidence at least 0.8 and unambiguous geometric assignment. The candidate needs at least four fresh supporting observations spanning one second; candidate uncertainty, conflicting readings, broad obstruction, lighting/alignment failure, or a camera gap interrupt settlement. No-move is an explicit outcome. Ko/superko and server rejection still use the existing OGS client.

Server changes create targeted placement/removal obligations. An acknowledged own move retains its visual evidence across split turn/position updates. A new opponent stone must be seen at its destination before another own move can send. Captures may be removed before or after dispatch; a captured remnant is excluded from candidates until observed empty. Initial connection, rotation, changed game/account or reset still requires a board match. Known contradictory changes remain blocking; remembered values never replace raw camera classifications, archived training labels, or the interpretation display.

This version reuses the existing appearance classifier and temporal empty-to-stone evidence. It does not yet implement raw-pixel differencing against a per-move photograph, nor alter offline game recording. The compact timing journal uses schema 2 and marks its evidence scope as local candidate.

Validation: `--online-test`, `--historical-move-test`, `--move-timing-test`. The online suite includes 300 differential legal/capture positions, both colors, all board sizes/rotations, illegal ko, server rejection, no retry and duplicate suppression. New sequence tests cover split acknowledgments, unplaced opponents, captured remnants, captured-point reuse, weak/ambiguous evidence, competing candidates and broad obstruction.

A saved 4,260-observation / 19-minute recent-game excerpt was replayed through the original 0.71 bridge and the new bridge in isolated temporary directories. Both submitted exactly six choices matching the next recorded server move. The median first-seen-to-request interval fell from 26.35s to 1.28s; the worst from 202.79s to 1.48s. The long 202.79s, 43.49s and 92.33s waits became 1.29s, 1.28s and 1.48s. These logs lack original confidence/geometry, so that replay uses classified labels with confidence=1, and seeds the established pre-excerpt synchronization. A separate 127-frame diagnostic replay retained original confidence, footprints and placement fits: both actual moves matched subsequent server positions, with delays 1.98→1.33s and 3.57→1.05s. No additional submissions occurred in either excerpt. These are decision-policy comparisons against recorded server moves, not independently labeled accuracy estimates or a new live-game validation.

Artifacts and the preserved original bridge are in `work/physical-historical-moves`. The replay tool writes only temporary offline bridge directories; source camera archives and user game files are read-only.

### 0.73: visible grid contradicts either stone color

Black candidates now participate in the existing exposed-wood/two-rail empty check. A separate shared `survivingGridCross` check handles both black and white proposals even when nearby wood-color correction is unavailable (the cause of the two remaining false-black cases). It compares the reference's horizontal and vertical ink contrast against the current frame within the proposed stone body, normalized by adjacent brightness. Both directions need at least two usable reference probes and 75% agreement; border intersections use the inward part of the grid line. A surviving cross withdraws the stone call to uncertain, without asserting a new empty label. Geometry cannot promote that contradicted proposal in the same frame.

Frozen native corpus replay, 34 photos / 455 labels (449 visible, 6 occluded): correct 391→392, uncertain 52→53, wrong 6→4. The two empty-as-black errors (6631BCB8 frame 269, points 304/323) become uncertain, not confidently empty. One labeled black point improves uncertain→black through downstream geometry. There are no correct→wrong or correct→uncertain labeled changes. All four remaining visible errors are white-as-empty. Occluded stone calls remain 2. There are 24 changed readings across all pixels sampled as intersections, of which only three are frozen labeled changes; the other 21 must not be counted as verified improvements. These published regression images are not a fresh holdout or general accuracy estimate.

`--visible-grid-stone-test` verifies both historical false positives across 27 brightness/alignment variants and retains labeled black/white controls. Existing `--shaded-cross-test` (81 variants plus 12 covering-object cases), `--touching-shadow-test` (27 variants plus 12 baseline-matched covering-object cases) and `--placement-confidence-test` (11 combined-session checks and 19 actual placement images) pass. The touching-shadow fixture has preexisting empty calls for some wood-colored covers; baseline parity does not establish perfect occlusion handling.

Paired native predictions, per-class/session metrics, provenance hashes and all changed readings are retained in `work/physical-black-grid/shared-cross-audit`. Raw images and frozen labels are unchanged.

### 0.74: covered grid challenges empty, bounded shape identifies color

The reference-grid comparison now distinguishes surviving ink from positively missing ink in both directions. A final empty classification is challenged when at least 75% of usable samples in each direction have lost their reference line contrast. Missing ink alone produces uncertain, not a stone label. `StoneGeometry.coveredStone` tests black and white body hypotheses and requires exactly one strong compact outline (quality >=0.86, non-sentinel radius, intersection containment, center within 0.28 grid spacing and no overlap with an independently fitted neighbor). A missing global wood-color adjustment permits a zero-shift fitting hypothesis only under these independent ink/body/boundary gates. Unbounded hands or glare are not assigned a color merely because they hide the grid.

Frozen 34-image corpus, same 449 visible labels and 6 occluded: correct 392→393, uncertain 53→56, wrong 4→0. All four prior white-as-empty cases lose the false empty call: 6631BCB8/269/78 is white; 6631BCB8/269/39, A7ACE3FA/1114/93 and A7ACE3FA/1270/51 remain uncertain. There are no formerly correct labeled losses. Both false-black cases from 0.72 remain uncertain. Occluded stone calls remain 2; zero errors on visible labeled cases does NOT imply zero mistakes under occlusion or in new games. Of 20 changed readings across the complete sampled frames, only four have frozen labels; other changes are not counted as independently verified improvements.

`--covered-grid-stone-test` checks 108 missed-white brightness/alignment perturbations: 44 white, 64 uncertain, none empty or wrong color; it also preserves both false-black guards. Shaded-cross tests retain all 37 control stones across 81 variants plus 12 covering-object checks. Touching-shadow tests retain all 11 stones across 27 variants; the normal-size plain wood-colored cover now becomes uncertain instead of empty. Three preexisting small/striped wood-cover false-empty cases remain and are explicitly reported, not disguised as passing occlusion accuracy. Placement confidence tests retain all 53 intended assignments across 11 session checks and pass 19 actual placement-image checks.

Results/provenance and the previous native engine are in `work/physical-covered-grid`. Frozen images and labels are unchanged. This is a selected historical regression comparison, not an untouched holdout, a live-game test or a general 100% accuracy claim.


### 0.75: neighbor- and color-conditioned overlap support

Covered-grid recovery now runs at unresolved points as well as empty points; surviving-grid and disputed-ownership blocks remain authoritative. If an independent outline fails, a new contextual fit uses only original same-frame neighbors with classification confidence >=0.90, outline quality >=0.86 and radii 0.38–0.52 grid spacings. Newly recovered stones cannot seed further contextual recovery in that frame. A measured wood-color correction is required for contextual masks.

The full stone radius remains within 0.04 grid spacing of the neighboring median, with its center within 0.20 of the assigned intersection. Neighbor masks combine by union and exclude pixels only where the observed color supports that particular neighbor. Thus same-color merging and opposite-color occlusion are accounted for spatially; neighbor count alone never lowers a threshold. At least 65% of the full body, 92% color support within that visible body, half the exterior ring, and outline quality >=0.90 are required. The equivalent visible-area radius is R*sqrt(visibleFraction), not a globally smaller stone-size threshold. The 65% floor is a conservative tested policy, not a measured physical maximum; camera angle, stone height and severe/multiple occlusion can leave too little evidence. Exactly one color must pass.

`--occlusion-context-test`: 105 controlled checks cover both target colors, one/two neighbors, mixed-color neighbors, both camera axes, absent targets, small fragments, incorrect/weak/uncertain neighbor labels, and severe four-sided occlusion. Fourteen controlled outlines rejected without neighbor context are recovered. These use constructed images and supplied neighbor evidence; they are not a measured live-game recovery rate.

The frozen 34-photo audit (449 visible labels, six occluded) changes 393 correct / 56 uncertain / zero wrong to 394 correct / 55 uncertain / zero wrong, without any formerly correct losses. White at 6631BCB8/269/40 improves. An explicit ablation disabling contextual masking produces the same historical classifications: this corpus improvement comes from extending covered-grid recovery to uncertain points, not from the new masks. All ten changed readings are uncertain-to-white in that image; only one has a frozen label. The other nine are not counted as verified improvements. Occluded stone calls remain two.

Other verification: 108 missed-white perturbations (48 white, 60 uncertain, none wrong/empty); 27 historical false-positive perturbations; 81 shaded-cross cases with all 37 stones; 27 touching-shadow cases with all 11 stones and the same three known small/striped wood-cover limitations; 11 placement-confidence cases retaining all 53 assignments plus 19 actual placement images; 27 geometry variants and adversarial objects; the core suite's 199 placement, 47 rectification and 373 vision/shared-SGF checks. Raw training images and frozen labels are unchanged. Artifacts, original source, native predictions and the mask ablation are in `work/physical-occlusion-context`. No new live game has been tested.


### Broad recorded-data replay of 0.75 (November 4)

`Tools/recorded_data_audit.py` reprocessed all 9,516 retained analyzed images across 23 local archives. Logs mention 12,576 analyzed images; 3,060 earlier images have been pruned. Seven archives have complete images and a restorable recorder state and were replayed continuously through the current detector and recorder. Other archives were reclassified from retained pixels without pretending to reconstruct missing chronology. Original manifests/event logs were hash-checked unchanged, and source photos were read-only. The replay uses recorded calibration, thresholds and controls, with no saved manual classifications or simulated stone centering.

`Tools/summarize_recorded_data_audit.py` reports sequence agreement separately from true accuracy. Across 199 comparable reference move slots, excluding seeded moves: 178 match and are automatically saved (89.4%), five match but remain pending (2.5%), 15 are not retained (7.5%), and one pending coordinate differs (0.5%). Fourteen of these slots extend the earlier saved/pending tails and match subsequent initial SGFs. The references originate from older recognizers; some endings are incomplete. Therefore these are agreement/completion numbers, not an independently validated all-moves recognition or error rate. The one disagreement in D228C8EC (raw points 114 versus 214 at move 68) visually favors the current interpretation, but remains disputed in the table pending full end-of-clip annotation. No frozen training labels were modified.

A7ACE3FA is a concrete recording regression/bottleneck: current replay saves 39 moves and retains no tail, whereas the archived reference contains 54. Each of the final 15 intended stones has multiple correct camera readings in the replay; correct individual classifications are not sufficient to reconstruct/commit the continuation. This audit does not change that behavior. A separate online replay with 127 freshly reclassified camera images matches both subsequent server moves, with no extras and first-seen-to-request delays of 1.33s and 1.05s. It covers only two move opportunities.

Full predictions, per-frame/per-move details, original-reference provenance, logs, compiled adapters and a readable HTML report are in `work/physical-recorded-data-audit`. These tools write new output directories only.

### 0.76: move evidence and timing distributions

Online timing schema 3 adds compact, persistent evidence at first unique candidate detection, first clear evidence, and submission. Submission records confidence, assignment ambiguity offset, physical placement offset (grid-spacing units), manual-correction provenance, and the final confirmation window's minimum/mean confidence, maximum assignment offset, scored/geometry/manual witness counts, and span. Missing geometry is null, never zero. Confirmation statistics reset with failed settlement and expire with the bridge's evidence window; post-submission frames cannot overwrite dispatch evidence. Each event includes app version/build/source hash. The journal also records maximum pre-submission observation gap and simultaneous uncertain-intersection count at dispatch; the older `uncertainPoints` remains a cumulative per-attempt count, not instantaneous uncertainty.

Diagnostics now displays this app session's per-game submitted-move count, mean, median, interpolated 95th percentile, maximum detection-to-send time, delay bins, and mean send-to-observed-server time. These statistics are observational and do not alter recognition, settlement, legality, or dispatch. Journals survive restarts; the live summary starts with the app session.

Generate a report across all retained runs of a game:

```
python3 PhysicalGo/Tools/summarize_move_timings.py --game 92223085 --output /tmp/physical-go-timing-report
```

The default input is `~/Library/Application Support/Physical Go/Online Bridge/Move Timing`; `--input` accepts another directory or a JSONL file. Output is `report.html`, `summary.json`, and `moves.csv`, with one row per submitted attempt, all timing-phase distributions, confidence distributions, missing-data coverage, and unsent-attempt outcomes. Camera-only confidence summaries exclude manually assisted confirmation windows and unknown provenance. Duplicate copies of an attempt's events do not double count it. Unreadable lines (including incomplete appends) are reported. Legacy schema-2 timing remains usable; absent confidence is never reconstructed.

Timing starts when a unique newly classified stone of the expected color is first observed in an attempt, not when the hand places it. Unrecognized intervals before that point are unknown. Replacements and withdrawals start separate attempts, so successful-attempt latency can understate the total wait for a physical move. First-clear-to-send includes interruptions; final-confirmation span describes only the successful settling window. Server acknowledgment means this app observed the updated server position, including polling/processing delay. Heuristic confidence is not a calibrated probability of correctness. Percentiles use linear interpolation; histogram intervals include the lower bound and exclude the upper bound.

The 76 submissions in game 92223085 were all acknowledged. First-detection-to-send: mean 1.521s, median 1.301s, P95 2.320s, max 6.319s; bins 1–1.5s:47, 1.5–2s:21, 2–3s:6, 3–5s:1, 5–10s:1. Mean send-to-server-observed was 0.593s. The journal also contains 56 withdrawn and 57 replaced attempts; those are not independently labeled physical moves or recognition errors. No numerical confidence was saved for this legacy game.

Validation: `--move-timing-test`, `--online-test`, and `python3 -m unittest discover -s PhysicalGo/Tests -p test_move_timing_summary.py`. Coverage includes failed confirmation windows, missing geometric evidence, manual corrections, dispatch evidence frozen through acknowledgment, all four rotations, session statistics, legacy missing fields, missing acknowledgments, duplicate input, histogram boundaries, and percentiles.

### 0.77: automatic evidence clips and specific alignment failures

A separate automatic camera ring now runs while Online board is enabled. It samples delivered live frames at most twice a second, retains up to four seconds/nine full-resolution images with an 80 MiB image-memory ceiling, and writes nothing until triggered. Triggers are a five-second attempt delay, candidate confidence below 0.90 (including accepted 0.80–0.90 readings), or assignment offset at least 0.24 grid spacings (including accepted offsets below 0.30). Manual correction scores are excluded. This is a diagnostic selection policy, not a change to move acceptance or a calibrated error probability. Only the current new-stone attempt triggers; uncertainty on established stones does not create clips.

Triggers save the preceding ring plus three seconds afterward. Repeated triggers share an active clip, extending its tail up to twelve seconds after the first trigger. A delayed/borderline attempt triggers again on submission to capture the actual accepted move; if an earlier clip has already closed, this starts another clip. Temporal coverage can be shorter for startup, high-resolution frames reaching the memory cap, writer backpressure, camera/online shutdown, or disk limits. Available pre-roll, frame timestamps, dropped ring samples, and stop/failure reasons are recorded. Images are raw, lossless PNGs; view rotation is metadata so replay/inspection can use the playing orientation without changing training pixels.

Archives live under `~/Library/Application Support/Physical Go/Move Evidence`. They use the existing asynchronous diagnostic writer with at most twelve queued frame writes, reference-image and tracking-anchor versions, per-frame calibration/threshold/orientation/correction context, and raw analysis readings/outline fits linked by `captureUptime`. Manifests identify app/source version, game/attempt/trigger and sampling policy. Trigger metadata also preserves the expected server position for replay, explicitly marked as not camera ground truth; the compact timing journal still omits full boards. Timing events link to their archive folders; the timing-report CSV/JSON includes those paths. These automatic captures are observations, not authoritative training labels. A shared 5 GB disk allowance (increased from 512 MB in 0.78) stops new capture when full; existing clips are never silently removed. The writer also preserves at least 2 GB free space and reports failures. Diagnostics exposes an automatic-capture toggle, status/error text, and Show move captures. Camera stop and app shutdown finish pending clips. Manual diagnostic recordings remain separate.

Alignment telemetry now records the unchanged tracker's exact rejection path: initial/fallback line counts and required minima, matching fraction, support on each outer rail/quadrant, maximum movement in grid cells and pixels, and old/new profile errors and thresholds. Nonfinite numeric evidence is represented as null. Alignment-failure counts and latest detailed failure are also retained in each attempt's persistent timing journal, independently of rotating camera decisions or image capture.

Validation: `--move-capture-test` checks lossless original dimensions/pixels, temporal sampling, pre/post windows, coalescing, duration/memory/storage limits, disabled capture, orientation/context, and shutdown. `--move-timing-test` covers accepted-but-borderline confidence, near-threshold geometry with strong color evidence, exclusion of manual confidence, slow triggers and journal correlation. `--bump-test` passes 137 checks; its stale expectation that the historical fixture remained uncertain was replaced with the invariant that only fully resolved positions can export. The fixture now resolves all 16 stones under the existing recognition algorithms. A separate original/instrumented tracker comparison over 16 saved-image variants (movement, blur, brightness) produced identical calibrations/rejections. The full online regression suite also passes.

### Play modes and SGF export (0.79)

The top bar offers **Local game** and **Online play**, plus an independent
**Diagnostics** switch and **Save SGF file** button.

- Local game records two players at the physical board. Start recording on a
  verified empty board; accepted moves are autosaved as SGF in the existing
  Recordings folder. Save SGF file exports a copy of the recorded sequence.
- Online play uses the existing SGF Player bridge. Enable Use physical board in
  the connected game's SGF Player panel. Camera observations are routed only to
  the selected mode. Switching modes pauses a local recording without discarding
  its saved or tentative moves; returning to it requires Resume and a board check.
- Diagnostics shows camera overlays, the interpreted board, per-intersection
  confidence, live alignment reports, tuning, timing and capture controls. It
  does not start image capture or pause gameplay. Mode and diagnostic visibility
  are remembered independently. Manual diagnostic capture works in both modes;
  automatic unusual-move clips and server timing remain specific to online play.
- Save SGF file in online mode requests the entire SGF through SGF Player's
  existing OGS download service, including a finished game while its panel stays
  connected. This does not infer a game from the current camera position or copy
  credentials into Physical Go. Requests are pinned to a game/session and checked
  against the response UUID, with stale-state, download-error and timeout feedback.

Validation: `python3 PhysicalGo/build.py --play-mode-test` checks local autosave,
mode transitions and preference restoration, independent diagnostic visibility,
native views in all four combinations, and isolated SGF request/reply scenarios.

### Timing dashboard, End game and game info (0.80)

With Diagnostics enabled, **Move timing** is now the first panel on the Game tab.
It reads saved online journals and local observation journals in the background,
updates incrementally, and reloads after restarting. Choose a game to inspect its
mean, median, P95, maximum, timing histogram, individual moves and exception clips.
Online confirmation timing ends when the bridge request is written; subsequent
server acknowledgment is displayed separately. New local recordings save explicit
first-retained-candidate-to-recorded durations. Older local durations can be
estimated from ordered candidate observations and acceptance events; these are
labeled estimates. Manual moves, passes, missing evidence and measurements crossing
pauses/recovery are excluded rather than counted as zero. None of these timings
measure physical placement, first independent visibility, or CPU execution time.

The existing bounded automatic camera archive now also operates during local
recording: unresolved low-confidence/placement candidates lasting 2 seconds,
confirmation delays of at least 5 seconds, and unrecorded-stone warnings request a
short clip. Normal local moves do not save images. The shared 5 GB retention limit,
4-second pre-buffer, 3-second post-window, 2 fps rate and 80 MiB memory bound remain.
Capture failures do not block recognition; event records identify missing clips.

**End game** is always visible in local mode, enabled for an unfinished recording.
It preserves the SGF and does not infer a winner. Unresolved moves block finishing
and retain their history. Online games still end through OGS controls.

The **Info** tab edits black/white names and ranks, komi, date, event and result.
Local changes autosave into SGF, using the existing SGF writer's escaping. New
recordings default to today's date and 6.5 komi; existing metadata is preserved.
Online metadata can be loaded read-only through the existing SGF Player export
bridge, with its authoritative settings edited in OGS/SGF Player.

Validation: `python3 PhysicalGo/build.py --timing-panel-test`, `--recorder-test`,
and `--move-capture-test`. The dashboard reader was also checked against existing
local and online recordings without altering them.


### Rules and fixed handicaps (0.81)
Info and New game offer Japanese, Chinese, AGA, Korean, New Zealand and Tromp-Taylor presets using the shared engine's legality policies. The recorder does not automatically score games; enter the agreed result in Info. Current rules/setup are locked; “Next game settings” edits the next recording. Komi remains explicit and editable; handicap selection does not silently change it.

Choose no handicap or 2–9 fixed black stones. First verify the empty board and start the recording, then place the stones shown on the setup diagram (same orientation as the playing board). Five matching camera frames over at least 0.8 seconds verify the entire setup before White plays. Missing/extra/wrong-color/uncertain intersections and camera interruptions prevent premature completion. Free placement is not offered in this version. Online settings continue to come from OGS.

SGF writes RU, HA, AB and PL[W]; setup stones are never numbered moves. Restoring, undoing and history recovery retain the starting position and correct turn. Existing Japanese empty-board checkpoints remain compatible.

Validation: 324 new rules/handicap checks across 9/13/19 boards and every supported count, plus the existing recorder/replay and Info/timing suites.


### Local clocks and AI scoring (0.82)
Info contains the next game's time-control settings and independent sound controls. Default: 10 minutes main time, five 30-second Japanese byoyomi periods, with a spoken final-ten-second countdown in overtime and period announcements. Without Japanese byoyomi, optional speech announces 1:30 and the final ten seconds. Quiet move beeps, every-second ticking, final-ten ticks, timeout sound, volume and installed English voice are independent options. Preferences persist.

All six OGS clock types are available: byoyomi, Fischer with a cap, Canadian overtime, per-move, absolute and none. Large clock opens an enlarged two-player display with Pass and clock controls. Pause clock also pauses recording; Resume waits for board verification. Clocks begin after empty-board/handicap verification, switch on verified legal moves and passes, and use retained first-sighting times to account for confirmation delay within an uninterrupted turn. Unreliably timed catch-up sequences require explicit clock adjustment. Time expiry is visible and does not automatically declare a winner; a verified on-time sighting can correct an apparent expiry. Each recording has an atomic clock checkpoint restored paused, plus SGF TM/OT and available BL/WL/OB/OW values. Undo restores the last clock press. Old untimed recordings can attach clocks from their current paused position.

Score game pauses clock/recording and uses the shared SGF Player KataGo engine, bundled model/config, ownership interpretation and local scoring arithmetic. During play it returns an estimate. After End game/two passes it proposes dead groups and neutral regions with a territory/prisoner/living-stone/komi/handicap breakdown. Players can correct groups or neutral areas before explicitly saving RE in SGF; a score.json report records the agreed review. AI ownership is a proposal, not automatic adjudication of seki or disputed life/death. Missing komi must be supplied in Info. Scoring runs locally without OGS login; this macOS build uses the installed KataGo executable, with the transport isolated for a later iOS adaptation.

Verification includes deterministic clock boundaries, timer frequency invariance, pause/recovery, late confirmation, handicap/recognition/pass/undo, persisted clocks and SGF; real KataGo estimate/final-score requests, dead-group correction and explicit SGF/result saving; and the existing recording, timing, handicap and AI engine regression tests.

Background scoring is power-aware: while externally powered, continuous KataGo analysis follows the latest confirmed local position and supplies a warm estimate to Score game. The power adapter is polled once per second. Battery or unknown power stops the background process; explicitly requested scoring remains available and stops its worker on completion. Online mode, finished games, unresolved moves, and foreground scoring suspend background analysis. Info shows the current policy/status. Switching to online play cancels local scoring immediately, and app shutdown stops both workers. Captures are maintained by the deterministic Go rules engine and reconstructed from the saved history, independent of AI. Power detection and worker policy are isolated for testing and later device adapters.

### Stone-guided board recovery (0.83)
After local tracking loses alignment, recovery uses the committed local position or the OGS position mapped into camera coordinates. Distributed black/white disk contrast proposes translations up to three intersections from the previous grid; full-view rectangle search handles larger shifts. Printed-grid validation is still mandatory. Known landmarks rank candidate orientations, with at least four matches, 60% support, spatial spread and a margin over competing alignments. Missing/captured/new/nudged stones are tolerated as outliers; insufficient or ambiguous evidence pauses automatic play. The recorded position is never overwritten with a recognition guess.

A prominent recovery banner is visible with diagnostics hidden and clears when alignment is verified. Failed full-grid verification asks for all four corners and outer rails, and provides a retry button; online users are reminded that the server clock continues. An enabled-by-default spoken repositioning prompt uses the clock voice/volume settings, once per episode with a 30-second cooldown against flicker. Info → Camera recovery controls speech independently. Bump regressions include larger translation, orientation identity, stale/new landmarks, wrong colors, cropped/missing boards and speech suppression.

### Lighting compensation and recovery (0.84)
Recognition can adjust comparison pixels for smooth brightness changes across the board. A robust exposure plane is fitted to wood between intersections, with bounded gain, residual limits and agreement in all four regions. The independent current-view classifier must also agree; the original camera image and empty reference are preserved. Existing local color, shadow and line-coverage checks remain in use. This compensates brightness, not arbitrary color-temperature changes or clipped glare; unresolved views are withheld rather than relabeled from game history.

Grid tracking compares printed-line profiles independently of brightness, retaining absolute contrast, shape, border and quadrant checks. Gross darkness or clipping is treated as lighting failure before attempting camera reacquisition. Unreadable lighting immediately blocks automatic recording/sending and shows a banner outside Diagnostics. Recovery requires at least three fresh readable frames spanning 0.6 seconds, with gaps resetting that window. After three seconds of failure, default-on speech requests even lighting and less glare, once per episode with a 30-second cooldown. Info → Camera recovery controls speech and the clock's voice/volume are reused. Stones may stay in place. Manually paused games remain paused. Local clocks follow the existing “pause on interruption” preference; online clocks continue on the server.

Diagnostic frame records include the adjustment flag, fitted gain field/residual, blocked status, and recovery transitions. `--lighting-test` checks saved photos under uniform dimming, brightening and two spatial gradients, extreme exposure, tracking and speech/recovery timing. `--recovery-ui-test` exercises lights-out and restoration through the native frame pipeline, preserves the saved game/reference, and renders the lighting banner. `--test` and `--bump-test` cover existing recognition and motion regressions. Synthetic lighting transformations supplement saved photos; real room-light changes still need live validation.

### Clock review recovery (0.85)
When recovered move timing or a timeout requires review, both clock displays offer an enabled **Review & resume…** action instead of a disabled Resume button. The review accepts unchanged times if both players agree, or corrected times/overtime allowances. **Confirm times & resume** clears the review flag and resumes recording through normal physical-board verification; the clock cannot start on an unreadable view. Cancel leaves play paused. Adjust clocks remains available as a save-only action. Later moves retain the original timing-review reason and restored checkpoints explicitly direct the user to review. `--clock-review-test` covers the review lifecycle, unchanged/invalid values, verification gates, persistence, and native action/sheet rendering, plus the full deterministic clock suite.

### Unique off-center placements (0.86)
A strong stone outline can establish an unambiguous intersection without satisfying the old 0.24-cell centering limit. The intended point must lie inside the outline shrunk by 0.08 grid spacings, and every neighboring playable point outside the outline expanded by 0.08. Both appearance and outline scores must be at least 0.94, and fitted radii must be within the supported stone-size range. Raw measured displacement remains available in diagnostics; only assignment uncertainty is cleared. Conflicting outlines still use the most conservative result, and existing temporal confirmation remains mandatory. Unsupported geometry, boundary ambiguity, and missing outlines cannot clear a prior concern.

The move banner now distinguishes placement review from ordinary pending confirmation. `--unique-placement-test` exercises both colors, axes, diagonals, boundary/quality/size/conflicting-outline rejection, the actual stalled move-20 photo/sequence, and its persisted pending checkpoint. The historical sequence now accepts the white move 2.34 seconds after its first white sighting, with all 19 previous moves unchanged. This is a saved-data replay result, not a live latency guarantee. Older photographed ambiguous placements remain held where the geometric margin is insufficient. The old displacement-only chronology replay uses explicitly ambiguous synthetic outlines to continue testing preservation of all 53 intended moves; those outlines are not claimed to be measurements from the archived photos.

### Saved-observation order recovery (0.98)

Unresolved pure-placement sections now trigger a bounded background replay of
saved observations, including sightings logged while recording was paused.
Recovery uses per-intersection empty-to-stone intervals, alternating turns, full
Go legality and an exact match with the frozen final position. An earlier false
stone sighting followed by sustained empty readings does not establish order.
A lighting-blocked frame can extend a locally consistent run only if that run
also contains an unblocked matching reading; three sightings spanning at least
0.4 seconds are required. Global lighting trouble no longer discards all local
chronology. Runs separated by more than 1.5 seconds cannot be joined.

A unique legal order is retained automatically in the review journal, with
provenance and interval evidence in the observation log. It does not change the
live clock or manufacture historical clock presses. Ambiguous orders are offered
in the review window; unsupported captures, missing history and excessive search
remain manual reviews. An open review draft is protected from background changes.
Saving a review explicitly offers **Keep paused** or **Resume clock and recording**.

`python3 PhysicalGo/build.py --order-recovery-test` includes a compact 22-move
historical regression, lighting interruptions, early false positives, ambiguity
and missing evidence. `PHYSICAL_GO_ORDER_FIXTURE=/path/to/game.sgf` additionally
validates recovery of the original 41-to-63-move recording on a temporary copy,
including legal replay, exact final position, clock preservation and restart.

### Resume with bright bare wood (0.99)

Brightness against an older empty-board reference can resemble a white stone
when room lighting changes. A white candidate without an independently fitted
stone outline is now withheld when at least 75% of its sampled body still has
the reference wood's hue and saturation. This produces an uncertain reading,
not a fabricated empty label. Existing history can tolerate a small number of
uncertain empty points while verifying the unchanged board. Real outlined stones
and white stones that lose the wood tint keep their existing recognition paths.

The main turn indicator and pass label no longer advance on an unconfirmed
candidate; the separate pending-move text describes the ongoing check.

`Tests/Fixtures/ResumeGlare/v1` retains four photos from the actual false-white
incident, including the borderline frame, with checksums and label provenance.
Run `python3 PhysicalGo/Tests/resume_glare.py --engine /path/to/ConfidenceReplay`.
The `--review-queue-test` runner also accepts `PHYSICAL_GO_RESUME_REPLAY` (native
replay JSON) and `PHYSICAL_GO_RESUME_GAME` (saved SGF with its checkpoints) to
exercise the entire resume path on temporary copies: no false moves/reviews,
correct turn, successful board synchronization and the correct running clock.

### Quiet confirmation and continuous catch-up clocks (0.100)

The warning monitor allows five seconds for an untracked stone and ten seconds
for a stone already retained in one legal sequence. This avoids a failure sound
immediately before ordinary confirmation. Persistent stalls still warn, and
illegal moves retain their separate conflict warning.

When multiple legal moves are confirmed together, live timing continues on the
confirmed next player. Accrued clock totals are retained; missing clock presses,
increments and overtime resets are not invented. The clock checkpoint advances
to the confirmed move number so the next ordinary move does not reopen a review
gate. A timing note remains available under Earlier clock timing. Explicit clock
corrections and real timeouts still require review. The transport button now
prioritizes Review & resume consistently in its text, icon, accessibility label
and action whenever that review is required.

`python3 PhysicalGo/build.py --clock-feedback-test` covers warning timing,
catch-up, duplicate delivery, the subsequent ordinary move, persistence, manual
pauses, timeouts and the mixed recording/clock-review UI state, together with the
existing local-clock and recording-warning suites.


### 0.101 — live wood evidence and actionable recognition failures

Both visible grid rails plus independently sampled live wood can reject a false
stone even when the saved reference has different glare or exposure. The check
also samples the proposed body of a displaced stone, so exposed lines beside it
do not erase that stone. Wood-colored unbounded dark/bright candidates remain
uncertain. Strong black evidence can survive a variable reference-lighting
estimate when the independent live classifier agrees and both rails are covered.
No game-history labels are used to train or rewrite camera classifications.

Recording warnings now explain the current failure, state whether the clock is
running, and offer Pause and inspect board to stop timing/recording and reveal
both views. Changing noisy candidates share a 30-second reminder interval; each
alert sounds once. Sustained broad unreadability follows the existing camera
interruption clock preference after 10 seconds, with automatic recovery only
when the view becomes verifiable. Manual pauses and unresolved-order workflows
retain their separate behavior.

`--clock-feedback-test` includes short/sustained obstruction, clock preference,
manual pause, recovery, and alarm-storm checks. `Tests/live_wood.py --engine …`
checks visually labeled photographs in `Fixtures/LiveWood/v1`; the immutable
449-label historical comparison improved from 394 correct / 55 uncertain /
0 wrong to 425 / 24 / 0. These selected regressions do not estimate overall
live-game accuracy. The incident's archived photos replayed four successive
moves in order, retaining the fifth pending a fresh view.

## Correcting a saved intersection (0.128)

In **Board interpretation → Saved moves**, enter a move number, then choose
**Correct move…**. Drag the marked stone, click its actual intersection, or enter
its displayed coordinate. The preview replays the entire sequence with the Go
rules engine. An illegal continuation blocks saving; explicitly disabling
**Keep later moves** sets that suffix aside in the original recording.
**Save corrected copy** preserves the original game and opens a new recording.
Clocks stay paused, measured balances are preserved, and pending reviews are
rechecked against the corrected position. Truncating history requires clock
review. A correction to this local recorder does not rewrite an online server's
move history.

The move55 test incident is retained in `Tests/Fixtures/Move55Correction`.
White N18 (SGF rm) was reported as actually played at N17 (qm). The observation
journal shows N17 remaining uncertain, then N18 becoming White after Black M18
appeared. Moves55–56 were accepted together. No identity remapping was logged.
Diagnostic frame capture hit its storage limit, so the exact visual cause cannot
be established from this incident. A proposed blanket hold for unreadable
neighbors also blocked a verified edge-board regression and was not retained.
Candidate-neighbor confidence and assignment offsets are now journaled so a
future visual diagnosis can distinguish glare, geometry and classification errors.

The playback journal records completed generic pause/resume phrases, interrupted
board-clear phrases, and no location-specific warning about N17/N18. New
unresolved reviews now trigger their own spoken notice, independently of whether
the clock was already paused. Recovery speech follows the recovery-speech setting;
optional warning tones follow All feedback. Fresh frames containing a hand now
maintain camera continuity without contributing move-confirmation evidence.
Ordinary hand placements no longer produce board-recovery chatter. Actual camera
gaps still invalidate verification and follow the interruption policy.

Regression command: `python3 PhysicalGo/build.py --historical-correction-test`
(from the repository root). This covers the actual 62-move record, preservation of
Review3 and clock balances, restart, provenance, illegal suffixes, explicit
truncation, stale previews, hand/camera continuity, write failures,
review notices, and a native editor render.

## Rotating evidence and review-board corrections (0.129)

Automatic move clips and continuous camera diagnostics share a 10 GB archive
budget. Before a new capture starts, the oldest inactive, unpinned diagnostic
folders are removed until the capture has room. Space is reserved for the whole
bounded automatic clip, rather than starting with only a few megabytes left.
Writer locks protect active captures across app processes; interrupted captures
become eligible after their writer exits. Recordings, correction photographs,
regression fixtures and unknown folders are outside deletion eligibility.

**Keep this capture — exclude from rotation** pins the latest capture. A `KEEP`
file inside any older diagnostic folder has the same effect. If active or pinned
captures occupy the budget, collection reports the blocked state instead of
deleting protected evidence. Continuous captures still stop at their selected
maximum (up to 10 GB) or when the app closes. The 10 GB allowance is shared, not
an additional allocation for each capture mode.

A review board displays the interpretation saved when the review began; it can
therefore still show a wrong detection after an earlier saved move is corrected.
Drag that detection to its actual intersection to open a correction preview.
**Use corrected interpretation** changes only that review snapshot, retains its
original camera interpretation, and reopens affected later sections for review.
It does not apply persistent camera overrides, infer move order or restart clocks.
If the source stone is still at the wrong location in accepted history, the drag
opens the saved-move correction editor instead; saving that corrected copy also
updates the selected review snapshot. Every review also offers **Correct saved
move…** with a move-number field. Canceling a preview keeps existing selections.

`python3 PhysicalGo/build.py --archive-review-test --move-capture-test --diagnostic-test --historical-correction-test --review-queue-test` exercises rotation and real
frame capture, active/pinned protection, the actual move55/Review3 scenario,
stale edits, retained original evidence, unchanged clocks, persistence and native
review rendering.

## Specific recovery speech (0.130)

Spoken guidance identifies incomplete captures, possible displaced stones,
missing stones, color disagreements, new additions, mixed changes, unreadable
lighting, lost camera alignment, uncertain turns and clock/save problems.
Locations use the interpretation board's current orientation, with at most three
coordinates per announcement. A possible bump asks the player to check the stone;
it does not instruct them to relocate it based on an uncertain reading. Capture
guidance names remaining captured intersections and the appropriate verification
or **Confirm capture** step, rather than requesting move order.

Recovery speech finishes an audible sentence when clocks restart or the view
recovers. Important instructions precede queued acknowledgements. Repeated
requests replace only the queued update for that topic, and queued recorder
guidance is refreshed before playback so resolved problems and old coordinates
do not produce stale instructions. A clock restart does not discard an unresolved
review warning. Stopping/freezing the camera drops queued guidance while an
audible sentence finishes. Explicit mute still stops speech immediately.
Speech events record natural completion, deliberate stopping and obsolete queued
prompts; they cannot prove that external speakers were audible.

`--recovery-guidance-test` exercises actual capture/review fixtures, rotated
coordinates, warning priority, changing/obsolete guidance, the model's clock
restart callback, explicit mute and natural completion using muted real audio.

## Quiet ordinary play (0.131)

“Board view clear” now closes a camera/lighting warning that actually started
playing during the same interruption. Duration alone never triggers it, so an
ordinary hand placement stays silent even when the hand detector misses it.
Playback counters prevent an old warning from causing acknowledgements on later
moves. Fresh stable views, explicit mute and clock-resume deduplication still
apply. `--obstruction-feedback-test` covers repeated short/long silent episodes,
heard versus queued warnings, old warnings, camera gaps and recovery acknowledgements.

An audit of the 50-move test game on November 9 found that moves 1–40 used the
retained hand-clear boundary exactly in their clock checkpoints. Recognition
delay had a median of 0.584 seconds (range 0.131–1.052), and the saved balances
matched charging the opponent from that boundary. Moves 41–42 and 44–50 were
batch confirmations without reconstructed individual presses; move 43's earlier
candidate preceded the new clock baseline and was not backdated. These later
times should not be treated as independently verified per-player timings.

Recognition delay is not measurement error. Eight hand-to-delivered transitions
in the saved difficult-sequence clips span 0.231–0.467 seconds, conditional on
correct hand classification. Motion interpolation can refine a crossing estimate
within a frame interval; its uncertainty must come from tracking residuals,
motion changes and camera timing. The current detector discards joint trajectories,
stored images sample at most twice per second, and timestamps measure camera
callback arrival rather than exposure time. No sub-frame accuracy or physical
hand-exit error bar has been validated by this audit, and no clock values were
changed. Catch-up timing and higher-rate trajectory measurement remain separate
follow-up work.

## Hand-motion clock timing (0.132)

Camera presentation timestamps are converted from the capture session clock to
host uptime when available, retaining callback arrival and an explicit fallback
source. Two or three reliable single-hand poses now fit common joint trajectories
to the edge of the playing area. The last predicted joint exit refines the
hand-clear boundary only within the observed obstructed-to-clear interval.
Residuals, acceleration and a joint/outline allowance produce an estimated error;
weak, discontinuous, multiple-hand or nonlinear tracks keep the first clear frame
and the wider observed interval. These are engineering error estimates, not yet
calibrated physical accuracy or statistical confidence intervals. The clock panel
can disclose the latest press's method and uncertainty without adding audio to
ordinary moves.

A bounded clear-view history survives hand re-entry, retaining each intermediate
board and press for recognition catch-up. Unexplained camera gaps, calibration
changes and pauses reset the epoch; a definite stone withdrawal invalidates its
earlier placement boundary. Complete chronological sequences replay each press
through the clock engine, including increments and overtime, and charge subsequent
thinking time to the correct opponent. Missing or invalid times are retained as
unapplied evidence without invented bonuses. Manual pauses stay paused; ambiguous
expiry requires clock review. Deferred live presses keep their estimates through
review finalization. Clock sidecars and observation journals preserve the estimates
and observed bounds; restarting never reapplies old uptime-based presses.

The separate [Hand Timing Lab](Tools/HandTimingLab/README.md) records short,
high-rate JPEG sequences, timestamps and drop records for independent frame labels
and offline replay. Its executable and capture UI are excluded from release
builds. Native-rate labels are the next validation step; synthetic timing and clock
tests verify behavior but do not establish real hand-clear accuracy.

Validation for this build: hand-motion, hand-clock, capture-clock, clock-review,
clock-feedback and lab-writer suites pass, along with the build registry. The
native lab camera smoke check saved 294 1920×1080 frames from Dave11 Camera in
9.93 seconds (29.5 fps), all with camera presentation timestamps. Median frame
spacing was 33.33 ms; the widest interval was 150 ms, so actual timestamps remain
essential. Replaying that unobstructed baseline detected no hands and emitted no
presses. It contains no scripted withdrawals or independent accuracy labels.

The first withdrawal validation on November 9 saved 596 frames over 19.90 s
(session `69B81321-7DD6-4C98-9DFA-2039C19286B8`). Visual labels were made before
estimator replay: frames 330–331, 405–407 (blur requires a wider interval), and
556–557. All three withdrawals fell back to detector-frame timing at native rate
and in 5/10 fps phase replays; none validated the motion fit. At native rate the
first two estimates preceded visible clearance by 33–67 ms and 67–133 ms, and
the third by 0–33 ms. Across six fixed 5 fps phases the signed error envelope was
−133 to +167 ms. These are three independent withdrawals, not 39 independent
trials, and the visual intervals have frame/blur and boundary-definition uncertainty.

The pose detector loses fingertips while they remain visibly above the board;
an empty pose result is therefore not proof of physical clearance. Joint identities
also become unstable near exit. The observed bracket is conditional on correct
classification and must not be advertised as a guaranteed physical bound. Further
work should retain visual hand-edge tracking through pose loss and independently
verify clearance before trusting narrower error estimates. The lab scoring was
corrected to retain early/late failures and keep sampling phases on a fixed
timeline. Raw captures, independent labels, replay outputs and the CSV summary
remain together in the lab capture folder. The test did not run or alter clocks.

## Visual hand-exit tracking (0.133)

A hand pose now seeds a visual foreground tracker rather than acting as the sole
clearance signal. The tracker learns the observed hand's appearance relative to
a recent clear board image; it does not use a fixed skin-color range. References
lag entry by at least half a second so delayed pose recognition cannot immediately
teach the hand itself as background. Connected regions retain their boundary
pixels but must have a solid core, reducing confusion with thin shadows/grid
artifacts and detached stones. The tracked trailing edge continues through joint
loss. Two visually clear observations confirm an exit; the estimate retains the
original crossing/first-clear interval rather than charging confirmation delay.

Reliable withdrawal samples estimate the boundary crossing. When acceleration
or sparse frames do not support interpolation, the midpoint of the observed visual
interval is retained with a wider error estimate. Timing includes outline/blur
allowances, not just fit residuals. Pose failures, multiple hands, camera gaps,
invalid imagery, revision changes and timestamp-source changes cannot manufacture
an interpolated exit. Clock expiry review now considers the model error band as
well as the sampled interval. Existing per-move catch-up/checkpoint behavior remains.

Replay of session `69B81321-7DD6-4C98-9DFA-2039C19286B8` against the unchanged
independent visual labels found:

| Sampling | Mean absolute offset from labeled interval midpoint, before → after | Largest absolute offset, before → after | Accepted motion estimates |
|---|---|---|---|
| 5 fps, six phases | 59 → 31 ms | 150 → 83 ms | 8 of 18 |
| 10 fps, six phases | 41 → 18 ms | 100 → 36 ms | 12 of 18 |
| Native ~30 fps | 56 → 12 ms | 100 → 29 ms | 3 of 3 |

All new error bands overlap the manual intervals; at 5 and 10 fps they contain
the entire intervals. The native run contains two entire intervals and overlaps
the third. These are three independent withdrawals replayed at several phases,
not 39 independent trials. They were used while developing the change, and the
interval midpoints are approximations, not exact ground truth. More varied held-out
motions/cameras/lighting are needed to establish general accuracy. Production
board analysis remains at 5 fps; high-rate capture remains a separate lab tool.

`--hand-outline-test` covers all four edges, pose loss, confirmation delay,
clock-press uncertainty, source/camera gaps and the recorded fixtures. Clock,
capture and obstruction-feedback suites exercise integration. The capture's
`outline-evaluation.json` retains detailed tracking decisions; the local analysis
folder `Captures/Analyses/Hand outline 2026-11-09` contains the CSV, summary and plot.

## Capture continuity and clock-aware processing (0.134)

A clear, confident glimpse of a legal qualifying capture now survives fresh
hand-covered frames during prisoner removal. Those covered frames prove camera
continuity only; they never confirm a placement. Later intermediate views or the
fully removed target can confirm the same move, and the clock pause is backdated
to the earliest retained clear observation. Final verification retains its first
clear timestamp, so verification delay is charged to the next player. A provisional
timeout can be rewound only when the uninterrupted turn proves the capture was
seen before expiry. A capture first seen after expiry cannot revive a clock.

Conflicting/uncertain clear views, camera interruption, explicit pause, and an
age limit of 120 seconds invalidate tentative capture evidence. Hand re-entry
also resets final-clear verification, but no longer erases the original placement.
There is no inference of an exact placement time for a move hidden throughout
removal. Established automatic capture holds still keep both clocks stopped
until the complete target is verified, and announce the actual resumption.

Camera processing targets 5 fps normally and 10 fps in the last five seconds of
the active local clock period. This includes main time, every Japanese byoyomi
period, Canadian overtime blocks, Fischer/absolute time and per-move limits.
Paused, expired and untimed clocks use the normal rate. The policy projects an
immutable clock snapshot to the current time and follows the active player after
a move. Sampling uses fixed deadlines rather than accumulating camera jitter;
missed slots are dropped. Camera-to-UI delivery is bounded to one pending frame,
and the existing analysis-busy guard prevents queued vision work. Actual achieved
analysis rate remains dependent on the camera and processing load. Diagnostic
context includes the target processing rate. This policy is for local clocks;
online server clocks are not controlled by it.

`--adaptive-frame-rate-test` covers clock boundaries, player changes, pauses,
expiry, short periods, frame jitter, rate transitions and missed slots.
`--capture-clock-test` covers repeated hand entry, a single initial glimpse,
fully removed confirmation, reset conditions, expiry recovery and unchanged
0.4-second capture / 0.8-second final-verification durations at 10 fps.

## Capture uncertainty outside the removal area (0.135)

A November 10 six-stone capture exposed a mismatch between tentative capture
recognition and final board verification. Intermittent uncertainty away from the
capture repeatedly discarded the tentative plan, so the move eventually saved
without a capture-removal pause. Both stages now use the same bounded verification
policy: the capturing stone and every prisoner intersection must be clear, while
limited uncertainty at unchanged points does not erase the legal position.
Definite extra, missing, moved or wrong-colored stones still reject the candidate.
Uncertainty in the capture itself and broad loss of the board also reject it.
Contradictions during an established hold prevent completion and keep clocks
stopped until fresh consistent views arrive.

Expected intermediate positions persisted for a pending hold use legal history
at unchanged intersections. Camera observations are never overwritten and no
persistent camera overrides are introduced. Reopening and manual-review handoff
continue to work when the initial observation included unrelated uncertainty.

`--capture-clock-test` includes `CaptureUncertaintyTests` and the 33 saved
classifications in `Tests/Fixtures/CaptureUncertainty`. The old implementation
fails the recorded replay because it never pauses. The regression checks the
pause boundary, excluded removal time, opponent verification time, exactly one
saved move and one completion announcement. Synthetic controls cover conflicts
before and after a hold, unclear capture points, low confidence, broad obstruction,
hand re-entry, uncertain final views, persistence and the manual-review escape.
The fixture documents the journal's timing/confidence limitations; it is a
recorder/clock replay, not a fresh image-recognition or interpolation benchmark.

## Specific capture-conflict guidance (0.136)

During an established capture-removal hold, a definite disagreement that remains
visible for at least two seconds and three fresh observations gets its own spoken
instruction. It names up to three intersections in the displayed orientation,
states that clocks remain paused, and asks the player to compare the physical and
interpretation boards before correcting anything. The status panel switches to
"Check board before resuming" instead of continuing to request prisoner removal.
Remaining prisoners in their original locations and unknown readings do not count
as conflicts. Speech evidence never changes the capture verification rules.

Each continuously visible conflict is announced once. Hand entry, uncertainty at
that point, camera interruption, manual pause or correction clears stale speech
evidence; another warning needs fresh sustained sightings. Unsaid queued warnings
are discarded when obsolete. An audible sentence finishes naturally, with the
capture-complete/clock-resume announcement queued after it. Explicit mute still
stops speech. Ordinary recording warnings are suppressed while the specific
capture-conflict guidance applies.

`CaptureConflictGuidanceTests`, included in `--capture-clock-test`, exercises the
real recorder/model callbacks with a controllable speech output. Coverage includes
extra/missing/moved/wrong-colored stones, timing at 10 fps, stale/repeated frames,
transient uncertainty, all board orientations, unchanged held clocks, no premature
move saving, screen instructions, deduplication, queued cancellation, hand re-entry,
natural warning completion, resume acknowledgement and mute.


### Capture removals split across reviews

A single legal capture can now be confirmed even when its prisoner removals were
saved as successive review sections. Either review opens the same live capture
check; one confirmation saves the capturing move and resolves removal-only
sections without adding moves for the prisoners. Original snapshots remain in
the audit history. Only a contiguous unresolved sequence of prisoner removals is
combined: extra/missing unrelated stones, moved stones, changed colors,
reappearing prisoners, broken continuity, and previously reviewed sections all
retain normal review requirements. Fresh camera verification is still required;
confirmation keeps clocks paused and queues the completion announcement for Resume.

`Tests/Fixtures/SplitCapture` preserves the actual two-section E5 capture from
2026-11-10. The physical-review regression checks both entry points, live conflicts,
single-move saving, clock preservation, restart, duplicate confirmation, and
conflicting later history. This is review recovery coverage, not a successful
live test of automatic capture timing. The live test runner also timed out while
reading a stale persisted clock snapshot before its start cue; future timing
runs must wait on current app/journal state instead of that sidecar alone.


### Routine recovery speech assets

The Kokoro asset generator includes the full capture-completion and restored-board
restart announcements for both Black and White. The live 0.137 test exposed that
only the shorter “Clocks resumed” messages had been cached: the combined capture
sentence hit the 1.5-second synthesis deadline and used the system voice. These
four exact messages now have bundled audio and are decoded/cache-checked by
`--voice-assets`. Uncommon messages retain the existing timely fallback.

Live 0.137 validation confirmed that the two-part E5 capture can be resolved by
one confirmation, preserving both snapshots and saving one move. Resume delivered
the complete announcement, then the test harness paused the clocks. Automatic
capture detection did not establish its hold in this run; the D5 placement warning
and camera interruption are retained for investigation. This is a successful live
recovery test, not evidence that automatic capture timing passed.


### Drag and batch-correct saved moves

The interpretation board and saved-position browser open a correction preview
when a saved stone is dragged. Move ownership comes from the position being
viewed, so an older stone is not confused with the latest move; captured stones
can be edited by browsing to a position where they were still present. The
preview stages multiple move locations, shows every edit, and replays the entire
sequence after applying the complete batch. Conflicting edits remain editable;
Save is disabled until the resulting game is legal. Original SGF timing
properties and clock balances remain intact. Confirmation creates a corrected
SGF copy and makes it the active game; the original stays available.

The displaced-stone review also accepts dragging on its saved interpretation,
with a coordinate-specific correction shortcut. It explains the distinction
between correcting a wrong recorded location and restoring an accidentally
bumped stone. When corrected history exactly explains an unresolved prefix of
observed changes, those reviews resolve with zero additional moves and keep their
original before/after evidence. Other board differences and later unresolved
chronology still require review. Resume verifies the corrected physical position.

`Tests/Fixtures/DisplacedMoveCorrection` preserves the demo where Black move 7
was saved at B16 and physically moved to intended C16. Batch regression coverage
includes this recovery, several older edits at once, temporarily conflicting
individual edits that become legal as a batch, capture recomputation, original
file preservation, clock invariance, restart, stale previews, and unrelated
board-change rejection.

In 0.142, **Clear diagnostic data…** asks for confirmation before deleting completed
camera archives and their contained logs. It preserves active writers, captures marked
KEEP, unrecognized files, saved games, game/clock history, calibration and photo samples.
Cleanup uses the same interprocess locks as rotation and runs off the UI thread.
Diagnostics settings remain unchanged, so enabled collection may create new clips.
“Save uncertain or delayed moves” means recognition difficulty: local uncertainty
lasting two seconds, recognition taking five seconds, an unrecorded-stones warning, or move-order review/recovery;
online detection also triggers below 0.90 confidence or at a 0.24-grid-spacing assignment
offset. This says nothing about the strategic quality of a move.

## Clock catch-up and shadow regression (0.143)

Fresh frames with unknown hand status now maintain camera continuity without
creating clock presses. This preserves earlier verified presses while the hand
detector reacquires the board. Genuine camera gaps and contradictory placements
still invalidate stale evidence. When a confirmed sequence lacks usable presses,
clocks stop for explicit time review instead of charging one player for several
turns without period resets or increments.

The outline tracker rejects a lighting-change component only when the pose detector
reports no hand and strong background texture correspondence survives throughout
it. Whole-component correlation, per-cell residuals and individual residuals protect
against small remaining fingers being hidden by a large background match. Two clear
views are still required, and the original first-clear timestamp is retained.

The recorded Black65–67 incident is replayed by `--hand-clock-test` and
`--hand-outline-test`, alongside older withdrawals, all four entry edges, hand-pose
loss, actual camera gaps, missing presses and synthetic fingertips within changing
light. This is regression evidence, not a guarantee of accuracy for every camera
and lighting condition.
