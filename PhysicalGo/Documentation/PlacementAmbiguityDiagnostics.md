# Bounded placement-ambiguity diagnostics

Source candidate, November25,2026. No installation or physical validation is
claimed. Recognition thresholds, move acceptance and laser admission are
unchanged. This prepares evidence for a recurrence of the R16 delay; it does not
fix that delay.

When `PhysicalAI` rejects `ambiguous_new_stone`, it captures the candidate and its
eight neighboring crossings before clearing placement witnesses. The metadata
includes exact current confidence/occupancy/delta, expected and verified labels,
which neighbor caused rejection, admitted outlines/placement fits or their
absence, raw offsets and assignment offsets, local tracked assignments and manual
flags. Verification distinguishes a restored saved position from a freshly
confirmed board or accepted transition, with camera context and capture uptime.

Initial outline and placement-refinement attempts now retain the best score,
center/radii/offset and rejection reason already computed by `StoneGeometry`.
Reasons include quality below the unchanged minimum, search-boundary radius,
conflicting outlines, no eligible neighbor masks and failed placement
qualification. The receipts do not cover every recovery fitting path and are not
an exact tracker checkpoint. No additional vision pass or fit search is run.
Receipts follow observations through established-stone tracking, known-empty
lighting interpretation and manual preview handling; they remain diagnostic data.

The broker's epoch/frame ID and timestamps are included only when its current
frame has the exact observation capture uptime. A newer or missing broker frame
is explicitly unavailable. Metadata cannot be substituted for fresh optical or
hand-clearance evidence.

## Retention and cost

`AIRecognitionTrace` writes on its existing utility queue. No JSON encoding,
image rendering or disk writes are added to the camera/UI path. The two files in
the existing AI Games directory are:

- `placement-ambiguity.json`: first rejection plus at most seven distinct changed
  reason signatures in the current game/move/generation/camera-context episode.
- `placement-ambiguity-previous.json`: the preceding retained episode.

Confidence jitter alone does not consume another slot. Different candidate,
neighbor occupancy/reason, admitted-geometry state or fit failure reason can
produce a representative event. After eight events a one-time limit flag is
written; first evidence stays pinned. Archive publication is atomic, each file is
limited to2MB, and loaded records are validated against that size/event bound.
Local fit/attempt lists are capped at64 each, with an explicit omitted count.
Restart reloads retained evidence before deduplication. The1200-row rolling trace
continues independently and cannot evict these snapshots. No image recording is
enabled and no raw frame is copied by this feature.

## Offline checks and remaining review

Focused command:

```sh
python3 PhysicalGo/build.py --placement-ambiguity-diagnostic-test --debug-tests
```

The focused Swift subset passed1426 checks when run with the retained R16 fixture.
It tested exact first/change metadata,1400 repeated readings, eight-event/two-file
bounds, restart/rotation, frame mismatch, verification provenance, and actual
1200-row trace eviction. On the later retained R16 camera frame, all361 readings,
admitted footprints and placement fits were exactly equal to the0.264 baseline.
The new receipts identified below-quality outlines for canonical41 and60 and no
eligible masks for their placement refinement. This later image is not an exact
replay of the delayed live frames.

The local `PhysicalGo/.build/r16-fixture` directory in the
`pg23-ambiguity-snapshots` worktree links the retained metadata, frame, reference
and immutable baseline output. Set `PHYSICAL_GO_R16_DIAGNOSTIC_FIXTURE` to that
directory to include the seven real-frame equivalence/receipt checks. Without
that variable, the suite runs1419 synthetic/storage checks.

A controller integration case was added to `--ai-ambiguous-placement-test` to
check pre-reset witnesses, camera identity, verification provenance and unchanged
admission through real `PhysicalAI`. It is syntax-checked but **not yet compiled
or run with the complete native runtime**. The PhysicalAI/Guidance metadata
integration and forwarding edits likewise received syntax checks only. Root owns
the subsequent full native review/build, existing PG-23 regression matrix,
installation and attended validation.

## Stone-count consistency: consideration, not implemented

Dave suggested using the known stone count by color to constrain implausible
extra-stone interpretations. This is recorded for future evaluation only. The
logical board after captures differs from the physical board while an AI stone
awaits placement or prisoners await removal. Pending placements, partial cleanup,
corrections and uncertainty in existing stones must be represented explicitly.
A count cannot determine which intersection owns an ambiguous disk, establish
fresh clearance, or replace independent image evidence. Any future constraint
must preserve those unresolved alternatives rather than fill them from expected
history. This diagnostic candidate adds no count heuristic.
