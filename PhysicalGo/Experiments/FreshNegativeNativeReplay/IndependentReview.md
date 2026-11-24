# Independent native replay audit

Reviewed November 23, 2026 by the contract-review agent against experiment commit `46b9cdd`. No compilation, app, camera or hardware operation during this final audit.

**PASS:** all 32 raw detector outputs exactly match the committed compact summary's frame counts, labels, heuristic score ranges, local fit counts/centers, manual-point counts and lighting flags. Each episode contains eight frames, not eight independent physical trials.

| Episode | Reading at (14,9) | Reading at (15,9) | Local fitted center |
|---|---|---|---|
| Centered Black | Empty, 1 | Black, 1 | (15,8.96) |
| Centered White | Empty, 1 | White, .8125–.875 | (15,8.76) |
| Displaced Black | Uncertain, .6875 | Black, 1 | (14.56,8.96) |
| Displaced White | Uncertain, .625–.71875 | Uncertain, .5625–.59375 | None |

Archived frame 697's four footprints and zero placement fits match separately and exactly. Every recorded source/input hash, generated input-manifest hash, executable hash and native-results/summary/provenance hash was independently recomputed and matched. Earlier review passed eight temporary-only preflight/integrity checks, with compilation/native execution mocked for those negative controls.

The README correctly limits these results to stateless detector output. They do not establish temporal game acceptance, laser-hint activation, clock behavior or the cause of the White fit displacement. Threshold 0.13 comes from the archived control; matching persisted reference bytes are not a per-frame in-memory reference attestation. No blocking review finding remains.
