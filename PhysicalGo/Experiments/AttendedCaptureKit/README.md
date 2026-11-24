# Artifact-only capture operator kit

[Run card](RUN_CARD.md) describes controlled single/two-stone human captures and
the explicit fixture-loading gap. This experiment is based on `8c142a2`; it adds
no app code, fixture import, forced-AI hook or hardware operation.

Generate into a **new artifact folder**, outside Library/application support:

```sh
python3 PhysicalGo/Experiments/AttendedCaptureKit/generate.py /absolute/path/to/new-artifact-folder
```

The small Swift generator compiles the unchanged production Go engine and timing
type, validates every legal move and exact prisoner set, then writes two separate
`current.json` snapshots, reference SGFs and one manifest. It refuses existing
output directories. The manifest records source/fixture hashes and labels the
history synthetic. Neither snapshot contains a fabricated observed timestamp or
camera verification; both use Human Black before the capturing fifth move.

`ValidateController.swift` is an optional small client for an **existing** testable
app runtime. It copies snapshots into UUID temporary folders, uses real
`PhysicalAI` loading/recognition/clock paths with synthetic observations, and
injects an AI generator. It never loads live app data. It is deliberately not a
full-app build or fixture activation tool. Controller validation and artifact
checks are documented in `VALIDATION.md` after execution.

Authoritative code boundaries inspected:

- `Sources/PhysicalAI.swift`: `Snapshot`, `init(directory:)`, `resume`, `commit`.
- `Sources/ExperimentModel.swift`: constructs default `PhysicalAI()`.
- `Sources/PhysicalAIView.swift`: Resume and SGF export, no fixture/SGF import.
- `Sources/PhysicalAITiming.swift`: single-capture clock runs; default two-or-more
  cleanup hold is applied by the controller.
- `Tests/PhysicalCaptureControllerTests.swift`: analogous 9×9 capture scenarios.

The kit is reviewable and reversible because all output is isolated. The run card
requires a separately agreed attended loading transaction or isolated harness
before it can be used with the installed camera app. It does not claim that an
SGF export can be imported as an AI game.

## Loading boundary: pending attended decision

The installed AI panel has no SGF-import or fixture-picker UI. Its supported
restore path is `PhysicalAI(directory:)` reading `current.json` on initialization;
`ExperimentModel` currently constructs the default app-support directory. Opening
`reference.sgf` does not activate an AI fixture. A dedicated injected-directory
harness would require a separate attended integration decision; none is added.

Alternatively, an explicitly agreed attended stop/backup/restore transaction
could place a disposable fixture in the default AI directory. This kit provides
no activation script. Such a transaction must first preserve the **entire existing
AI directory and both known real-game checkpoints (five moves and three moves)**,
record checksums, ensure the app cannot write during replacement, and restore the
original before returning to the real game. No transaction has been performed.
Never overwrite a real checkpoint with a fixture. Merely placing stones on the
board cannot change which saved AI game is loaded.

Settings and zero clock balances are explicit synthetic test choices, not copied
user preferences. The first four moves are legal constructed history; no real
move receipt timestamps, capture timestamp, verified camera position or removal
ledger are asserted. The attended fifth move creates those records normally.
