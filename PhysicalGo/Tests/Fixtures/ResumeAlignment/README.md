# Occupied-board restart, 2026-11-11

`frame.png` and `sample.json` were captured through Save sample from the live
camera while the older 0.120 copy was asking to show the whole board. All four
printed outer rails are visible. The saved calibration precedes a camera shift.
`game.sgf` is the user's paused 67-move recording; `expected.json` is its replayed
62-stone position. `corners.json` contains independently estimated printed corner
pixels, clockwise from the image's top-left, for geometric assertions.

Before the fix, recovery with the saved position returned no grid: additional
projection peaks from stone edges exceeded the generic empty-grid allowance.
Saved-position recovery now permits those extra peaks, still requiring the full
printed lattice, outer rails, spatially distributed matching stones and an
unambiguous orientation. The image verifies 61 of 62 known stones. It is not a
claim that every physical placement exactly matches the recorded position.

Run `--resume-alignment-test` for this image, absent prior calibration, reversed
stone colors, a cropped board and wrong board sizes. `--session-resume-test`
also checks normal session restoration before model-level reacquisition, without
starting clocks or rewriting moves.
