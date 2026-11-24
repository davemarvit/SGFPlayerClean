# Local recording, review and scoring

November 24 retention review: all unique games, camera recordings and calibration
evidence were retained. Only three abandoned partial install backups were removed
after exact duplicate/prefix checks; `work/data-pruning-20261124` contains hashes,
retained origins and restoration metadata. Preserve KEEP-marked backups and useful
fault tails. Clone consolidation is not evidence of reclaimed disk space.
See [current status](../IntegrationChecklist.md) before further pruning.

[Start here](README.md) · [Current status](../IntegrationChecklist.md)

This page covers the local two-player recorder. AI practice and online play use
different controllers; see [GameAIClocks.md](GameAIClocks.md) before transferring
an acceptance or timing policy between modes.

## Recording and unresolved observations

[GameRecorder.swift](../../Sources/GameRecorder.swift) owns the accepted game,
recording state, reconciliation and clock coordination. Camera observations may
support a legal transition without proving every location or the order of a
sequence. Keep accepted history, tentative observation history and review work
separate.

| Need | Source entry point |
|---|---|
| Fresh evidence and tentative chronology | [LocalMoveEvidence.swift](../../Sources/LocalMoveEvidence.swift), [MoveObservationHistory.swift](../../Sources/MoveObservationHistory.swift), [CandidateMoveHistory.swift](../../Sources/CandidateMoveHistory.swift) |
| Deferred locations/order | [DeferredMoveHistory.swift](../../Sources/DeferredMoveHistory.swift), [DeferredStoneState.swift](../../Sources/DeferredStoneState.swift), [RetainedTurnPosition.swift](../../Sources/RetainedTurnPosition.swift) |
| One actionable issue per underlying problem | [LivePositionIssue.swift](../../Sources/LivePositionIssue.swift), [LiveIssueReviewView.swift](../../Sources/LiveIssueReviewView.swift) |
| Review persistence and interrupted commits | [ReviewHistoryCoordinator.swift](../../Sources/ReviewHistoryCoordinator.swift), [RecordingStore.swift](../../Sources/RecordingStore.swift) |
| Explicit correction and undo | [HistoricalMoveCorrection.swift](../../Sources/HistoricalMoveCorrection.swift), [ManualBoardCorrections.swift](../../Sources/ManualBoardCorrections.swift), [PhysicalUndoController.swift](../../Sources/PhysicalUndoController.swift) |

`LivePositionIssue` separates the issue, actionable marker, evidence source and
clock hold. A discrepancy or an action does not itself imply a timing pause.
More specific explanations claim overlapping points first, so one capture or
sequence does not become several contradictory instructions.

Review restoration checks accepted SGF signatures. If an SGF write completed
before the review sidecar recorded its commit, the coordinator matches the entire
resolved suffix before recognizing the interrupted commit; it must not append the
same moves twice. Unknown order is not a pass or a known move. Resolving a stone's
location later does not authorize changing its already recorded turn time.

The numbered cases, intended reconciliation behavior and acceptance criteria are
maintained in [LivePositionIssues.md](../LivePositionIssues.md). Read the specific
case and latest follow-up before generalizing from an older incident.

## Scoring is an explicit agreement

[PhysicalScoring.swift](../../Sources/PhysicalScoring.swift) reuses KataGo transport,
ownership interpretation and shared [LocalScoring.swift](../../../SGFPlayerClean/Models/LocalScoring.swift)
rules. Opening scoring pauses the recorder and local clock. Analysis snapshots
do not change recorded moves or automatically declare a result.

The workflow distinguishes a forecast, a countable territory proposal, user
corrections and an agreed final result. `canAccept` requires final review, available
completed analysis, required approvals and a countable result. Required approvals
cover dead groups, territory and neutral points, plus prisoner totals when the
selected rule uses territory scoring. See
[PhysicalScoreApprovals.swift](../../Sources/PhysicalScoreApprovals.swift),
[PhysicalScoreBoard.swift](../../Sources/PhysicalScoreBoard.swift) and
[PhysicalScoringView.swift](../../Sources/PhysicalScoringView.swift).

Continuous ownership shading is a forecast, not a calibrated probability or
automatic ownership decision. Do not substitute its visual confidence scale for
the conservative counting/approval path.

## Background and whole-game analysis

[PhysicalBackgroundAnalysis.swift](../../Sources/PhysicalBackgroundAnalysis.swift)
coordinates cached analysis and worker use. [PhysicalGameReview.swift](../../Sources/PhysicalGameReview.swift)
performs a bounded cancellable history sweep, rejects stale/insufficient results
and reports actual coverage. It does not seek or edit the recorder. Graphs may
have gaps where analysis is absent; incomplete coverage must not be presented as
a fully analyzed game.

Start with the targeted review, live-position, clock and scoring suites listed in
[test_suites.py](../../scripts/test_suites.py). Use a saved incident fixture when
the problem concerns retained chronology or an interrupted commit. A UI rendering
test alone does not establish preservation of history or clock balances.
