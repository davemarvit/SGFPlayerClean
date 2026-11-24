# Recorded intersection-assignment regression

Extracted without changing readings or outlines from `Diagnostic 2026-11-23 16-37-13 81D4E9F0/events.jsonl` (SHA-256 in observations.json), installed 0.253/build254. The original recording remains preserved with KEEP.

Frames 445–448 show the legitimate White move at point180. Frames 697–700 show the attended test stone placed between two intersections: the app incorrectly labeled it White at point 275 and accepted a fourth move. White classification was correct; choosing point 275 was not. Its neighbor294 remained uncertain. Both legitimate and incorrect footprints have maximum fitted displacement 0.28, so lowering the global 0.30 threshold cannot distinguish these observations.

The fixture retains all 361 readings, footprints, placementFits, capture timestamps, lighting and hand flags for each frame. It replays the recorded observation boundary through the real PhysicalAI controller. It does not rerun pixel analysis or prove why the outline fit underestimated physical displacement. Controller tests also use explicitly marked synthetic variants for recovery, interruption and edge cases.
