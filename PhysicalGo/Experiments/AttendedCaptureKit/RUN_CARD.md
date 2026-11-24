# Attended capture card — not physically tested

**Prerequisite:** agree fixture loading with the root operator. The AI app has
Resume and SGF export, **no AI SGF-import/fixture picker**. These artifact files do
not load themselves. See [loading boundary](README.md#loading-boundary-pending-attended-decision).
Neither preserved real-game checkpoint (five moves and three moves) may be altered.
Use a disposable fixture copy; no loading/install script is included.

Each fixture is a separate synthetic session: **19×19, Human Black, four moves,
paused, Fast test mode enabled, zero elapsed balances**. No real move timestamps or camera evidence are
claimed. The fifth human move creates the capture normally; no AI choice is needed.

## Board-only pass: laser disabled

Verify selected camera, grid and physical orientation first. A19 is canonical
top-left; T1 is bottom-right; I is skipped. Confirm correspondence with the app's
coordinate overlay. Place exactly these four stones, all other points empty:

| Fixture | Black | White | Next human Black move | Expected White prisoners |
|---|---|---|---|---|
| Single | A18, T1 | A19, C19 | **B19** | **A19 only** |
| Two | B19, B18 | A19, A18 | **A17** | **A19 + A18** |

1. Confirm the disposable fixture's UUID/settings/four moves. Resume; withdraw
   hands and wait for the existing position to verify and the human turn to start.
2. Place the specified Black stone; **leave prisoners initially**. Withdraw hands.
   Expect one acceptance, history at five, and exactly the listed captured set.
3. **Single:** wait briefly with A19 present. The next player's elapsed clock
   continues. Remove A19 and withdraw; positive empty evidence completes cleanup.
   White C19 stays. Removal must not invent another move.
4. **Two:** both elapsed clocks stay held until cleanup completes. Remove **A18
   first**, leaving A19: expect one prisoner remaining, history still five, clock
   still held. Remove A19; fresh complete agreement releases the hold.
5. On fresh disposable copies, reverse the removal order, then remove both
   together. Enter/withdraw a hand without removal: that is not cleanup. Pause
   during partial cleanup and Resume: the same remaining prisoner needs fresh
   evidence. Optional mismatch check: remove unrelated C19 (single) or B18 (two);
   expect mismatch, not capture completion. Restore before continuing.

After full cleanup the AI may legitimately produce move six. Record the result
and pause; do not confuse a new AI decision with a phantom removal move. While
prisoners remain, history must stay at five. These are practice elapsed clocks;
the default hold applies to captures of **two or more**, not a single prisoner.

## Separate laser pass: attended only

Repeat on a fresh disposable fixture **only after** camera/laser calibration is
verified and root explicitly enables the laser. Camera-grid accuracy alone is not
laser calibration. Require live captured-stone indication capability; otherwise
mark the laser path untested.

Expect a marker on a remaining prisoner, beam OFF on hand entry, fresh dark proof
before returning, and no marker on a positively removed prisoner. Remove the
non-indicated prisoner first to test selection of the true remainder. Capture
cleanup must not play the ordinary move-arrival cue. Centering hints must not
replace prisoner guidance. Verify spot accuracy separately.

This kit does not qualify AI placement-before-capture indication, Black prisoner
surfaces, online play or forced AI choices. Offline tests inject an AI generator;
there is no installed forced-move UI and this kit adds no production hook.

Record fixture UUID, version, camera/orientation, captured set, removal order,
clock/history behavior, hand clearance and beam/cue observations. Keep board-only
and laser results separate. Pause on an unexpected move, wrong prisoner/target,
missing hold or unclear hand clearance; preserve the disposable test evidence.
Generating this kit is **not a physical pass**.
