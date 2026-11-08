# Missed sequence regression

Frozen 29-move recording before user ordering. Current extra detections were
white at source indices 31 and 32, and black at 15 (19x19). Both W31/B15/W32
and W32/B15/W31 are legal and produce the same final board, including a capture.
Neither ordering is a human-confirmed label. Tests exercise both on temporary
copies and never modify the live recording.
