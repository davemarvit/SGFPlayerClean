# Reversible practice test positions — candidate

This candidate exposes **Practice tests** in the AI Setup and Play panels. It
provides four separate, synthetic 19×19 positions with Fast test mode enabled:

- **Empty board — you play Black:** zero moves; ordinary empty-board verification
  after Resume starts the human Black turn.
- **Empty board — you play White:** zero moves; no AI request until Resume and
  ordinary fresh empty-board verification.
- **Single capture:** Black A18/T1, White A19/C19; the human's next Black B19
  captures A19. The next player's elapsed clock runs during cleanup.
- **Two-stone capture:** Black B19/B18, White A19/A18; Black A17 captures A19/A18.
  Elapsed clocks remain held until both prisoners are removed.

Coordinates in the UI follow its current display orientation. Camera-board size
changes only after a successful load or return, through the same size-change
callback used by ordinary setup. This does not calibrate the camera or laser.

## UI path

Pause the existing game. Open **Practice tests**, select an option, then confirm
**Load test position**. A new UUID, explicit **Test position · …** label and a
paused state distinguish the test. Arrange the indicated board before Resume.
Loading does not start the AI, accept a camera observation, enable the laser or
reuse the prior game's camera witness. The empty-board choice is a safe route to
zero moves without ending the preserved real game.

Pause the test, then choose **Return to saved game** (or **Return to setup** if
there was no game) and confirm. Normal new-game creation is blocked while in a
test; return first. Nested practice loads are also refused. A restored unfinished
game remains paused and must verify its own board before continuing.

## Persistence boundary

The original `current.json` bytes and draft settings are saved in an immutable
per-test `PracticeTests/<UUID>/previous-game.json` record before activation. The
record is read back, synchronized, and identified by a SHA-256 hash in the test
snapshot. The test's distinct SGF is prepared before the atomic authoritative
`current.json` write. No fallible derived SGF write follows that commit. The
original SGF and other checkpoints are untouched.

Return verifies the current exact bytes, test identity and backup hash, archives
outgoing test state, then restores the original bytes. A later game or even an
unknown-field edit to the current file invalidates an old return action. Backup,
SGF or current-write failures leave the previous in-memory game and authoritative
file unchanged; abandoned prepared test files do not become active. Retry remains
available. Backups are retained after return.

Current unresolved native/controller recheck state carries into new and restored
games; loading is not a hardware-fault reset. Controller-only shutdown latches
are preserved too. Returning to no game while a recheck remains unresolved is
refused, because deleting the only snapshot would lose its restart protection.
After an explicit healthy recheck, returning directly does not require starting
play merely to clear the old pause explanation. No broader fault tombstone or
automatic reset command is added.

## Validation status

Source and test parsing plus dependency resolution pass. Independent transaction
review contributed failure/retry/stale-identity tests, included in
`--practice-positions-test`. Root owns the first combined native execution and
app build; **no passing full-suite, installation or physical test is claimed by
this candidate checkpoint**. All tests inject temporary game/bridge directories
and synthetic observations. The source branch changes no live saved game.

Root merge points: Snapshot marker; initializer store argument and exact-byte
tracking; `save` byte tracking; lifecycle load/return helper (uses default
`cancel()`, which must stop the test worker); SGF synthetic label; AI views; one
ExperimentView size callback; source/test registry. Preserve root's newer
`cancel(preserveIdleTestWorker:)` API and keep these switches on its default stop
path. No application version change belongs to this candidate.
