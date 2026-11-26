# Wooden board perimeter profile

The physical wood edge is stored independently from `BoardCalibration` in
`~/Library/Application Support/Physical Go/wooden-board-perimeter.json`.
The printed-grid encoding, camera context and laser calibration remain unchanged.
This is an explicitly measured installation profile, not automatic wood detection.

```json
{
  "schemaVersion": 1,
  "cameraID": "camera unique ID",
  "referenceCalibrationSHA256": "64 lowercase hex characters",
  "referenceImageSHA256": "64 lowercase hex characters",
  "imageWidth": 1920,
  "imageHeight": 1080,
  "boundary": {
    "size": 19,
    "vertices": [
      {"x": -0.6, "y": -0.6},
      {"x": 18.6, "y": -0.6},
      {"x": 18.6, "y": 18.6},
      {"x": -0.6, "y": 18.6}
    ]
  }
}
```

Those example vertices are illustrative, not a measurement for any real board.
Measure TL/TR/BR/BL at the edge of the top wooden surface in an independently
aligned camera frame, then project through that frame's grid transform into
canonical grid coordinates. `referenceImageSHA256` records the measured camera
image's provenance; it need not be the app's empty-board reference image.
`referenceCalibrationSHA256` is the SHA256 of the sorted-key JSONEncoder encoding
of the app's reference grid. The exact bytes are already available by base64
decoding the suffix of its `cameraContext` (after the first slash).

The store reads the bounded profile once during `ExperimentModel` initialization.
Camera processing receives an immutable snapshot; no file reads occur on the
analysis path. A snapshot requires matching camera ID, reference-grid digest,
image dimensions and a valid convex polygon enclosing the outer grid within the
existing two-cell sampling margin. Current independently tracked grid geometry
projects the canonical wood boundary into each image. A present invalid or
mismatched profile produces an unknown hand verdict and an explanatory camera
notice. It does not silently become a clear view. An absent profile preserves
the existing legacy boundary behavior. Installation/replacement requires an app
restart to load the new profile.

`HandOutlineSampling` passes the profile boundary to the outline tracker; pose
fallback uses the same boundary. Pose coordinates are measured with the same
current grid calibration used for outline sampling. The perimeter is not evidence
of hand clearance, stone occupancy, board alignment or a completed move.

## Verification

The focused `--wood-perimeter-test --debug-tests` suite passed 21 checks, including
profile roundtrip; missing, malformed, oversized, wrong-camera, wrong-resolution
and wrong-reference files; crossed polygons; immutable loaded snapshots; unchanged
grid encoding; and unknown early/full pipeline verdicts for invalid configuration.
An optional `PHYSICAL_GO_MEASURED_PERIMETER` path adds validation against the
adjacent retained `wood-boundary-camera/frame.json` and `frame.png` artifacts.
The November 25 measured profile passed the actual Swift loader, reference-grid
digest, camera/dimensions and source-image digest checks.

These tests used the companion `HandBoardBoundary`, `HandMotionTiming` and
`HandOutlineTracker` implementation from the edge-placement branch. Root owns
combined native regression/build validation, package installation and attended
edge/corner/outside-motion checks. No hardware, live app or calibration was
modified by this source work.
