# Physical Go process map

Open [index.html](index.html) for the complete, self-contained review. Start with [overview.svg](overview.svg), then follow the seven linked maps. The HTML embeds the SVGs and needs no network connection. Narrow windows intentionally scroll diagrams horizontally to preserve readable text; browser zoom and printing are supported.

| Map | Scope |
|---|---|
| [Overview](overview.svg) | Setup → observe → decide → guide → aim → human placement → confirmation |
| [Calibration](calibration.svg) | Separate camera-grid and motor-map fits; independent qualification; READY |
| [Camera and IPC](data.svg) | Capture, queues, early safety, exact PNG publication, host consumers |
| [AI gameplay](gameplay.svg) | Ambiguity, stable evidence, legal commit, pending physical placement |
| [Laser aiming](laser.svg) | Cold/warm admission, dark preparation, coarse travel, optical correction, holding/renewal |
| [Recovery](recovery.svg) | Generation cancellation, dark holding versus full OFF, transient versus explicit recovery |
| [Other modes](modes.svg) | Local recording, online bridge, review, clocks, persistence and scoring |

Raster previews and browser logs are deliberately omitted from this repository copy. The original rendered work artifact remains at `/Users/Dave/Documents/SGF PLayer/work/physical-go-process-map-20261125/`. `diagram-data.json` is the machine-readable diagram content; `build_map.py` owns its editable source. `findings.html` supplies the review notes and timing tables. [sources.md](sources.md) lists all 27 source entry points.

## Architectural findings

1. **Initial observation → holding repeats a dark preparation cycle even when already at the target.** Investigate retaining that first accepted beam with all proof scopes preserved. Fresh hold verification remains necessary. This is a proposal, not an implemented speedup.
2. **PG23 is repeated evidence rejection, not the measured camera backlog.** R16 had 130 ambiguity resets over 25.418 s; capture-to-consume ages were 122 ms median / 151 ms maximum. Retain exact neighbor/outline/grid evidence before changing the recognition policy. Color counts can constrain consistency but cannot prove hidden emptiness or location.
3. **Evidence scope should be explicit across subsystems.** Native geometry, host registration, temporal tracking, actual spot, motor pose and firmware limits are independent proofs. Consolidate their descriptions and invalidation diagnostics before attempting to combine checks. PG35's installed 12 s admission-episode repair illustrates why session and operation scopes must differ.
4. **Separate appearance, motion estimation and visibility failures.** The installed host already treats live brightness scores as diagnostic-only and uses geometry to admit dark registration. The later temporal alias repair is separate. The reviewed normalization repair preserved the original pyramid/coverage and passed 112 focused tests plus paired acceptance. The latest installed host is `968ba538d457c03fc34ed0b17b0d59e853817838-app0264`; the final attended test still failed temporal reuse at frame57014. Sustained reliability remains open. It adds ~0.61–0.84 ms in reported warm module benchmarks; it is a reliability repair, not a compute speedup.
5. **Measure one correlated turn timeline.** Recognition acceptance, AI answer, first-light acknowledgement, target acceptance, verified hold and physical confirmation differ. Native audio currently follows first light, not accepted target. Record frame waiting, mandatory flush, serial/settling, computation and rejection retries separately.

The HTML contains the source links, confidence/tradeoffs, latest Q17 measured table and scoped timing limits. Values are not additive “timeout allowances.”

## Snapshot and limits

Architecture snapshot: November 25, 2026. Native **0.264/build265**, source `0f9ac752414b12b85dae5e10b161bd7e6de69950`; host `fc8cb7d2648c198c319e4f046098d8fabc8b8f89`; firmware v44. Current runtime state must be read from the integration checklist/release pointer, not this document.

At the recorded checkpoint Q17 was optically accepted in **3.048924 s / 0.098258 cell with zero moves**, then temporal reuse rejected frame 21221. The game remained paused with 8 logical moves / 7 physical stones and Q17 pending. The separate direct full-OFF receipt was Unix **1795593357.6117432**. PG41 illuminated fine movement was installed but not exercised in that zero-move retry. PG35's admission-timer defect was physically verified fixed; broader sustained recovery remained open.

Latest installed/frozen host: **968ba538d457c03fc34ed0b17b0d59e853817838-app0264**. The final attended retry acquired Q17 in **3.323906 s / 0.103718 cell** with zero moves and three fresh optical results (maximum capture age **0.471306 s**), then failed temporal reuse at **frame57014**, median **0.062 px**, p95 **27.330 px**. Separate full OFF was confirmed at **1795596934.1468098**. Driver and camera stopped; Q17 remains empty/pending with eight saved moves and seven physical stones. **No passing sustained-play result is claimed.**

The source index and diagrams remain pinned to the earlier `fc8cb7d` process-flow snapshot. Subsequent exposure-normalization and dark-validation algorithm changes leave this high-level flow unchanged; they are not silently represented as part of the pinned source. Module timing numbers are the active owner's reported offline results, not a measured total-latency improvement.

The user-requested approximately **20-minute attended baseline** and separately authorized final retry have ended. Further work is offline on isolated branches. Proposed simplifications are absent from the installed baseline; see the authoritative register for any later offline candidate status. This documentation commit changes no runtime code.

See [frozen baseline](../BeforeArchitectureBaseline20261125.md), [current register](../IntegrationChecklist.md), and [final outcome and OFF receipt](</Users/Dave/Documents/SGF PLayer/work/feedback-play-release-20261124/dark-residual/final-retry/outcome.json>).

Older guide status/version paragraphs were superseded by the current checklist. These maps summarize decision/evidence ownership, not every executable branch or every experimental launcher. They do not authorize hardware actions, establish current clearance or replace protocol source.

## Rebuild and validation

```sh
python3 build_map.py
```

Run from this directory or pass the absolute script path. Python standard library only; application/host modules are never imported. The build reads `findings.html` and writes the HTML, SVGs, diagram JSON and source index. PNG previews were generated only in the original work artifact using a separate headless Chrome profile, not desktop captures; they are not required to rebuild or view this copy.

Validation performed:

- Headless Chrome rendered the self-contained HTML and all seven SVGs. All **80 node labels** fit their rectangles. Connector labels fit each SVG canvas and overlap neither nodes nor one another; all internal HTML anchors resolve.
- All **27 local source paths** exist, including `AimControl/AimControl.ino`. The historical and final run-evidence links resolve.
- Independent SVG geometry checks found no connector segment crossing a node interior. PNG previews of all seven maps were visually inspected; the overview's initially crowded connector labels were corrected.
- Exact Q17 result events were checked for acceptance, both geometry qualifications, freshness ages and rejection. The immutable source identities and snapshot caveats are preserved.

`validation.json` records the final check result. Chrome logged headless GPU/utility warnings; page execution and geometry checks completed successfully. No app build, runtime test, desktop screenshot, camera acquisition, serial access, installation or hardware action was performed. Responsive page text was checked structurally; small-window diagrams intentionally scroll rather than shrinking below legibility. No exhaustive accessibility audit or complete state-space equivalence proof is claimed.
