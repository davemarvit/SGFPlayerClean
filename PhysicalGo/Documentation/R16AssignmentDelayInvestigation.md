# R16 assignment delay: retained-frame investigation

November 24, 2026 Pacific. **No runtime fix promoted.** This report documents a
negative offline geometry experiment against installed native source `0f9ac75`
(app0.264). PG-23 remains open. Hardware, app controls and installed files were
not accessed or changed by this investigation.

## Established delay and limits

PG-16's retained native trace attributes the Black R16 (canonical41) delay to
placement confirmation:255 fresh observations over25.418 seconds after hand/dark
recovery,130 ambiguity resets,124 stable waits and final acceptance. Neighbor59
was usually EMPTY with confidence.75 or.7778, below the existing.8 neighbor gate;
it had already appeared weak-EMPTY in157 of326 earlier board-confirmed frames.
Some later frames instead called it uncertain, which remains distinct evidence.
Capture ages were median122ms/max151ms, with no processing backlog indicated.

The trace does not retain raw pixels, footprints, placement fits or a complete
tracker checkpoint. It cannot prove that a geometry-based exception would have
accepted the delayed frames. Source evidence is under
`work/feedback-play-release-20261124/arming-episode-0264/recognition-attribution`
in Dave's SGF PLayer workspace. PG-16's analysis owns the exact event accounting.

A later retained camera-only frame, `post-texture-fault-board.png`, was captured
at1795591929.286429, after R16 acceptance. The reference archive saved at
2026-11-25T07:18:50.422768 UTC has exactly matching camera/current/reference
calibration identities. The offline detector used threshold.13 and that saved
reference, without reconstructing the historical live tracker state.

## Finite hypothesis and result

Current placement-only refinement permits provisional exterior masks for White
clusters. The experiment applied that same mechanism symmetrically to Black
neighbors. It retained existing body coverage>=92%, visible exterior>=50%,
disjoint-interior checks, ordinary minimum fit quality.78 and strong placement
quality.90. It did not change occupancy thresholds or the AI neighbor gate.

| Canonical point | Reading | Ordinary outline quality | Masked outline quality |
|---|---|---:|---:|
|41 (new Black)|Black,.9666667|.7307114|.7389170|
|60 (adjacent Black)|Black,.9655172|.7216001|.7385464|
|59 (neighbor)|EMPTY,.75|No outline|No outline|

Neither Black outline met the unchanged.78 minimum; neither produced a placement
fit. All361 readings were exactly equal between baseline and experimental
pipelines. Estimated centers near the intended intersections do not compensate
for failed boundary evidence. The geometry experiment therefore does not justify
an exception to the neighbor gate, and no runtime change was made.

In particular, `assignmentOffsets[41] == nil` means missing geometry; it must not
be treated as a zero offset or a unique assignment certificate. The historical
halfway regression also underestimated displacement at.28cells, so strong color
or a permissive offset threshold alone cannot restore safe assignment. Previous
verified empty labels are not fresh proof of a newly placed stone.

## Reproduction and provenance

`Tools/replay_touching_black_assignment.py` verifies every source and artifact
hash of an explicitly supplied immutable shared runtime, compiles only diagnostic
runners, and evaluates baseline and experimental detection on one saved frame.
It refuses mismatched calibration identities and writes all generated files to
a new output directory. It performs no camera acquisition or installation.

Example from the isolated `pg23-verified-empty-neighbor` worktree:

```sh
python3 PhysicalGo/Tools/replay_touching_black_assignment.py \
  --runtime /Users/Dave/SGFPlayerClean-worktrees/arming-episode-release-20261124/PhysicalGo/.build/RegressionModules/runtimes/e076ce4cec2f4b22fe55b9101691277814563e017cb17df01e09fbd8995b7f48 \
  --metadata '/Users/Dave/Documents/SGF PLayer/work/feedback-play-release-20261124/arming-episode-0264/post-texture-fault-board.json' \
  --frame '/Users/Dave/Documents/SGF PLayer/work/feedback-play-release-20261124/arming-episode-0264/post-texture-fault-board.png' \
  --reference-plist '/Users/Dave/Library/Application Support/Physical Go/EmptyBoardReference.plist' \
  --output /tmp/r16-assignment-replay-unique-output
```

The completed reproduction is retained at
`PhysicalGo/.build/pg23-r16-reproduction` in that worktree. `report.json` contains
commands and input hashes; baseline/candidate JSON retain all readings and
admitted fits. `candidate.log` includes rejected fit scores.172 runtime input
hashes matched source0f9ac75;349 cached artifact hashes verified. Raw input hashes:

- Camera PNG: `3fb132480aa848f858f2f6a43cdee48827057a129c816365e51c703b91d92a2b`.
- Frame metadata: `f1f6990877d9c0115011c559d47ad9948c5a97591f06c0ddab9e80606a42296a`.
- Reference archive at investigation: `7a3105354138f564a09535574ceeec53459f2c8b9107a1598f0b0a0788eda09e`.

The live reference archive can change later; use retained `reference-archive.plist`, extracted PNG and
provenance receipt for this exact result. No physical timing improvement is
claimed. A future candidate needs fresh independent target geometry or an
independent empty-neighbor certificate, exact affected-frame evidence, and the
existing both-color/hint/halfway regression matrix before integration review.
