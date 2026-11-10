# Hand Timing Lab

Development-only camera capture, manual labeling and offline evaluation. None of
these tools is linked or copied into the Physical Go release app. The lab never
opens the recording store or changes clock balances.

Build and open:

```sh
python3 Tools/build_hand_timing_lab.py
open '.build/Hand Timing Lab.app'
```

Keep Physical Go paused. Choose the Go-board camera and record 10–30 seconds of
ordinary placements/withdrawals, including slow, fast and diagonal exits. Avoid
moving the camera or changing the lighting within one capture. The lab requests
30 fps at 1080p when supported; **actual frame timestamps and drops determine the
available resolution**, not the requested frame rate. It saves high-quality JPEG
frames (quality 0.95), not lossless images, with a 2 GB limit per capture. The
capture stops automatically. Camera permission is separate from Physical Go.

Captures live in `~/Movies/Physical Go Timing Lab/<session UUID>/`. They are
development evidence outside the app's rotating diagnostics. Delete unwanted
captures in Finder after inspection; they are not uploaded anywhere.

Use the frame slider or arrow keys to find each withdrawal. Mark the last frame
with a hand/arm over the playing area and the first completely clear frame, then
save the withdrawal. These labels are independent of the hand detector and bound
the true crossing; they do not give an exact timestamp. Label several events,
including failures, before looking at the estimator's output. Set the board size
and click the four **corner intersections** clockwise from the top left on a clear
frame. The grid is specific to that capture and camera position.

```sh
python3 Tools/replay_hand_timing.py '/absolute/path/to/capture-folder'
```

The evaluator reuses the production Vision detector and motion estimator. It
runs 5 and 10 fps sampling at six phase offsets plus every saved native frame,
writing `poses.json` and `evaluation.json`. For each manual interval it reports
the estimate, observed bracket, model error, distance outside the manual interval
and whether the model band overlaps it. For scoring, the capture is partitioned
halfway between independently labeled withdrawals. Exactly one estimate in each
window is scored even when it is early or late; matching only overlapping brackets
would hide timing failures. Unmatched or ambiguous transitions stay unscored;
count these failures rather than reporting accuracy only on successes. Sampling
offsets follow a fixed schedule so frame jitter cannot collapse them to one phase.
The native run's `fps: 30` denotes the requested capture rate; it uses every saved
frame even when actual delivery is lower or irregular. Dropped frames widen the
manual interval. A wide interval cannot establish fine accuracy.

The app fits joint motion, not a full hand/forearm silhouette. Joint confidence,
outline allowance, acceleration, shadows and camera/exposure timing can all affect
physical clearance. Its estimated ± error is an uncalibrated engineering estimate,
not a confidence interval. Use the labeled captures to measure coverage and bias
before claiming a particular physical timing accuracy. Offline replay isolates
motion estimation; compare live app journals separately for recognition latency
and clock balance accounting under processing load.

Regression commands:

```sh
python3 build.py --hand-motion-test --hand-clock-test --hand-lab-test
python3 build.py --capture-clock-test --clock-review-test --clock-feedback-test
```

The lab regression sends synthetic camera sample buffers through the actual
image/journal writer, checks timestamp conversion/fallback, frame decode and drop
indexing, and requires no camera grant. For an inspectable fixture, run
`.build/HandTimingLabTests /absolute/path/to/new-fixture` after building the suite.
It is an integration fixture, **not hand-motion accuracy evidence**.
