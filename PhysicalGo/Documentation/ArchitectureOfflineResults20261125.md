# Architecture offline batch results — November 25, 2026

**Reviewed and tested; installation pending root's receipt.** Candidate native `3fe6290d0ed8612b2aa852b7bb6a8b218a53c7cd` (0.266/build267) and host `2f8c4daed12389f1c96bcd930b893ed9bf3bd580` are committed/pushed. Installed0.265/native1f6fb91 + hostb9a524e remain unchanged at this checkpoint. The app is closed and no hardware/camera work occurred. [Compact provenance](ArchitectureOfflineResults20261125.json) · [Current register](IntegrationChecklist.md).

## Completed source outcomes

- **PG37 motor admission:** `9a6e5f3` + `54e4180` integrated as `fe58f8d` + `9113e0e`. Pure bookkeeping and typed blocker diagnostics preserve timeout/reset ordering; this does not establish the cause of the historical persistent OFF loop.
- **PG34 checking help:** `2c79bde` + `c7d471c` + wording fix `79be6e5`, integrated as `16ef377` + `d9b07b1` + `fa84534`. Persistent checks automatically show affected crossings/recovery help after three seconds, using existing setup navigation and preserving stones. Actual interruption resets and first-human-move guidance are covered. Recognition decisions, clocks and history are unchanged; weak recognition/reference causes remain open.
- **Host supervision I/O:** `e57e341` + reviewed session-origin fix `9594381`, integrated at `2f8c4da`, isolate file evidence/diagnostic work from thermal supervision. Generation/session-scoped publication, original600ms expiry, reader protections and OFF/shutdown boundaries remain. Independent review `8ccc3ef` reports no source blocker.
- **PG21:** retained timeline `e94c5dd` integrated as `984b332`;16 focused tests pass. It preserves original time domains and leaves unrecorded physical/engine onset unknown.
- **PG24:** `a5e4a17` is a completed negative shadow experiment, **DEFER** for production:358.56/361 cells selected on average, three missed EMPTY-confidence0.95 crossings (not missed stones), and1.63ms/frame net overhead. No production scheduling gate.

## Final validation

Nine native suites passed after the final wording fix. Counts use each suite's original units; the312,326 parity assertions must not be presented as312,326 physical cases.

| Suite | Result |
|---|---:|
| Motor admission |312,326 assertions, including4,096 sequences/1,024 gate combinations|
| Accepted click |28 checks|
| Guidance continuity |263 checks|
| Checking controller |31 checks|
| Checking progress |54 checks|
| Ambiguous placement |57 checks|
| Monitored standby |387 checks|
| Ambiguity diagnostics |1,427 checks|
| AI laser lifecycle |325 checks|

Final combined host: **301 tests passed**. Mandatory paired acceptance also **passed**; fake hardware and composed native/host stages do not establish live timing or physical reliability. Signed build is awaiting root's final receipt. [Native log](</Users/Dave/Documents/SGF PLayer/work/architecture-offline-20261125/native-tests.log>) · [Host log](</Users/Dave/Documents/SGF PLayer/work/architecture-offline-20261125/host-integrated-tests.log>) · [Paired acceptance](</Users/Dave/Documents/SGF PLayer/work/architecture-offline-20261125/paired-acceptance/acceptance.json>).

## Next attended evidence and queued policy

PG34 help is automatic when its condition persists. **Motor-admission metadata tracing is opt-in:** set `PHYSICAL_GO_LATENCY_TRACE_DIRECTORY` to an absolute evidence directory in the environment of the next attended app launch. Merely installing this source does not enable it. The existing bounded asynchronous text writer emits `motor_admission` changes; no new image recording or camera acquisition is enabled. Trace fields never grant hardware authority.

Persistent OFF-loop causality, real checking/reference recovery, temporal matcher/live600ms margins, actual child shutdown receipt, accepted click and same-light/lit-movement behavior still require physical acceptance. Preserve seven stones, empty pending Q17, game/clocks and last actual OFF1795596934.1468098. Root owns any new attended camera/alignment/READY flow.

**Queued offline architecture policy:** define local-AI clock continuity for genuine camera stream loss/confirmed alignment failure, distinct from normal hand/unclear frames and online server clocks. The [source audit](ArchitectureFollowThrough20261125.md) keeps this visible; it is not silently solved by the motor-admission extraction.
