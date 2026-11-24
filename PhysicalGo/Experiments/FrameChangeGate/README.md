# Regional change detection — offline feasibility, November 24

A cheap comparison can identify which parts of the Go board deserve expensive
analysis. This experiment is **not connected to the app** and provides no current
occupancy, hand-clearance, clock, placement or laser authority.

The installed camera repair is separate. Root's new native trace measured safety
analysis at median 57.3 ms / p95 60.3 ms in the current scene, with negligible detection
queue delay. There was no sustained backlog after the file-I/O repair. The host
optical feedback loop has different, longer registration timings; those are not
native stone-analysis times and this experiment does not modify that loop.

## What the prototype does

1. Sample only the board area into a 380 × 380 image, 20 samples per intersection
   spacing. Each image uses its own fresh board transform.
2. Blur small sensor/compression noise. Compare local luminance detail and color
   proportions to a **fixed, fully analyzed anchor**. Remove smoothly varying
   illumination from the luminance comparison; ignore unstable color ratios in
   very dark pixels.
3. Flag changed intersection cells, then include their immediate neighbors so a
   stone crossing a cell boundary does not leave a neighboring fit unexamined.
4. Request every cell after a context change. Invalid image-boundary samples
   request work; they never count as unchanged evidence.

This is ordinary background/frame differencing applied locally. OpenCV documents
[background subtraction](https://docs.opencv.org/4.8.0/d1/dc5/tutorial_background_subtraction.html)
and its [MOG2 background model and shadow handling](https://docs.opencv.org/5.0/main_modules/classcv_1_1BackgroundSubtractorMOG2.html).
Our deliberate difference is a fixed anchor: adapting the background on every
frame could absorb a slowly moving object or a newly placed stationary stone.
That is a design inference for this application, not an OpenCV safety guarantee.

## Measurements and limits

The Python/OpenCV prototype took median 8.72 ms, p95 11.32 ms over 40 passes on this Mac.
This includes board sampling, descriptor construction and region comparison;
it excludes image decoding. It is not a Swift pipeline speedup measurement.
`results-20261124.json` records the parameters, image hashes and every case.

| Input | Regions selected, including neighbor margin |
|---|---:|
| Same pixels; synthetic noise σ 2/255; uniform 5% dimming |0/361 each|
| Synthetic smooth 8% shadow |9/361|
| Synthetic 2-pixel camera translation |361/361|
| Actual White insertion in glare |237/361; changed crossing found|
| Actual removal of that White |129/361; changed crossing found|
| Actual White A18 placement |68/361; canonical crossing 17 found|
| Actual White C1 placement sequence |135/361; canonical crossing 322 found|
|30 successive clear-board sample comparisons before/after A18 placement |Mean 56.6/361, range49–69|

Thus the successive clear frames leave roughly 84% of regions unselected. This
is **not 84% less computation**: hand detection, exposure, geometry, image delivery,
shared lighting estimates and other global work still run. Widely separated
photos and lighting changes selected many more regions, correctly reducing the
possible benefit. Unknown shadows request more work rather than being declared
irrelevant.

The recorded tests use original photographs already present in the repository.
The30 successive comparisons reconstruct RGB from the existing quantized native
chroma/light fixture, with its exact 10 samples/pitch, 2-pitch margin. They are
sampling-level evidence, not original full-resolution camera frames. Synthetic
noise, shadows, shifts and stones are labeled explicitly and are never described
as additional physical tests. Historical fixtures do not establish performance
or accuracy for the currently calibrated setup.

Black and White placement/removal, a 0.025/0.05/0.1-pitch shift at center and corners,
region-boundary movement, camera translation, fixed-anchor behavior and context
reset are covered. A looser 8/255 detail threshold **missed** the synthetic
0.025-pitch White shifts. The 6/255 threshold catches them but requests more work
under lighting variation. This was development-set tuning, not held-out
validation; smaller/subtler changes can still be missed.

## Why it is not installed

The current hand checker intentionally uses **this frame's independently fitted
White stone shapes** to avoid treating White stones as a hand. Its source says
history must never supply those masks (`HandOutlineSampling.swift`). Simply
reusing the old full observation would violate that rule. Likewise, an unchanged
region is not a new vote confirming a stone, and an old pre-light observation is
not post-OFF evidence.

A production design would need to keep current hand/alignment/exposure checks,
use the region hints only to schedule expensive recognition, and explicitly
separate cached display data from fresh game evidence. A pending placement,
capture removal, centering correction, hand transition, geometry failure or new
post-dark barrier must force the relevant current checks. Shared lighting or
reference changes can invalidate the whole board. Any skipped computation needs
a measured classifier-dependency contract, not just a threshold that passes these
examples. A periodic full refresh and fixed accepted anchor are necessary
backstops, not substitutes for those rules.

The practical recommendation is to keep this as a measured optional optimization
while the now-stable native camera path is physically exercised. Next useful work
is profiling the expensive detector sub-stages and proving a per-region fresh
verification path; avoid adding this 9 ms gate merely to make a 57 ms path more complex.

## Reproduce offline

Use the existing Python installation with NumPy/OpenCV; no camera or serial
client is created and no live state is read or changed:

```sh
OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 /Library/Frameworks/Python.framework/Versions/3.13/bin/python3 PhysicalGo/Experiments/FrameChangeGate/benchmark.py --output /tmp/frame-change-results.json
OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 /Library/Frameworks/Python.framework/Versions/3.13/bin/python3 -m unittest discover -s PhysicalGo/Experiments/FrameChangeGate -p 'test_*.py'
```

The 7 test methods include the actual fixture transitions and 30 synthetic
placement/removal/subtle-motion controls. No runtime Swift sources, installed
bundle, calibration, game state or hardware behavior change in this branch.
