# Physical Go issue register

Updated November 24, 2026 (Pacific), after the 18:20 final-two-target run.
This is the **single authoritative checklist**. Handoffs link here; they do not
maintain competing work lists. Existing item numbers 0–27 are preserved as PG IDs.

**Current state:** controller fully OFF, no active driver or pending READY.
Last receipt: AimControl v44 OFF at `1795573364.868653`, no controller or cleanup
errors. App 0.261/build262 and firmware v44 remain installed. The empty Human Black
practice game is paused. **Laser-guided gameplay is not yet activated.**

## How an item gets checked off

- `[ ]` means open, including implemented or offline-tested work awaiting installation/physical verification.
- `[x]` means the stated scope is complete, with dated evidence. A completed experiment is not a completed gameplay feature.
- Every open item has a next action or acceptance criterion. The fresh-context issue coordinator assigns offline owners; root retains integration, installation and hardware authority.
- After each material change/test, update this entry in place with source, installed version, result and remaining work. If a closed issue recurs, reopen its existing ID.
- Do not remove deferred work. Preserve raw evidence and historical records; do not append an old “current status” above this register.

## Work needed for dependable laser play

- [ ] **PG-31 — False native alignment rejection. Investigating.** Exact 18:15 rejected camera frame reproduced a native failure: 339/658 profile matches, edge counts `[18,18,1,18]`, at least3 required per edge. Independent replay found331 inliers, all72 boundary points, 0.493px maximum grid movement and0.99548 image correlation. Reconstructed anchor, not an exact saved live tracker checkpoint. Next: quantify profile sensitivity and fix verification without admitting moved/covered boards; regression-test, install and physically verify. Native candidate in `alignment-profile-jitter` searches at most one image pixel across an outer rail (also capped at4% of grid spacing), retaining contrast/shape/distribution thresholds. Exact rejected-frame replay changes the weak edge from1 to18 matches and accepts the stable grid. Committed candidate `002e4c7`: occupied74, crowded48, glare64 and resume18 checks passed (204 total); synthetic blank, covered-edge and30px-translation controls rejected. Independent issue-agent review pending; not installed or physically verified. [Replay evidence](</Users/Dave/Documents/SGF PLayer/work/attended-recheck-20261124-105259/alignment-rejection-1815>).
- [ ] **PG-32 — Serial-write timeout. Diagnostics implemented; cause unresolved.** The14:40 run exceeded the100ms write-completion deadline; later OFF traffic evicted the initiating diagnostic. `5612839` pins early write failures; retained in tested host `2da3c29`. Recent runs had no recurrence, which does not prove resolution. Next: inspect captured failure if it recurs, establish cause/recovery, then verify sustained play. Distinct from600ms camera freshness.
- [ ] **PG-06a — 600ms camera/lease reliability. Partial repairs installed.** Background IO and independent checked safety metadata are in0.261 with host `04b76c7`; injected-stall and paired tests passed. No sustained current-version gameplay pass. Next: measure tail ages during play and verify bounded recovery. Calibration's experimental timing policy does not validate gameplay's600ms policy. [Evidence and plan](CameraFreshnessReliability.md).
- [ ] **PG-06b — Aiming speed. Measured; optimization active.** S10 took69.4s/11 moves; K18 took95.7s/15 moves. Full guarded correction cycles average about 6.42s. K18 used one coarse move then 14 fine moves: the 15px planning cap within 90px of an edge kept every later step in the fine regime. This is conservative step policy, not demonstrated analysis backlog. Owner: root. Agent completed/pushed offline candidate `7d8b530` in `feedback-optical-latency`: exact same-batch median reuse and local centroid arithmetic,75 tests pass; recorded five-frame median+detect0.504→0.278s with equal outputs. About3.5% of a complete cycle, not a cure for excessive step count; holds about50MB of temporary median data through registration. Not installed or physically tested. Next: reduce unnecessary small travel cycles and redundant image work, then measure live latency; do not claim a speedup from offline timings alone.
- [ ] **PG-33 — Put optical-feedback aiming into gameplay. Not implemented.** The benchmark uses the three-point seed plus measured corrections. Installed gameplay still performs a predicted coarse landing using the older model. Next: integrate the validated approach with target cancellation, hand/lease guards, actual-pose reacquisition, monitored holding and full OFF; pass paired tests, install and conduct an attended game. Passing PG-30 does not close this item or authorize an old binding.
- [ ] **PG-03 — False hand warnings and hand-stop recovery. Open.** Earlier false pose was on fabric beside the board; rim replay is sensitive to its background. Fresh reference captured, but no detector fix proven. Preserve distinction between false-positive, genuine obstruction and unknown clearance. Next: capture the first obstruction's exact tracker state, verify hand entry turns beam off and clear withdrawal recovers; confirm the orange message clears after accepted placement.
- [ ] **PG-04 — End-to-end ordinary gameplay acceptance. Awaiting PG-33.** Earlier moves and F5 indication worked; current setup/version has no complete play pass. Done when Black/White placement, AI answer, actual dot, virtual marker, clock transition and pause/resume all work without lost state. Preserve existing games.

## Completed, with limited scope

- [x] **PG-28 — Recover the reconnected camera/controller and fresh baseline. Completed Nov24.** Webcam `0x21000000bda0567`,1920×1080; user confirmed equipment unmoved and captured reference at18:02:03 PST. Controller reappeared as OpenRB-150 `/dev/cu.usbmodem1101`, serial `4F32C94A5157375037202020FF121D36`. Explicit geometric requalification `3bbb6f6` preserves historical evidence and model coefficients, adopts fresh empty pixels, and passed live preflights and later runs. This closes this reconnect episode, not general automatic reconnect reliability.
- [x] **PG-29 — Edge waypoint/refinement regression. Fixed and physically verified Nov24.** The18:09 run moved an already acceptable K2 dot inward during optional refinement; stopped fully OFF. `2da3c29` skips inward waypoints for nearby targets, clears them at acceptance and defaults to no extra refinements. Ten feedback regressions pass; corrected K2 subsequently reached0.148cells in13.4s. The broader speed issue remains PG-06b.
- [x] **PG-30 — Wide three-point experiment and seven-location feedback benchmark. Completed Nov24 across multiple runs.** Three widely separated observations acquired in87.63s; only those three enter the affine fit. All seven targets now have successful observations; no single uninterrupted seven-target pass is claimed. Final two-target run took117.39s READY-to-full-OFF. [Combined results](</Users/Dave/Documents/SGF PLayer/work/attended-recheck-20261124-105259/feedback-seven-target-summary.json>).
- [x] **PG-26a — Large AI clocks and labels on all four board sides. Installed and UI-smoke verified in0.260, retained in0.261.** Independent click controls included. Audio audibility remains PG-26b.
- [x] **PG-27 — Requested saved-data pruning pass. Completed Nov24.** Three abandoned duplicate/prefix backups removed after verification:306,201,499 logical bytes. Unique games, recordings and calibration evidence retained. No material APFS free-space improvement claimed. [Audit](</Users/Dave/Documents/SGF PLayer/work/data-pruning-20261124>).
- [x] **PG-14a — Consolidate issue tracking. Completed Nov24.** This register replaces conflicting “current” updates; full previous documents preserved in [snapshot](</Users/Dave/Documents/SGF PLayer/work/attended-recheck-20261124-105259/docs-before-issue-register>). Ongoing documentation upkeep remains PG-14b.

## Remaining requested work and follow-up

- [ ] **PG-00 — Fast AI test mode validation. Installed:** eight visits/no HumanSL, completed idle-worker reuse only. Next: measure cold and warm physical reply latency separately.
- [ ] **PG-01 — Motor/stand instability. Unresolved:** released/held encoder and velocity evidence is inconclusive. Next: compare optical jitter with stationary/stepping motors and untouched stand if faults or accuracy suggest it; do not attribute noise to mechanical motion without measurements.
- [ ] **PG-02 — Calibration model and board distortion. Evidence retained:**97 observations and four fitting targets, plus wide-three and new feedback data. Next: compare prediction/response errors spatially and reuse qualified observations. Full five-plus-nine tour is optional research, not the next mandatory step to play.
- [ ] **PG-05 — Captures. Offline-tested:** physically verify single, multiple and partial removals, both colors, retained prisoner identity and correct clock behavior.
- [ ] **PG-07 — Keep motors ready during play. Implemented in v44/schema2; short runs exercised.** Next: verify holding, hand interruption, transition/status freshness and resume on the current paired app/host. Full OFF must still release motor power.
- [ ] **PG-08 — Thermal endurance and cooling. Short evidence only.** Next: monitor actual play and cooling/re-engagement; a formal two-hour test is optional and not scheduled unattended.
- [ ] **PG-09 — Ended-game/reopened-app grid recovery. Fix installed since0.252.** Next: physically finish/reopen a game and verify recovery without losing unfinished-game state.
- [ ] **PG-10 — Laser centering hints. Implemented, preference off.** Next: validate observed stone-center targeting, hand stop and removal. Do not infer intended intersection from an ambiguous stone.
- [ ] **PG-11 — Captured-stone laser indications. Implemented.** Next: verify placement-first order, silent prisoner indications and partial cleanup on the board.
- [ ] **PG-12 — Online-opponent laser play. Not implemented.** Next: add authoritative native target production and server-clock-safe integration; a schema accepting `online` is insufficient.
- [ ] **PG-13 — Illegal-move feedback. Screen behavior installed since0.258.** Next: physically verify suicide/ko/restoration. Laser error patterns remain a proposal, not a shipped feature.
- [ ] **PG-14b — Keep documentation current. Ongoing.** Update this register after each change/test; reconcile architecture/protocol/install guides when behavior changes. Keep historical reports explicitly dated.
- [ ] **PG-15 — Minimal practical setup workflow. Three-wide experiment done.** Next: make that path usable through gameplay startup, retain calibration across recoverable interruptions and measure true setup-to-play time. Do not repeat a full tour merely because the first guess is inaccurate.
- [ ] **PG-16 — Camera/occupied-board latency attribution. Instrumentation `1f28d4c` offline-tested, not installed.** Existing native analysis median60.1ms/max173.6ms showed no sustained backlog. Next: identify current occupied-board tail delays; distinguish native recognition from host optical-registration work.
- [ ] **PG-17 — Gameplay fault continuity. Partial fixes installed.** Next: exercise transient camera/lease recovery, three-second transition bound, app closure/reopen and unrecoverable fault pause without losing game/clocks.
- [ ] **PG-18 — Learn from gameplay observations. Offline shadow learner only (`3ad106c`).** Ten tests pass; some medians improve but tail errors regress. Next: collect settled actual pose/spot pairs with provenance, score before training and retain rollback. No live updates or learned spatial derivative promoted.
- [ ] **PG-19 — Calibration progress UI. Existing five-plus-nine display installed.** Next: represent minimal/feedback workflows accurately, preserve completed points and show measured timing without treating progress as activation authority.
- [ ] **PG-20 — Architecture/process follow-through. Recovery reducer, immutable builds and paired acceptance integrated.** Next: keep new gameplay work within these boundaries and verify the installed combination physically; no wholesale rewrite required.
- [ ] **PG-21 — Timing/first-fault evidence. Optional tracing exists.** Next: retain first rejected frame plus alignment/hand reasons and tracker checkpoint, and separate command acknowledgement from actual light/click onset and cross-process clocks.
- [ ] **PG-22 — Stone thickness/parallax. Named sets/manual thickness installed; passive study `d0ed574` complete offline.** Shape/displacement cannot yet separate physical thickness from placement bias/camera geometry. Next: passive collector and held-out evaluation; no automatic optical correction activated.
- [ ] **PG-23 — Ambiguous/halfway placement. Guard installed since0.258;52 focused checks passed.** Next: physical Black/White halfway placements with hints off/on; correct color alone is not correct intersection.
- [ ] **PG-24 — Regional frame differences. Offline studies only.** Empty-board audit averages4.26/361 requested regions across19 comparisons. Next: include stones, hands, shadows and lighting controls before live use; unchanged pixels do not establish fresh clearance or a new stone.
- [ ] **PG-25 — Reversible practice fixtures. Four starts installed;166 controller/persistence checks recorded.** Next: use them for physical acceptance while preserving the original saved-game snapshot.
- [ ] **PG-26b — Stone click in AirPod Pro3. Controls and first-light-per-move logic installed.** Next: verify audible click on a genuinely new AI move, distinguish it from controller beeps and retry deduplication. Keep AirPod Pro3; do not switch system audio without asking.

## Latest physical measurements

Times below describe the successful attempt segment, not cold setup or total time
spent on interrupted targets. K2 and P15 resumed near their targets. Earlier K10,
F14,B10 runs allowed up to3 optional refinements; later runs stop at0.20cells.

| Target | Time to accepted indication | Final segment time | Final error (cells / pixels) |
|---|---:|---:|---:|
| K10 |19.12s|19.12s|0.052 /2.63|
| F14 |24.18s|24.18s|0.071 /2.54|
| B10 |25.12s|30.35s|0.023 /0.96|
| K2 |13.42s|13.42s|0.148 /8.14|
| S10 |69.39s|69.39s|0.179 /9.13|
| P15 |6.96s|6.96s|0.159 /7.93|
| K18 |95.71s|95.71s|0.016 /0.73|

Last run: `three-point-feedback-20261124-182047-85434`, source `2da3c29`.
Previous run stopped at138.011636s for native alignment rejection during P15,
with hand=false; full OFF confirmed. Earlier18:09 refinement-bug run stopped at
33.421239s, full OFF confirmed. None of these latest runs had a serial timeout.
Do not interpret calibration-only timing overrides as a gameplay reliability pass.

## Installed versions, sources and durable evidence

| Component | Current identity |
|---|---|
| Installed app | `/Users/Dave/Applications/Physical Go.app`,0.261/build262 |
| Installed app source | `/Users/Dave/SGFPlayerClean-worktrees/camera-safety-delivery`; runtime `9c516f1`, documentation HEAD `0628a33` |
| Embedded app source hash | `79f2ec079f3d116af313d612b4ad4a8f71ddb569211cce14f4c6f4a0569a30d7` |
| Existing paired gameplay host | `/Users/Dave/DYNAMIXEL-Go-Pointer-worktrees/camera-safety-delivery`, `04b76c7`; gameplay launcher remains blocked |
| Physically tested feedback host | `/Users/Dave/DYNAMIXEL-Go-Pointer-worktrees/feedback-indication-stop`, `2da3c29785aa7337871b299380dd3dc289437332` |
| Feedback launcher | `work/PhysicalGo-Feedback-Remaining.command`; currently P15/K18-only; no live PTY |
| Firmware | AimControl v44; unchanged |
| Camera | FULL HD WEB CAM/AUSDOM AF660,`0x21000000bda0567`,1920×1080; current epoch `C3601E4D-5053-478F-9BDC-207867A7EE1F` |
| Controller | `/dev/cu.usbmodem1101`; verify identity and exclusivity before next opening |
| Saved game | `D710D336-2746-4004-9796-F63A8D2FB8F5`, empty Human Black practice, paused; older games preserved |
| Rollback | Signed0.260 in `work/camera-safety-delivery-20261124`; do not overwrite |
| Active experiments | Native `alignment-profile-jitter`,002e4c7 (204 checks passed, independent review pending); host `feedback-optical-latency`,7d8b530 (offline tested only) |

Canonical repositories hold current documentation but older runtime sources.
Never build them assuming they match the installed app. Frozen hardware-tested
worktrees remain immutable; make a new branch/worktree for further changes.

Evidence root: `/Users/Dave/Documents/SGF PLayer/work/attended-recheck-20261124-105259`.
Raw runs: `work/ai-laser-integration/laser-position-recovery-20261123/calibration-acceptance-redesign`.
`session-status.json` tracks execution state; this register tracks issues and acceptance.

## Operating constraints

Root is sole hardware owner. Check existing runs before opening serial; ask READY
at the actual launcher prompt, monitor to completion, verify full OFF. No unattended
physical run is scheduled. No desktop screenshots without advance notice; use the
board webcam and accessibility text. Preserve game/clocks/calibration and unique
recordings. Diagnostic image saving and warning sounds are currently off; no
repetitive recording tail was removed in this session. Keep independent hand,
lease, thermal and actual-pose safeguards. Three-pixel aiming is optional, not a
universal requirement; geometry checks have different meanings and units.
