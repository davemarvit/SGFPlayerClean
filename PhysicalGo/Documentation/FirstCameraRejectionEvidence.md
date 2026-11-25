# First camera rejection evidence

PG-21 candidate, November 24, 2026. This is implementation documentation;
`IntegrationChecklist.md` remains the acceptance and installation register.
Native compilation and the extended regression are pending the coordinator's
combined optional-runtime test slot. This candidate is not installed or
physically verified.

When an explicitly enabled diagnostic recording receives its first fresh
camera analysis with a hand obstruction or failed requested alignment check,
`ExperimentModel` sends that exact camera image and its pre-analysis hand
tracker checkpoint to `DiagnosticRecorder`. Stale analysis, a changed model
revision, and results belonging to an earlier diagnostic session cannot claim
the new session's evidence slot. Recording being disabled remains disabled.

The archive's `first camera rejection` event links the lossless camera image,
the original reference image when available, the original alignment anchor's
gray pixels and geometry, and `assets/first-camera-rejection-hand.json`. It also
records the alignment report, separate hand verdict/pose/outline reason,
before/after calibration, exposure and lighting flags, and original camera
frame identity/timestamps. The checkpoint is captured **before** submission to
camera analysis. Exact temporal replay requires the complete checkpoint from
PG-03 (`56e8740`); historical partial checkpoints are not exact replay state.

Only one rejection is retained per explicit recording session. One extra
bounded writer slot allows that first frame to survive a full ordinary image
queue. Checkpoint/anchor serialization and image encoding run on the existing
background writer queue. Storage limits, disk failures, and archive retention
policy still apply: this is not a promise of storage after a write failure.
Later faults cannot replace the initiating frame, and stopping recording does
not wait on camera analysis to manufacture another fault capture.

`captureUptime` uses the native process monotonic clock. `time` is native wall
time when the archive work was enqueued. Neither is a controller acknowledgement,
observed beam onset, audio onset, or a synchronized cross-process measurement.
Existing original camera timestamp/source fields remain separate.

The regression extends `AsyncDiagnosticsTests` with disabled/stopped recording,
a blocked writer with a full ordinary queue, immutable checkpoint capture,
background encoding, later-fault rejection, raw image/reference and reason
retention, old-session rejection, and explicit-session reset. It uses synthetic
images only. No app, camera, controller, or physical acceptance is involved.
