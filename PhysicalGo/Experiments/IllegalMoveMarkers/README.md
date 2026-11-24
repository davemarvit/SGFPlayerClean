# Illegal-move marker experiment

November 24 integration note: this directory remains the isolated precursor.
The promoted `Sources/PhysicalIllegalMoveWarning.swift` is integrated and installed
since 0.258, retained in 0.260. The statement below about no production integration
describes the original experiment, not the later app. The illegal-laser pattern
remains unimplemented. See [current status](../../Documentation/IntegrationChecklist.md).

**Experimental, not part of the app build, not installed.** This is a tested
diagnostic candidate, not a new legal-move acceptance path or laser command.
It cannot open a camera or serial port, illuminate the laser, play audio, or
modify a real saved game. No production integration is applied.

Read the [design and limitations](../../Documentation/IllegalMoveMarkerDesign.md).
The existing legal-move inference excludes suicide before the AI's specific
illegal-move explanation. This candidate detects a positively observed attempted
illegal placement without relaxing that legal-move filter.

## Files

- `PhysicalIllegalMoveWarning.swift`: candidate classifier and stable-evidence
  tracker, using the actual `SGFPlayer` legality engine and a private simulation.
- `IllegalMoveWarningTests.swift`: 83 current checks for rule-dependent legality,
  ko/restoration, capture permission, temporal evidence and rejection of uncertainty.
- `run_tests.py`: portable repository-relative runner requiring macOS and Xcode
  command-line tools. It compiles only the shared engine/models and this experiment.
- `validated-result.json`: committed record of the last reviewed run and exact
  source/runner hashes. It is evidence for that revision, not an automatically
  current pass after edits.

## Run

From any working directory:

```sh
python3 /path/to/SGFPlayerClean/PhysicalGo/Experiments/IllegalMoveMarkers/run_tests.py
```

Or from the repository root:

```sh
python3 PhysicalGo/Experiments/IllegalMoveMarkers/run_tests.py
```

The runner extracts the exact pure `PhysicalMoveInference` declaration from the
current production source, records its hash, and builds against the real engine;
it does not maintain a copied rules model. Source-boundary changes fail explicitly.
Generated source, binary, compile/test logs and the newest result go under
`PhysicalGo/.build/Experiments/IllegalMoveMarkers/`, which is ignored by Git.
The runner does not overwrite the committed validation record.

## Integration boundary

Warnings require three distinct fresh clear/dark observations over at least
450 ms, exact game/history/rules/camera context, one unambiguous human addition,
and the existing capture-permission decision. The initial candidate requires
positive readings at all intersections, so uncertain crowded boards may suppress
a warning. It does not use retained history as new photographic evidence.

The candidate returns a point, color, engine rejection and any restoration
points. It has no access to clocks or saved-game writes and never mutates the live
engine. A future app integration must reset its context on lifecycle changes and
keep warning presentation separate from accepted moves. The optional distinct
laser pattern described in the design remains unimplemented.
