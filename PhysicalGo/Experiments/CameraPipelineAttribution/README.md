# Calibration camera gap attribution — November 24, 2026

Offline source and saved-log investigation. No app, camera, controller, or serial
port was opened. The installed 0.261 app and its active stream are unchanged.
This branch adds optional timing diagnostics only, not a delivery or safety-policy
change. It is based on native runtime `9c516f1`.

## Exact saved evidence

Source: `recovery-full-20261124-114432-37324/attempt-000/result.json`.
The compact [attribution artifact](calibration-gap-20261124.json) preserves its
SHA-256, original clock values, final OFF receipt, and terminal qualification
failures. The host observed 1,471 distinct optical manifests during this attempt.

| Frame | Capture uptime | Capture → manifest timestamp | Hand | Alignment |
|---|---:|---:|---|---|
| 29511 | 1987631.456034 | 143.450 ms | clear | valid |
| 29512 | 1987631.549001 | 948.592 ms | clear | valid |
| 29520 | 1987632.349034 | 225.740 ms | unknown | valid |

The 29512→29520 capture interval is **800.033 ms**. The next-largest observed
manifest capture interval in this attempt is 298.033 ms. This is an isolated large
interruption in these saved records, not evidence of a sustained unbounded backlog.

`PhysicalLaserFrameBroker.frame()` assigns IDs when `ExperimentModel` receives a
camera frame on main, before analysis. Seven intervening IDs therefore establish
that camera frames reached that boundary. They do **not** establish which were
analyzed: the analysis queue retains only the latest waiting input, and the
publication broker can also coalesce pending work. This evidence does not support
calling the event an 800 ms absence of camera hardware frames.

`HandOutlineTracker` resets after a gap greater than 650 ms, then needs three
clear observations to establish its visual reference. The unknown result is
consistent with such a reset if intervening frames were not analyzed. Other
paths also reset or yield unknown clearance; the saved optical manifests do not
contain the native hand reason. No native timing trace was enabled for this run.
Thus an analysis-stage stall, post-safety display work, completion delivery,
publication coalescing, or an independent unavailable hand result cannot yet be
uniquely distinguished. Unknown clearance remains a stop condition.

`publishedAtUnix` is sampled while constructing a manifest, not after atomic
visibility. A host read-start timestamp precedes the reads and cannot be treated
as their completion time. Long read intervals include scheduling and parsing;
these records do not isolate syscall execution time or prove fsync as the cause.

## Remaining source dependencies

- `CameraCapture` drops new raw callbacks while a prior main delivery is pending.
  CI image conversion and feed-health assessment precede that main delivery.
- `CameraAnalysisPipeline` computes current hand pose, gray/exposure, alignment,
  stone evidence, hand outline and lighting before emitting safety evidence.
  Its existing safety callback still runs on main.
- Stone tracking, aspect estimation and rectification run after safety but before
  the full completion. `processingBusy` remains set until that completion, so a
  slow display stage can delay the next frame's hand analysis even if the preceding
  safety result was published promptly.
- Completion applies temporal state on main, then takes the latest waiting input.
  No older hand, exposure, geometry, or lighting verdict is reused as current.
- Version 0.261 independently writes safety metadata and optical PNGs. That removes
  PNG work from the safety writer but does not remove the earlier dependencies.

There is insufficient evidence to choose a behavioral fix. In particular, moving
only a callback to another queue would not make the entire capture/temporal-state
pipeline independent of main and would introduce revocation/ordering obligations.
The instrumentation below is the smaller next step.

## Optional bounded instrumentation

The existing `PhysicalLatencyTrace` writer is unchanged: nonblocking bounded event
admission, at most 256 queued events, a utility JSON writer, and two rotating files
of approximately 1 MiB each. Producers do no JSON/file IO. The added events are:

| Event | Interpretation |
|---|---|
| `camera_capture_delivery` | Original capture/arrival uptime; conversion + feed health; main queue delay; callback duration; callbacks dropped while a prior delivery was pending. |
| `camera_analysis_stages` | Worker durations for Vision pose, gray/exposure, alignment, stones, outline, lighting, safety callback, stone tracking, aspect, rectification; total and post-safety durations. |
| `camera_safety_ready` | Existing queue/analysis/main delivery/capture age, now with original capture uptime and frame ID/epoch. |
| `camera_analysis_applied` | Full worker time, full-completion main delay, synchronous apply duration, original capture uptime and frame identity. |

Capture events precede allocation of the broker frame ID; join them to analysis
by the original `capturedAtUptime`. Analysis and broker events also carry epoch/ID.
Capture events describe accepted usable frames, not every hardware sample; the
pending-delivery counter describes only that specific drop path.
Do not join by wall time alone. Stage timings describe elapsed wall time, including
scheduling/preemption; they are not CPU or syscall measurements. Event drop/failure
counters remain essential when interpreting missing events.

For a **root-coordinated future launch** of an installed build containing this
candidate, set the existing environment variable to a private absolute directory:

```sh
PHYSICAL_GO_LATENCY_TRACE_DIRECTORY=/absolute/private/run-directory \
  "$HOME/Applications/Physical Go.app/Contents/MacOS/PhysicalGo"
```

This path matches the current user-installed app's Info.plist; the example is not
an instruction to launch now. This requires a coordinated app restart and does not
enable diagnostic image saving. The already installed 0.261 build can emit its
existing safety/publication timing events with the same variable, but lacks the
new stage attribution. Copy both rotating JSONL files promptly after a relevant
event; record whether droppedEvents/writerFailures are nonzero. Never change a
live environment, restart the active stream, or install from this child task.

## Verification

Run offline, from this worktree:

```sh
PHYSICAL_GO_SHARED_REGRESSIONS=1 python3 PhysicalGo/build.py \
  --hand-stone-pipeline-test --latency-trace-test --debug-tests
```

Final verification: **54 photographed hand/stone pipeline checks pass** and
**26 bounded trace checks pass**. The full shared native runtime compiled, including
the changed capture and model call sites. Logs are
`/tmp/physicalgo-pipeline-attribution-hand-tests.log` and
`/tmp/physicalgo-pipeline-attribution-tests-rerun.log` (the latter also records an
intermediate test-expression compiler failure corrected before the final 54-check
pass). These were offline tests, not a runtime benchmark or physical validation.

The photographed hand/stone regression additionally verifies that safety precedes
stage reporting, original capture times remain intact, and stage durations form a
finite nonnegative partition of the worker interval. This instrumentation neither
changes observations nor relaxes the 600 ms camera, 650 ms hand-gap, lease, or
other acceptance limits. Test results are recorded in the branch checkpoint.
