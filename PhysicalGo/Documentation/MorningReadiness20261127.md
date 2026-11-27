# Installed0.270 — morning readiness and review

**Current installed state —0.270 prepared offline, app/driver closed:** native **0.270/build271** `7188dc4ddd613f158cc2418ce8c7844cdcd66f33` and host **`936bf10e3942a0a32a47e57eb1b58cfba5af07d8-app0270`** are installed, manifest `88d6c31b480a785713fd51896dbd73a2ccf13fd9b6dcbf32c64bb07bff4481ca`. Final independent source approval `6c91eb03`;16 combined native suites,1,335 host tests (57 skipped), eight retained replays, mandatory paired acceptance and verified signed build passed. Game, startup anchor and wood profile are byte-identical across installation; previous0.269 app retained in backup. App and driver are absent, controller USB absent. **No camera/live alignment or hardware operation tonight, no new OFF receipt and no physical latency-fix claim.** Latest0.269 attempt remains unverified OFF; USB disconnection does not establish full pointer power off. Root asked the user to switch off the remaining pointer supply; confirmation is absent. Nine stones/O17 empty, paused move10 preserved.

One fresh morning chat **READY** authorizes root's prepared sequence after lights/controller power/USB are restored, hands clear, user watching and board unchanged. Root checks identity/exclusivity, starts one app with opt-in stage tracing, confirms game/camera, runs fresh alignment checks and the short attended O17 test without asking READY again if prerequisites pass. No active READY now and no unattended hardware. [Release/review record](MorningReadiness20261127.md) · [Exact morning plan and script](</Users/Dave/Documents/SGF PLayer/work/morning-readiness-20261127/morning-plan.json>) · [Install receipt](</Users/Dave/Documents/SGF PLayer/work/morning-readiness-20261127/install-receipt.json>).

## Source, scope and validation

[Compact pins](MorningReadiness20261127.json) · [Combined checks](</Users/Dave/Documents/SGF PLayer/work/morning-readiness-20261127/checks.json>) · [Native suites](</Users/Dave/Documents/SGF PLayer/work/morning-readiness-20261127/native-test-summary.json>) · [Signed build](</Users/Dave/Documents/SGF PLayer/work/morning-readiness-20261127/native-build-receipt.json>). The build receipt's earlier `installed:false` is superseded by the later installation receipt.

| Identity | Exact value |
|---|---|
| Native source hash | `6941a6a5fd59cd723d137c26147e41656da4f46d1d4cfcdb3df5b959f8382bdd` |
| Native binary SHA256 | `3ee013b3a7551822cbebd37c2a46fbe3189272ace58367beba8138ea78e7ba2d` |
| Final source approval | `6c91eb03da718bbf38d9279f8ed327578f5a7c28` |

Host reporting separates raw shutdown acknowledgement from gate acceptance/rejection, retains initiating runtime write exceptions beyond worker exit, and exports bounded serial evidence after close; optional thread-CPU timing leaves deadlines and OFF verification unchanged. Native opt-in camera-stage elapsed/thread-CPU tracing preserves original-capture provenance and safety behavior. These changes improve attribution; the serial timeout and600ms live stalls remain unexplained.

Recorder90ade4e caches unchanged checkpoint JSON and removes gap-triggered full-manifest rewrites without changing schema/readers/images/events. Source/retained sequence shows56.37MB context rewritten57times≈3.21GB; publications fall57→9 under the repair. This demonstrates removed serialization amplification, not causation of the live stall. [Recorder validation](</Users/Dave/Documents/SGF PLayer/work/morning-readiness-20261127/recorder-validation/validation.json>) retains baseline and candidate debug failures, unsuccessful test-only wait/reversion, and passing optimized **unchanged** broad recording suite62checks. Async131, writer16, compatibility25 and three full-checkpoint equality comparisons also pass; no gate waiver. Sixteen combined native suites and1,335 host tests/57skips, eight retained replays and mandatory paired acceptance pass.

Root's earlier default/1/0/default OpenCV probes did not reproduce live stalls:1,190 safety samples, maximum246.5ms, zero600ms expiry. No production thread cap adopted;53f083b is docs/probe-only GCD getter-semantics correction. No deadline/firmware/calibration changes.

## Morning acceptance remains physical

The exact [morning plan](</Users/Dave/Documents/SGF PLayer/work/morning-readiness-20261127/morning-plan.json>) pins `start_app_for_attended_test.py`, accessibility helper, trace/monitor setup and launcher verification. Root uses the user's one fresh chat READY for this short O17 test; it is not permission for unattended ongoing play. Preconditions: room lights restored, pointer power and USB reconnected, board/stand unchanged, nine stones/O17 empty, hands clear and user watching. Stop if identity/alignment/current safety fails. Preserve AirPod Pro3 and game clocks.

No hardware/camera/live alignment occurred during installation. App/driver are closed; controller USB absent. The latest0.269 run exited promptly but lacked a verified controller OFF receipt; remaining pointer power-off was requested, not confirmed. Earlier actual OFF1795712291.8697388 is historical only. On the next test, retain stage/cancellation/serial evidence, distinguish raw acknowledgement from accepted OFF, and require a fresh actual full-OFF receipt at the end. Broad physical reliability, recognition and shutdown acceptance remain open.
