# Game decisions, AI, clocks and saved state

[Start here](README.md) · [Current status](../IntegrationChecklist.md)

Local recording, AI practice and online play share vision and Go models but have
different acceptance, timing and persistence owners. Check the selected play mode
before changing a clock, save or recovery policy.

## Mode boundaries

| Mode | Owner | Timing and authority |
|---|---|---|
| Local two-player recording | [GameRecorder.swift](../../Sources/GameRecorder.swift) | [LocalGameClock.swift](../../Sources/LocalGameClock.swift) coordinates pure [LocalClockEngine.swift](../../Sources/LocalClockEngine.swift) arithmetic, capture pauses and review. Supports several configured clock types. |
| AI practice | [PhysicalAI.swift](../../Sources/PhysicalAI.swift) | [PhysicalAITiming.swift](../../Sources/PhysicalAITiming.swift) measures elapsed practice time. It does not adjudicate time loss. |
| Online physical board | [PhysicalOnlineBoard.swift](../../Sources/PhysicalOnlineBoard.swift) | SGF Player/OGS retains server state and clock authority. Physical cleanup policy must not rewrite server clocks. |

Local uncertain chronology and review are handled by
[MoveObservationHistory.swift](../../Sources/MoveObservationHistory.swift),
[LocalMoveEvidence.swift](../../Sources/LocalMoveEvidence.swift),
[DeferredMoveHistory.swift](../../Sources/DeferredMoveHistory.swift) and
[ReviewHistoryCoordinator.swift](../../Sources/ReviewHistoryCoordinator.swift).
Do not replace their evidence with whichever frame arrived last or recompute
recorded turn times simply because a stone's location is resolved later.

## Online opponent indication intent

`PhysicalOnlineBoard.guidanceTarget(atUnix:)` exposes a proven single opponent
transition through `PhysicalOnlineGuidance`. It has no live pointer consumer.
The online camera/frame and confirmed-dark gates still require integration before
laser play; server clock authority is unchanged. See [producer lifecycle and
remaining integration](../OnlineGuidanceProducer.md). Operation generation is
local and must not be presented as the server's move count.

## AI lifecycle and fast testing

`PhysicalAI` phases are idle, checking, human, thinking, placing, paused, finished
and failed. An AI answer is checked and committed to legal history before the
human physically mirrors it. `pendingPlacement` records that physical work;
`referenceCells` preserves the pre-placement recognition reference.

Fast test mode uses eight visits, no HumanSL and a retained warm KataGo worker.
It preserves normal strength/rank settings and changes thinking time, not camera
clearance or move confirmation. Mode changes are allowed before a game or while
paused/finished/failed. Installed [idle reuse](../FastTestIdleReuse.md) retains only
completed idle test workers across ordinary pause/resume, with cancellation and
asset revalidation guards. Active work, faults and shutdown invalidate the worker.
First-use latency includes startup; report cold and warm timings separately.

Sources: [PhysicalAI.swift](../../Sources/PhysicalAI.swift) (`TestWorker`,
`setFastTestMode`, `kataMove`), [KataGoEngine.swift](../../../SGFPlayerClean/Services/KataGoEngine.swift)
and [AIModels.swift](../../../SGFPlayerClean/Models/AIModels.swift).

## AI play presentation

[PhysicalAIClockView.swift](../../Sources/PhysicalAIClockView.swift) displays the
same large two-clock layout used by local play, with You/KataGo labels and
Pause/Resume. Values and running-side emphasis read `PhysicalAITiming`; viewing,
resizing, switching sides or opening the large clock cannot change time or turn
ownership. `PhysicalAIMoveClick` supplies the separate AI first-light sound
preference; its test button only plays audio, and warning/clock-volume settings
do not override it. These controls are installed in 0.260; see
[AI clock layout](../AIPlayClockLayout.md) for offline and first-launch evidence.
Actual AirPod Pro 3 audibility remains to be checked with Dave present.

## Clock events in AI practice

- Accepting a human move or receiving/committing the AI answer changes the side
  to play. AI decision receipt time is recorded before pointing begins.
- Laser dispatch, first visible light, final optical refinement, hand entry and
  a thermal acknowledgement do not switch clock ownership.
- A current scoped hard guidance fault pauses the game and clock. 0.260 also
  pauses on invalid/overlong transitions and unrecoverable own-game link loss.
  Classified transient camera/lease recovery remains separate; neither a new
  heartbeat nor a hardware recovery automatically resumes a paused game.
- Captures of two or more stones pause elapsed practice time until the played
  stone and complete capture cleanup are physically verified. A single-stone
  capture keeps the clock running under the accepted AI-practice policy.
- Partial removal, uncertainty or a dark receipt cannot finish cleanup. Pause
  freezes elapsed time; restart restores accumulated time without charging app
  downtime.

The capture-indication ledger covers all legal captures, including single stones.
It is separate from the threshold for a clock pause. See [Markers](Markers.md).

## Rules and illegal input

[SGFPlayerEngine.moveRejection](../../../SGFPlayerClean/Models/SGFPlayerEngine.swift)
distinguishes occupied/outside, suicide, ko and superko. It uses
`GoRulePolicy` in [OGSModels.swift](../../../SGFPlayerClean/Models/OGSModels.swift).
Recorded/server-confirmed history remains replayable; legality checks apply to
new input. Do not rewrite history to make a current camera observation legal.

At this guide's code review, Physical AI settings expose Japanese and Chinese.
The current local policy maps those names to simple ko and no self-capture;
Chinese-OGS/Chinese-KGS map to positional superko. This describes the code, not a
claim that all events using the word “Chinese” have identical rules. Consult the
actual active settings/overrides before presenting an illegal-move explanation.

`PhysicalMoveInference` in [PhysicalOnlineBoard.swift](../../Sources/PhysicalOnlineBoard.swift)
infers one added stone with optional partial capture removal; it rejects
no-liberty placements before returning a candidate. Therefore a physical suicide
used to become a generic mismatch before the AI controller reached its specific
legality message. The separate installed `PhysicalIllegalMoveWarning` diagnostic
now evaluates stable qualified illegal additions without broadening legal move
acceptance. It supplies screen reasons/removal/restoration marks only. A distinct
illegal-move laser pattern is still a proposal; ambiguous vision is not illegality.

## Persistence and recovery

| Data | Location/owner |
|---|---|
| AI snapshot | `~/Library/Application Support/Physical Go/AI Games/current.json`; authoritative `PhysicalAI.Snapshot`. The UUID SGF is a derived export. |
| AI recognition trace | `AI Games/recognition-trace.json`; diagnostic, not legal history. |
| Local recordings | `~/Library/Application Support/Physical Go/Recordings/`; SGF and matching clock/review/pending sidecars. |
| Last local session | Explicit `PhysicalGo.lastLocalGame` preference via [LastLocalGame.swift](../../Sources/LastLocalGame.swift), not “newest SGF”. |
| Online bridge | `~/Library/Application Support/Physical Go/Online Bridge/`; `state.json`, `move.json`, timing/decision diagnostics. |

[RecordingStore.swift](../../Sources/RecordingStore.swift) validates sidecars
against the accepted SGF signature. A failed sidecar load blocks writes to
preserve the originals. [RecordingStorage.swift](../../Sources/RecordingStorage.swift)
orders background writes and stops dependent writes on failure. Ordinary atomic
file replacement is not a multi-file crash transaction.

AI saves predating capture-indication context do not gain prisoner markers from
stale history. When the real board is cleared, preserve the old game and clocks
and explicitly establish the intended new or restored game.

## Reversible practice positions

Introduced in 0.258 and retained in 0.260, four paused fast-mode positions use
[PhysicalAIPracticePosition.swift](../../Sources/PhysicalAIPracticePosition.swift)
and the ordinary AI Setup/Play controls. The loader stores an immutable original
snapshot backup, writes the new SGF before atomically replacing current.json, and
preserves fault requirements. Return checks identity, original bytes/hash and
current-file authority. Load/return stop retained workers and clear observations;
Resume still requires fresh physical-board verification. See
[practice controls and persistence](../PracticeTestPositions.md) and
[the current test plan](../NextPhysicalTestPlan.md). Test via
`--practice-positions-test`; saved practice context also affects rollback.

Fast-test worker reuse retains only completed idle work across ordinary pause;
active requests, faults and shutdown invalidate it. The combined recovery test
requires fresh post-human-move board evidence before expecting the next AI search.
Screen illegal feedback is diagnostic only and cannot change accepted history,
clocks or laser targets; exercise `--ai-illegal-move-test`.
