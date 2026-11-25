# First-light identity regression

November 24, 2026; PG26b offline coverage, based on installed-source checkpoint
`0628a33`. The authoritative issue status remains in
`Documentation/IntegrationChecklist.md`.

The existing `ai-laser-test` checks first light before settling, repeated receipts,
hand recovery, simulation, hints and a blocked fake audio backend. The independent
`first-light-identity-test` adds cancellation before the first light, superseded
target revisions, wrong producers, stale/future status timestamps, missing
illumination confirmation, and new moves at the same intersection. It also checks
the installed schema2 holding-to-first-light path and late light after cancellation.
Each fixture must publish a real admitted `point` request before rejection cases
run, preventing a permanently disabled fixture from passing accidentally.

Run from the repository root:

```sh
python3 PhysicalGo/build.py --first-light-identity-test --debug-tests
```

Result: **PASS, 19 first-light identity, cancellation and receipt checks**. The
suite compiles 16 source files without the sound backend. No production change
was required by these cases.

Only synthetic request/status files in a unique temporary directory are used.
The suite contains no sound backend, camera acquisition, app lifecycle operation,
or controller communication. Camera frame metadata is synthetic. No device or
audio-output preference is changed; AirPod Pro3 remains untouched.

This coverage does not prove audible playback or controller-beep distinction.
PG26b still requires a root-owned attended genuinely new AI move with the actual
selected output, including retry deduplication. No installation or physical
validation is claimed by this test artifact.

The PG33 feedback candidate has two distinct sounds to recognize during attended
acceptance. Native guidance announces its first positively confirmed
`approaching` illumination, which may be an optical acquisition flash before
aiming finishes; later flashes and settling do not replay that move's stone
click. The host suppresses its separate two-beep cue during those acquisitions
and emits it at final accepted TRACK. The native click is first-light evidence,
not proof of accepted aiming accuracy or audible playback at the headphones.
