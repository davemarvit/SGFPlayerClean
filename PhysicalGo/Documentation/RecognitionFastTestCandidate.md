# Recognition and fast-test candidate 0.257

This isolated candidate combines the narrow ambiguous-intersection guard
(`347eb84`) with reviewed idle fast-test worker reuse (`8c142a2`). Version commit
`47dc15b` sets Physical Go 0.257/build 258. It does not include the broader
experimental overnight architecture, stone-profile or optical correction work.

The ambiguity guard requires fresh neighboring evidence before assigning a new
stone. Fast-test mode can retain a completed, idle engine across an ordinary
Pause/Resume; active work still cancels, and normal opponent settings retain their
existing lifecycle. No physical speed or recognition improvement is claimed yet.

Prior verification on unchanged feature source `8c142a2`: 42 targeted idle-worker
checks, 162 AI-play checks, 278 AI-laser checks and 52 ambiguity checks passed.
This packaging pass also runs the eight build-registry checks and an optimized
full-app compile/signature verification. It does not rerun those feature suites.

The frozen candidate and detailed source/build/binary receipts are stored at:

`/Users/dave/Documents/SGF PLayer/work/ai-laser-integration/stone-session-20261123/app-0257-candidate`

Packaging preserves `PhysicalGoCaptureDirectory` as
`/Users/Dave/SGFPlayerClean/PhysicalGo/Captures`; the isolated worktree must not
become a new recording destination. The established `PhysicalGo/build.py` performs
an optimized build and Developer ID signing. Packaging then changes only that
capture-directory plist value, re-signs with the same identity, copies the bundle
to the candidate directory, and verifies the copied signature and source hash.

The receipt lists all 158 ordered Swift inputs and their hashes, frozen source
copies, build scripts, compiler/SDK identity, before/after input equality, and
final bundle file hashes. The baseline build script does not have the experimental
snapshot build implementation; an external packaging check verifies unchanged
ordered inputs before publishing this candidate. Input identity is not a claim
that mutable runtime recordings or fixtures are snapshotted.

Installation and launching are root-owned follow-up actions. Existing 0.253 and
0.256 bundles, game/clocks, preferences, camera and hardware remain untouched.
The candidate is reversible by selecting the separately retained prior bundle;
this build task performs no deployment or game migration.

## Verified package

The optimized build, source checks and both original/copied bundle signature
checks passed on November 23, 2026. All eight build-registry tests passed.

- Compiled source commit: `47dc15b` (feature code unchanged from `8c142a2`).
- Ordered Swift-source SHA-256: `142bb2374398dbac1df8b445047d703370436ed97aa768c366740d0c4dae4394`.
- Signed executable SHA-256: `4b4d8076dd60772f504d771ac9d84d43604178fce480ed189430086e376cf5af`.
- Canonical bundle-file manifest SHA-256: `51f9a31ead611fee421ca0fd97ae2b45a32c8b20c7cd901cccfb40624c1e76ca`.
- Signing authority: Developer ID Application: DAVID LOREN MARVIT (4H3MZNGDCC).

[Detailed verification](</Users/dave/Documents/SGF PLayer/work/ai-laser-integration/stone-session-20261123/app-0257-candidate/verification.json>)
records the exact signing commands and archive path. Installed 0.253 and retained
0.256 executable/plist hashes were checked unchanged after packaging. Compiler
warnings match the prior narrow build; no compiler error occurred. The frozen
candidate directory is made read-only after its receipts are complete.
