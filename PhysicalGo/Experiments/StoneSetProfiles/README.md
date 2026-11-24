# Named stone-set UI and data candidate

November 23, 2026. Isolated on `codex/stone-set-profiles`, based on narrow
installed-baseline commit `347eb84`. Nothing here is wired into the application,
active vision, grid, game, marker thresholds or laser. Only focused offline
compilation/tests were run; no app or hardware operation was performed.

## Proposed user flow

1. During board setup, choose **Stone set**, **New set…**, or **Edit…**. A set has
   a memorable name such as “Club glass” or “Travel slate.” Selection is saved
   for later calibration; it does not claim to change current recognition.
2. Leave Black and White thickness **Unknown** by default. If the user knows a
   physical measurement, they can enter each color separately in the optional
   measured-thickness section. These values are never filled from a camera fit.
3. Saved camera estimates appear separately as **needs validation**. The main
   flow says “Saved with its original board and camera setup; recheck with a
   different board or after moving the camera.” Original numerical units, model/geometry assumptions,
   support and provenance are available in expandable **Estimate details**.
4. A live automatic collection/fitting hook is not built here. There is no fake
   Learn button. The UI shows “No camera estimate saved” until sourced candidate
   evidence exists. The offline study supplies that evidence through a separate,
   reviewed adapter; selecting or saving it never activates it.

The bar for runtime adoption is intentionally separate: validate on held-out
centered stones and real misplaced/ambiguous negative controls, check the new
setup's geometry and scale, and preserve the mandatory raw placement-assignment
guard. This candidate neither alters nor bypasses that guard.

## Agreed data distinctions

The contract was coordinated with the intersection-appearance/height study.

- `StoneSetProfile`: stable `stoneSetID`, name and timestamps; separate `black`
  and `white` entries. Unknown thickness and an empty candidate list are valid.
- `physicalThicknessMm`: optional user-measured value, optional uncertainty,
  `source: userMeasurement`, measurement date. Physical thickness and effective
  optical height are never substituted for each other.
- `opticalHeightCandidates`: an array preserving separate geometry hypotheses,
  each with `candidateID` and `status: offlineCandidate`. There is no active or
  preferred candidate field and no automatic “choose the best error” behavior.
- Each candidate carries `value`, `units` (`rowPitch` or `millimetres`), the
  measurement model/version, separate `setupModelID`, geometry hypothesis and
  assumptions, captures with image/metadata hashes, and source-code hashes.
- `rowPitch` requires `referenceBoardPitchID`. Same board dimensions (19×19) do
  not establish the same physical spacing. A metric conversion requires a known
  `rowPitchMm` plus measurement source and preserves the original value/unit.
  A directly metric optical estimate requires `metricScaleSource`.
- Confidence is explicitly **uncalibrated descriptive support**. Uncertainty
  distinguishes a sensitivity range, statistical interval, or unknown. An
  independent-setup validation claim requires a report reference; it still
  cannot change candidate status or activate recognition.
- Camera intrinsics/crop/grid/pose remain in the referenced setup model, never
  stored as reusable physical attributes of the stones.

`StoneSetProfile.swift` is the exact Codable contract. JSON dates use ISO 8601.
`StoneSetProfileStore` requires an explicit injected file URL, validates before
atomic save, applies the same 2 MB encoded-size bound on both save and load,
and refuses to overwrite a library it could not read. Selection
stores only a set ID. No live application-directory writes are performed by the
experiment itself.

## Files and eventual integration

- `StoneSetProfile.swift`: Foundation-only profile/library validation.
- `StoneSetProfileStore.swift`: observable library loading, selection and saving.
- `StoneSetProfileView.swift`: picker and sheet, with optional measured thickness
  and a separate unvalidated-camera-estimate section.
- `StoneSetProfileTests.swift`: temporary-directory tests only; no app data.

After review, the native setup owner can host `StoneSetProfilePicker(store:)`
next to board/grid setup controls. The caller owns a store with an explicitly
chosen dedicated profile-library location. This does not require touching
`BoardVision`, `StoneGeometry`, move acceptance or laser marker thresholds.

## Offline validation

The parent authorized a small offline compilation window after physical evidence
collection. The model/store/tests compile, and the new SwiftUI component
typechecks cleanly. **34 checks pass**, including decoding the actual producer
profile below. These commands do not launch the application or operate hardware.

```sh
xcrun swiftc -swift-version 5 PhysicalGo/Experiments/StoneSetProfiles/StoneSetProfile.swift PhysicalGo/Experiments/StoneSetProfiles/StoneSetProfileStore.swift PhysicalGo/Experiments/StoneSetProfiles/StoneSetProfileTests.swift -o /tmp/stone-set-profile-tests
/tmp/stone-set-profile-tests
xcrun swiftc -swift-version 5 -typecheck PhysicalGo/Experiments/StoneSetProfiles/StoneSetProfile.swift PhysicalGo/Experiments/StoneSetProfiles/StoneSetProfileStore.swift PhysicalGo/Experiments/StoneSetProfiles/StoneSetProfileView.swift
```

Tests cover unknown defaults, independent Black/White measurements, retention of
multiple geometry candidates, metric scale/provenance requirements, unchanged
physical thickness, uncalibrated confidence, absent validation reports,
selection/reload, invalid edits and unreadable-file preservation. Native/UI
compilation, test execution, integration, installation and physical validation
are separate: focused native/UI compilation and tests have passed; app
integration, visual interaction testing, installation and physical validation
remain pending.

The actual offline study now emits a compatible standalone `StoneSetProfile` at
`/Users/dave/Documents/SGF PLayer/work/ai-laser-integration/stone-session-20261123/stone-set-calibration/offline-body-study-01/offline-stone-set-profile.json`.
Pass that file as the test binary's first argument to additionally decode and
validate real producer output. It preserves three geometry hypotheses per color;
manual thickness remains unknown and no candidate is selected or activated.
The producer agent reviewed the exact Swift model and confirmed field/unit
agreement. Native decoding and validation of this actual file passed on
November 23, 2026. Its six candidates remain unvalidated estimates, not six
approved correction models.

## Independent review

The independent reviewer found and reproduced a persistence defect: a valid but
oversized encoded library could previously be saved even though the loader
rejected files over 2 MB. The store now uses one shared limit for bounded loading
and encoded output, rejecting an oversized save before any filesystem mutation.
The reviewer also tightened user-facing wording so saved estimates refer to
their **original** board/camera setup, without implying compatibility with the
currently selected setup.

After the fixes, **15 independent checks pass**, in addition to the **34 author
checks** and clean SwiftUI typecheck. Independent cases include preserved bytes,
published state and reload after oversized input; invalid selection; actual
filesystem write failure with unrelated content preserved; retained original
units; conversion overflow; metric double-conversion rejection; incomplete
uncertainty; and missing setup identity. The review found no remaining blocker
for this isolated candidate. No runtime correctness claim follows from these
persistence/contract checks.

```sh
xcrun swiftc -swift-version 5 PhysicalGo/Experiments/StoneSetProfiles/StoneSetProfile.swift PhysicalGo/Experiments/StoneSetProfiles/StoneSetProfileStore.swift PhysicalGo/Experiments/StoneSetProfiles/StoneSetProfileReviewTests.swift -o /tmp/stone-set-profile-review-tests
/tmp/stone-set-profile-review-tests
```
