# Physical Go process maps — installed November27 release

Open [index.html](index.html) for the self-contained seven-map review. [Audit20261126.md](Audit20261126.md) records the findings, repairs and remaining limits. [release-snapshot.json](release-snapshot.json) pins the installed source. **Native0.270/build271 7188dc4 + host936bf10 is installed and offline validated. Apps/driver are closed and controller USB absent; morning READY and physical validation remain pending.**

| Map | Scope |
|---|---|
| [Overview](overview.svg) | Qualify setup, observe, decide, guide, recover and independently confirm physical change |
| [Calibration](calibration.svg) | Camera grid versus motor map; wooden perimeter; bound artifacts; attended READY |
| [Camera/IPC](data.svg) | Original timestamps, early safety, exact PNG, independent request/status loops and stopped-publication fences |
| [AI game](gameplay.svg) | Qualified EMPTY evidence, independent hand/dark/stable/legality gates and pending placement |
| [Aiming](laser.svg) | Historical startup hint, initial route, contained correction, independent hold and proof renewal |
| [Recovery](recovery.svg) | One work ledger, typed expiry/geometry recovery, flag-only signal and verified OFF receipt |
| [Other modes](modes.svg) | Local recording, online state, clocks, review, scoring and persistence |

Open each SVG at full size or horizontally scroll the HTML. All diagrams are embedded; no network is required. The directory name is retained for link continuity. Git preserves the earlier November25/26 snapshots. No camera images, desktop screenshots, browser logs, temporary DOM output or PNG previews are included.

## Installed0.270 diagnostics and recorder cache

Installed source **native7188dc4 / host936bf10**, final review6c91eb03, includes the concrete recorder cache and the earlier diagnostics pair approved164af9f. Combined checks and offline installation are complete. Gameplay, deadline, safety, admission and retry behavior below is unchanged; no physical-acceptance claim follows.

Native stage tracing is opt-in (`PHYSICAL_GO_CAMERA_STAGE_TRACE=1` plus the existing trace directory). It separates capture preparation/delivery, admitted latest-slot residence, vision/safety stages and completion, with original capture identity when present. Missing photo/redraw provenance remains absent. The existing bounded writer may drop records; missing events do not prove work absent. Thread CPU excludes other worker threads/GPU, so wall minus CPU is not a scheduler-delay measurement; overlapping queues cannot be summed.

Host diagnostics preserve up to eight observed serial failures across request lifetimes and the bounded controller tail after raw close, including receiver/close uncertainty. Shutdown records raw OFF-barrier observation separately from the gate's acceptance and rejection reason. These optional fields do not participate in `full_off_verified`: a raw acknowledgement, process exit or USB disconnect is not a complete OFF receipt. Failed storage, abrupt kill and a live receiver can still leave incomplete evidence. No extra diagnostic serial command is added.

The recorder fix addresses demonstrated write amplification: one retained recording's56,372,567-byte manifest was source-implied to publish57 times (open + seven25-frame checkpoints +48 gaps + close), about3.21GB logical JSON payload, not measured physical-disk writes. Installed7188dc4 caches immutable compact inline context once (28,087,701 bytes in that recording), releases the boxed dictionary and serializes only changing counts/status before joining each output. Gaps still append exact ranges/counts to JSONL but no longer rewrite the manifest; existing25-frame/final/abort atomic publications retain exact lifecycle counts. Source-implied publications become nine for that same recording. All original fields remain inline; no schema migration or replay change.

This is not a complete writer-bound solution: image admission is bounded, but metadata events still queue without an admission bound. Each remaining atomic manifest write needs an output buffer/file; initial checkpoint conversion and capture-start serialization still occur. Live gap counts remain in UI/journal while periodic manifest counts can lag until the next existing checkpoint. The recorded amplification overlaps the stall but does not prove its sole cause or a live timing improvement.

Bedtime plan: lights off and no hardware tonight. In the morning, one chat **READY**, after lights/controller are restored, Mac unlocked, hands clear, user watching and board unchanged, authorizes root's checks and O17 attempt without a repeat READY question. Current controller USB disconnection is recorded separately from full power OFF. Root owns all runtime actions.

## Release evidence and physical boundary

The [root installation receipt](/Users/Dave/Documents/SGF%20PLayer/work/morning-readiness-20261127/install-receipt.json) pins native **7188dc4ddd613f158cc2418ce8c7844cdcd66f33**, host **936bf10e3942a0a32a47e57eb1b58cfba5af07d8**, final source approval **6c91eb03da718bbf38d9279f8ed327578f5a7c28**, and manifest **88d6c31b480a785713fd51896dbd73a2ccf13fd9b6dcbf32c64bb07bff4481ca**. Root reports **1,335 host tests /57 skips,16 native suites,eight renewal replays,mandatory paired acceptance and signed build PASS**. All app/driver processes are closed, controller USB absent, and saved game/anchor preserved. No app/camera/controller was started for this installation. These are offline/install results, not a passing game or measured physical latency improvement.

| Change | Installed behavior |
|---|---|
| Hold recovery / shared work ledger | One operation owns acquisition, confirmation, correction and recovery; stable verified waiting pauses only active-work accounting |
| A1 transport lock | Validator rejects/revokes without recursively writing OFF under the raw transport lock |
| PG23 recognition receipt | Current original-capture positive EMPTY proof can exempt a low-confidence EMPTY neighbor; UNCERTAIN and independent clearance/legality/stability remain blocking |
| Native admission | Default12s; qualified16s outer episode only with causally advancing authenticated dark evidence; firmware engagement remains12s |
| A2 cue age | Immutable original optical proof survives status writes/heartbeats; native checks original age and scope before consuming the once-per-move cue |
| A3 host I/O and frame reread | Request/status loops independent; one nonblocking publisher owner/no queue; at most one strictly newer, same-scope, fully fresh replacement read |
| A4 shutdown/startup | Signal handler only assigns a flag; normal flow checks cancellation during startup/admission/cleanup; stopped background work cannot poll or publish late |

**Latest attended result (prior release):** 0.269 run1795767435349051000 point12 passed pre/post-READY alignment but failed before adequate. Cached gameplay safety frame1864 reached604.260ms capture age (checked age414.192ms) against600ms, followed by a lease fault and serial write-completion deadline fault. Ctrl-C exited promptly; the prior signal hang did not recur in this attempt. However `controller_off:null` and `full_off_verified:false` mean **no verified final OFF receipt**. User disconnected controller USB; that establishes USB disconnection only, not full power OFF. Prompt process exit is not controller OFF, and fault-status `laserOn:true` with `illuminationConfirmed:false` does not establish actual illumination. No physical acceptance or retry is claimed. See [the current release record](/Users/Dave/SGFPlayerClean/PhysicalGo/Documentation/RequirementsRelease20261127.md).

The source and installation pins remain valid. This map work performed no runtime action. The installed strict-newer raw-frame reread and the separate cached-gameplay-safety failure above are different evidence boundaries; this update does not infer a cause or propose relaxing600ms.

The prior **nativefb4697c/host8ce91a1 returned-O17 run1795765307207891000** retained14 observations and one lit renewal, then failed. Raw frame2071 was initially published fresh but later rejected at728.298ms capture age versus600ms. Thermal-unavailable OFF intent preceded the later lease fault. The7.556s adequate-to-fault monitor interval is not continuous optical proof or exact light duration. No correction plans were consumed;4.429s active work did not exhaust the150s budget. Failed pixels were not retained.

That prior shutdown stalled under SIGINT. User confirmed physical power OFF before root killed the child; **there is no verified final controller OFF receipt for that run**. Installation cannot retroactively supply it. Earlier verified OFF1795712291.8697388 is historical. Game remains paused at ten logical moves/nine physical stones, O17 unplaced in the installation receipt. See [the frozen failure review](/Users/Dave/SGFPlayerClean/PhysicalGo/Documentation/ReturnedO17Failure20261127.md).

## Evidence boundaries and remaining limits

The operation shares150s active work/25 local correction plans, with a provisional30s recovery wall cap; initial predicted waypoints have their separate existing cap and run once. Retry does not restart optical, lease, motor, thermal, geometry or illumination origins. Raw-frame reread is exactly one replacement attempt for eligible finite expired clear data; frame ID and capture uptime must both advance within the original scope and deadline. Unknown/hand/future/reversed evidence is not rescued.

Status `updatedAtUnix` describes liveness, `adequate` the last measured state, and `opticalEvidence` the immutable source receipt. An aged historical adequate state alone causes no blink, DARK or fault and does not consume the move's later fresh cue. A historical measured anchor can be valid even when off target; it grants neither present accuracy nor stone acceptance.

I/O isolation removes request/status coupling, not all filesystem stalls. Atomic status replacement still holds the generation lock to prevent obsolete publication. A blocked rename can delay cancellation. Close skips a busy publisher without waiting; if it owns publication, the final status write can still block. Actual controller OFF and a complete shared-status shutdown receipt are separate results. Late background work is fenced before snapshot, lease polling and rename; only close's explicit `shutdown=True` path may publish confirmed OFF after stop. Missing receipts remain failures.

Root owns app, camera, launcher and hardware. The single morning chat READY described above authorizes root checks and O17; current post-READY checks remain necessary, without a second READY question. Maps and old preflight do not independently authorize motion.

## Rebuild and verification

```sh
python3 -B build_map.py
python3 -B verify_map.py
```

The builder uses Python's standard library. The validator optionally uses Pillow/local Arial metrics and records whether that check ran. `release-snapshot.json` supplies source paths/status; `findings.html` supplies prose/tables. HTML, SVGs, `diagram-data.json` and `sources.md` are generated. `source-hashes.json` and `validation.json` record the examined files and actual validation scope.

The original November25 maps had artifact-only headless render inspection. This update uses static SVG/XML, font metrics, connector geometry, local links, AST and source-hash checks; no screenshot, browser render, app, camera, hardware or runtime tests. It is a review aid, not an exhaustive executable state machine.
