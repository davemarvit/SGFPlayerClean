# Recording manifest amplification: bounded repair

Base: `be8befe` (root's diagnostics-only 0.270 candidate). This change preserves
recording images, events, original checkpoints, schema and reader-visible fields.
No camera, controller, app, installation or historical archive changes occurred.

## Concrete evidence

The completed `Diagnostic 2026-11-27 00-17-09 7D7916C0` recording contains 1,341
events, 184 images and 48 image-writing gaps. Its `session.json` is 56,372,567
bytes because the initial hand-outline checkpoint contains a 48,841-pixel
background and six temporal references. The first capture-start event also
retains the full checkpoint; it is a one-time event, not a per-frame checkpoint.

The old writer rebuilt and atomically wrote the entire pretty-printed context
on open, every 25 saved images, every writing gap, and completion. This recording
therefore required 57 manifest publications: 1 + 7 + 48 + 1. Multiplying the final
manifest size by that count gives approximately 3.21 GB of logical JSON payload,
not a measured physical-disk write total. The normal 25-to-26 boundaries increase
writer queue delay by about 0.68 seconds. The interval following frame 150 was
much larger. Final frame 184 waited 6.217 seconds while its measured image work
was only 78 ms. `imageWriteSeconds` excludes event append/fsync and manifest work.

A gap event executed on the writer at Unix 1795767468.505962. The following
image, frame 146, reached its writer block at approximately 1795767474.382.
This interval overlaps native camera frames 1866/1867's 524/505 ms analysis and
502/543 ms PNG preparation. The interval includes gap append/fsync, manifest work
and scheduling; it is **not an isolated manifest measurement or proof of the
live stall's sole cause**. Estimated writer start combines producer wall time
with queue duration; the producer timestamp slightly precedes enqueue.

[Source hashes, counts and timing extracts](retained-evidence.json) preserve the
exact recording identity. Original evidence remains untouched.

## Small compatible change

`DiagnosticManifest` encodes immutable context once into a compact JSON prefix.
Each publication serializes only the small changing status/count/time/reason
object and joins it to the prefix. Reserved dynamic fields are removed from the
prefix so there are no duplicate JSON keys. The old dictionary-overlay behavior,
including an initial context reason, is preserved. The writer releases its boxed
static context after successful caching.

Gap events remain exact and ordered in `events.jsonl`, but no longer request a
full manifest rewrite. The existing 25-frame periodic publication and final/abort
snapshots still publish exact counters. For this recording the source-implied
publication count becomes 9. This does not drop a frame, operation, checkpoint,
writing-gap range or shutdown event. No metadata queue cap is introduced.

The retained-data cache occupies 28,087,701 serialized bytes. Each atomic write
still needs an output buffer/file; allocator and filesystem overhead are not
measured. Compact encoding roughly halves this checkpoint's file size. This is
bounded additional cached storage for one session, not a claim of zero memory
or IO cost. The initial checkpoint conversion and capture-start serialization
still occur once; they are not eliminated.

## Reader compatibility audit

No reader changes or migrations are needed. All inspected consumers parse JSON;
none depends on indentation or global key order. Every original context field,
including `handOutlineCheckpoint`, remains inline in `session.json`.

- `DiagnosticArchiveStorage`: unchanged schemaVersion, startedAt, byteLimit,
  status and updatedAt; actual writer locks still protect active sessions.
- `ReplayDiagnosticSession`, `recorded_data_audit`, parallax and visibility tools:
  unchanged recorder, initialSGF, reference/calibration and provenance fields.
- `confidence_audit`: unchanged appVersion/sourceHash.
- `trim_recording_tail`: reads and preserves the dictionary; its later offline
  pretty-print is compatible. No old recordings were trimmed for this work.
- Diagnostic, asynchronous, automatic-capture and cleanup tests read final
  status/counts using the same schema. Gap counts may now lag in the periodic
  manifest until its next existing 25-frame checkpoint; the live UI and gap
  journal retain the current counts, and final/abort counts remain exact.

## Producer paths and limits

`DiagnosticRecorder.value` synchronously JSON-encodes then parses values. At
recording start, `ExperimentModel` uses it for the large tracker checkpoint on
main. During recording, each completed analysis converts two 361-reading arrays
plus smaller diagnostics on main before the existing completion defer drains the
next input. The 553 finished operations occupy about 38 MB of JSONL. New stage
tracing can separate this completion work from worker analysis. The whole-board
recognizer and safety callback run before this completion work; main completion
cost alone cannot be substituted for the measured worker-analysis duration.

Images have bounded admission, but `DiagnosticWriter.event` queues metadata
without an admission bound. Analysis operations continue even when image saving
is full. This can retain metadata behind a blocked writer. This repair removes
the demonstrated gap/manifest amplification; it does not claim to bound every
metadata queue or identify CPU versus filesystem contention in the old incident.

## Validation

The Foundation suite checks old-schema equality across empty/nested/escaped
contexts, all lifecycle states, reserved fields and reason overlays, and immutable
checkpoint encoding. The actual writer suite checks that a recovered gap does
not rewrite the manifest, exact gap ranges survive, final counters/checkpoints
match, and 25-frame, exit and abort snapshots remain correct. Existing diagnostic
and asynchronous writer suites are also run from one shared native runtime.

A finite three-sample retained-context comparison verified whole-document
semantic equality. [Measurements](benchmark.json) are explicitly **contended**
by root's concurrent host validation: old serialization was 3.15–3.21 seconds,
cache assembly 0.054–0.107 ms after one 3.09-second cache preparation. These
exclude file writes and are not uncontended or live performance claims. The
proven result is elimination of repeated full-object serialization, not a
promised camera freshness improvement.

Initial validation checkpoint:

- Foundation compatibility: 25 checks; three full retained-document comparisons.
- Actual writer lifecycle: 16 checks passed.
- Existing asynchronous diagnostics: 131 checks passed.
- Build tools: 8 Python tests passed after adding omitted Tools sources to the
  sparse checkout; the initial missing-file preflight failure was environmental.
- The broader `diagnostic-test` fails on both unchanged baseline and candidate
  under forced `-Onone`: fixed sleeps offer busy frames, and a completed empty
  observation took 1.538 seconds, exceeding the unchanged 1.5-second limit. A
  test-only initial-completion wait also failed on both and was reverted.
- The unchanged broad test is declared optimized; its optimized candidate run
  is pending. Debug failures are preserved in [validation.json](validation.json),
  not hidden by weakening an assertion or changing a production freshness gate.
