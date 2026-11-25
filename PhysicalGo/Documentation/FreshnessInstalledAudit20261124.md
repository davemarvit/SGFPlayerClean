# Installed freshness repairs and the current optical failure

Read-only audit on November 24, 2026. No app/UI changes, camera acquisition, controller access, installation, protocol change or test execution occurred. Root owns the runtime fix and canonical issue register.

**The earlier background-IO and independent safety-delivery repairs are installed. The latest rejected operation instead exceeded the separate processed-optical-result deadline.** This does not establish that all native delivery stalls are solved.

## Installed-byte evidence

[Machine-readable audit](</Users/Dave/Documents/SGF PLayer/work/feedback-play-release-20261124/freshness-investigation/installed-freshness-inheritance-audit.json>), SHA256 `f163e92f0a7f0166e5253f4944087193a657d001077ea954a8275169b2781f26`, records paths, hashes, comparison results and retained run evidence.

- Installed app: 0.262/build263, source `c53ac0502e920fda5a3ac5b50cba1ec330fdc051`.
- Recomputing the release builder's ordered 173-source fingerprint yields `79960c73c337d906768560ac5dc82a6440ebd8bdad12e119a4a735d483430bd2`, identical to the installed plist.
- Actual installed executable SHA256 is `b7957d160075884e63cf2081702849fd68716738f817dcdc5649694f2b2259f9`, matching the app receipt and host release manifest.
- Native `LatestFileExchange.swift`, `PhysicalLaserGuidance.swift`, `PhysicalLaserFrameBroker.swift`, `CameraAnalysisPipeline.swift` and `ExperimentModel.swift` are byte-identical to `9c516f1`. The first two retain bounded independent read/write queues introduced by `2b7b434`; broker safety publication retains its independent bounded queue.
- Current installed host is `3f5802f5d773e5b5464c3c9f49260a74cf8f7cfd`. All 482 release files match manifest `8a09f68a0e56518f1e597907c2f249b65ba94d31ab039f1b9b4a69f5950f39f2`. Packaged `bridge_gameplay.py`, `bridge_frames.py` and `bridge_runtime.py` are byte-identical to `04b76c7` and the current source checkout.

No lost/reverted IO or safety-delivery repair was found in these installed paths.

## Two distinct 600 ms rejection sites

| Gate | Evidence and use | Installed location |
|---|---|---|
| Camera safety/lease supervision | Independent `safety.json` supplies original capture/arrival/publication times, frame identity, hand and alignment verdict. Cached checks run at command use; clearance never supplies optical pixels. | `bridge_gameplay.py:69–113`, `bridge_frames.py:64–200`; separate supervision thread. |
| Processed optical result | `latest.json` and matching PNGs supply five-frame spot evidence. After registration/detection, a second actual-pose check and response calculation, the newest contributing frame must still be within 600 ms before the observation can enter the anchor cache. | `bridge_hardware.py:182–245`, `bridge_feedback.py:200–229`. |

The second check arrived with feedback gameplay (`f2a7531`, integrated equivalent `b434aa6`). Fresh safety metadata cannot refresh those older optical pixels. Conversely, an optical-result expiry alone does not prove that independent safety metadata was stale.

Native IO queues and safety publication are visible in `LatestFileExchange.swift:8–35`, `PhysicalLaserGuidance.swift:193–211` and `PhysicalLaserFrameBroker.swift:121–167`. The same-frame native analysis callback still passes through the main thread; that remains a possible delay source, not a demonstrated cause of this latest rejection.

## Retained failure comparison

The historical 0.259 bedtime fault reached a cached capture age of 0.601021528 s, publication age 0.214029074 s, with nearby request-write/status-read durations of 136.8/159.5 ms. This supported investigation of scheduling/IO contention; it did not prove one particular filesystem call caused the expiry. Those measurements and the partial repair history remain in [CameraFreshnessReliability.md](CameraFreshnessReliability.md).

The [after-restart run](</Users/Dave/Documents/SGF PLayer/work/feedback-play-release-20261124/first-ai-fault/after-restart-run>) contains three completed acquisitions:

| Request sequence / newest frame | Collection | Median | Registration | Detection stage | Newest-frame age at measurement event |
|---|---:|---:|---:|---:|---:|
| 11 / 1077 | 0.834 s | 0.227 s | 1.632 s | 0.062 s | 2.122 s |
| 14 / 1208 | 0.852 s | 0.215 s | 0.630 s | 0.052 s | 1.169 s |
| 17 / 1324 | 0.771 s | 0.216 s | 0.513 s | 0.043 s | 0.960 s |

All three events say `accepted=true`, `frames=5`, followed by “Optical result outlived the600ms gameplay evidence window.” The event precedes the final pose/response/age check, so these ages are not measurements of the exact exception instant. Collection duration spans several source frames and must not simply be added to the age of the newest frame.

No GOTO/coarse/fine target-travel command appears in those operations. They reached light acquisition and pose checks, then failed before retaining an observation or planning target travel. A fourth operation was cancelled. The durable launcher receipt confirms full OFF at1795581215.1416974.

## Paused native-delivery control

Root's [20-second metadata-only probe](</Users/Dave/Documents/SGF PLayer/work/feedback-play-release-20261124/freshness-investigation/paused-live-delivery.json>) records 351 samples and 201 distinct frames per channel, no errors, with timings sampled after completed reads:

| Channel | Capture-age median / p95 / maximum | Read median / maximum |
|---|---|---|
| `latest.json` | 180 / 228 / 260 ms | 1.66 / 41.9 ms |
| `safety.json` | 148 / 200 / 238 ms | 0.99 / 13.6 ms |

This was a paused app, not sustained gameplay. It supports current delivery functioning in that observed window; it does not prove future tail bounds or rule out simultaneous native contention.

## Fix and diagnostic implications

The measured critical path is host optical processing. Installed `acquire_spot` performs two registrations for the same current batch (`reference→current` and `off→current`), plus median and spot work. `RegistrationReference` is present but has no gameplay call site. Candidate optimization belongs with the assigned optical-performance owner and must preserve actual geometry, same-frame provenance, independent clearance and original timestamps. Threading work off the UI does not by itself reduce the elapsed age of an already captured optical sample.

Both expiry sites currently use `FrameExpired` and become `camera_frame_stale`. Retained status history shows `fresh_after_camera_delay` retries after the processed-result error. This can obscure attribution and repeat identical expensive work. A diagnostic-only proposal is to retain existing recovery semantics while adding an explicit cause/substage such as `camera_safety_age`, `optical_frame_read_age` or `optical_result_age`, with original frame identity, measured ages and stage durations. Any new reason code or recovery behavior requires separate review; none was changed in this audit.

The remaining acceptance is measured frame-to-command age during the actual guarded flow, bounded failure/recovery, and attended gameplay. Neither widening 600 ms nor retimestamping processed images is an acceptable substitute. Earlier repairs remain useful partial fixes; the current operation still fails and needs the separately measured optical-path correction.
