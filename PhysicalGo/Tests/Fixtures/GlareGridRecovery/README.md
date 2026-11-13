# Glare after camera interruption

Twelve distinct, unedited PNG frames sampled from the 23-frame automatic clip
`Diagnostic 2026-11-12 21-12-08 C7EB7F8A`. Original camera capture uptime values
and image SHA-256 hashes are in metadata.json. No repeated image is presented
as a recorded sequence. Anchor grayscale pixels and empty reference are copied
from that clip. The expected twelve stones follow the user-verified thirteen-move
record (White A1 had been captured); image labels are regression expectations,
not calibration inputs that establish occupancy.

The old tracker accepted a slightly displaced grid through its broad known-stone
and exposed-segment checks. Fitting the four exposed outer rails corrects the
remaining few-pixel error without changing the reference, lighting or occupancy
thresholds. Test old and corrected geometry on the same source pixels.
