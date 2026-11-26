# Feedback reliability host release — November25,2026

**Installed offline; no new physical test.** Host `193b10c088cb6b14b28420331e20a706e289cc38` is installed as `193b10c088cb6b14b28420331e20a706e289cc38-app0267`, manifest `e413d55a0eca88547bfed38b9098c50af219ca1c110ca81bea79aa9c4b473e55`. Native0.267/build268 source939106ae20fde41f3a3fb5093a34128dd7b94388 is unchanged; PID21030 remains the sole app. The newly pinned launcher was **not run**. [Final verification](</Users/Dave/Documents/SGF PLayer/work/feedback-reliability-20261125/final-verification.json>) confirms every installed manifest-file hash, the new helper, sole nativePID21030, no serial-port owner and unchanged game files. No app relaunch, camera start, controller operation, calibration or firmware change accompanied this installation.

All AI Games file hashes are unchanged across installation. Setup/model/binding/startup-hint/firmware artifact bytes are unchanged; previous release and launcher are preserved under `work/feedback-reliability-20261125/before-install`. The game remains paused at8 logical moves, with8 user-reported physical stones. **White Q17 is present; native pendingPlacement is still true.** Future attended work verifies that existing placement rather than asking for an empty-Q17 aiming target. Last actual acknowledged full OFF remains1795672713.6296027 from the previous clean run; installation supplies no newer acknowledgement.

## Reviewed fixes

| Fault / source | Implemented boundary | Evidence and limit |
|---|---|---|
| PG06a post-image pose, `c235548` | Use causal actual-session/generation acknowledgement encoders after image collection instead of a redundant serial post-POSE. Preserve scope, causal freshness and actual pose requirements. | Retained frame1605 budget was approximately335ms capture/collection +150ms processing +203ms serial delay =689ms. Baseline budget regression fails;14 new plus67 existing focused tests passed. This is not a replay of the missing failed pixels. |
| PG06a detector, `ac2b1a8` + `5a95218` | Exact mask-crop work, exact seven-frame median network and per-frame read/decode/verification timing. Masks, component ordering and outputs are preserved. |105 focused tests passed; two regressions fail on baseline. Historical image workload:5 frames102.46→46.27ms;7 frames432.62→49.90ms, identical outputs. Requested OpenCV1 thread but reported10; these are offline workload measurements, not live latency guarantees. |
| PG07/PG37 standby completion, `6c11b8f` | Wait for valid completion within the existing2s deadline when an early QG sees transitional standby state. Final holding/cooling and fresh thermal proof remain required. | Unchanged actual firmware reproduces SB interrupted by early QG, intermediate R/B (RN10/BP10), then final H/C.113 host tests and444 firmware assertions passed; baseline fails the focused regression. The bad live reply was not retained, so its exact intermediate phase is unproven. |

Independent reviews `9b7742b` and `75ca27b` approve the changes. No600ms limit, geometry lifetime, illumination deadline or clearance threshold was widened. These fixes address demonstrated offline causes; broad physical reliability remains open.

## Combined validation and receipts

Full host suite: **1,169 tests,57 skipped,1,112 passed, no failures**. Read-only historical fixtures were restored for the run. Initial harness failures were also reproduced on baseline; test-only UUID/preflight-mock corrections were separate from production fixes. Mandatory paired acceptance passed against the exact unchanged native0.267 source/cached receipts and final host193b10c. The actual-firmware standby reproduction was rerun with444 assertions passing.

[Install receipt](</Users/Dave/Documents/SGF PLayer/work/feedback-reliability-20261125/install-receipt.json>) · [Host test log](</Users/Dave/Documents/SGF PLayer/work/feedback-reliability-20261125/all-host-tests-with-fixtures.log>) · [Current release pointer](</Users/Dave/Documents/SGF PLayer/work/feedback-play-release-20261124/current-release.json>).

Next physical acceptance, only in a new attended session with fresh identity/alignment checks and READY: verify White Q17 placement, standby completion and optical freshness tails. Blinking from periodic dark geometry renewal remains a separate PG41 limitation. Preserve metadata trace opt-in `PHYSICAL_GO_LATENCY_TRACE_DIRECTORY`; it is not automatically enabled by installation and adds no images. [Authoritative issues](IntegrationChecklist.md).
