# Online opponent intent producer — PG-12

November 24, 2026. This is an offline implementation submilestone, not online laser
activation. The issue register remains authoritative for installation and physical
acceptance. The candidate is based on installed app source `0628a33`.

`PhysicalOnlineBoard.guidanceTarget(atUnix:)` now exposes an optional
`PhysicalOnlineGuidance.Target` from the existing SGF Player/OGS bridge. It does
not write pointer requests. No network session, app, camera or controller was
opened to develop this change.

## Authority and lifecycle

A target requires a fresh, ready bridge snapshot and a single legal opponent
stone transition from a previously synchronized position with no outstanding
physical placements/removals. The transition must reproduce the complete new
server board, including captures. Historical snapshots, reconnects, multi-move
catch-up, passes and takebacks cannot create an indication. Board-first and
turn-first updates are supported; an intent is visible only when the server says
it is the local player's turn.

The target retains its original decision receipt and operation identity through
heartbeats. A local UUID keeps bridge tokens out of exported identity. The
`generation` is a local indication sequence, **not** the server's move count.
`point` uses server/display orientation; a future consumer must perform the
existing explicit inverse display-to-camera mapping before dispatch.

A sufficiently confident, unambiguous physical reading retires the target.
Manual correction, disabled mode, stale/unready bridge, pending undo, accepted
undo, context change and a two-second upstream publication gap cancel it. A
heartbeat cannot resurrect a retired target. Reading the intent after its
upstream publication expires returns nil even if camera callbacks have stopped.

This component never pauses, edits or projects server clocks. It does not send
moves or infer server acceptance from pointer progress. Online clocks continue
while a player mirrors an opponent move or removes captured stones.

## Verification

Build registry: eight checks passed. Native online suite is queued with the
coordinator; no native pass is claimed yet.

Run `python3 PhysicalGo/build.py --online-test --debug-tests` for existing online
regressions plus producer cases covering both stone colors, split snapshots,
constant revisions, stable identities, expiry, weak/strong placement readings,
manual correction, reconnect, disabled mode, catch-up/pass/takeback, and retained
server-state bytes. `python3 PhysicalGo/Tests/test_build.py` checks source closure.

## Required integration before online laser play

The current `ExperimentModel` frame broker, frame publication, camera safety
updates and confirmed-dark observation gate are still selected only for AI play.
Connecting this intent directly to the AI laser would bypass that online
integration. Therefore this candidate deliberately has no dispatch consumer.

The next change must provide one mode-scoped laser owner, online frame and
clearance publication, orientation conversion, renewable current-target
admission, cancellation/recovery, and the reviewed PG-33 feedback backend. Pointer
faults may stop local guidance and show recovery instructions; they must never
pretend to stop the server clock. Run paired offline contract tests, then install
and verify an attended online game under root's hardware ownership. PG-12 remains
open until those requirements are met.
