Captured November 10, 2026, Physical Go 0.134 (build 135).
Native camera session: C8C71696-D27B-4AE7-8CA0-DC2E9870AA0A, 635 frames.
The player placed White at canonical G13, removed two of six Black stones,
withdrew for several seconds, then removed the other four in two trips.
The correct move was saved, but automatic capture pause never engaged.

before.sgf is the explicitly synthetic, legal 171-move initialization used
for this arranged-board test, with the final real capture removed.
observations.json retains all 33 journal board classifications from baseline
through acceptance, including every '?' (uncertain) intersection. Times are
journal processing uptimes relative to the first included observation.
The source session and journal SHA-256 identify the original evidence stored
under Captures/Analyses/Capture timing 2026-11-10.

This is a recorder/clock regression, not a vision or interpolation benchmark.
The journal lacks per-point confidence, geometry and capture timestamps:
the test supplies unit confidence, no geometry, and zero processing latency.
Covered frames do not appear in this journal. Within the three gaps shown
as hand-removal trips in the video, the test inserts continuity-only hand
notifications. They cannot confirm a stone or create a capture timestamp.
No classified board reading is changed or generated for the recorded replay.
Additional mutated-board cases are explicitly synthetic safety controls.
