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
