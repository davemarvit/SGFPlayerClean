# Native detector replay of fresh misplaced stones

November 23, 2026. **Stateless detector evidence, not a live move-acceptance test.**
This diagnostic compiles the unchanged native `BoardDetector` dependency closure
from narrow ambiguity baseline `347eb84` and reads saved images only. No profile
correction, altered color threshold, app launch, camera, controller or hardware
operation is involved.

Before interpreting the fresh examples, it reproduces the actual archived frame
697's four footprints and zero placement fits exactly, comparing the categories
separately. That control includes the earlier correctly colored but incorrectly
assigned White stone. All 32 fresh/centered samples then replay successfully;
source and input hashes remain unchanged across compilation and execution.

## Observed side-middle results

Coordinates are raw camera `(col,row)`, zero based. The moved stone came from
`(15,9)` toward `(14.5,9)`; it was a fresh negative episode at a previously fitted
location, not the preselected held-out location. Each row below summarizes eight
distinct camera frames of one placement, not eight independent physical trials.

| Saved episode | Reading at `(14,9)` | Reading at `(15,9)` | Native fitted center |
|---|---|---|---|
| Centered Black | Empty, score 1 | Black, score 1 | `(15,8.96)` |
| Centered White | Empty, score 1 | White, score .8125–.875 | `(15,8.76)` |
| Displaced Black | Uncertain, score .6875 | Black, score 1 | `(14.56,8.96)` |
| Displaced White | Uncertain, score .625–.71875 | Uncertain, score .5625–.59375 | No local footprint or placement fit |

The centers and reading labels in this table are identical across each episode's
eight frames. Scores are existing heuristic separations, not probabilities.
Neither lighting-blocked nor manual-point flags are set in these detector outputs.

These results separate three questions:

1. **Class/occupancy:** the Black negative has a confident Black reading at one
   crossing but unresolved neighboring occupancy. The White negative has two
   unresolved crossings.
2. **Visible fitted center:** the Black negative has a clearly displaced native
   fit. The White negative supplies no native fitted outline in this local area.
   The centered White fit also remains above its declared grid intersection.
3. **Game/laser action:** this replay does not execute temporal tracking,
   `PhysicalAI.consume`, history stabilization, clocks or hint dispatch. It cannot
   claim that a move was accepted/rejected or that a centering marker would fire.
   In particular, spatial abstention does not by itself provide a usable marker
   center. The independent full-boundary experiment also has shadow-identity
   failures and must not fill this gap automatically.

## Evidence and reference limits

`run.py` checks all sample hashes, exact frame payloads, globally distinct frame
identities, eight samples per case, explicit clear/aligned flags, camera identity
and reference calibration. It passes **each frame's own current calibration** to
the native detector, preserving the small grid updates in the midpoint captures.

The archived reference PNG exactly matches the PNG in the supplied persisted
`EmptyBoardReference.plist` snapshot (SHA256
`cdc8d10f006fe81fec510f06ab212a75e6b39e412e7d14cdddcf9f0b70a4c268`).
Root also checked the retained pre-install backup has that identical PNG. This
is strong persisted-reference correspondence, not a per-frame attestation of the
app's in-memory reference: broker metadata lacks that image hash.

The threshold is the archived control's **0.13**, explicitly retained in inputs.
Fresh broker metadata does not supply threshold, so this is not represented as a
fresh preference read. The replay excludes later temporal tracking, hand logic,
appearance adaptation outside this detector call, and app/controller decisions.
Archived control parity bounds the replay correspondence; it does not prove
complete source equivalence for every installed subsystem.

Full images, metadata, native outputs, source/build/input hashes and control result
are local under:

`/Users/dave/Documents/SGF PLayer/work/ai-laser-integration/stone-session-20261123/stone-set-calibration/native-fresh-replay-01/`

## Reproduction

```sh
python3 PhysicalGo/Experiments/FreshNegativeNativeReplay/run.py RECORDING_DIRECTORY STONE_SAMPLE_DIRECTORY NEW_OUTPUT_DIRECTORY --reference-state SAVED_REFERENCE_PLIST
```

The sample directory must contain `black-01`, `white-01`, `black-midpoint-01` and
`white-midpoint-01`, each with its recorded `samples.json`. The recording supplies
archived frame 697 and its reference. The output directory must be new. The tool
hashes ordered native sources, refuses changed evidence, and preserves failures
instead of presenting an incomplete run as a pass.

Independent review exercised eight bounded preflight/parity integrity controls:
valid data, unknown hand, nonboolean alignment, empty capture, duplicate frame,
wrong reference PNG, swapped footprint categories and changed generated input.
Actual native execution subsequently passed the archived control and all 32
saved samples. No physical or production correction is claimed.
