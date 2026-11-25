# Overnight readiness — November 25, 2026

The reviewed pair is **installed offline**. The app is **left closed**; it was not relaunched, and no camera/controller action accompanied installation. All saved-game files are byte-identical. [Final verification](</Users/Dave/Documents/SGF PLayer/work/overnight-readiness-20261125/final-verification.json>) confirms installed pins, absent app/controller owner and both remote baseline tags. This is not physical acceptance. The [issue register](IntegrationChecklist.md) owns open scopes; [compact provenance](OvernightReadiness20261125.json) pins this release without raw game or image data.

| Component | Installed identity |
|---|---|
| App | 0.265/build266 |
| Native source | `1f6fb91cac57616791d47c2fea4cc4eca0426a28` |
| App source hash | `f24ce0db668c4638306164c3457dd8cb1ea061adcbffc0f5700a3d248540ff0a` |
| App binary SHA256 | `7fa48c519d4e70a95e8164c8411c19a54f8ea81420468adac1cf599f00c92871` |
| Host source | `b9a524e2b521e535de913daa92098742f1f34233` |
| Host manifest SHA256 | `74696b245c133f9fc3954357fd9233d295c248afc46201122841e711981b155b` |

Both source trees are named `overnight-readiness-20261125` under their respective native/host worktree roots. Canonical repositories carry documentation and must not be assumed to match these runtime sources.

Native changes retain bounded ambiguity/failed-fit diagnostics (55c2ba3 +7ac2f6a) and cue the stone click only after confirmed illuminated adequate status (36b0265). These diagnostics do not change recognition decisions or implement stone-count heuristics. Host changes retain the initial accepted light through fresh holding verification (409df8a), bind final shutdown proof to the actual fresh OFF acknowledgement (82e1113), and add independently reviewed temporal correspondence handling (e5ffa0d).

Eight native suites passed **2,588 checks/cases**; the final combined host passed **219 tests**. Mandatory paired acceptance passed on the installed source combination. Its contract harness uses fake hardware and does not replace live timing or physical validation. Temporal review retained all44 motion/occlusion rejections; nominal full-path replay447–577ms leaves only23ms at the worst replay, so live margin remains unvalidated.

[Installation receipt](</Users/Dave/Documents/SGF PLayer/work/overnight-readiness-20261125/install-receipt.json>) · [Paired acceptance](</Users/Dave/Documents/SGF PLayer/work/overnight-readiness-20261125/paired-acceptance/acceptance.json>) · [Authoritative release pointer](</Users/Dave/Documents/SGF PLayer/work/feedback-play-release-20261124/current-release.json>).

The tagged [before-architecture baseline](BeforeArchitectureBaseline20261125.md), its app clone, games and launcher/binding receipts remain preserved. Previous0.264 app is additionally retained under `work/overnight-readiness-20261125/before-install`. Last actual full OFF is **1795596934.1468098**; installation created no new hardware receipt.

Next attended test: reopen the app, start the camera, verify fresh live alignment and then obtain fresh READY at the launcher. Preserve seven stones, eight saved moves and empty/pending Q17. Verify matcher reliability, actual child shutdown receipt, click timing and same-light holding/illuminated correction; all remain open. Keep AirPod Pro3. Root owns activation and monitoring; no overnight hardware run is authorized.
