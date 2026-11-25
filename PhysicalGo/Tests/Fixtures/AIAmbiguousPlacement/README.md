# Recorded intersection-assignment regression

Extracted without changing readings or outlines from `Diagnostic 2026-11-23 16-37-13 81D4E9F0/events.jsonl` (SHA-256 in observations.json), installed 0.253/build254. The original recording remains preserved with KEEP.

Frames 445–448 show the legitimate White move at point180. Frames 697–700 show the attended test stone placed between two intersections: the app incorrectly labeled it White at point 275 and accepted a fourth move. White classification was correct; choosing point 275 was not. Its neighbor294 remained uncertain. Both legitimate and incorrect footprints have maximum fitted displacement 0.28, so lowering the global 0.30 threshold cannot distinguish these observations.

The fixture retains all 361 readings, footprints, placementFits, capture timestamps, lighting and hand flags for each frame. It replays the recorded observation boundary through the real PhysicalAI controller. It does not rerun pixel analysis or prove why the outline fit underestimated physical displacement. Controller tests also use explicitly marked synthetic variants for recovery, interruption and edge cases.


## PG-23 controller matrix, November 24, 2026

The focused suite now covers both stone colors with centering hints on and off,
including a preference change while placement evidence is blocked. It checks
that unresolved neighboring crossings preserve the running human clock, saved
history and absence of a pending AI target. Both colors also exercise pending AI
placement with and without a prompt human reply; blocked evidence must preserve
the pending-placement flag and discard earlier confirmation witnesses.

For the Black geometry case, the test explicitly reverses the colors of the
archived White observations and prepends a Black pass to reverse the logical
history. Confidence, outlines, coordinates and frame intervals remain unchanged.
This is a synthetic controller control, not a recorded physical Black placement.
The exact original White observations remain unmodified.

The laser stays disabled in these isolated temporary-game tests. They establish
that the mandatory assignment gate is independent of the hint preference; they
do not validate enabled laser targeting, image classification, or a physical
Black/White halfway-placement test. PG-23 therefore remains open for attended
physical acceptance. PG-10 owns actual centering-target behavior.

Offline result: **156 checks passed** against runtime source `0628a33`. Only the
test runner was rebuilt, using the immutable shared runtime
`042461a3b62061066f190810d77d16832c4bb285e481bf9dd4c7446f1c2b83ba` from the
`camera-safety-delivery` worktree. All 172 runtime source hashes matched that Git
base and all 349 cached artifact hashes verified before reuse. The local runner
command and source hash are retained in
`PhysicalGo/.build/pg23-contract/verification.json` in the
`pg23-ambiguity-matrix` worktree. The ordinary reproducible suite entry point is
`python3 PhysicalGo/build.py --ai-ambiguous-placement-test --debug-tests`.
No app installation or physical test was performed.
