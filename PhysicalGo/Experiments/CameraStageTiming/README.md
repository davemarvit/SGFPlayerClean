# Native camera stage timing candidate

Base: installed native 0.269, `d014c63b2f4b07e81e10b7c4f9f9ecfed51c15a4`.
This candidate adds diagnostics only. It does not change safety checks, camera
cadence, freshness limits, latest-input admission, recognition order, host thread
policy or recording settings. It has not been installed or physically tested.

## Why

In retained run `1795767435349051000`, frames 1866/1867 took 524/505 ms from
analysis start to safety dispatch, while PNG preparation took 502/543 ms on
another queue. Capture-to-safety ages were 1.070/1.307 s. Analysis queue wait was
about 2 ms; main safety delivery was 14/0.2 ms. Existing timers leave roughly
529/799 ms before analysis submission unattributed. That interval includes
capture delivery, CGImage detachment, feed-health measurements, main delivery,
and any residence in the replaceable analysis-input slot. It is not proof of an
AVFoundation frame backlog. `alwaysDiscardsLateVideoFrames` was already true.

Both slow diagnostic operations reported supported alignment, six footprints,
no lighting failure and clear hands. Exact slow-frame pixels were not saved;
nearby frames 1860/1884 are only representative replay inputs. Root's separate
OpenCV default/1/0/default replay and synthetic PNG-write probes did not reproduce
the stall. No causal claim or production thread cap follows from these results.

Retained incident extracts and initial plan:
`work/requirements-implementation-20261126/camera-stage-profile-plan-0269/`
in Dave's SGF PLayer workspace. Frozen originals remain unchanged.

## Opt-in and interpretation

The process must have both:

- `PHYSICAL_GO_LATENCY_TRACE_DIRECTORY=/absolute/trace/directory`
- `PHYSICAL_GO_CAMERA_STAGE_TRACE=1`

These are startup environment settings, not permission to launch the app or
camera. Root owns any later installation and attended collection. No diagnostic
images are required by this instrumentation.

The existing bounded utility trace writer handles all output. Producers neither
encode JSON nor wait for writer capacity. Existing event sequence/drop/failure
counters and two rotating 1 MiB files remain unchanged. Extra records shorten
the retained time window: preserve the incident promptly. A missing event can
reflect a dropped trace record, a rejected frame, or a disabled path; it is not
proof that work did not occur.

| Event | Measurement |
|---|---|
| `camera_delegate_arrival` | Original capture uptime and delegate entry; capture-to-delegate elapsed time |
| `camera_capture_stages` | CGImage detachment, feed-health measure, feed-health assessment |
| `camera_capture_main_wait` | Capture queue dispatch to main callback entry |
| `camera_capture_delivery` | Main-thread callback work, including app intake |
| `camera_latest_slot_offer` | Attempt to retain an input while recognition is busy |
| `camera_latest_slot_take` | Residence of the input actually admitted from that slot |
| `camera_analysis_stages` | Gray/color conversion, exposure, alignment, stone detection, pose, outline sampling/tracking, lighting, safety dispatch |
| `camera_post_safety_stages` | Established-stone tracking, aspect estimation, rectification |
| `camera_completion_delivery` | Worker completion dispatch to main callback entry |
| `camera_completion_apply` | Main completion work, including its existing defers and next-input dispatch |

Pipeline events carry broker frame ID/stream epoch when supplied by the live AI
path. Capture events precede broker allocation and carry camera stream plus
original capture uptime. Join them by original capture uptime in the same trace
run, then preserve broker epoch/frame identity. Photo/redraw inputs may have no
original capture timestamp or broker identity; do not invent one.

Stage durations use elapsed monotonic time and `CLOCK_THREAD_CPUTIME_ID` on the
same synchronous thread. Each timing object stays on that thread. At most ten
stage pairs plus start/capture and total wall/CPU values fit the writer's 24-metric
limit. Unsupported CPU readings are omitted. Thread CPU excludes CI/Vision worker
threads and GPU execution: wall minus thread CPU is **not** a scheduler-delay
measurement. Different queues overlap and their durations must not be added.
Totals include small instrumentation overhead and unmarked bookkeeping. These
counters are for attribution, not a zero-overhead benchmark.

The latest-input container and its 200 ms admission rule are unchanged. An offer
is an attempt, not proof of retention: an older offer may be ignored; a retained
input may be replaced or fail age/revision checks. A take event reports only an
admitted input. No take event alone does not distinguish those causes.

## Validation

Focused Foundation checks verify CPU/wall separation with deterministic clocks,
original capture identity, event bounds, unavailable CPU omission, idempotent
finish and existing nonblocking writer behavior. The synthetic pipeline suite
runs enabled and disabled, checking same-frame safety/completion agreement,
post-safety rendering and stage identity/metrics. It starts no app or camera.
The shared native regression runtime compiles the actual capture, model and
pipeline integration. Build/test receipts are recorded after validation below.

Future profiling should use an optimized runtime, decode inputs outside timing,
and a finite warmed replay. The debug correctness runtime is not performance
evidence. Live diagnosis still needs an attended reproduction with these counters;
the candidate does not establish a latency improvement or fix the reported stall.

Validation completed November 27, 2026:

- Full native shared runtime `af9341e92ded36d165de51708fa08bab0b0a86fa9cab2fefd46a8a0612203605` compiled from the candidate source snapshot with `-Onone`; changed files produced no compiler warnings. Existing unrelated warnings remain.
- Foundation latency/stage writer: 38 checks passed.
- Pipeline stage timing: 26 enabled, 7 disabled and 26 absent-original-capture checks passed.
- Existing wooden-board perimeter/profile/pipeline: 110,620 checks passed.
- Independent camera safety delivery: 18 checks passed.
- Latest-only input ordering, one-time consumption, age/context rejection: passed.
- Build tooling: 8 Python tests passed; `git diff --check` passed.

[Machine-readable receipts](validation.json) retain immutable runtime/runner identities
and changed-source hashes. No asset downloads or resource preflight were needed.
Capture delegate and live latest-slot instrumentation compiled but were not
exercised by acquiring a camera. Main pipeline handoff and completion timing
were exercised by the synthetic asynchronous test.

A final diagnostic provenance correction ensures the completion-delivery record
omits capture uptime for photo/redraw inputs without an original capture time.
It never relabels the tracking-time fallback as capture evidence. The final shared
runtime and all native suites were rebuilt/rerun after this correction.
[Initial successful pre-correction receipts](validation-initial.json) are retained
separately; final receipts are in `validation.json`.
