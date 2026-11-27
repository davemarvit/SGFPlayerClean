# Returned O17 failure — frozen evidence review

Installed pair: native0.268/build269 `fb4697c4ef314d83a253bd0aa219de1bb6b3d61f`, host `8ce91a17bb8e968dbb40bf0058ff5bd768b95f1c`. Run1795765307207891000, seq85; game10 logical/nine physical stones, White O17 unplaced. Review reads saved artifacts only; no hardware, camera, UI, build or test actions.

[Root outcome](</Users/Dave/Documents/SGF PLayer/work/requirements-implementation-20261126/returned-o17/outcome.json>) · [Worker result](</Users/dave/Library/Application Support/Physical Go/LaserDriverLogs/1795765307207891000/events/1795765333945923000-feedback-85/result.json>) · [Monitor](</Users/Dave/Documents/SGF PLayer/work/requirements-implementation-20261126/returned-o17/monitor.jsonl>) · [Native trace](</Users/Dave/Documents/SGF PLayer/work/requirements-implementation-20261126/returned-o17/first-driver-request_lease_expired/native-latency.jsonl>) · [Hang sample](</Users/Dave/Documents/SGF PLayer/work/requirements-implementation-20261126/returned-o17/driver-hang.sample.txt>).

| Recorded event | Unix time / evidence |
|---|---|
| First monitored adequate |1795765340.277897; internal seek3.755s, error0.149930cell, zero moves|
| Frame2071 published by native |1795765347.074964; capture age157.834ms, publication total24.083ms|
| Worker error |Frame2071 raw capturedAtUnix age728.298ms, publication age573.043ms; error has no explicit event timestamp|
| Native motor admission requests OFF |1795765347.648278; thermal_telemetry_unavailable / awaiting_full_off|
| Delayed point85 publication |1795765347.728327; write335.534ms, decision age335.599ms|
| Separate safety frame2077 publication |1795765347.728342; capture age198.231ms|
| Native OFF88 publication |1795765347.728929; reason camera_unverified|
| First monitor lease-expired fault |1795765347.833813; status updated1795765347.728858|

The worker retained14 accepted observations and one lit renewal. No correction plans were consumed; active-work spend4.429s leaves145.571s. This was not work-budget exhaustion. The7.556s adequate-to-fault monitor interval is not a claim of continuous optical proof or exact visible-light duration. User reports the dot stayed on for a while then disappeared.

The raw frame timestamp error differs from typed postprocessing/renewal expiry. Frame2071 was initially published fresh; later rejection does not by itself locate the delay in acquisition, reading, processing or contention. Native safety remained independently fresh nearby. Thermal unavailability and request-write delays require joint causal analysis; the later request_lease_expired status must not be substituted for the initiating fault. Exact failed pixels were not retained (`optical_failure_evidence.retained=false`); no failed-image replay claim. The native process sample contains lock waits, but this review does not identify the responsible Python lock owner or prove recurrence of the earlier A1 path.

SIGINT shutdown stalled. Root sampled the process; user confirmed all physical power off before root killed child92696. Launcher exited1. **No verified final controller OFF receipt.** Prior OFF1795712291.8697388 is historical only. Game paused and recording off; no new physical action.

PG06a owner temporal_requirements_audit: explain the saved capture/publication/thermal timeline, reproduce the identified path offline, and preserve independent safety/600ms authority. PG20 owner adaptive_motion_speed: reproduce shutdown lock/order failure using actual runtime and fake transport, repair bounded cancellation/OFF completion, retain truthful failure receipts, and obtain independent review. Full candidate remains uninstalled; these blockers and the failing final lit-renewal replay require resolution before release. PG36's earlier schema-proof fix is distinct from this missing receipt caused by shutdown noncompletion.

## Reviewed repairs and separate intent-lease follow-up

**Offline candidate progress (not installed):** root host `9e7c0c0` combines the independently approved signal/startup repairs `8354e8b` + `8927308`, approved replay-only repair `1759411` (review `9f596b2`), and IPC isolation/newer-frame retry `90c7bff`, which remains under independent review. Signal handler reentry into `Event.set()` is a reproduced vulnerability, not a fully proven attribution of the live hang; the first patch's startup cancellation race was caught and repaired before approval. Replay-only review verified eight actual renewals, matching artifacts and530.49ms maximum final evidence age; this repairs the replay gate without changing production behavior. Root is running full host/replay/paired checks on exact9e7c0c0/native `d014c63`. Signed native0.269/build270 is ready and verified, **not installed**. Final combined results/review and installation receipt remain required. Installed8ce/nativefb and user-confirmed physical power-off state are unchanged.

The docs-only TTL audit `fc49f49f057f19e2a32796b8f62d651a8b817aa7` in `Firmware/Experiments/IPCLatencyIsolation/README.md` separates native600ms app-intent lease from host700ms parser cap and independent hand/optical600ms, thermal750ms, firmware watchdog and light limits. Some finite intent lease is necessary; exact600ms lacks a measured physical/human-response rationale in this investigation. No limits change now. Future evaluation must measure bounded recording load and write/read tails, app suspension/crash/quit, explicit OFF delayed behind a write, and producer/target replacement. Compare stale-target persistence and cancellation as well as latency; native/host contract changes require coordinated review and paired tests. Fresh camera safety alone does not establish continuing app intent.

Root retained all236 recording frames; final saved frame1795765385.549442 lies26.75s after the later fault. Camera-only frames194/236 were reviewed; no deletion. Exact failed broker2071 pixels in this separate recording are not established. [Recording review](</Users/Dave/Documents/SGF PLayer/work/requirements-implementation-20261126/returned-o17/recording-review.json>).
