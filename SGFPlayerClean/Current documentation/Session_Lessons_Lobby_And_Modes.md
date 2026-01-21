# Session Lessons: Lobby, Modes & State Persistence
**Date**: 2026-01-20

## 1. OGS Protocol Quirks
### Lobby Deletion
-   **Lesson**: The OGS `seekgraph` and lobby updates use flexible deletion keys.
-   **Behavior**: A deletion event often arrives not as a full object with a `challenge_id`, but as a concise dictionary: `{ "delete": 12345 }` or `{ "game_id": 123, "delete": true }`.
-   **Fix**: `OGSClient.updateLobbyItem` must explicitly check if the root "delete" key is an Integer (the ID) *before* attempting to parse `challenge_id` from the body. Failing to do so causes "ghost" games to persist in the list.

## 2. App Lifecycle & "Start on Launch"
### The "Data vs. UI" Race
-   **Problem**: Enabling "Start on Launch" logic inside `AppModel` would often fail with "No Game Selected" because the logic relied on asynchronous file loading to populate `app.selection`. If the folder was empty or slow to load, the UI remained in a "waiting" state despite the engine being ready.
-   **Solution**: Implement an explicit `startInstantGame()` method.
    -   **Mechanism**: Instantiate a dummy `SGFGameWrapper` with "Instant Game" metadata and assign it to `selection` immediately.
    -   **Benefit**: This guarantees a valid UI state (Active Game Panel) instantly, decoupling the ability to play from the filesystem state.

## 3. State Synchronization (View vs. Engine)
### Visual Artifacts (Board Glow)
-   **Problem**: When switching from Local (Analysis) to Online (Lobby), clearing the engine (`player.clear()`) was not sufficient to remove visual artifacts like the "Last Move Glow".
-   **Cause**: The View Model (`BoardViewModel`) observes the engine but may process updates on the run loop. If `clear()` happens silently or if the VM retains its own derived state (`lastMovePosition`), the UI desynchronizes.
-   **Fix**: Explicitly invoke `boardVM.resetToEmpty()` when changing contexts. This forces both the Engine (Data) and the ViewModel (Visual State) to clear synchronously, removing all artifacts.

## 4. Mode Persistence
### Snapshotting
-   **Implementation**: To allow seamless toggling between "Analysis" and "Play", `SGFPlayer` now supports `createSnapshot()` and `restoreSnapshot()`.
-   **Strategy**: When switching to Online, save the snapshot (Moves, Setup, Captures). When returning to Local, replay the snapshot moves. This preserves the user's analysis context perfectly, even though the engine was reused for online play in between.

## 5. UI Layout (SwiftUI)
### List Clipping
-   **Observation**: Standard `List` components on macOS/iOS often clip their top content under custom headers if `safeAreaInset` is not manually managed.
-   **Fix**: Adding specific `.padding(.top, 1)` or adjusting standard spacing resolved the "chopped off" first item in the Lobby list.
