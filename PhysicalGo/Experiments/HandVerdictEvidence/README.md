# Saved hand-verdict evidence — November 24, 2026

**The exact stop is not reproduced.** The saved image is frame 59446, captured
2.008 seconds before missing rejected frame 59466. It shows an empty board, a
laser spot, lower-board glare, and surrounding fabric/furniture. It cannot show
whether anything entered the scene during the following two seconds.

The host records show frame 59465 clear and frame 59466 obstructed **112 ms later**,
both with valid alignment. This is distinct from the earlier 800 ms gap that
produced unknown clearance. The final receipt in this attempt is `AimControl v44
OFF`, `off_since_unix=1795552619.3439188`, without controller error. Root retains
all physical ownership. The earlier user-confirmed obstruction in source d92e6a8
is not treated as evidence for or against this event.

## Offline result

The small [snapshot probe](../../Tools/ReplayHandSnapshot.swift) used the existing
compiled native regression module, whose library and manifest hashes are in
[provenance](provenance-20261124.json). No app rebuild, install, launch, camera,
desktop image, audio, serial, or live bridge access was involved. Original images
were read without modification and are not copied into Git.

| Input | Vision pose | Final hand verdict, three repeated target evaluations |
|---|---|---|
| Saved spot097 / frame59446 | Zero hands; reliable result | Clear, clear, clear |
| Existing A18 photographed placing-hand control | Obstructing hand detected | Obstructed, obstructed, obstructed |

The saved target's laser spot and visible glare/fabric did not produce an
image-level false positive in this probe. The positive control demonstrates that
the probe exercises the hand gate. Neither result establishes the content or
correct classification of missing frame59466.

This is a **snapshot diagnostic**, not a temporal replay. Four repetitions of the
saved reference initialize a synthetic clear baseline, followed by three repetitions
of the target at synthetic 200 ms intervals. The first three baseline results are
unknown, as required by the existing initialization behavior; the fourth is clear.
The native calibration was extracted from the stop manifest. The application
default threshold 0.13, an empty expected board, and fresh tracker state are explicit
assumptions. The live native reference/threshold, lighting state, expected position,
and tracker history were not saved here. Native grid tracking, aspect estimation,
and rectification are disabled for the probe; no alignment qualification follows.
Apple Vision runs on the current OS rather than replaying a historical model output.

## How a positive verdict can arise

Source entry points:
[BoardHandDetector](../../Sources/BoardHandDetector.swift),
[HandMotionPose](../../Sources/HandMotionTiming.swift),
[HandOutlineTracker](../../Sources/HandOutlineTracker.swift), and
[pipeline](../../Sources/CameraAnalysisPipeline.swift).

- Vision requests up to four hands, retaining joints with confidence ≥0.25. A
  reliable pose requires at least eight retained joints in each detected hand.
  An obstructing hand needs only one qualifying joint inside the grid plus its
  0.75-pitch perimeter margin. A real hand near an outer intersection can therefore
  legitimately block even without covering the playable center of a cell.
- After a clear baseline exists, unchanged rim evidence can suppress poses wholly
  beyond an outer grid line. A pose inside the grid always blocks.
- A previously inactive outline tracker becomes active from a positive hand-pose
  cue. Foreground changes from a shadow or red spot do not independently activate
  it. They could still matter if Vision misidentifies them as a hand, or after an
  already active track needs visual clearance.
- Once active, the outline tracker uses current color/texture differences and
  boundary evidence; pose loss alone is not clearance. It requires two clear views
  to confirm exit. Thus a retained obstruction can have a different cause from
  the initial hand entry.
- Gaps over 650 ms reset the tracker to unknown initialization. A positive
  obstruction is not interchangeable with missing/unknown hand evidence.

The last clear manifest alone does not expose the internal pose/outline path.
A brief real entry, a pose false positive, and other state-dependent paths remain
possible. No confidence, rim, clearance, or freshness rule was changed.

## Evidence needed on the next event

Root's post-OFF exact rejected-frame retention is the appropriate next step.
Preserve the exact immutable image plus the matching original manifest/epoch/frame
ID, capture/arrival/publish timestamps, and reason. If the file has already been
pruned, record that fact; do not substitute an earlier image as the rejected frame.

To distinguish a Vision false positive from a retained outline track, a future
native diagnostic should additionally retain the matching pose/joints/confidences,
`HandOutlineTracker.Result` (especially reason, poseLost, edge and depth), and the
**pre-observation** tracker checkpoint/background. Record native calibration,
reference identity, threshold, lighting/expected-board state, and intervening
capture timestamps. Exact pixels can test a pose hypothesis; reconstructing an
outline decision requires the original temporal state. Such retention should be
bounded, asynchronous and subordinate to the immediate OFF path. This branch adds
no runtime recording or policy change.

## Reproduce with an already built regression module

`ReplayHandSnapshot.swift` intentionally imports the app's shared regression module,
so it uses the actual detector rather than a duplicate implementation. Provide an
existing `PhysicalGoTestRuntime.swiftmodule` and its matching dylib directory:

```sh
runtime_path=/absolute/path/to/the/matching/regression/runtime
xcrun --sdk macosx swiftc -swift-version 5 -target arm64-apple-macosx14.0 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" -Onone -parse-as-library \
  -I "$runtime_path" -L "$runtime_path" -lPhysicalGoTestRuntime \
  -Xlinker -rpath -Xlinker "$runtime_path" \
  PhysicalGo/Tools/ReplayHandSnapshot.swift -o /private/tmp/ReplayHandSnapshot
/private/tmp/ReplayHandSnapshot input.json output.json
```

The checked-in input/report pairs preserve the assumptions and image hashes.
Both probes completed; assertions verified all three saved-target evaluations clear
with zero detected hands and all three known-hand evaluations obstructed. Repeated
photographs are not independent validation samples. No installed behavior changed.
