# Saved stone sets in Setup

Installed since 0.258 and retained in 0.260. Storage/editor validation does not
establish an optical correction; [current status](IntegrationChecklist.md) tracks
physical tests separately.

The reviewed named stone-set controls are hosted in **Setup → Camera & board**,
below camera/grid options. They are shared by Local, AI and Online setup views.

Users can name a set, select it again, rename it, and optionally record measured
Black and White thickness separately. Unknown thickness is valid and remains
the default. Selection and edits persist across app restarts in:

`~/Library/Application Support/Physical Go/Stone Sets/library.json`

The panel says **Saved for calibration**. Selection does not change current
recognition, placement acceptance, the printed grid, game/clocks or laser aiming.
This release does not collect automatic height estimates, import the offline
study, train a model, or apply optical correction. It adds working profile
management, not a dormant button claiming those capabilities.

## Data ownership and limits

`ExperimentModel.stoneSets` owns one stable `StoneSetProfileStore`. Its final
optional initializer argument, `stoneSetLibraryURL`, permits isolated test
storage. The setup picker observes that store directly, so successful saves and
selection changes update the visible name and details. Opening Setup or the
store does not create a library; the first successful user save does.

`StoneSetProfile.swift`, `StoneSetProfileStore.swift` and `StoneSetProfileView.swift`
come from independently reviewed candidate `bf241bc`. Hosting adds only the
store's dedicated path helpers and the model/view connections. The model keeps
manual measured thickness separate from sourced, unvalidated optical-height
candidates. Multiple internal geometry hypotheses remain in expanded details;
the main panel does not describe them as independent camera calibrations.

Known-scale conversion preserves original board-relative units and provenance.
Unknown spacing cannot become millimetres, and a saved estimate cannot silently
transfer to another board/camera setup. All optical candidates remain inactive.
The library validates before atomic save, has the same 2 MB load/save bound,
and refuses to overwrite an unreadable saved library.

## Focused validation

Registered suites:

- `--stone-set-profile-test`: profile, units/provenance and persistence.
- `--stone-set-profile-review-test`: independent failure and unit boundaries.
- `--stone-set-setup-test`: dedicated destination, observable selection/edit,
  relaunch persistence, independent color values and unrelated-data preservation.

Current build infrastructure can compile the shared full-app runtime even for
these registered standalone groups. Use the following direct commands when
only a small compilation window is available:

```sh
xcrun swiftc -swift-version 5 PhysicalGo/Sources/StoneSetProfile.swift PhysicalGo/Sources/StoneSetProfileStore.swift PhysicalGo/Tests/StoneSetProfileTests.swift -o /tmp/stone-set-integrated-profile-tests
xcrun swiftc -swift-version 5 PhysicalGo/Sources/StoneSetProfile.swift PhysicalGo/Sources/StoneSetProfileStore.swift PhysicalGo/Tests/StoneSetProfileReviewTests.swift -o /tmp/stone-set-integrated-review-tests
xcrun swiftc -swift-version 5 PhysicalGo/Sources/StoneSetProfile.swift PhysicalGo/Sources/StoneSetProfileStore.swift PhysicalGo/Sources/StoneSetProfileView.swift PhysicalGo/Tests/StoneSetSetupTests.swift -o /tmp/stone-set-integrated-setup-tests
```

The direct author run passed **34 profile checks**, including actual reviewed
study02 JSON, **15 independent regression checks**, and **18 setup-store checks**.
The copied UI and store typecheck cleanly. An initial shared-runtime attempt
exposed actor isolation on the default path helper; the pure path helpers are
now explicitly nonisolated. A full combined-app build and actual UI interaction
remain required before installation/physical validation. These tests used only
temporary libraries, never the live profile library or game.

The optional first argument to the profile-test binary can be the actual
reviewed producer output:
`/Users/dave/Documents/SGF PLayer/work/ai-laser-integration/stone-session-20261123/stone-set-calibration/offline-body-study-02/offline-stone-set-profile.json`.
This validates decoding/provenance, not the estimates' physical accuracy.

## User check in the next test app

1. Open Setup → Camera & board and choose **New set…**. Name it and save with
   both thicknesses unknown. The selected name should appear immediately.
2. Add another set, then switch back with the **Stone set** picker.
3. Choose **Edit…**, rename the first set, and expand **Measured thickness
   (optional)**. Save separate Black/White measurements if known. Otherwise
   leave them unknown; invented measurements are unnecessary.
4. Reopen the editor and, if values were entered, clear just White with
   **Unknown**. Black should remain unchanged. Cancel should discard unsaved edits.
5. Relaunch when the root operator schedules it. The selected set and saved
   values should persist; current game, clocks and grid should remain unchanged.

There is deliberately no automatic calibration/import action in this UI yet.
