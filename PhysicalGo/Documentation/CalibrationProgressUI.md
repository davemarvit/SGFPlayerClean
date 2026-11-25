# Laser setup progress display

Full-calibration and spot-check progress were installed in0.258 and retained in
0.261. Earlier candidate/build statements below are dated validation records,
not current installation authority. Read the issue register for the current
setup qualification and gameplay status.

## Minimal setup and feedback extension (offline candidate, November 24, 2026)

PG15/PG19 candidate source extends the passive publisher and reader to the
three-wide acquisition and optical feedback benchmark. It is not installed or
physically verified. Current implementation/installation authority remains
[IntegrationChecklist.md](IntegrationChecklist.md).

- `three_point_seed`: three selected observations, excluding transit observations;
  `seed_ready` means acquisition and fitting completed after full OFF. It does
  not activate gameplay or approve the pointer binding.
- `feedback_check`: zero fitting points and the actual number of targets in this
  run (one through seven). A P15/K18 suffix reports two targets, not a seven-target
  uninterrupted pass. `feedback_checked` means the listed targets were reached
  and the run finished full OFF; it does not claim an ordinary-game pass.

Both use schema1 with new mode/state values, retain measured monotonic elapsed
and stage durations, and leave `bindingActivated` false. Older native readers
reject unknown modes rather than displaying a misleading full-calibration bar.
The reader preserves completed counts through unavailable/stale updates and
rejects changes to a run's mode or totals. A fresh run remains a distinct run;
counts are never silently combined across runs. Calibration artifacts are not
changed by the display or by a missing publisher.

The progress-only scope does not implement PG33's reviewed gameplay binding or
turn a benchmark result into startup authority. Root still needs to integrate
that binding and measure setup-to-play time. A full five-plus-nine tour is not
implied by spot-only wording.

Focused verification adds actual Python-produced native fixtures
`ThreePointProgress.json` and `FeedbackProgress.json`, plus host
`test_minimal_setup_progress.py`: count accuracy, retained partial observations,
suffix routes, display-failure isolation, real runner shutdown ordering and
failure termination. Existing full/spot progress tests remain applicable.

Offline candidate verification: **46 native parsing/lifetime checks**, independent
SwiftUI model/view typecheck, and **36 host tests** pass. The host set combines
progress, progress-failure isolation, wide acquisition, feedback convergence and
11 new minimal-workflow collector/runner tests. No app launch, installation,
physical run or setup-to-play timing was performed. Host commit: `a7d8d66` on
`codex/minimal-setup-progress`, based on the frozen feedback host `2da3c29`.
Native candidate is based on installed-source documentation HEAD `0628a33`.

## Existing full calibration and spot-check display

The setup and play panels include passive progress for the externally operated
initial laser calibration. It appears when the calibration runner publishes a
status file; there is no new hardware command, Start button or binding authority
in the display.

The panel shows the current stage and target, elapsed time, time in that stage,
and actual completed point checks. Full calibration has **5 calibration targets
and 9 independent accuracy targets**; repeated K10 entries are separate checks.
The bar measures completed checks, not elapsed-time fraction. Individual targets
can need different numbers of optical corrections. The completed November 24 run
spanned 1,230.9 seconds from first to last observation; one run does not establish
a useful remaining-time estimate, so the UI does not invent an ETA. An initial spot-only check has no full-board progress bar.

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

Root integration: registered `--calibration-progress-test` passes all26 checks;
the four-suite final app regression and8 build-registry checks pass. Full signed
0.254/build255 candidate builds and verifies successfully. It remains uninstalled;
visual and physical validation are deferred until the user returns.
