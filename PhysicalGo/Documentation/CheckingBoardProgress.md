# Actionable AI board-check progress

PG-34 source candidate, November25,2026; based on installed source `1f6fb91`.
This addresses silent prolonged checking, not the underlying recognition or
reference fault. There is no automatic model/reference reset and no relaxation
of placement, camera, hand, laser, clock or move-acceptance rules.

The existing immediate status remains visible. After at least three fresh
assessments spanning three seconds without a completed check, Play adds a
“Board check needs attention” panel. It explains currently required uncertain
intersections, ambiguous placement, inconsistent readings or a board mismatch.
Point names follow the displayed board orientation; at most eight are listed,
with an additional count when necessary. The panel refreshes at most once per
second. A nearby “Camera & setup” button uses the existing navigation action and
preserves the active game.

Recovery text asks the user to inspect the physical board, camera view, grid and
lighting. Empty-reference capture is mentioned only for a game with no moves,
with an explicit requirement to remove every physical stone first. For an
occupied saved game, guidance preserves the board and points to existing occupied
reference controls. The panel never declares a reference stale or performs a
capture itself; existing controls retain their own availability rules.

Presentation state is independent of recognition witnesses. Hand/dark/invalid
camera interruptions, Pause, replacement game/camera scope and confirmed recovery
clear the old explanation. Fresh observations get a new grace period. Alternating
ambiguous and briefly stable frames retain the presentation's elapsed waiting
period, so repeated recognition resets do not conceal a long placement delay.
A valid later sequence can still complete normal startup or move acceptance.

## Evidence and checks

The retained pre-reference trace contains600 fresh required-intersection
rejections over about60 seconds, with changing blockers and no completed check.
`Tests/Fixtures/CheckingProgress/retained-startup.json` is a63KB metadata-only
extraction containing all600 captured times, ages and affected points, plus source
path/hash. It contains no camera pixels and does not establish a bad reference.

The small standalone helper build passed54 checks. It compiled the production
progress reducer, coordinate/orientation code, and the unchanged ImagePoint
value type extracted from BoardVision, without compiling the app or vision
pipeline. It replays the retained stall and verifies the three-second bound,
one-second refresh bound, hand/pause/gap/scope reset behavior, orientation labels,
occupied-game recovery text and later clear recovery. Command and output are in
`PhysicalGo/.build/checking-progress-standalone` in the candidate worktree.

Registered test flags for root's combined native verification:

```sh
python3 PhysicalGo/build.py --ai-checking-progress-test --ai-checking-controller-test --ai-ambiguous-placement-test --debug-tests
```

The controller suite exercises actual PhysicalAI with temporary saved games and
fake engine/camera observations: persistent startup uncertainty, hand withdrawal,
pause/resume, camera-context replacement, eventual valid readiness, and an
occupied-game ambiguity followed by a valid move. It checks preserved game IDs,
move history and normal clock boundaries. **This controller suite and full app
integration have not yet been compiled/run in this workstream.** Source syntax and
diff checks passed. Root owns combined build, installation and physical validation.
