# Frozen Physical Go baseline before architectural changes

Requested by Dave on November 25, 2026. This is a reproducible comparison and
rollback checkpoint, **not a passing gameplay release**. New architectural and
recognition work stays on separate branches; the installed source trees and
immutable host release are preserved.

## Exact installed pair

The annotated tag `physical-go-baseline-20261125-before-architecture` identifies
the actual installed runtime in each repository:

| Component | Revision |
|---|---|
| Native app | `0f9ac752414b12b85dae5e10b161bd7e6de69950`, version 0.264/build 265 |
| Python host | `968ba538d457c03fc34ed0b17b0d59e853817838` |
| Firmware | AimControl v44 + PG08; binary SHA256 `f3e4cd52285eaadd4aa9c5772c232201e6b1f758a275d2669543576343119be7` |
| Host release manifest | `e5a5bda3c013ffc1f9a8a7cd20f11b127d094a83e88c17c98d8140e26d468e34` |

[Machine-readable pins](BeforeArchitectureBaseline20261125.json) include app
source/binary hashes, host manifest, game hash and the direct controller OFF
receipt. The local snapshot at
`/Users/Dave/Documents/SGF PLayer/work/physical-go-baseline-20261125-before-architecture`
contains an APFS clone of the signed installed app, the saved game, launcher,
binding, historical startup-anchor provenance, release manifest and OFF receipt.
The immutable host release itself remains under Application Support. Raw game and
camera data remain local; only metadata and source revisions are committed.

## Preserved physical state and observed failure

The game is paused with eight logical moves, seven physical stones, and White Q17
pending and empty. No game history, clocks or calibration were edited to create
this checkpoint. Recording and warning feedback are off. The final driver exited;
a separate fresh `AimControl v44 OFF` acknowledgement at Unix
`1795596934.1468098` confirmed both beam and motor bus off, with no controller or
close error. There is no active launcher or pending READY prompt. Overnight work
is offline; future hardware activation needs fresh live checks and readiness.

The last attended run was `1795596781138197000`, operation
`1795596851896742000-feedback-86`. It accepted Q17 at 0.103718 cell error in
3.323906 seconds, with zero motor moves. Three optical results passed freshness;
maximum capture age was 0.471306 seconds. Holding then stopped on temporal grid
tracking: median displacement 0.062 pixel but p95 27.330 pixels. Exact failed
frame 57014 and its reference/diagnostics were retained. Independent saved-frame
replay reproduces neighboring-grid aliases; the exposure repair did not establish
sustained physical reliability. The dark-refresh repair was not exercised at the
next refresh before this earlier temporal stop. Illuminated fine correction also
remains physically untested because these Q17 retries had zero moves.

[Final result and OFF evidence](</Users/Dave/Documents/SGF PLayer/work/feedback-play-release-20261124/dark-residual/final-retry/outcome.json>)
are preserved alongside the complete run. The preceding baseline also retains
its distinct dark-refresh failure and exact three-frame batch. Do not replace
these negative observations with the passing offline replay results.

## Validation and open work

- Native 0.264: 379 standby and 263 continuity checks, signed build, paired
  contract acceptance, and physical recovery/indication history.
- Installed host: independently reviewed temporal exposure normalization and
  two-line post-transform dark residual repair. Root ran 97 focused regressions
  and mandatory actual native-to-host-to-native contract checks on this revision.
- The retained original 13 dark-registration controls keep nine accepts and four
  rejects, including covered edge/quadrant. Exact dark-refresh batch passes offline.
- Gameplay remains blocked by temporal correspondence ambiguity. Recognition PG23,
  shutdown receipt PG36, sound semantics PG26b and practical aiming speed remain
  open. A partial successful indication does not close those issues.

Existing offline candidates are **excluded** from this installed baseline:
native placement diagnostics `55c2ba3`, confirmed shutdown receipt `82e1113`, and
any later geometric-consensus or same-light initial-hold experiments. Each needs
its own review, relevant tests and integration evidence.

[Process maps and architectural findings](</Users/Dave/Documents/SGF PLayer/work/physical-go-process-map-20261125/index.html>)
provide the comparison plan. They are documentation, not authorization to bypass
proofs or a claim that proposed changes are installed. The
[issue register](IntegrationChecklist.md) remains authoritative for subsequent
state and installation changes.

## Return to this baseline

Use the tagged source revisions and their frozen worktrees, not the canonical
repositories' older runtime files. Verify the recorded app binary and host
manifest hashes before replacing an installation. The saved launcher pins this
host release and matching app. Restoring software does not authorize motion or
prove unchanged equipment: keep the app paused, establish exclusive controller
ownership, rerun camera alignment, then obtain fresh READY. Do not overwrite a
later game with the snapshot merely to roll back software.
