# Offline validation — November 23, 2026

Branch `codex/attended-capture-kit`, based on `8c142a2`. No app source changes,
installation, camera, laser, audio, preferences or live saved-game writes.

## Results

- **34 real Goengine legal checks pass:** four alternating legal opening moves,
  Black to move, vacant capture point, legal fifth move, exact White prisoner set,
  capture counters, remaining stones, and out-of-order removal reaching the legal
  post-capture board. Sources are the unchanged repository `OGSModels`,
  `OGSScoringState`, `SGFPlayerEngine`, and `PhysicalAITiming`.
- **20 actual controller checks pass:** decode real `PhysicalAI.Snapshot`, verify
  Fast test mode=true, restore paused through `PhysicalAI(directory:)`, recognize
  the four-move position, accept the human fifth move, create capture context,
  keep the single-capture clock running, hold two-stone/partial cleanup, persist
  out-of-order removal and release after all prisoners disappear.
- Controller checks used **synthetic observations and injected AI generation** in
  newly copied UUID temporary directories, deleted afterward. They did not use
  camera images or physically validate recognition, spot accuracy or clearance.
- Final artifact hashes remain identical after controller checks. Existing output
  and Library/application-support output are rejected before generation. No
  observed move timestamps, verified camera context or capture timestamp is
  inserted into either four-move snapshot.

## Final artifact set

`/Users/dave/Documents/SGF PLayer/work/ai-laser-integration/attended-capture-kit-20261123/validated-fixtures`

Contains `manifest.json` and two dedicated folders, each with `current.json` and
`reference.sgf`. The manifest records exact grids, each partial-removal case,
unique synthetic session IDs, source SHA-256s, file SHA-256s and generation
provenance. The generation date is artifact metadata, not move history. Its
source commit is the base HEAD at generation and `sourceWorkingTreeDirty=true`
explicitly records the new experimental generator files; source hashes identify
the actual inputs.

The adjacent `RUN_CARD.md` is the attended operator card. Both real preserved
checkpoints remain untouched. Fixture activation is a separate attended decision;
no installed AI SGF-import/fixture picker exists.

## Reproduce

Generate a new folder using `generate.py` as described in README. For controller
validation, use an existing reviewed testable runtime; no full app rebuild is
needed. This run reused runtime:

`/Users/dave/SGFPlayerClean-worktrees/fast-test-idle-reuse/PhysicalGo/.build/RegressionModules/317e5eab27b903a5775048ee4d8f16d9026211d06390d078bacd342ae6bc2ead`

```sh
CAPTURE_RUNTIME=/absolute/path/to/reviewed/RegressionModules/hash
swiftc -parse-as-library -swift-version 5 -D PHYSICAL_GO -target arm64-apple-macosx14.0 -I "$CAPTURE_RUNTIME" -L "$CAPTURE_RUNTIME" -lPhysicalGoTestRuntime -Xlinker -rpath -Xlinker "$CAPTURE_RUNTIME" PhysicalGo/Experiments/AttendedCaptureKit/ValidateController.swift -o PhysicalGo/.build/capture-kit/ValidateCaptureKit
PhysicalGo/.build/capture-kit/ValidateCaptureKit /absolute/path/to/generated-fixtures
```

Generator and controller logs are retained in this worktree's
`PhysicalGo/.build/capture-kit/` and copied beside the final artifacts. No physical
pass, laser capability, online integration or forced-AI move support is asserted.
