# Initial calibration progress display

The setup and play panels include passive progress for the externally operated
initial laser calibration. It appears when the calibration runner publishes a
status file; there is no new hardware command, Start button or binding authority
in the display.

The panel shows the current stage and target, elapsed time, time in that stage,
and actual completed point checks. Full calibration has **5 calibration targets
and 9 independent accuracy targets**; repeated K10 entries are separate checks.
The bar measures completed checks, not elapsed-time fraction. Individual targets
can need different numbers of optical corrections, and no complete measured run
currently supports a useful remaining-time estimate, so the UI does not invent
an ETA. An initial spot-only check has no full-board progress bar.

Successful measurement and fitting displays “Measurements complete — setup
review still required.” It never means the map was activated. Stop, unconfirmed
shutdown, and missing/stale updates have distinct messages. A stopped publisher
cannot leave an animated apparent success: running status expires after three
seconds. Terminal results retain their last-update date. Progress does not prove
the current hardware state, and none of this display data enters the safety or
game-state admission logic.

## Display-only contract

The runner's worker atomically publishes
`~/Library/Application Support/Physical Go/LaserBridge/calibration-progress.json`.
Schema version 1 fields:

| Fields | Meaning |
|---|---|
| `runID`, `sequence` | Unique run and increasing publication sequence. |
| `startedAtUnix`, `startedAtUptime`, `updatedAtUnix` | Original run identity/timing and most recent publication. |
| `state`, `stage`, `target`, `mode` | Running or terminal status, current work, optional board coordinate, full calibration or spot check. |
| `fitCompleted`, `fitTotal`, `validationCompleted`, `validationTotal` | Actual route entries completed, never correction attempts or image samples. |
| `elapsedSeconds`, `stageElapsedSeconds` | Measured monotonic durations; terminal durations stop advancing. |
| `bindingActivated` | Always false. This producer cannot activate a binding. |
| `error` | Optional diagnostic retained in the status file. Not used as hardware authority. |

The UI validates version, finite bounded values, coordinate names, counts and
completion consistency. It rejects rollback within a run, return to an older
run, and resurrection of a terminal run. Reads are bounded to 64 KiB and happen
on a utility task at 2 Hz. Invalid/missing data after a valid report displays
unavailability instead of reusing a current-looking success.

Producer updates only replace small immutable in-memory snapshots. A daemon
worker handles all progress file operations, using a separate nonblocking writer
lock and atomic replace. Under that lock a newer run prevents an old worker's
late final status from overwriting it. Every runner progress call is exception
isolated; a missing file, full disk, busy writer or broken publisher cannot skip
full OFF, change calibration qualification or extend a freshness limit. There
are no progress hooks between the accepted final light ticket and SWEEP.

## Entry points and verification

- `Sources/PhysicalCalibrationProgress.swift`: bounded decoder and run lifetime.
- `Sources/PhysicalCalibrationProgressView.swift`: display and asynchronous polling.
- `Sources/PhysicalAIView.swift`: additive setup/play panel insertion.
- Laser `Firmware/calibration_progress.py`: passive publisher.
- Laser `Firmware/Tools/commission_gameplay_calibration.py`: actual stage/target hooks.

Native focused test (no hardware or app launch):

```sh
python3 PhysicalGo/build.py --calibration-progress-test
```

`Tests/Fixtures/CalibrationProgress.json` was produced by the actual Python
`CalibrationProgress.snapshot()` with fixed test clocks and no worker/hardware.
It establishes native decoding of the producer's real field names and types.

Laser tests: `test_calibration_progress.py` covers ownership, lock contention,
atomic failures, finite terminal publishing and display failure isolation.
Independent `test_calibration_progress_safety.py` drives complete fake runner
paths with throwing update/finish methods and checks that original OFF/result
behavior survives. Existing calibration and dark suites must also pass after
runner edits. Installation and physical/UI validation remain root's work.

Offline verification on November 23, 2026: **26 native decoder/lifetime tests**
pass, and the new SwiftUI view typechecks independently. Independent host review
passes **104 calibration/progress tests plus 24 dark tests**, including both
retained-image cases and four complete runner/route tests with a deliberately
broken progress publisher. Full app build, installation and visual/physical
validation are not implied by these results.
