Recorded Physical Go 0.142 incident, 2026-11-11, Black moves 65–67.

observations.json retains classifications, source capture timestamps, hand states,
and available hand-clear estimates from the automatic diagnostic clip. The legal
targets are replayed from the saved SGF, not claimed as camera ground truth.
A 0.73-second sampling gap restarted the outline detector; three subsequent fresh
frames had unknown hand status. ClearBoardTiming incorrectly ignored those frames
for continuity and discarded its earlier history when clearance returned after
1.63 seconds. Black65's press was lost, so neither Black65 nor White66 was applied
to the clock. The former catch-up fallback kept charging Black across all turns.

Outline/ contains only production-sampled 221x221 color/luminance features from
saved full-resolution frames 12–40, plus saved poses where present and offline
Vision poses for other saved frames. Features use the same quantization format as
Fixtures/HandOutline. Sampling is at the recorded cadence, without interpolation.
Independent visual labels: frame 27 at 849483.3933602086 still contains a hand;
frame 28 at 849483.8266102921 is clear. These labels are used only for assertions.
The old outline tracker attached itself to a lighting change with hand-like color.
Its live clock estimate was 849486.4261202293, 2.60 seconds after visible clearance.
A replay from frame 12 could remain blocked even longer because its clear reference
was slightly different. The regression requires one exit with an uncertainty band
intersecting the visual bracket and no early clearance while the hand is visible.

The full diagnostic clip and original game/clock snapshots remain in the local,
ignored Captures/Analyses/Black byoyomi move 65-67 2026-11-11 folder.
