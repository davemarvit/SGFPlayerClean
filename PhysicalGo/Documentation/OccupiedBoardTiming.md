# Occupied-board image-processing timing

These measurements concern the host's optical image-registration path. They
exclude native analysis and publication IO and must not be used as the measured
cause of the later 600 ms expiry. See [recent camera-pipeline evidence](CameraFreshnessReliability.md).

Measured November 22, 2026. Offline recordings only; no hardware, live camera, app, saved game or production source was changed. The [integration checklist](IntegrationChecklist.md) owns current installation and physical-test status.

The user’s concern is supported by measurement: an empty-board timing check is insufficient for gameplay. Some archived sparse positions take more than a second to register, while a heavily occupied position with a suitable occupied reference takes about 0.15 seconds. Stone count alone is not a useful latency predictor. Reference differences, lighting, feature matching and dense-alignment convergence affect which processing path runs.

## What was measured

The benchmark calls the actual laser host `point_vision.register`, with the original matched reference and geometry for each recorded operation. It compares the ordinary path with the new `RegistrationReference` cache. The cache is currently used by the calibration runner; the comparison does **not** claim that every production gameplay call already uses it. All matching, foreground, texture and movement thresholds remain unchanged.

Images are decoded before timing. Results exclude PNG decoding, camera capture/publication, native hand/stone analysis, serial transport, audio, motor movement and spot-detection consensus. A successful registration here is not live laser admission. In particular, offline computation on an archived image cannot establish its live freshness.

Each pair had one first call followed by three repeated warm calls per method, interleaved. These are repeated timings of the same pixels, not four independently sampled scenes. “First” means first call for this pair after imports, image decode and cache preparation; it is **not** a cold application/process launch. Maxima are shown instead of estimating p95 from this tiny sample. OpenCV used its existing ten-thread setting; the benchmark process ran at nice 15, sequentially, and was paused during root’s physical calibration.

One cached two-stone sample includes that explicit process suspension (34.958s). It remains in the raw result with `excludedReason` and is excluded from all timing statistics. That method therefore has three valid samples, including two warm samples.

## Main results

Times below are milliseconds. “Move” identifies the recorded game stage; captures mean move number is **not** a stone count. The move-263 image was visually checked and is heavily occupied. Nov21 images are from the app-owned FULL HD WEB CAM setup before the equipment moved; these results do not approve the current physical mapping.

| Archived scene | Ordinary first / warm median / max | Cached first / warm median / max | Registration result |
|---|---:|---:|---|
| empty Nov21 reference self baseline | 108 / 114 / 116 | 83 / 82 / 88 | Accepted, identical transform |
| two stones Nov21 | 1463 / 1290 / 1463 | 1285 / 1361 / 1416 | Accepted, identical transform |
| actual operation move 3 | 1307 / 1229 / 1378 | 1458 / 1267 / 1458 | Accepted, identical transform |
| actual operation move 29 | 122 / 124 / 127 | 95 / 98 / 101 | Accepted, identical transform |
| actual operation move 57 | 1110 / 1240 / 1319 | 1138 / 1255 / 1343 | Accepted, identical transform |
| actual operation move 89 | 158 / 150 / 158 | 123 / 116 / 123 | Accepted, identical transform |
| actual operation move 263 | 144 / 152 / 156 | 115 / 117 / 117 | Accepted, identical transform |
| CaptureContinuation/frame.png | 1422 / 1462 / 1485 | 1334 / 1383 / 1429 | Rejected: foreground coverage |
| A18HandOutline/hand.png | 528 / 600 / 631 | 591 / 563 / 596 | Rejected: foreground coverage |
| A18HandOutline/after.png | 233 / 228 / 274 | 211 / 201 / 211 | Rejected: foreground coverage |

The empty baseline registers the reference against itself; it is a best-case cost baseline, not a fresh empty-board observation. The two-stone case is an existing physical-play regression with its original empty reference. Recorded operations at moves 29, 57, 89 and 263 use their exact archived `setup_id` and that setup’s reference; they are not registered against an unrelated empty board.

The two-stone and move-3 cases invoked dense ECC alignment twice: once initially, then again after masking localized foreground differences. The slower move-57 case invoked ECC only once, so counting refinement calls alone is also insufficient. The crowded move-263 case needed one ECC call and remained fast. No accepted case needed the 12,000-feature fallback in this small set. The capture fixture did need the fallback before rejection.

For all seven accepted pairs, cached and ordinary methods produced numerically identical homography matrices in every repeat. The three rejected pairs remained rejected with both methods. Cache preparation cost 54–149ms per reference and occurs before acquiring the fresh image; it is not included in the registration columns. The cache saves about 25–35ms on the fast accepted pairs, but did not reliably speed up the one-second cases.

The native capture/hand fixtures are a separate camera/setup cohort. `CaptureContinuation` is the November 2 diagnostic’s paired final image/reference. `A18HandOutline` is the November 13 hand-withdrawal regression with its own paired reference. Their coverage rejections show the host’s conservative response to those input pairs; they do not establish a defect in native recognition, a hand-clearance timing result, or a claim that the production bridge would choose those same references.

## Two distinct sources of delay

The laser host registers board texture and detects the optical spot. `point_vision.register` can try 3,500 then 12,000 ORB features, perform up to 70 ECC iterations per refinement, and perform a second refinement after foreground masking. More stones can hide grid/wood texture or change the foreground mask, but stones already present in a good reference can also provide stable features. Lighting and reference age affect this as well.

The app separately performs [camera analysis](../Sources/CameraAnalysisPipeline.swift). Its safety callback is published after grid verification, stone detection, hand-outline sampling and known-empty lighting checks. Later established-stone tracking, aspect checking and display rendering are deliberately outside that callback. Thus later display work is not on this immediate publication path, but earlier stone analysis can affect camera age before the host receives it.

[BoardDetector.detect](../Sources/BoardVision.swift) does substantial fixed work across all intersections, plus conditional geometry/recovery work for stone or uncertain candidates. [StoneGeometry.refine](../Sources/StoneGeometry.swift) fits detected candidates; it changes from one worker to up to four once there are at least eight candidates. [AutoGridDetector.track](../Sources/AutoGridDetector.swift) uses occupied landmarks and exposed rails in different branches. These structures explain why delay need not increase linearly with the number of stones. This audit did not time the native Swift pipeline.

[CameraProcessingCadence](../Sources/CameraProcessingCadence.swift) requests a 0.1s cadence while laser guidance is enabled and skips missed slots rather than accumulating them. That cadence is a scheduling target, not a guarantee that every analysis finishes within 0.1s.

## Consequence for gameplay testing

Keep empty-board calibration as the setup procedure, but assess gameplay separately across sparse, middle-game and crowded positions, captures, glare/reference changes and hand withdrawal. Log capture, native-safety publication, PNG completion, host decode/registration, light dispatch and final pointing times separately. Measure end-to-end image age at the relevant gate as well as component duration.

The archived one-second registration cases are longer than the current 0.6s camera-image lifetime before adding capture/publication cost. They demonstrate a performance issue for any path requiring that **same registered image** to remain fresh through completion. They do not prove that the recent empty-board prelight failure had this cause, nor that every gameplay indication will fail: different call sites and reference-refresh state must be traced. Freshness limits should not be widened to hide the cost.

The call-site distinction is concrete: calibration `optical_permit_until` checks all four ages **after** registration (runner lines 105–112 and 337–347). Existing gameplay runs initial alignment alongside dark motor preparation and can reuse validated alignment in its baseline work (`bridge_hardware.py`, lines 390–434). After baseline processing it deliberately obtains another current clear frame before illumination (lines 442–448). Therefore the archived 1.3-second registrations must not be described as proof of an automatic 0.6-second rejection in every gameplay call. The same-frame evidence contract and the independent live gate need separate timing traces.

Next engineering work should resolve geometry/reference mismatch and perform reference-only preparation before acquiring the frame whose age is critical, while retaining fresh current-image checks and every existing timestamp gate. Reuse must remain tied to verified camera, reference and geometry identity; it must not relabel old processing as new evidence. Instrument ECC duration/convergence and foreground fallback on these exact pairs, then optimize expensive paths without losing their rejection checks. Preserve occupied-reference provenance and revalidation. Add a representative performance corpus rather than treating this ten-pair exploratory measurement as a statistical service-level guarantee. Hand-present images remain stop evidence, not an opportunity to speed through admission.

## Reproduction and provenance

Raw artifacts: `/Users/dave/Documents/SGF PLayer/work/ai-laser-integration/fresh-board-20261122-133741/gameplay-holding-validation/occupied-board-timing`.

- `benchmark.py`: offline runner; sequential, no camera/controller instances or device access.
- `results.json`: all 80 attempted timings, one explicit suspension exclusion, image hashes, source paths, setup IDs, ECC-call counts and ORB feature counts.
- `summary.json`: first/warm/max statistics with the suspended sample excluded.
- `catalog.json`: selected archived operation/setup associations, used by the runner.
- Source SHA-256 before and after: `60d5b98c4c33141f3f5b6c2975eea4deeb3521c78be04cda97ff82f60223ff3d` for `Firmware/point_vision.py`.

No raw recordings were changed or deleted. No production code or thermal/camera limits were modified. No independent cold-process or complete native-pipeline latency claim is made.

## Offline optimization follow-up

An isolated [ROI/ECC prototype](</Users/dave/Documents/SGF PLayer/work/ai-laser-integration/fresh-board-20261122-133741/gameplay-holding-validation/occupied-board-timing/prototype/README.md>) profiles the expensive calls and compares a cropped computation domain across 17 pairs. It remains outside production; the report records both speed improvements and slower negative cases, geometric agreement, and unresolved validation requirements.
