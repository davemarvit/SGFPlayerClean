# Physical Go process maps — November26 audit

Open [index.html](index.html) for the self-contained seven-map review. [Audit20261126.md](Audit20261126.md) records source boundaries, race findings and measurement-led optimizations. [release-snapshot.json](release-snapshot.json) separates diagrammed candidate sources from the installed baseline. **This checkpoint is a candidate audit, not a release or installation approval.**

| Map | Scope |
|---|---|
| [Overview](overview.svg) | Qualify setup, observe, decide, guide, aim/recover, physical change and independent confirmation |
| [Calibration](calibration.svg) | Camera grid versus motor map; explicit wooden perimeter; bound artifacts; fresh attended READY |
| [Camera/IPC](data.svg) | Original timestamps, early safety, exact PNG, separate IO/supervision and publication boundaries |
| [AI game](gameplay.svg) | Qualified assignment evidence, hand/dark gates, stable witnesses, legal history and pending placement |
| [Aiming](laser.svg) | Historical startup hint, initial route, contained correction, independent hold and lit/dark renewal |
| [Recovery](recovery.svg) | Single retry owner, shared work ledger, typed expiry/geometry recovery and coordinator-owned full OFF |
| [Other modes](modes.svg) | Local recording, online state, clocks, review, explicit scoring and persistence |

The diagrams remain readable at full size: horizontally scroll on narrow windows or open each SVG. HTML embeds all SVGs and needs no network connection. The directory name is retained for link continuity with the original November25 maps; Git preserves the earlier flow snapshot. No camera images, desktop screenshots, browser logs, temporary DOM output or PNG previews are included.

## Current review boundary

Installed baseline at audit start: native0.268/build269 **fb4697c** and host **32d7911**. The last user-requested replay produced three same-pose O17 errors **0.1959703,0.1971448,0.20074545 cell**; installed policy stopped at the crossing. Separate full OFF **1795683450.8051615** was confirmed. Game paused at ten logical moves/nine physical stones, O17 empty/pending, no READY pending. The candidate's recovery behavior has not been physically demonstrated by that recording.

The single-operation candidate shares **150 seconds active work /25 local correction plans**, with a provisional **30-second recovery wall cap**. Stable verified adequate waiting pauses only this ledger. Initial predicted waypoints retain their separate existing cap and run once. Optical age, lease, motor/thermal evidence, geometry certificate and illumination origins never pause or restart through retry.

Two initial audit findings require final disposition: nested OFF transport write from a validator already holding the raw write lock; and adequate sample freshness through later wire publication/native consumption. The audit records their precise scope and evidence. The qualified-EMPTY receipt candidate is being independently reviewed; it cannot replace hand/visibility, target, legality or temporal confirmation gates. Final merged source and root installation receipts will supersede draft labels.

Root alone owns tests/build slots, final installation, paused-app relaunch, camera-only readiness and hardware operation. A reviewed source branch is not installed readiness. The requested morning start still requires fresh user go-ahead/READY and current post-READY checks; it cannot be pre-authorized by an overnight map or old preflight.

## Rebuild and verification

```sh
python3 build_map.py
python3 -B verify_map.py
```

The builder uses only Python's standard library. The validator additionally uses Pillow/local Arial metrics when available and reports whether that check ran. `release-snapshot.json` supplies source paths and source/installed labels; `findings.html` supplies narrative/timing tables. `diagram-data.json`, HTML, SVGs and `sources.md` are generated. Source hashes and validation receipts must be refreshed against the final frozen candidate, not inferred from an earlier green result.

Original November25 maps were inspected using artifact-only headless renders. This update uses source review and offline SVG geometry/font-metric/link checks; no screenshots, camera, app operation or hardware actions are part of the audit. `validation.json` must identify the exact revision and actual check scope. Seven-map readability does not establish state-machine completeness, physical latency or gameplay acceptance.
