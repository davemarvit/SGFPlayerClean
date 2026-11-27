# Physical Go process maps — November26 audit, November27 failure update

Open [index.html](index.html) for the self-contained seven-map review. [Audit20261126.md](Audit20261126.md) records source boundaries, race findings and measurement-led optimizations. [release-snapshot.json](release-snapshot.json) separates diagrammed candidate sources from the installed baseline. **The installed limited pair failed the returned O17 test. Full-batch source and the newly labelled I/O/shutdown proposals remain uninstalled and unaccepted. This documentation is not release approval.**

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

The currently installed limited pair is native **0.268/build269 fb4697c** plus host **8ce91a1**. Root reports source approval **1ebd12e**, 1,287 host tests /57 skips, eight renewal replays and paired preflight PASS. It includes bounded hold recovery, the latest cached-safety publication guard and the A1 transport-lock repair. It does **not** include PG23 recognition receipts, the qualified native16s admission margin or paired A2 optical cue-age proof.

| Work | Installed limited pair | Forthcoming full-batch source |
|---|---|---|
| One recovery owner / shared work ledger | Included in host8ce91a1 | Same behavior |
| A1 nested OFF transport-lock race | Fixed, integrated8ce91a1 from13129ec | Same repair |
| PG23 positive EMPTY receipt | Not included in nativefb4697c | Source approved1ebd12e; integratedb87af40 |
| Qualified native16s outer admission episode | Not included | Integratedd270ee1; firmware engagement unchanged |
| A2 original optical proof through wire/native cue | Preexisting age conflation remains | Host74d0b83 + native97fd067; final combined approval/install pending |

The full-batch diagram source snapshot is native **d014c63** / host **74d0b83**. The source index and per-file hashes identify the examined files. Packaging version0.269 in candidate source is not an installed-version claim.

An earlier morning launch was cancelled before controller open after no READY. That historical cancellation has been superseded by the later attended **returned O17 run1795765307207891000**, authorized by fresh READY. The installed limited pair retained **14 accepted optical observations**, one lit renewal and about **7.556s first-adequate-to-fault monitor interval**. This is not proof of uninterrupted optical validity or exact visible-light duration. No correction plans were consumed; active work was4.429s, so the150s work budget did not cause the stop.

Raw frame2071 was published fresh by native, but later rejected at **728.298ms capture age versus600ms** (publication age573.043ms). Native thermal-unavailable OFF request and delayed request publication appeared nearby, followed by a lease fault. Fresh independent safety frame2077 does not make2071 current. Saved evidence does not fully attribute the initiating delay; failed pixels were not retained.

**Shutdown did not complete:** SIGINT stalled; user confirmed all physical power OFF before root killed the child. There is **no verified final controller OFF receipt** for this run. Earlier OFF timestamps are historical, not the current receipt. Game remains paused at ten logical moves/nine physical stones, O17 unplaced. See [the frozen evidence review](/Users/Dave/SGFPlayerClean/PhysicalGo/Documentation/ReturnedO17Failure20261127.md).

Installed source couples request reading to synchronous status publication inside `_inputs`; a slow publish can delay the next request read. The proposed split keeps one independent bounded publisher and preserves generation/identity fences. Proposed raw-frame retry discards expired input and requires strictly newer, independently fresh pixels in the same identity/scope; it cannot extend600ms. The signal proposal makes the handler set only a flag, with stop/cleanup in normal control flow and explicit startup cancellation. Both repairs remain owner/reviewer work. Signal candidate8354e8b was not approved because startup could admit OFF→POINT work after stop; its predicate-aware startup follow-up is pending. The separate final lit-renewal replay failure also blocks full-candidate release. Maps3 and6 label these additions as proposals; final source pins remain pending.

The recovery implementation shares **150 seconds active work /25 local correction plans**, with a provisional **30-second recovery wall cap**. Stable verified adequate waiting pauses only this ledger. Initial predicted waypoints retain their separate existing cap and run once. Optical age, lease, motor/thermal evidence, geometry certificate and illumination origins never pause or restart through retry.

The paired A2 candidate preserves immutable original optical timestamps through status-file replacement and heartbeats, then checks them at native first-indication/click consumption. Aged historical adequate remains a reported state; age alone causes no blink, DARK or controller fault. The move's cue remains available for a later fresh measurement. PG23 receipts exempt only qualified low-confidence EMPTY neighbors; UNCERTAIN, hand/visibility, target, legality and temporal confirmation gates remain independent. Neither source change establishes physical latency improvement.

Root alone owns tests/build slots, final installation, paused-app relaunch, camera-only readiness and hardware operation. A reviewed source branch is not installed readiness. The requested morning start still requires fresh user go-ahead/READY and current post-READY checks; it cannot be pre-authorized by an overnight map or old preflight.

## Rebuild and verification

```sh
python3 build_map.py
python3 -B verify_map.py
```

The builder uses only Python's standard library. The validator additionally uses Pillow/local Arial metrics when available and reports whether that check ran. `release-snapshot.json` supplies source paths and source/installed labels; `findings.html` supplies narrative/timing tables. `diagram-data.json`, HTML, SVGs and `sources.md` are generated. Source hashes and validation receipts must be refreshed against the final frozen candidate, not inferred from an earlier green result.

Original November25 maps were inspected using artifact-only headless renders. This update uses source review and offline SVG geometry/font-metric/link checks; no screenshots, camera, app operation or hardware actions are part of the audit. `validation.json` must identify the exact revision and actual check scope. Seven-map readability does not establish state-machine completeness, physical latency or gameplay acceptance.
