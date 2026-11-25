# Fast-test worker latency evidence (PG-00)

November 24, 2026. This candidate adds optional worker-level timing diagnostics;
it is not installed or physically validated. PG-00 stays open until current-version
physical reply timings are measured separately for first use, uninterrupted reuse
and reuse after an ordinary pause/resume.

## Existing evidence

The retained `app-0258-candidate/ai-play-test.log` under the November 23
`stone-session-20261123` evidence directory records a real 19×19 eight-visit
cold-worker reply of **8.275 s** and a following warm-worker reply of **0.114 s**.
Those are historical offline engine-call measurements, not current physical
reply or decision-to-light timings. The existing `--ai-idle-reuse-test` separately
checks worker lifecycle and cancellation with fake engines. No further heavy
engine benchmark is required to demonstrate that this measurement path exists.

Existing `ai_engine_started`/`ai_engine_returned` traces lack actual worker
identity and reuse state. A short duration, the first event in a rotated file,
or a high move number cannot establish warm/cold status.

## Candidate diagnostics

`PhysicalAI.TestWorker` now emits `ai_test_worker_started`,
`ai_test_worker_returned` and `ai_test_worker_failed` through the existing opt-in
bounded trace sink. Every request carries unique request and worker IDs,
`workerStart=new|reused`, `afterIdleRetention=true|false`, board size and move
number. Reuse is classified **after** configuration/liveness validation. Changed
assets or a stopped worker therefore report a new worker. Late cancelled results
remain failed requests with their original identity, even if a replacement
worker has already completed.

The measured interval includes configuration validation, backend construction
when needed, process/model startup when needed, and the asynchronous move call.
It excludes physical recognition before the call and aiming afterward. “New”
means a new backend/process, not a cold operating-system file cache.
`afterIdleRetention` includes ordinary pause/resume and camera freeze; it is
not a claim that a particular UI control was used. There is no game/session ID
in these events, so do not join them to physical game events by move number alone.
The existing scoped AI lifecycle events remain available for that separate
measurement. These fields never authorize a move or change game state.

## Offline summary

After root captures traces during an authorized attended run:

```sh
python3 PhysicalGo/Tools/summarize_ai_worker_latency.py \
  /absolute/run/native-latency.previous.jsonl \
  /absolute/run/native-latency.jsonl > /absolute/run/ai-worker-summary.json
```

Supply only existing files. This reads at most 64 MiB and opens no engine, app,
camera or serial port. The JSON includes count/median/maximum for new workers,
uninterrupted reuse, and reuse after idle retention; it also retains each
successful pair and counts failed/incomplete requests. Identical repeated input
rows are deduplicated. Conflicting endpoints, mismatched identities and crossed
run/clock domains cannot become timings. Legacy engine events remain unclassified.
Rolling logs never establish completeness; trace loss is reported separately.

## Validation and remaining acceptance

```sh
python3 -m unittest discover -s PhysicalGo/Tools -p test_summarize_ai_worker_latency.py
python3 PhysicalGo/build.py --ai-idle-reuse-test --debug-tests
```

Python summary validation passed **10 tests** on this candidate. A read-only run
against the retained 0.258 rolling trace files found no surviving worker-classified
requests; it did not manufacture timings from missing evidence.

Python tests cover actual-state classification despite counterintuitive timings,
rotated duplicates, cross-run separation, cancellation, replacement identity,
incomplete/conflicting endpoints, legacy unknown state, invalid clocks and
nonfinite/reversed timestamps. Native fake-backend additions cover first use,
idle reuse, asset replacement and cancellation-ignoring old completions. Native
compilation requires the coordinator's shared build slot.

Root must integrate and test the reviewed source before installation. An attended
current-version sequence must then measure physical reply latency and verify
clock/history preservation. Keep these worker-call measurements separate from
camera clearance, board verification, final dot acquisition and audible click.
