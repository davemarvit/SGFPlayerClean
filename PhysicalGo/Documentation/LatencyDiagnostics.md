# Optional latency diagnostics

Experimental overnight branch, November 23, 2026. These changes are not in the
preserved signed 0.254 candidate and have not been used with hardware. The primary
game, installed app and calibration are unchanged. This is diagnostic logging,
not an admission signal, a new timeout policy or adaptive-map activation.

## Enable for a later supervised run

Both processes opt in only when `PHYSICAL_GO_LATENCY_TRACE_DIRECTORY` is an
absolute directory path in their launch environment. With the variable absent,
there is no trace writer. This branch does not modify persistent app settings,
`launchctl` environment, or the running application.

After root builds and reviews a candidate containing these changes, launch that
candidate with the environment variable, for example:

```sh
env PHYSICAL_GO_LATENCY_TRACE_DIRECTORY="/absolute/test-session/latency" \
  "/absolute/candidate/Physical Go.app/Contents/MacOS/PhysicalGo"
```

Prefix the separately reviewed hardware bridge launch with the **same** variable
when physical testing is authorized. This is not a replacement bridge command;
the existing port, setup, model, binding, log directory and safety requirements
still apply. To disable tracing, quit normally and relaunch without the variable.
Do not launch a second app or bridge to add tracing to an already running one.

The output directory contains `native-latency.jsonl` and `host-latency.jsonl`, each
with one `.previous.jsonl` rotated predecessor. Default cap is 1 MiB per file,
approximately 4 MiB across both roles, plus two fixed worker lock files. Each role
has a nonblocking writer lock so another process cannot race its rotation.
All trace values are text/numbers; no images, raw camera-context blob, paths,
engine output text or serial replies are captured.

Offline summary, from the paired laser repository:

```sh
python3 Firmware/Tools/summarize_latency.py \
  /absolute/test-session/latency/*latency*.jsonl \
  --output /absolute/test-session/latency-summary.json
```

The summary does not open the camera, serial port or application. It bounds input
size, rejects malformed rows, and reports invalid input as warnings.

## What the events tell us

| Question | Evidence | Limit |
|---|---|---|
| How long did AI thinking take? | Native engine start/return, scoped by game/move/**generation**. | Includes the asynchronous engine call's elapsed time, not just engine CPU time. |
| How long from decision receipt to a point request? | Native current-generation receipt and first point publication joined by the exact decision receipt identity. | Includes deliberate camera/hand/recovery waits; receipt does not itself mean the move was legally accepted. |
| Where did the host spend time? | Accepted request, worker start, dark admission/travel, alignment/collection/detection, coarse/fine settlement and command replies. | Parallel stages overlap. Summed work durations are not critical-path latency. |
| Did file reporting add delay? | Native status read/request write durations; host existing `result.json` write duration per point event. | Existing report persistence behavior is preserved, not silently moved or suppressed. |
| When was light commanded? | TRACK/SWEEP host write completion and matching reply. | Neither timestamp is actual beam onset. The cue remains dispatched before the new trace hook. |
| When did optical correction become accurate? | First nonprovisional observed spot with finite error in 0–3 pixels. | This is camera evidence observed after sample processing and a later pose readback, not a physical-onset sensor. |

Request heartbeats are sampled only when producer/revision changes. Native request
and driver-state transitions are sampled; slow status reads/writes over 20 ms are
also recorded. Those are diagnostic sampling thresholds, not safety deadlines.
Host optical sample timings preserve frame waiting, image processing and existing
report-write costs separately. Native camera pipeline CPU time is not newly
profiled by this change; existing recognition recordings/traces remain separate.

## Clock and loss semantics

Every process has a fresh `runID` and explicit `clockDomain`. Native events use
`swift-systemUptime/<runID>`; host events use `python-monotonic/<runID>`. Original
observation timestamps are saved before asynchronous writes. Host point events
also retain their timestamp before the existing synchronous report write.
Human-readable Unix timestamps are not used for elapsed-time subtraction.

Producer UUID and revision correlate the native and host records, but **the
summary never subtracts timestamps across process/run clock domains**. It does
not invent a single end-to-end move-to-light number. Exact decision receipt time
is used only as an identity copied at both native boundaries, never subtracted.
Camera capture uptime is labeled separately and is not assumed to share the host
Python clock's epoch. MCU timestamps are not included or compared to Mac clocks.

Producer-side work is bounded validation plus a nonblocking capacity/lock attempt.
JSON encoding, directory/file operations and rotation happen on one utility
writer. Native capacity is 256 outstanding events; host capacity is 256 queued
events plus the current write. Full queues drop diagnostics. Oversized rows and
writer errors cannot enter game/hardware control or bypass OFF.

Rows expose writer failures and known queue drops. Python's independent
`offerSequence` exposes validation/contention gaps without mistaking reordered
concurrent offers for loss; `eventSequence` is serialized writer order. Swift
reports capacity/validation drops asynchronously, in bounded accounting batches.
The summary marks known loss and missing endpoints as unknown. Files are rolling
and daemon shutdown does not wait for logging, so **no complete-session claim** is
made, even if retained rows show no gap. Final failures, truncated prefixes/tails
and abandoned queue entries may have no later row reporting them.

## Audit data for future adaptive calibration

When tracing is enabled, a `calibration_observation_audit` event can retain actual
spot coordinates in the reference board, requested target, measured pose counts,
newest frame identity/original timestamps, later POSE write/reply interval, and
the setup/model/reference identities already checked by the active binding.
Camera context is represented by SHA-256, not its large encoded value.

Current optics observes a multiframe spot and then reads pose. That does **not**
prove a settled pose throughout the image capture interval. The audit explicitly
marks `trainingEligible=false`, `surface=unknown`, `poseValidity=unproven` and
`sampleWindow=newest_frame_only`. It supplies no invented spot uncertainty,
confidence, earliest exposure or pose-validity interval. These records can guide
future instrumentation; they are not accepted online training pairs.

## Verification and rollback

- `python3 PhysicalGo/build.py --latency-trace-test`: standalone sink isolation
  tests, including blocked writer, capacity, failed writes and oversized JSON.
- Laser `test_latency_trace_review.py`: independent queue/rotation/clock/loss and
  summary tests. `test_latency_trace_hooks.py` drives real runtime/point paths with
  fake hardware and a broken sink, checking existing OFF/expiry/fault behavior.
- Existing bridge and fast-feedback tests cover the unchanged control path,
  including retained recordings supplied read-only in the isolated worktree.

Full native integration compilation and physical overhead measurements remain
root's integration gates. Disable the environment variable for immediate runtime
rollback; the paired branch commits can also be omitted/reverted without changing
the model, binding, saved game or firmware. The preserved 0.254 candidate remains
the separate physical-testing fallback.
