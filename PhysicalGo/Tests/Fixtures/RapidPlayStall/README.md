# Rapid play and a shifted false white candidate

Source: Desktop “Rapid play stall Physical Go Sample 2026-11-02 00-15-38”,
saved after pausing a 0.29 session. Frame/reference/sample metadata are unmodified.
The frame visibly contains 8 black and 8 white stones. The saved detector output
also claims White at row 15, col 3 (zero based; D4), where printed grid and wood
are exposed. `expected.json` excludes that false stone and preserves all 16 real
stones. The uncertain point N17 remains unspecified.

`observations.jsonl` preserves the first 140 seconds of session
7C5E7B7F-C1DC-47E5-9DD7-BC36622459D5; `original.sgf` is the unmodified eight-move
record. At ~51.8 seconds a weak black candidate at B5 becomes uncertain and blocks
the recorder. Much of its surrounding area was simultaneously changing, so the
candidate should not have the same authority as a repeatedly isolated new stone.
Later frames contain >100 black candidates and many uncertainties. The grid search
at ~76 seconds invalidates the buffered coordinate history. No raw frames from that
interval exist; its physical cause cannot be established from the journal.

Replay with qualified hidden-candidate protection preserves the original eight
moves and adds B[dn], W[cm], B[en], reaching 11 moves around 61 seconds. The remaining
five stones are not safely ordered by this replay and must remain unrecorded.
The initial empty-board preflight is recreated before feeding the original times,
and all journaled vision interruptions are honored. This fixture establishes a
supported prefix, not independent ground-truth video of every physical move.
