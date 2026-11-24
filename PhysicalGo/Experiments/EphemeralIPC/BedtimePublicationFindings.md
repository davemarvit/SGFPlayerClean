# Bedtime publication evidence — November 24

This is retained evidence from the earlier bedtime run. Later 0.260 installation
adds instrumentation and recovery changes, but has not established that camera
expiry is solved. See [current findings](../../Documentation/CameraFreshnessReliability.md).

The recording supports a delay **after the native safety calculation**, with a
short simultaneous increase in recognition and background file-I/O time. It does
not establish that fsync caused the stop. A later hand-triggered interruption is
separate and occurred with normal image-delivery timings.

Source recordings are `gameplay-activation-20261124/bedtime-play-20261124-023109`
and the startup sibling `bedtime-play-20261124-022905`. The original PNGs and
metadata were read only. App 0.259 and host f45b5e6 were recorded; the ephemeral-IO
candidate was not installed. No benchmark/compiler was running during capture,
according to the hardware owner. This is not a claim that macOS had no other work.

## Matching method and coverage

`analyze_publication_recording.py` deduplicates manifests by epoch/frame identity,
then matches capture uptime to native safety event uptime minus its recorded
capture age. The main recording matched 1,025 of 1,111 distinct sampled manifests,
with median matching error 6.6 µs and maximum 36.5 µs. The first 86 manifests precede
the retained native safety trace, which starts at Unix 1795516281.571694. Native
trace counters show no dropped events or writer failures in retained events.
No mutated manifest identity was found in either recording.

| Main recording metric | Median | p95 | Maximum |
|---|---:|---:|---:|
| Capture → manifest timestamp |133.2 ms|170.0 ms|387.1 ms|
| Native safety callback → manifest timestamp |19.3 ms|33.6 ms|237.6 ms|
| Native safety analysis |60.1 ms|67.1 ms|173.6 ms|
| Native main-thread delivery |0.050 ms|0.076 ms|16.25 ms|
| Native analysis queue |0.023 ms|0.044 ms|8.80 ms|

In the startup recording all 270 sampled manifests matched. Capture→manifest
median 142.4 ms/max 296.0 ms; safety→manifest median 32.5 ms/max 192.2 ms. Analysis remained
near 58.5 ms median and 65.2 ms maximum, with main delivery below 0.64 ms. This separately
shows post-analysis publication variation while analysis itself remains steady.

## First freshness interruption

The first observed fault status is near Unix 1795516283.1 (02:31:23 Pacific).
Two precise recorded pairs are:

| Frame | Capture Unix | Safety callback Unix | Manifest timestamp Unix | Safety → manifest |
|---|---:|---:|---:|---:|
|27828|1795516282.249032|1795516282.410451|1795516282.618556|208.1 ms|
|27830|1795516282.472038|1795516282.621425|1795516282.859038|237.6 ms|

The machine-readable report retains exact values. During this interval main
safety delivery was approximately 0.05 ms; moving that callback off main would
not address this recorded bottleneck. Analysis briefly rose to 137 ms and 174 ms,
while background status reading reached 159.5 ms and request writing 136.8 ms.
The existing installed trace cannot split broker waiting, encoding, PNG writing,
manifest writing and pruning. The candidate stage trace does.

Do not infer an exact expiration gap solely from the sampled frame IDs. The
recorder can omit intermediate publications, and the host's cached supervisory
frame may differ from the latest manifest. Precise fault attribution also needs
the host's failed frameID, cached-check age and capture/publication ages.

There are 24 main-recording rows (34 startup rows) whose manifest timestamp is
later than `observedAtUnix` by more than 1 ms. The recorder sampled that timestamp
**before** its file reads. It is not a post-read freshness clock. Likewise,
`publishedAtUnix` is sampled before manifest encoding/write/rename and is not an
exact visibility timestamp. No “future frame” or freshness breach is inferred
from those recorder rows.

## Later hand interruption

Frame 27974, captured at Unix 1795516296.861350, is marked hand-obstructed; frames
through 27979 agree. Frame 27987 at 6298.162371 is briefly obstructed again. The
corresponding capture→manifest times are roughly 127–161 ms, not another measured
publication stall. The request changes toward standby/OFF for hand clearance.
Root's host/recovery investigation owns the subsequent transition behavior.

Visual inspection of original PNGs 27974 and 27987 shows a hand reaching beside
the right board edge/stone bowl. No intersection is visibly covered in these two
photos. Frame 27974 still shows the laser spot; frame27987 does not. This supports
a real nearby-hand episode or conservative perimeter check. It does not justify
calling all hand detections false positives or weakening the hand boundary.

## Recommendation

Keep the diagnostic stage trace and tested bounded cleanup changes as a candidate;
collect an actual recurrence with those measurements before naming a file-I/O
operation as the cause. The no-fsync helper has a valid transient-IPC contract but
has not demonstrated a speedup. Preserve all capture-age, request-lease, OFF and
same-frame evidence checks.

Do not change PNG filtering: correctly nested filters were lossless but slower
or neutral. An additional opaque-RGB view of an actual recorded frame reduced
PNG size from 3.18 MB to 2.80 MB but increased median encode time from 72.8 ms to 114.8 ms;
it was not adopted. These measurements argue against speculative encoder tuning.

Do not prioritize regional recognition caching or broader camera-thread ownership
as the fix for this event. Current evidence points to publication/host supervision
and transition behavior, with native recognition normally around 60 ms. The source
candidate passes 43 writer assertions, 49 broker checks, 283 AI lifecycle checks and
the asynchronous exchange tests; installation and physical validation remain
separate work owned by the root integration session.
