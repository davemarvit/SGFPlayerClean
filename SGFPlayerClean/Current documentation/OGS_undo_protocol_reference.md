# OGS Undo Protocol & Implementation Notes

## 1. The Protocol (Wire Format)
Unlike some OGS messages which require a `sequence` number (to track state version), the Undo Request is treated as a meta-action and **must not** include a sequence number, but **must** include the reference Move Number.

### Outgoing Request (Sender)
When requesting an undo, the client sends:
```json
["game/undo/request", {
    "game_id": 12345678,
    "move_number": 123
}]
```
-   **`game_id`**: Integer.
-   **`move_number`**: Integer. This represents the **Server's Last Move Number**, not the Client's local move index.
-   **No Sequence**: Do not append the generic sequence number (e.g., `, 42]`) to the packet. It is a 2-element packet: `[EventName, Payload]`.

### Incoming Request (Recipient)
When the opponent requests an undo, the client receives:
```json
["game/12345678/undo_requested", {
    "move_number": 123,
    "requested_by": 987654,
    "undo_move_count": 1
}]
```
-   **`undo_move_count`**: Usually 1, but could be more if multiple moves need to be rolled back (e.g. undoing a self-capture sequence or complex state).

### Acceptance
To accept an undo, the client sends:
```json
["game/undo/accept", {
    "game_id": 12345678,
    "move_number": 123
}, 42]
```
-   **Sequence Required**: Note that `undo/accept` DOES typically include a sequence number (or at least observed logs suggest it), likely because it mutates the board state immediately.

## 2. Implementation Pitfalls

### A. The "Ghost Move" Desync
**Symptom**: You send an undo request, but the server ignores it.
**Cause**: The client often optimistically applies a move locally ("Ghost Move") before the server acknowledges it.
-   **Scenario**:
    1.  Server is at Move 10.
    2.  Client plays Move 11 (Local/Ghost).
    3.  User clicks Undo.
    4.  Client sends `undo/request` for Move 11.
    5.  **Server Ignores**: Server doesn't know about Move 11 yet (or rejected it, or lag). Server expects undo for Move 10 (or 9?).
**Solution**:
-   Always track `lastKnownRemoteMoveNumber` derived strictly from Server Data (`gamedata` or `move` events).
-   When requesting Undo, use the **Remote** number, not the Local Engine number.

### B. The "Zombie" Lobby Loop
**Symptom**: A finished game keeps reappearing in the Active Games list ("Return to Game"), causing a connection loop.
**Cause**:
-   OGS continues to send `active_game` events with `phase: "play"` and `outcome: nil` even after the game is technically finished, until the room is fully closed or archived.
-   If the client reconnects upon seeing `active_game`, it fetches data, sees it's finished, leaves, but then `active_game` triggers a reconnect again.
**Solution**:
-   **Persist Finished IDs**: Maintain a `Set<Int>` of `finishedGameIDs` for the session.
-   **Check Before Connect**: If `active_game` event arrives for an ID in `finishedGameIDs`, **ignore it**.
-   **Debounce**: If already connected to Game X, ignore `active_game` events for Game X.

### C. Clock Synchronization
-   **Thinking Time**: The `thinking_time` field in OGS `clock` data is **static** (the time at the start of the turn). It does *not* count down in real-time.
-   **Expiration**: The strict server time is calculated as `expiration - now`.
-   **Fischer Increment**: Be careful when overriding time. Fischer increment is often added *at the start* of the turn. If you calculate `expiration - now` blindly, you might see "Extra Time" (the increment) which confuses users who expect "Time Remaining from previous move".

### D. Chat Duplication (Game End)
**Symptom**: Chat history appears duplicated (or appended to itself) immediately when the game ends.
**Cause**:
-   When `phase` transitions to `finished`, the client receives a full `gamedata` payload (inc. chat history).
-   **Simultaneously**, the OGS server (or client logic) may emit individual `chat` events for the messages in the history.
-   If the client naively appends incoming chat *and* parses the history, duplication occurs.
**Solution**:
-   **Idempotency**: Implement robust deduplication in the Chat View Model. Comparing Message IDs (UUIDs) is insufficient if they are generated locally.
-   **Content Signature**: Deduplicate based on a content signature: `Timestamp + Sender + Body`.
-   **Incoming Filter**: When receiving a live chat message, check if it already exists in the history before appending.

### E. Scoring & Dead Stone Protocol
**Symptom**: Dead stones are not visualized, or the "Score" is unknown.
**Architecture**:
-   **Server Authority**: OGS calculates life/death ("Autoscore") and is the Source of Truth. The client does not calculate the score locally.
-   **Protocol**:
    -   During the `stone_removal` phase, the server includes a `removed` field (string of coordinates, e.g. "aaab") in the `gamedata` payload.
    -   The client must parse this field to identify which stones are considered dead.
-   **Interaction**: To mark a group as dead/alive, the client sends a `stone_removal/removed` (or `stone_removal/update`) command. The server validates and broadcasts the new state.

### F. Audio Architecture
**Issue**: Needed separate volume controls for "Voice/System" vs "Stone/Interaction" sounds.
**Implementation**:
-   **Separation of Concerns**:
    -   `SoundManager`: Handles "One-off" System/Voice sounds (e.g., "Game Started", "Byoyomi") loaded from `.aiff`.
    -   `AppModel`: Handles high-frequency "Interaction" sounds (e.g., "Stone Click", "Capture") loaded from `.mp3`.
-   **Volume Logic**:
    -   Since `AVAudioPlayer` instances are independent (no master mixer bus), we use `AppSettings` observers.
    -   When `stoneVolume` changes, `AppModel` iterates its players (`clickPlayer`, etc.) and updates `volume`.
    -   When `voiceVolume` changes, `SoundManager` iterates its dictionary of players and updates `volume`.
-   **Lesson**: Always ensure dynamic volume updates propagate to *idle* players too, so the next sound played is at the correct level of the current slider.
